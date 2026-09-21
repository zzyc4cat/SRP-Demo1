using UnityEngine;
using UnityEngine.Rendering.Universal;

namespace CustomPP
{
    /// <summary>
    /// 自定义后处理 Renderer Feature。
    /// - 不依赖 URP Volume / 内置 PostProcess
    /// - 每个效果使用独立 Shader / Material
    /// - 运行时从场景中的 <see cref="CustomPostProcessManager"/> 读取开关与参数
    /// </summary>
    public sealed class CustomPostProcessFeature : ScriptableRendererFeature
    {
        /// <summary>Pass 插入 URP 渲染管线的位置。</summary>
        public enum InjectionPoint
        {
            BeforePostProcessing = 0, // 内置后处理之前（推荐，本方案关闭了内置 PP）
            AfterPostProcessing = 1,
            AfterRendering = 2
        }

        [System.Serializable]
        public class Settings
        {
            [Tooltip("Pass 注入点")]
            public InjectionPoint injectionPoint = InjectionPoint.BeforePostProcessing;

            [Tooltip("仅 Game / SceneView 相机执行，跳过 Preview 等")]
            public bool gameAndSceneOnly = true;

            [Tooltip("可选：手动指定各效果 Shader；留空则从 Resources/05.renderfeature 加载")]
            public CustomPostProcessMaterials.ShaderOverrides shaderOverrides =
                new CustomPostProcessMaterials.ShaderOverrides();
        }

        public Settings settings = new Settings();

        CustomPostProcessPass _pass;
        CustomPostProcessMaterials _materials;

        /// <summary>Feature 创建/域重载时调用：准备材质与 Pass。</summary>
        public override void Create()
        {
            _materials ??= new CustomPostProcessMaterials();
            _materials.EnsureCreated(settings.shaderOverrides);

            _pass = new CustomPostProcessPass(_materials);
            _pass.renderPassEvent = ToEvent(settings.injectionPoint);
        }

        /// <summary>每相机每帧：若有激活效果则入队自定义 Pass。</summary>
        public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
        {
            _materials ??= new CustomPostProcessMaterials();
            _materials.EnsureCreated(settings.shaderOverrides);
            if (!_materials.IsReady)
                return;

            // 过滤非游戏相机，避免 Scene 缩略图等重复开销
            if (settings.gameAndSceneOnly)
            {
                var t = renderingData.cameraData.cameraType;
                if (t != CameraType.Game && t != CameraType.SceneView)
                    return;
            }

            var manager = CustomPostProcessManager.Instance;
            if (manager == null || !manager.HasAnyActiveEffect())
                return;

            _pass.Setup(_materials, manager);
            // 声明需要颜色 + 深度（雾 / 描边 / 景深依赖深度图）
            _pass.ConfigureInput(ScriptableRenderPassInput.Color | ScriptableRenderPassInput.Depth);
            _pass.renderPassEvent = ToEvent(settings.injectionPoint);
            renderer.EnqueuePass(_pass);
        }

        protected override void Dispose(bool disposing)
        {
            _pass?.Dispose();
            _pass = null;
            _materials?.Dispose();
            _materials = null;
        }

        static RenderPassEvent ToEvent(InjectionPoint point)
        {
            switch (point)
            {
                case InjectionPoint.AfterPostProcessing:
                    return RenderPassEvent.AfterRenderingPostProcessing;
                case InjectionPoint.AfterRendering:
                    return RenderPassEvent.AfterRendering;
                default:
                    return RenderPassEvent.BeforeRenderingPostProcessing;
            }
        }
    }
}
