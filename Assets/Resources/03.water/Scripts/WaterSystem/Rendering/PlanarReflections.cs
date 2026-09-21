using System;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Serialization;
using Unity.Mathematics;

namespace UnityEngine.Rendering.Universal
{
    /// <summary>
    /// 平面反射。在真实相机渲染前，用镜像相机加斜裁剪近平面画出水面以上的倒影。
    /// </summary>
    [ExecuteAlways]
    public class PlanarReflections : MonoBehaviour
    {
        [Serializable]
        public enum ResolutionMulltiplier
        {
            Full,
            Half,
            Third,
            Quarter
        }

        [Serializable]
        public class PlanarReflectionSettings
        {
            public ResolutionMulltiplier m_ResolutionMultiplier = ResolutionMulltiplier.Third; // 相对主相机的分辨率
            public float m_ClipPlaneOffset = 0.07f; // 反射平面上下微调，避免和水面重合闪烁
            public LayerMask m_ReflectLayers = -1; // 参与倒影的图层
            public bool m_Shadows; // 倒影里是否画阴影
        }

        [SerializeField]
        public PlanarReflectionSettings m_settings = new PlanarReflectionSettings();

        public GameObject target;
        [FormerlySerializedAs("camOffset")] public float m_planeOffset;

        private static Camera _reflectionCamera;
        private RenderTexture _reflectionTexture;
        private readonly int _planarReflectionTextureId = Shader.PropertyToID("_PlanarReflectionTexture");

        private int2 _oldReflectionTextureSize;

        public static event Action<ScriptableRenderContext, Camera> BeginPlanarReflections;

        // 反射相机比主相机先画，结果写进全局贴图
        private void OnEnable()
        {
            RenderPipelineManager.beginCameraRendering += ExecutePlanarReflections;
        }

        private void OnDisable()
        {
            Cleanup();
        }

        private void OnDestroy()
        {
            Cleanup();
        }

        private void Cleanup()
        {
            RenderPipelineManager.beginCameraRendering -= ExecutePlanarReflections;

            if(_reflectionCamera)
            {
                _reflectionCamera.targetTexture = null;
                SafeDestroy(_reflectionCamera.gameObject);
            }
            if (_reflectionTexture)
            {
                RenderTexture.ReleaseTemporary(_reflectionTexture);
            }
        }

        private static void SafeDestroy(Object obj)
        {
            if (Application.isEditor)
            {
                DestroyImmediate(obj);
            }
            else
            {
                Destroy(obj);
            }
        }

        private void UpdateCamera(Camera src, Camera dest)
        {
            if (dest == null) return;

            dest.CopyFrom(src);
            dest.useOcclusionCulling = false;
            if (dest.gameObject.TryGetComponent(out UniversalAdditionalCameraData camData))
            {
                camData.renderShadows = m_settings.m_Shadows;
            }
        }

        private void UpdateReflectionCamera(Camera realCamera)
        {
            if (_reflectionCamera == null)
                _reflectionCamera = CreateMirrorObjects();

            // 反射平面默认水平，有目标物体时跟它的朝向
            Vector3 pos = Vector3.zero;
            Vector3 normal = Vector3.up;
            if (target != null)
            {
                pos = target.transform.position + Vector3.up * m_planeOffset;
                normal = target.transform.up;
            }

            UpdateCamera(realCamera, _reflectionCamera);

            // 把相机沿水平面镜像，并用斜投影裁掉水面以下
            var d = -Vector3.Dot(normal, pos) - m_settings.m_ClipPlaneOffset;
            var reflectionPlane = new Vector4(normal.x, normal.y, normal.z, d);

            var reflection = Matrix4x4.identity;
            reflection *= Matrix4x4.Scale(new Vector3(1, -1, 1));

            CalculateReflectionMatrix(ref reflection, reflectionPlane);
            var oldPosition = realCamera.transform.position - new Vector3(0, pos.y * 2, 0);
            var newPosition = ReflectPosition(oldPosition);
            _reflectionCamera.transform.forward = Vector3.Scale(realCamera.transform.forward, new Vector3(1, -1, 1));
            _reflectionCamera.worldToCameraMatrix = realCamera.worldToCameraMatrix * reflection;

            var clipPlane = CameraSpacePlane(_reflectionCamera, pos - Vector3.up * 0.1f, normal, 1.0f);
            var projection = realCamera.CalculateObliqueMatrix(clipPlane);
            _reflectionCamera.projectionMatrix = projection;
            _reflectionCamera.cullingMask = m_settings.m_ReflectLayers;
            _reflectionCamera.transform.position = newPosition;
        }

        // 由平面方程写出反射矩阵
        private static void CalculateReflectionMatrix(ref Matrix4x4 reflectionMat, Vector4 plane)
        {
            reflectionMat.m00 = (1F - 2F * plane[0] * plane[0]);
            reflectionMat.m01 = (-2F * plane[0] * plane[1]);
            reflectionMat.m02 = (-2F * plane[0] * plane[2]);
            reflectionMat.m03 = (-2F * plane[3] * plane[0]);

            reflectionMat.m10 = (-2F * plane[1] * plane[0]);
            reflectionMat.m11 = (1F - 2F * plane[1] * plane[1]);
            reflectionMat.m12 = (-2F * plane[1] * plane[2]);
            reflectionMat.m13 = (-2F * plane[3] * plane[1]);

            reflectionMat.m20 = (-2F * plane[2] * plane[0]);
            reflectionMat.m21 = (-2F * plane[2] * plane[1]);
            reflectionMat.m22 = (1F - 2F * plane[2] * plane[2]);
            reflectionMat.m23 = (-2F * plane[3] * plane[2]);

            reflectionMat.m30 = 0F;
            reflectionMat.m31 = 0F;
            reflectionMat.m32 = 0F;
            reflectionMat.m33 = 1F;
        }

        private static Vector3 ReflectPosition(Vector3 pos)
        {
            var newPos = new Vector3(pos.x, -pos.y, pos.z);
            return newPos;
        }

        private float GetScaleValue()
        {
            switch(m_settings.m_ResolutionMultiplier)
            {
                case ResolutionMulltiplier.Full:
                    return 1f;
                case ResolutionMulltiplier.Half:
                    return 0.5f;
                case ResolutionMulltiplier.Third:
                    return 0.33f;
                case ResolutionMulltiplier.Quarter:
                    return 0.25f;
                default:
                    return 0.5f;
            }
        }

        private static bool Int2Compare(int2 a, int2 b)
        {
            return a.x == b.x && a.y == b.y;
        }

        // 把世界空间反射平面变到相机空间，供斜裁剪使用
        private Vector4 CameraSpacePlane(Camera cam, Vector3 pos, Vector3 normal, float sideSign)
        {
            var offsetPos = pos + normal * m_settings.m_ClipPlaneOffset;
            var m = cam.worldToCameraMatrix;
            var cameraPosition = m.MultiplyPoint(offsetPos);
            var cameraNormal = m.MultiplyVector(normal).normalized * sideSign;
            return new Vector4(cameraNormal.x, cameraNormal.y, cameraNormal.z, -Vector3.Dot(cameraPosition, cameraNormal));
        }

        private Camera CreateMirrorObjects()
        {
            var go = new GameObject("Planar Reflections",typeof(Camera));
            var cameraData = go.AddComponent(typeof(UniversalAdditionalCameraData)) as UniversalAdditionalCameraData;

            cameraData.requiresColorOption = CameraOverrideOption.Off;
            cameraData.requiresDepthOption = CameraOverrideOption.Off;
            cameraData.SetRenderer(1); // 用管线第 1 号渲染器，避免反射相机再画一遍水面 Feature

            var t = transform;
            var reflectionCamera = go.GetComponent<Camera>();
            reflectionCamera.transform.SetPositionAndRotation(t.position, t.rotation);
            reflectionCamera.depth = -10;
            reflectionCamera.enabled = false;
            go.hideFlags = HideFlags.HideAndDontSave;

            return reflectionCamera;
        }

        private void PlanarReflectionTexture(Camera cam)
        {
            if (_reflectionTexture == null)
            {
                var res = ReflectionResolution(cam, UniversalRenderPipeline.asset.renderScale);
                bool useHdr10 = RenderingUtils.SupportsRenderTextureFormat(RenderTextureFormat.RGB111110Float);
                RenderTextureFormat hdrFormat = useHdr10 ? RenderTextureFormat.RGB111110Float : RenderTextureFormat.DefaultHDR;
                _reflectionTexture = RenderTexture.GetTemporary(res.x, res.y, 16,
                    GraphicsFormatUtility.GetGraphicsFormat(hdrFormat, true));
            }
            _reflectionCamera.targetTexture =  _reflectionTexture;
        }

        private int2 ReflectionResolution(Camera cam, float scale)
        {
            var x = (int)(cam.pixelWidth * scale * GetScaleValue());
            var y = (int)(cam.pixelHeight * scale * GetScaleValue());
            return new int2(x, y);
        }

        // 反射相机不递归画反射，预览窗口也不画
        private void ExecutePlanarReflections(ScriptableRenderContext context, Camera camera)
        {
            if (camera.cameraType == CameraType.Reflection || camera.cameraType == CameraType.Preview)
                return;

            UpdateReflectionCamera(camera);
            PlanarReflectionTexture(camera);

            // 倒影降一档 LOD，并关掉雾，画完再恢复
            var data = new PlanarReflectionSettingData();
            data.Set();
            
            Shader.EnableKeyword("_PLANAR_REFLECTION_CAMERA");

            BeginPlanarReflections?.Invoke(context, _reflectionCamera);
            UniversalRenderPipeline.RenderSingleCamera(context, _reflectionCamera);

            data.Restore();
            Shader.SetGlobalTexture(_planarReflectionTextureId, _reflectionTexture);
            Shader.DisableKeyword("_PLANAR_REFLECTION_CAMERA");
        }

        class PlanarReflectionSettingData
        {
            private readonly bool _fog;
            private readonly int _maxLod;
            private readonly float _lodBias;

            public PlanarReflectionSettingData()
            {
                _fog = RenderSettings.fog;
                _maxLod = QualitySettings.maximumLODLevel;
                _lodBias = QualitySettings.lodBias;
            }

            public void Set()
            {
                GL.invertCulling = true;
                RenderSettings.fog = false;
                QualitySettings.maximumLODLevel = 1;
                QualitySettings.lodBias = _lodBias * 0.5f;
            }

            public void Restore()
            {
                GL.invertCulling = false;
                RenderSettings.fog = _fog;
                QualitySettings.maximumLODLevel = _maxLod;
                QualitySettings.lodBias = _lodBias;
            }
        }
    }
}
