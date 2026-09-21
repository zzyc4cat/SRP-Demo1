using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace WaterSystem
{
    /// <summary>
    /// 水面后处理。不透明物之前画半分辨率 WaterFX，天空之后把焦散乘到水下。
    /// </summary>
    public class WaterSystemFeature : ScriptableRendererFeature
    {

        #region Water Effects Pass

        // 半分辨率打包图：R 泡沫，G/B 法线 xz，A 位移。清空色是无扰动的中性值
        class WaterFxPass : ScriptableRenderPass
        {
            private const string k_RenderWaterFXTag = "Render Water FX";
            private ProfilingSampler m_WaterFX_Profile = new ProfilingSampler(k_RenderWaterFXTag);
            private readonly ShaderTagId m_WaterFXShaderTag = new ShaderTagId("WaterFX");
            private readonly Color m_ClearColor = new Color(0.0f, 0.5f, 0.5f, 0.5f);
            private FilteringSettings m_FilteringSettings;
            private RenderTargetHandle m_WaterFX = RenderTargetHandle.CameraTarget;

            public WaterFxPass()
            {
                m_WaterFX.Init("_WaterFXMap");
                m_FilteringSettings = new FilteringSettings(RenderQueueRange.transparent);
            }

            public override void Configure(CommandBuffer cmd, RenderTextureDescriptor cameraTextureDescriptor)
            {
                cameraTextureDescriptor.depthBufferBits = 0;
                cameraTextureDescriptor.width /= 2;
                cameraTextureDescriptor.height /= 2;
                cameraTextureDescriptor.colorFormat = RenderTextureFormat.Default;
                cmd.GetTemporaryRT(m_WaterFX.id, cameraTextureDescriptor, FilterMode.Bilinear);
                ConfigureTarget(m_WaterFX.Identifier());
                ConfigureClear(ClearFlag.Color, m_ClearColor);
            }

            public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
            {
                CommandBuffer cmd = CommandBufferPool.Get();
                using (new ProfilingScope(cmd, m_WaterFX_Profile))
                {
                    context.ExecuteCommandBuffer(cmd);
                    cmd.Clear();

                    // 只画 LightMode 为 WaterFX 的透明物体，从后往前
                    var drawSettings = CreateDrawingSettings(m_WaterFXShaderTag, ref renderingData,
                        SortingCriteria.CommonTransparent);

                    context.DrawRenderers(renderingData.cullResults, ref drawSettings, ref m_FilteringSettings);
                }
                context.ExecuteCommandBuffer(cmd);
                CommandBufferPool.Release(cmd);
            }

            public override void OnCameraCleanup(CommandBuffer cmd) 
            {
                cmd.ReleaseTemporaryRT(m_WaterFX.id);
            }
        }

        #endregion

        #region Caustics Pass

        // 天空之后画一张贴在水面高度的大平面，把焦散乘进已有颜色
        class WaterCausticsPass : ScriptableRenderPass
        {
            private const string k_RenderWaterCausticsTag = "Render Water Caustics";
            private ProfilingSampler m_WaterCaustics_Profile = new ProfilingSampler(k_RenderWaterCausticsTag);
            public Material WaterCausticMaterial;
            private static Mesh m_mesh;

            public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
            {
                var cam = renderingData.cameraData.camera;
                if (cam.cameraType == CameraType.Preview || !WaterCausticMaterial)
                    return;

                CommandBuffer cmd = CommandBufferPool.Get();
                using (new ProfilingScope(cmd, m_WaterCaustics_Profile))
                {
                    var sunMatrix = RenderSettings.sun != null
                        ? RenderSettings.sun.transform.localToWorldMatrix
                        : Matrix4x4.TRS(Vector3.zero, Quaternion.Euler(-45f, 45f, 0f), Vector3.one);
                    WaterCausticMaterial.SetMatrix("_MainLightDir", sunMatrix);
                
                
                    if (!m_mesh)
                        m_mesh = GenerateCausticsMesh(1000f);

                    // 平面跟相机走，高度固定在水面，覆盖视野里的水底
                    var position = cam.transform.position;
                    position.y = 0;
                    var matrix = Matrix4x4.TRS(position, Quaternion.identity, Vector3.one);
                    cmd.DrawMesh(m_mesh, matrix, WaterCausticMaterial, 0, 0);
                }

                context.ExecuteCommandBuffer(cmd);
                CommandBufferPool.Release(cmd);
            }
        }

        #endregion

        WaterFxPass m_WaterFxPass;
        WaterCausticsPass m_CausticsPass;

        public WaterSystemSettings settings = new WaterSystemSettings();
        [HideInInspector][SerializeField] private Shader causticShader;
        [HideInInspector][SerializeField] private Texture2D causticTexture;

        private Material _causticMaterial;

        private static readonly int SrcBlend = Shader.PropertyToID("_SrcBlend");
        private static readonly int DstBlend = Shader.PropertyToID("_DstBlend");
        private static readonly int Size = Shader.PropertyToID("_Size");
        private static readonly int CausticTexture = Shader.PropertyToID("_CausticMap");

        public override void Create()
        {
            // 不透明物之前：给水面着色器准备局部泡沫和法线
            m_WaterFxPass = new WaterFxPass {renderPassEvent = RenderPassEvent.BeforeRenderingOpaques};

            // 天空之后：焦散叠到已经画好的水下物体上
            m_CausticsPass = new WaterCausticsPass();

            causticShader = causticShader ? causticShader : Shader.Find("ZZY/03.water/Caustics");
            if (causticShader == null) return;
            if (_causticMaterial)
            {
                DestroyImmediate(_causticMaterial);
            }
            _causticMaterial = CoreUtils.CreateEngineMaterial(causticShader);
            _causticMaterial.SetFloat("_BlendDistance", settings.causticBlendDistance);
            
            if (causticTexture == null)
            {
                Debug.Log("Caustics Texture missing, attempting to load.");
#if UNITY_EDITOR
                causticTexture = UnityEditor.AssetDatabase.LoadAssetAtPath<Texture2D>("Assets/Resources/03.water/Textures/Water/WaterSurface_single.tif");
#endif
            }
            _causticMaterial.SetTexture(CausticTexture, causticTexture);
            
            switch (settings.debug)
            {
                case WaterSystemSettings.DebugMode.Caustics:
                    _causticMaterial.SetFloat(SrcBlend, 1f);
                    _causticMaterial.SetFloat(DstBlend, 0f);
                    _causticMaterial.EnableKeyword("_DEBUG");
                    m_CausticsPass.renderPassEvent = RenderPassEvent.AfterRenderingPostProcessing;
                    break;
                case WaterSystemSettings.DebugMode.WaterEffects:
                    break;
                case WaterSystemSettings.DebugMode.Disabled:
                    // SrcBlend 2、DstBlend 0 是 DstColor * Src，输出再加 1，正常亮度不变
                    _causticMaterial.SetFloat(SrcBlend, 2f);
                    _causticMaterial.SetFloat(DstBlend, 0f);
                    _causticMaterial.DisableKeyword("_DEBUG");
                    m_CausticsPass.renderPassEvent = RenderPassEvent.AfterRenderingSkybox + 1;
                    break;
            }

            _causticMaterial.SetFloat(Size, settings.causticScale);
            m_CausticsPass.WaterCausticMaterial = _causticMaterial;
        }

        public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
        {
            renderer.EnqueuePass(m_WaterFxPass);
            renderer.EnqueuePass(m_CausticsPass);
        }

        /// <summary>
        /// 焦散用的水平四边形，边长 size，中心在原点。
        /// </summary>
        private static Mesh GenerateCausticsMesh(float size)
        {
            var m = new Mesh();
            size *= 0.5f;

            var verts = new[]
            {
                new Vector3(-size, 0f, -size),
                new Vector3(size, 0f, -size),
                new Vector3(-size, 0f, size),
                new Vector3(size, 0f, size)
            };
            m.vertices = verts;

            var tris = new[]
            {
                0, 2, 1,
                2, 3, 1
            };
            m.triangles = tris;

            return m;
        }

        [System.Serializable]
        public class WaterSystemSettings
        {
            [Header("Caustics Settings")] [Range(0.1f, 1f)]
            public float causticScale = 0.25f; // 焦散贴图的平铺尺度

            public float causticBlendDistance = 3f; // 水面以下多少米内焦散逐渐消失

            [Header("Advanced Settings")] public DebugMode debug = DebugMode.Disabled;

            public enum DebugMode
            {
                Disabled, // 正常焦散：乘到目标颜色上
                WaterEffects, // 调试槽，当前不改混合
                Caustics // 用替换混合直接显示焦散
            }
        }
    }
}