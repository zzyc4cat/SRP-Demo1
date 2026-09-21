using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace CustomPP
{
    /// <summary>
    /// 自定义后处理执行 Pass。
    /// 顺序：Copy → HeightFog → DepthFog → DoF → Bloom(Layer) → Outline → CA → Tonemap
    /// </summary>
    public sealed class CustomPostProcessPass : ScriptableRenderPass
    {
        const string ProfilerTag = "Custom PostProcess (RF)";

        static readonly int SourceTex2Id = Shader.PropertyToID("_SourceTex2");
        static readonly int Params0Id = Shader.PropertyToID("_PPParams0");
        static readonly int Params1Id = Shader.PropertyToID("_PPParams1");
        static readonly int ColorId = Shader.PropertyToID("_PPColor");

        static readonly int TempAId = Shader.PropertyToID("_CustomPP_TempA");
        static readonly int TempBId = Shader.PropertyToID("_CustomPP_TempB");
        static readonly int BloomTempId = Shader.PropertyToID("_CustomPP_BloomTemp");
        static readonly int BloomSrcCopyId = Shader.PropertyToID("_CustomPP_BloomSrcCopy");

        const int BloomPassPre = 0;
        const int BloomPassDown = 1;
        const int BloomPassUp = 2;
        const int BloomPassApply = 3;
        const int BloomPassAdditive = 4;

        static readonly ShaderTagId[] BloomShaderTags =
        {
            new ShaderTagId("UniversalForward"),
            new ShaderTagId("UniversalForwardOnly"),
            new ShaderTagId("SRPDefaultUnlit"),
            new ShaderTagId("LightweightForward")
        };

        CustomPostProcessMaterials _mats;
        CustomPostProcessManager _manager;
        readonly int[] _bloomMipIds = new int[6];

        RenderTexture _bloomSourceRT;
        RenderTexture _bloomResultRT;

        public CustomPostProcessPass(CustomPostProcessMaterials materials)
        {
            _mats = materials;
            for (int i = 0; i < _bloomMipIds.Length; i++)
                _bloomMipIds[i] = Shader.PropertyToID($"_CustomPP_BloomMip{i}");
        }

        public void Setup(CustomPostProcessMaterials materials, CustomPostProcessManager manager)
        {
            _mats = materials;
            _manager = manager;
        }

        public void Dispose()
        {
            ReleaseBloomRT(ref _bloomSourceRT);
            ReleaseBloomRT(ref _bloomResultRT);
        }

        static void ReleaseBloomRT(ref RenderTexture rt)
        {
            if (rt == null) return;
            rt.Release();
            CoreUtils.Destroy(rt);
            rt = null;
        }

        void EnsureBloomSourceRT(int width, int height)
        {
            if (_bloomSourceRT != null &&
                _bloomSourceRT.width == width &&
                _bloomSourceRT.height == height)
                return;

            ReleaseBloomRT(ref _bloomSourceRT);
            _bloomSourceRT = new RenderTexture(width, height, 24, RenderTextureFormat.ARGBHalf)
            {
                name = "CustomPP_BloomLayerSource",
                filterMode = FilterMode.Bilinear,
                wrapMode = TextureWrapMode.Clamp,
                antiAliasing = 1
            };
            _bloomSourceRT.Create();
        }

        void EnsureBloomResultRT(int width, int height)
        {
            if (_bloomResultRT != null &&
                _bloomResultRT.width == width &&
                _bloomResultRT.height == height)
                return;

            ReleaseBloomRT(ref _bloomResultRT);
            _bloomResultRT = new RenderTexture(width, height, 0, RenderTextureFormat.ARGBHalf)
            {
                name = "CustomPP_BloomResult",
                filterMode = FilterMode.Bilinear,
                wrapMode = TextureWrapMode.Clamp,
                antiAliasing = 1
            };
            _bloomResultRT.Create();
        }

        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            var desc = renderingData.cameraData.cameraTargetDescriptor;
            desc.depthBufferBits = 0;
            desc.msaaSamples = 1;
            cmd.GetTemporaryRT(TempAId, desc, FilterMode.Bilinear);
            cmd.GetTemporaryRT(TempBId, desc, FilterMode.Bilinear);
        }

        public override void OnCameraCleanup(CommandBuffer cmd)
        {
            if (cmd == null) return;
            cmd.ReleaseTemporaryRT(TempAId);
            cmd.ReleaseTemporaryRT(TempBId);
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            if (_mats == null || _manager == null || !_manager.HasAnyActiveEffect())
                return;

            var cmd = CommandBufferPool.Get(ProfilerTag);
            var cameraColor = renderingData.cameraData.renderer.cameraColorTargetHandle;

            if (_mats.copy != null)
                cmd.Blit(cameraColor, TempAId, _mats.copy, 0);
            else
                cmd.Blit(cameraColor, TempAId);

            int src = TempAId;
            int dst = TempBId;
            void Swap() => (src, dst) = (dst, src);

            var heightFog = _manager.heightFog;
            if (heightFog.IsActive && _mats.heightFog != null)
            {
                cmd.SetGlobalVector(Params0Id, new Vector4(
                    heightFog.strength, heightFog.baseHeight,
                    heightFog.heightFalloff, heightFog.noiseStrength));
                cmd.SetGlobalVector(Params1Id, new Vector4(heightFog.skyboxInfluence, 0f, 0f, 0f));
                cmd.SetGlobalColor(ColorId, heightFog.fogColor);
                cmd.Blit(src, dst, _mats.heightFog, 0);
                Swap();
            }

            var depthFog = _manager.depthFog;
            if (depthFog.IsActive && _mats.depthFog != null)
            {
                cmd.SetGlobalVector(Params0Id, new Vector4(
                    depthFog.density, depthFog.startDistance,
                    depthFog.endDistance, 0f));
                cmd.SetGlobalVector(Params1Id, new Vector4(
                    depthFog.skyboxInfluence, depthFog.noiseStrength, 0f, 0f));
                cmd.SetGlobalColor(ColorId, depthFog.fogColor);
                cmd.Blit(src, dst, _mats.depthFog, 0);
                Swap();
            }

            var dof = _manager.depthOfField;
            if (dof.IsActive && _mats.depthOfField != null)
            {
                cmd.SetGlobalVector(Params0Id, new Vector4(
                    dof.focusDistance, dof.blurRadius,
                    dof.nearTransition, dof.farTransition));
                cmd.Blit(src, dst, _mats.depthOfField, 0);
                Swap();
            }

            var bloom = _manager.bloom;
            if (bloom.IsActive && _mats.bloom != null)
            {
                ExecuteBloomLayered(context, cmd, ref renderingData, src, dst, bloom);
                Swap();
            }

            var outline = _manager.outline;
            if (outline.IsActive && _mats.outline != null)
            {
                cmd.SetGlobalVector(Params0Id, new Vector4(
                    outline.thickness, outline.depthSensitivity,
                    outline.colorSensitivity, outline.strength));
                cmd.SetGlobalColor(ColorId, outline.color);
                cmd.Blit(src, dst, _mats.outline, 0);
                Swap();
            }

            var ca = _manager.chromaticAberration;
            if (ca.IsActive && _mats.chromaticAberration != null)
            {
                cmd.SetGlobalVector(Params0Id, new Vector4(ca.intensity, ca.start, 0f, 0f));
                cmd.Blit(src, dst, _mats.chromaticAberration, 0);
                Swap();
            }

            var tonemap = _manager.tonemapping;
            if (tonemap.IsActive && _mats.tonemapping != null)
            {
                cmd.SetGlobalVector(Params0Id, new Vector4(
                    tonemap.exposure, tonemap.contrast,
                    tonemap.saturation, (float)tonemap.mode));
                cmd.Blit(src, dst, _mats.tonemapping, 0);
                Swap();
            }

            cmd.Blit(src, cameraColor);
            context.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
        }

        /// <summary>
        /// Layer 限定 Bloom：
        /// 在独立 RT（自带深度）上 Clear 为黑，仅用真实材质重绘 layerMask 物体，
        /// 再对该 RT 做 Bloom，最后叠回全场景色。
        /// </summary>
        void ExecuteBloomLayered(
            ScriptableRenderContext context,
            CommandBuffer cmd,
            ref RenderingData renderingData,
            int src,
            int dst,
            CustomPostProcessManager.BloomSettings bloom)
        {
            var camDesc = renderingData.cameraData.cameraTargetDescriptor;
            int width = Mathf.Max(1, camDesc.width);
            int height = Mathf.Max(1, camDesc.height);
            int layerMask = bloom.layerMask.value;

            EnsureBloomSourceRT(width, height);

            // 立即清屏，避免未初始化内容
            var prevActive = RenderTexture.active;
            Graphics.SetRenderTarget(_bloomSourceRT);
            GL.Clear(true, true, Color.black);
            Graphics.SetRenderTarget(prevActive);

            cmd.SetRenderTarget(_bloomSourceRT);
            cmd.ClearRenderTarget(true, true, Color.black);
            context.ExecuteCommandBuffer(cmd);
            cmd.Clear();

            // 用物体自己的材质重绘（不要 override）— 只画指定 Layer
            var drawingOpaque = CreateDrawingSettings(
                BloomShaderTags[0], ref renderingData, SortingCriteria.CommonOpaque);
            for (int i = 1; i < BloomShaderTags.Length; i++)
                drawingOpaque.SetShaderPassName(i, BloomShaderTags[i]);
            var filterOpaque = new FilteringSettings(RenderQueueRange.opaque, layerMask);
            context.DrawRenderers(renderingData.cullResults, ref drawingOpaque, ref filterOpaque);

            var drawingTransparent = CreateDrawingSettings(
                BloomShaderTags[0], ref renderingData, SortingCriteria.CommonTransparent);
            for (int i = 1; i < BloomShaderTags.Length; i++)
                drawingTransparent.SetShaderPassName(i, BloomShaderTags[i]);
            var filterTransparent = new FilteringSettings(RenderQueueRange.transparent, layerMask);
            context.DrawRenderers(renderingData.cullResults, ref drawingTransparent, ref filterTransparent);

            // 金字塔 Bloom：先把 Layer 源拷到临时 RT（属性 ID），再 Prefilter
            // 避免 CommandBuffer.Blit(RenderTexture → mip, bloomMat) 误绑全场景 _MainTex
            int iterations = Mathf.Clamp(bloom.iterations, 2, _bloomMipIds.Length);
            var fullDesc = camDesc;
            fullDesc.depthBufferBits = 0;
            fullDesc.msaaSamples = 1;

            var desc = fullDesc;
            desc.width = Mathf.Max(1, width / 2);
            desc.height = Mathf.Max(1, height / 2);

            cmd.GetTemporaryRT(BloomSrcCopyId, fullDesc, FilterMode.Bilinear);
            cmd.Blit(_bloomSourceRT, BloomSrcCopyId); // 无 Material 的可靠拷贝

            cmd.GetTemporaryRT(_bloomMipIds[0], desc, FilterMode.Bilinear);
            cmd.SetGlobalVector(Params0Id, new Vector4(bloom.threshold, bloom.softKnee, 0f, 0f));
            cmd.Blit(BloomSrcCopyId, _bloomMipIds[0], _mats.bloom, BloomPassPre);

            for (int i = 1; i < iterations; i++)
            {
                desc.width = Mathf.Max(1, desc.width / 2);
                desc.height = Mathf.Max(1, desc.height / 2);
                cmd.GetTemporaryRT(_bloomMipIds[i], desc, FilterMode.Bilinear);
                cmd.Blit(_bloomMipIds[i - 1], _bloomMipIds[i], _mats.bloom, BloomPassDown);
            }

            for (int i = iterations - 2; i >= 0; i--)
            {
                int div = 1 << (i + 1);
                var upDesc = fullDesc;
                upDesc.width = Mathf.Max(1, width / div);
                upDesc.height = Mathf.Max(1, height / div);

                // 上采样模糊高一层 → Temp，再把低一层加进去（不依赖 _SourceTex2）
                cmd.GetTemporaryRT(BloomTempId, upDesc, FilterMode.Bilinear);
                cmd.SetGlobalVector(Params0Id, new Vector4(Mathf.Lerp(0.5f, 2.5f, bloom.scatter), 0f, 0f, 0f));
                cmd.Blit(_bloomMipIds[i + 1], BloomTempId, _mats.bloom, BloomPassUp);
                // Load 目标后加性合并低层 mip
                cmd.SetRenderTarget(BloomTempId,
                    RenderBufferLoadAction.Load, RenderBufferStoreAction.Store,
                    RenderBufferLoadAction.DontCare, RenderBufferStoreAction.DontCare);
                cmd.Blit(_bloomMipIds[i], BuiltinRenderTextureType.CurrentActive, _mats.bloom, BloomPassAdditive);
                cmd.Blit(BloomTempId, _bloomMipIds[i]);
                cmd.ReleaseTemporaryRT(BloomTempId);
            }

            // 最终 bloom 拷到真实 RenderTexture，再用 Material.SetTexture 绑定（SetGlobalTexture+临时RT 会失败变成白）
            int bloomW = Mathf.Max(1, width / 2);
            int bloomH = Mathf.Max(1, height / 2);
            EnsureBloomResultRT(bloomW, bloomH);
            cmd.Blit(_bloomMipIds[0], _bloomResultRT);
            _mats.bloom.SetTexture(SourceTex2Id, _bloomResultRT);
            cmd.SetGlobalVector(Params0Id, new Vector4(bloom.intensity, 0f, 0f, 0f));
            cmd.SetGlobalColor(ColorId, bloom.tint);
            cmd.Blit(src, dst, _mats.bloom, BloomPassApply);

            for (int i = 0; i < iterations; i++)
                cmd.ReleaseTemporaryRT(_bloomMipIds[i]);
            cmd.ReleaseTemporaryRT(BloomSrcCopyId);
        }
    }
}
