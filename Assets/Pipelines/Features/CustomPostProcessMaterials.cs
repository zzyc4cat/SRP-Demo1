using UnityEngine;
using UnityEngine.Rendering;

namespace CustomPP
{
    /// <summary>
    /// 各效果独立 Material 集合。
    /// Feature 负责创建/销毁，Pass 只负责按效果取用。
    /// </summary>
    public sealed class CustomPostProcessMaterials
    {
        public const string Root = "05.renderfeature/Shaders/";

        public Material copy;
        public Material heightFog;
        public Material depthFog;
        public Material depthOfField;
        public Material bloom; // Pass: 0 Pre / 1 Down / 2 Up / 3 Apply
        public Material bloomLayerMask; // Layer 白色遮罩
        public Material bloomMaskMultiply; // dest *= mask
        public Material outline;
        public Material chromaticAberration;
        public Material tonemapping;

        /// <summary>从 Resources / Shader.Find 创建全部材质；已有则跳过。</summary>
        public void EnsureCreated(ShaderOverrides overrides = null)
        {
            copy = CreateIfNeeded(copy, overrides?.copy, Root + "05.renderfeature_Copy", "ZZY/05.renderfeature/Copy");
            heightFog = CreateIfNeeded(heightFog, overrides?.heightFog, Root + "05.renderfeature_HeightFog", "ZZY/05.renderfeature/HeightFog");
            depthFog = CreateIfNeeded(depthFog, overrides?.depthFog, Root + "05.renderfeature_DepthFog", "ZZY/05.renderfeature/DepthFog");
            depthOfField = CreateIfNeeded(depthOfField, overrides?.depthOfField, Root + "05.renderfeature_DepthOfField", "ZZY/05.renderfeature/DepthOfField");
            bloom = CreateIfNeeded(bloom, overrides?.bloom, Root + "05.renderfeature_Bloom", "ZZY/05.renderfeature/Bloom");
            bloomLayerMask = CreateIfNeeded(bloomLayerMask, null, Root + "05.renderfeature_BloomLayerMask", "ZZY/05.renderfeature/BloomLayerMask");
            bloomMaskMultiply = CreateIfNeeded(bloomMaskMultiply, null, Root + "05.renderfeature_BloomMaskMultiply", "ZZY/05.renderfeature/BloomMaskMultiply");
            outline = CreateIfNeeded(outline, overrides?.outline, Root + "05.renderfeature_Outline", "ZZY/05.renderfeature/Outline");
            chromaticAberration = CreateIfNeeded(chromaticAberration, overrides?.chromaticAberration, Root + "05.renderfeature_ChromaticAberration", "ZZY/05.renderfeature/ChromaticAberration");
            tonemapping = CreateIfNeeded(tonemapping, overrides?.tonemapping, Root + "05.renderfeature_Tonemapping", "ZZY/05.renderfeature/Tonemapping");
        }

        public bool IsReady =>
            heightFog != null || depthFog != null || depthOfField != null || bloom != null ||
            outline != null || chromaticAberration != null || tonemapping != null;

        public void Dispose()
        {
            DestroyMat(ref copy);
            DestroyMat(ref heightFog);
            DestroyMat(ref depthFog);
            DestroyMat(ref depthOfField);
            DestroyMat(ref bloom);
            DestroyMat(ref bloomLayerMask);
            DestroyMat(ref bloomMaskMultiply);
            DestroyMat(ref outline);
            DestroyMat(ref chromaticAberration);
            DestroyMat(ref tonemapping);
        }

        static Material CreateIfNeeded(Material current, Shader overrideShader, string resourcesPath, string shaderName)
        {
            if (current != null)
                return current;

            Shader shader = overrideShader;
            if (shader == null)
                shader = Resources.Load<Shader>(resourcesPath);
            if (shader == null)
                shader = Shader.Find(shaderName);
            if (shader == null)
            {
                Debug.LogError($"[CustomPP] Shader not found: {shaderName} / Resources:{resourcesPath}");
                return null;
            }

            return CoreUtils.CreateEngineMaterial(shader);
        }

        static void DestroyMat(ref Material mat)
        {
            if (mat != null)
            {
                CoreUtils.Destroy(mat);
                mat = null;
            }
        }

        [System.Serializable]
        public class ShaderOverrides
        {
            public Shader copy;
            public Shader heightFog;
            public Shader depthFog;
            public Shader depthOfField;
            public Shader bloom;
            public Shader outline;
            public Shader chromaticAberration;
            public Shader tonemapping;
        }
    }
}
