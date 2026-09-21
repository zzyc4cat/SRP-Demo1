using System;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering.Universal;
using WaterSystem.Data;
using Object = UnityEngine.Object;
using Random = UnityEngine.Random;

namespace WaterSystem
{
    /// <summary>
    /// 水面总控。准备波浪、水深、水色和反射，再把海面网格画到每个相机前面。
    /// </summary>
    [ExecuteAlways]
    public class Water : MonoBehaviour
    {
        // 单例。浮力取样通过它读取当前水面的波列
        private static Water _instance;
        public static Water Instance
        {
            get
            {
                if (_instance == null)
                    _instance = (Water)FindObjectOfType(typeof(Water));
                return _instance;
            }
        }
        // 平面反射。反射类型不是 Planar 时会被关掉
        private PlanarReflections _planarReflections;

        private bool _useComputeBuffer;
        public bool computeOverride;

        [SerializeField] RenderTexture _depthTex;
        public Texture bakedDepthTex;
        private Camera _depthCam;
        private Texture2D _rampTexture;
        [SerializeField]
        public Wave[] _waves;
        [SerializeField]
        private ComputeBuffer waveBuffer;
        private float _maxWaveHeight;
        private float _waveHeight;

        [SerializeField]
        public WaterSettingsData settingsData;
        [SerializeField]
        public WaterSurfaceData surfaceData;
        [SerializeField]
        private WaterResources resources;

        private static readonly int CameraRoll = Shader.PropertyToID("_CameraRoll");
        private static readonly int InvViewProjection = Shader.PropertyToID("_InvViewProjection");
        private static readonly int WaterDepthMap = Shader.PropertyToID("_WaterDepthMap");
        private static readonly int FoamMap = Shader.PropertyToID("_FoamMap");
        private static readonly int SurfaceMap = Shader.PropertyToID("_SurfaceMap");
        private static readonly int WaveHeight = Shader.PropertyToID("_WaveHeight");
        private static readonly int MaxWaveHeight = Shader.PropertyToID("_MaxWaveHeight");
        private static readonly int MaxDepth = Shader.PropertyToID("_MaxDepth");
        private static readonly int WaveCount = Shader.PropertyToID("_WaveCount");
        private static readonly int CubemapTexture = Shader.PropertyToID("_CubemapTexture");
        private static readonly int WaveDataBuffer = Shader.PropertyToID("_WaveDataBuffer");
        private static readonly int WaveData = Shader.PropertyToID("waveData");
        private static readonly int AbsorptionScatteringRamp = Shader.PropertyToID("_AbsorptionScatteringRamp");
        private static readonly int DepthCamZParams = Shader.PropertyToID("_VeraslWater_DepthCamParams");

        // 选 GPU 波浪缓冲，加载资源，并挂到每次相机渲染前
        private void OnEnable()
        {
            if (!computeOverride)
                _useComputeBuffer = SystemInfo.supportsComputeShaders &&
                                   Application.platform != RuntimePlatform.WebGLPlayer &&
                                   Application.platform != RuntimePlatform.Android;
            else
                _useComputeBuffer = false;
            Init();
            RenderPipelineManager.beginCameraRendering += BeginCameraRendering;

            if(resources == null)
            {
                resources = Resources.Load("03.water/Data/WaterResources") as WaterResources;
            }
        }

        private void OnDisable() {
            Cleanup();
        }

        private void OnApplicationQuit()
        {
            GerstnerWavesJobs.Cleanup();
        }

        void Cleanup()
        {
            RenderPipelineManager.beginCameraRendering -= BeginCameraRendering;
            if (_depthCam)
            {
                _depthCam.targetTexture = null;
                SafeDestroy(_depthCam.gameObject);
            }
            if (_depthTex)
            {
                SafeDestroy(_depthTex);
            }

            waveBuffer?.Dispose();
        }

        private void BeginCameraRendering(ScriptableRenderContext src, Camera cam)
        {
            if (cam.cameraType == CameraType.Preview) return;

            var roll = cam.transform.localEulerAngles.z;
            Shader.SetGlobalFloat(CameraRoll, roll);
            Shader.SetGlobalMatrix(InvViewProjection,
                (GL.GetGPUProjectionMatrix(cam.projectionMatrix, false) * cam.worldToCameraMatrix).inverse);

            // 无限海面：网格跟在相机前 10 米，水平位置按 6.25 米对齐，避免接缝跟着镜头抖
            const float quantizeValue = 6.25f;
            const float forwards = 10f;
            const float yOffset = -0.25f;

            var newPos = cam.transform.TransformPoint(Vector3.forward * forwards);
            newPos.y = yOffset;
            newPos.x = quantizeValue * (int) (newPos.x / quantizeValue);
            newPos.z = quantizeValue * (int) (newPos.z / quantizeValue);

            var matrix = Matrix4x4.TRS(newPos + transform.position, Quaternion.identity, transform.localScale);

            foreach (var mesh in resources.defaultWaterMeshes)
            {
                Graphics.DrawMesh(mesh,
                    matrix,
                    resources.defaultSeaMaterial,
                    gameObject.layer,
                    cam,
                    0,
                    null,
                    ShadowCastingMode.Off,
                    true,
                    null,
                    LightProbeUsage.Off,
                    null);
            }
        }

        private static void SafeDestroy(Object o)
        {
            if(Application.isPlaying)
                Destroy(o);
            else
                DestroyImmediate(o);
        }

        // 组装波浪、水色、反射和岸边水深，全部写成全局着色器参数
        public void Init()
        {
            SetWaves();
            GenerateColorRamp();
            if (bakedDepthTex)
            {
                Shader.SetGlobalTexture(WaterDepthMap, bakedDepthTex);
            }

            if (!gameObject.TryGetComponent(out _planarReflections))
            {
                _planarReflections = gameObject.AddComponent<PlanarReflections>();
            }
            _planarReflections.hideFlags = HideFlags.HideAndDontSave | HideFlags.HideInInspector;
            _planarReflections.m_settings = settingsData.planarSettings;
            _planarReflections.enabled = settingsData.refType == ReflectionType.PlanarReflection;

            if(resources == null)
            {
                resources = Resources.Load("03.water/Data/WaterResources") as WaterResources;
            }
            // WebGL 的 OpenGL 深度有问题，跳过实时水深
            if(Application.platform != RuntimePlatform.WebGLPlayer)
                CaptureDepthMap();
        }

        // 每帧把已登记的浮力点交给 Burst Job 算高度
        private void LateUpdate()
        {
            GerstnerWavesJobs.UpdateHeights();
        }

        public void FragWaveNormals(bool toggle)
        {
            var mat = GetComponent<Renderer>().sharedMaterial;
            if (toggle)
                mat.EnableKeyword("GERSTNER_WAVES");
            else
                mat.DisableKeyword("GERSTNER_WAVES");
        }

        // 上传波列、反射关键字，以及泡沫和表面法线
        private void SetWaves()
        {
            SetupWaves(surfaceData._customWaves);

            // 泡沫贴图和表面法线是全局的，所有水面着色器共用
            Shader.SetGlobalTexture(FoamMap, resources.defaultFoamMap);
            Shader.SetGlobalTexture(SurfaceMap, resources.defaultSurfaceMap);

            _maxWaveHeight = 0f;
            foreach (var w in _waves)
            {
                _maxWaveHeight += w.amplitude;
            }
            _maxWaveHeight /= _waves.Length;

            _waveHeight = transform.position.y;

            Shader.SetGlobalFloat(WaveHeight, _waveHeight);
            Shader.SetGlobalFloat(MaxWaveHeight, _maxWaveHeight);
            Shader.SetGlobalFloat(MaxDepth, surfaceData._waterMaxVisibility);

            // 三种反射互斥，只开当前这一组关键字
            switch(settingsData.refType)
            {
                case ReflectionType.Cubemap:
                    Shader.EnableKeyword("_REFLECTION_CUBEMAP");
                    Shader.DisableKeyword("_REFLECTION_PROBES");
                    Shader.DisableKeyword("_REFLECTION_PLANARREFLECTION");
                    Shader.SetGlobalTexture(CubemapTexture, settingsData.cubemapRefType);
                    break;
                case ReflectionType.ReflectionProbe:
                    Shader.DisableKeyword("_REFLECTION_CUBEMAP");
                    Shader.EnableKeyword("_REFLECTION_PROBES");
                    Shader.DisableKeyword("_REFLECTION_PLANARREFLECTION");
                    break;
                case ReflectionType.PlanarReflection:
                    Shader.DisableKeyword("_REFLECTION_CUBEMAP");
                    Shader.DisableKeyword("_REFLECTION_PROBES");
                    Shader.EnableKeyword("_REFLECTION_PLANARREFLECTION");
                    break;
                default:
                    throw new ArgumentOutOfRangeException();
            }

            Shader.SetGlobalInt(WaveCount, _waves.Length);

            // GPU：优先用 StructuredBuffer，不支持时退回全局数组
            if (_useComputeBuffer)
            {
                Shader.EnableKeyword("USE_STRUCTURED_BUFFER");
                waveBuffer?.Dispose();
                waveBuffer = new ComputeBuffer(10, (sizeof(float) * 6));
                waveBuffer.SetData(_waves);
                Shader.SetGlobalBuffer(WaveDataBuffer, waveBuffer);
            }
            else
            {
                Shader.DisableKeyword("USE_STRUCTURED_BUFFER");
                Shader.SetGlobalVectorArray(WaveData, GetWaveData());
            }
            // CPU：同一套波列交给 Burst Job，供浮力取样，不参与画面位移
            if(GerstnerWavesJobs.Initialized == false && Application.isPlaying)
                GerstnerWavesJobs.Init();
        }

        private Vector4[] GetWaveData()
        {
            var waveData = new Vector4[20];
            for (var i = 0; i < _waves.Length; i++)
            {
                waveData[i] = new Vector4(_waves[i].amplitude, _waves[i].direction, _waves[i].wavelength, _waves[i].onmiDir);
                waveData[i+10] = new Vector4(_waves[i].origin.x, _waves[i].origin.y, 0, 0);
            }
            return waveData;
        }

        private void SetupWaves(bool custom)
        {
            if(!custom)
            {
                // 非手写模式：用种子生成一组方向、波长、振幅都略有差别的波
                var backupSeed = Random.state;
                Random.InitState(surfaceData.randomSeed);
                var basicWaves = surfaceData._basicWaveSettings;
                var a = basicWaves.amplitude;
                var d = basicWaves.direction;
                var l = basicWaves.wavelength;
                var numWave = basicWaves.numWaves;
                _waves = new Wave[numWave];

                var r = 1f / numWave;

                for (var i = 0; i < numWave; i++)
                {
                    var p = Mathf.Lerp(0.5f, 1.5f, i * r);
                    var amp = a * p * Random.Range(0.8f, 1.2f);
                    var dir = d + Random.Range(-90f, 90f);
                    var len = l * p * Random.Range(0.6f, 1.4f);
                    _waves[i] = new Wave(amp, dir, len, Vector2.zero, false);
                    Random.InitState(surfaceData.randomSeed + i + 1);
                }
                Random.state = backupSeed;
            }
            else
            {
                _waves = surfaceData._waves.ToArray();
            }
        }

        // 128x4 查找图：第 0 行吸收色，第 1 行散射色，第 2 行泡沫密度
        private void GenerateColorRamp()
        {
            if(_rampTexture == null)
                _rampTexture = new Texture2D(128, 4, GraphicsFormat.R8G8B8A8_SRGB, TextureCreationFlags.None);
            _rampTexture.wrapMode = TextureWrapMode.Clamp;

            var defaultFoamRamp = resources.defaultFoamRamp;

            var cols = new Color[512];
            for (var i = 0; i < 128; i++)
            {
                cols[i] = surfaceData._absorptionRamp.Evaluate(i / 128f);
            }
            for (var i = 0; i < 128; i++)
            {
                cols[i + 128] = surfaceData._scatterRamp.Evaluate(i / 128f);
            }
            for (var i = 0; i < 128; i++)
            {
                switch(surfaceData._foamSettings.foamType)
                {
                    case 0:
                        cols[i + 256] = defaultFoamRamp.GetPixelBilinear(i / 128f , 0.5f);
                        break;
                    case 1:
                        cols[i + 256] = defaultFoamRamp.GetPixelBilinear(surfaceData._foamSettings.basicFoam.Evaluate(i / 128f) , 0.5f);
                        break;
                    case 2:
                        cols[i + 256] = Color.black;
                        break;
                }
            }
            _rampTexture.SetPixels(cols);
            _rampTexture.Apply();
            Shader.SetGlobalTexture(AbsorptionScatteringRamp, _rampTexture);
        }

        // 岸边水深：从上往下拍一张正交深度，给浅水压浪、岸线泡沫和水色用
        [ContextMenu("Capture Depth")]
        public void CaptureDepthMap()
        {
            // 只渲染第 10 层，相机本身不参与游戏画面
            if(_depthCam == null)
            {
                var go =
                    new GameObject("depthCamera") {hideFlags = HideFlags.HideAndDontSave};
                _depthCam = go.AddComponent<Camera>();
            }

            var additionalCamData = _depthCam.GetUniversalAdditionalCameraData();
            additionalCamData.renderShadows = false;
            additionalCamData.requiresColorOption = CameraOverrideOption.Off;
            additionalCamData.requiresDepthOption = CameraOverrideOption.Off;

            var t = _depthCam.transform;
            var depthExtra = 4.0f;
            t.position = Vector3.up * (transform.position.y + depthExtra);
            t.up = Vector3.forward;

            _depthCam.enabled = true;
            _depthCam.orthographic = true;
            _depthCam.orthographicSize = 250;
            _depthCam.nearClipPlane =0.01f;
            _depthCam.farClipPlane = surfaceData._waterMaxVisibility + depthExtra;
            _depthCam.allowHDR = false;
            _depthCam.allowMSAA = false;
            _depthCam.cullingMask = (1 << 10);
            // 1024 深度图，覆盖约 500 米见方
            if (!_depthTex)
                _depthTex = new RenderTexture(1024, 1024, 24, RenderTextureFormat.Depth, RenderTextureReadWrite.Linear);
            if (SystemInfo.graphicsDeviceType == GraphicsDeviceType.OpenGLES2 || SystemInfo.graphicsDeviceType == GraphicsDeviceType.OpenGLES3)
            {
                _depthTex.filterMode = FilterMode.Point;
            }
            _depthTex.wrapMode = TextureWrapMode.Clamp;
            _depthTex.name = "WaterDepthMap";
            // 拍一次后关掉相机，结果留给着色器反复采样
            _depthCam.targetTexture = _depthTex;
            _depthCam.Render();
            Shader.SetGlobalTexture(WaterDepthMap, _depthTex);
            // 深度相机是临时的，把高度和正交尺寸写给着色器自己还原线性深度
            var _params = new Vector4(t.position.y, 250, 0, 0);
            Shader.SetGlobalVector(DepthCamZParams, _params);

            _depthCam.enabled = false;
            _depthCam.targetTexture = null;
        }

        [Serializable]
        public enum DebugMode { none, stationary, screen };
    }
}
