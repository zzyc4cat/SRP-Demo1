using System;
using UnityEngine;

namespace CustomPP
{
    /// <summary>
    /// 自定义后处理总管理器。
    /// 挂在场景物体上，集中配置各效果开关与参数；
    /// <see cref="CustomPostProcessFeature"/> 每帧通过 <see cref="Instance"/> 读取。
    /// 不使用 URP Volume / IPostProcessComponent。
    /// </summary>
    [ExecuteAlways]
    [DisallowMultipleComponent]
    [AddComponentMenu("Custom PP/Custom Post Process Manager")]
    public sealed class CustomPostProcessManager : MonoBehaviour
    {
        /// <summary>当前激活的管理器单例（场景中应只保留一个）。</summary>
        public static CustomPostProcessManager Instance { get; private set; }

        [Header("Master")]
        [Tooltip("总开关：关闭后 Feature 直接跳过整条效果链")]
        public bool enablePostProcess = true;

        [Header("Effects")]
        [Tooltip("高度雾（世界 Y）")]
        public HeightFogSettings heightFog = new HeightFogSettings { enabled = true };

        [Tooltip("深度雾 / 距离雾（相机视线距离）")]
        public DepthFogSettings depthFog = new DepthFogSettings { enabled = true };

        [Tooltip("景深")]
        public DepthOfFieldSettings depthOfField = new DepthOfFieldSettings { enabled = true };

        [Tooltip("辉光 Bloom（仅指定 Layer）")]
        public BloomSettings bloom = new BloomSettings { enabled = true };

        [Tooltip("屏幕空间描边")]
        public ScreenOutlineSettings outline = new ScreenOutlineSettings { enabled = true };

        [Tooltip("径向色差")]
        public ChromaticAberrationSettings chromaticAberration = new ChromaticAberrationSettings { enabled = true };

        [Tooltip("色调映射")]
        public TonemappingSettings tonemapping = new TonemappingSettings { enabled = true };

        void OnEnable() => Instance = this;

        void OnDisable()
        {
            if (Instance == this)
                Instance = null;
        }

        void OnValidate()
        {
            if (isActiveAndEnabled)
                Instance = this;
        }

        /// <summary>是否有任意效果需要执行。</summary>
        public bool HasAnyActiveEffect()
        {
            if (!enablePostProcess || !isActiveAndEnabled)
                return false;

            return heightFog.IsActive
                   || depthFog.IsActive
                   || depthOfField.IsActive
                   || bloom.IsActive
                   || outline.IsActive
                   || chromaticAberration.IsActive
                   || tonemapping.IsActive;
        }

        // ------------------------------------------------------------------
        // 各效果参数块
        // ------------------------------------------------------------------

        /// <summary>高度雾：沿世界高度分布，贴地浓、越高越稀。</summary>
        [Serializable]
        public class HeightFogSettings
        {
            public bool enabled = true;
            public Color fogColor = new Color(0.62f, 0.72f, 0.82f, 1f);
            [Range(0f, 2f)] public float strength = 0.85f;            // 整体强度
            public float baseHeight = 0f;                               // 雾最浓处的世界 Y
            [Range(0.001f, 2f)] public float heightFalloff = 0.18f;   // 向上衰减速度
            [Range(0f, 1f)] public float skyboxInfluence = 0.25f;
            [Range(0f, 1f)] public float noiseStrength = 0.2f;
            public bool IsActive => enabled && strength > 0.0001f;
        }

        /// <summary>深度雾：沿相机视线距离变浓。</summary>
        [Serializable]
        public class DepthFogSettings
        {
            public bool enabled = true;
            public Color fogColor = new Color(0.55f, 0.65f, 0.78f, 1f);
            [Range(0f, 0.2f)] public float density = 0.04f;           // 指数雾浓度 / 线性雾强度
            public float startDistance = 3f;                            // 起雾距离
            [Tooltip("<= start 时用指数雾；> start 时用线性雾（start→end）")]
            public float endDistance = 0f;
            [Range(0f, 1f)] public float skyboxInfluence = 0.45f;
            [Range(0f, 1f)] public float noiseStrength = 0.15f;
            public bool IsActive => enabled && density > 0.0001f;
        }

        /// <summary>景深参数。</summary>
        [Serializable]
        public class DepthOfFieldSettings
        {
            public bool enabled = true;
            public float focusDistance = 10f;
            [Range(0f, 8f)] public float blurRadius = 2.2f;
            public float nearTransition = 3f;
            public float farTransition = 8f;
            public bool IsActive => enabled && blurRadius > 0.01f;
        }

        /// <summary>Bloom：仅对 layerMask 内物体提取并叠加辉光。</summary>
        [Serializable]
        public class BloomSettings
        {
            public bool enabled = true;

            [Tooltip("只对这些 Layer 上的物体做 Bloom 提取（遮罩 × 场景色）")]
            public LayerMask layerMask = 1 << 13; // 默认 Bloom

            [Range(0f, 5f)] public float intensity = 1.1f;
            [Range(0f, 5f)] public float threshold = 0.85f;
            [Range(0f, 1f)] public float softKnee = 0.5f;
            [Range(0f, 1f)] public float scatter = 0.7f;
            public Color tint = new Color(1f, 0.92f, 0.85f, 1f);
            [Range(2, 6)] public int iterations = 4;
            public bool IsActive => enabled && intensity > 0.001f && layerMask.value != 0;
        }

        /// <summary>屏幕描边参数。</summary>
        [Serializable]
        public class ScreenOutlineSettings
        {
            public bool enabled = true;
            public Color color = new Color(0.08f, 0.07f, 0.1f, 1f);
            [Range(0.5f, 4f)] public float thickness = 1.25f;
            [Range(0.1f, 10f)] public float depthSensitivity = 1.8f;
            [Range(0f, 5f)] public float colorSensitivity = 0.7f;
            [Range(0f, 1f)] public float strength = 0.85f;
            public bool IsActive => enabled && strength > 0.001f;
        }

        /// <summary>色差参数。</summary>
        [Serializable]
        public class ChromaticAberrationSettings
        {
            public bool enabled = true;
            [Range(0f, 1f)] public float intensity = 0.28f;
            [Range(0f, 1f)] public float start = 0.25f;
            public bool IsActive => enabled && intensity > 0.001f;
        }

        public enum TonemapMode
        {
            Reinhard = 1,
            ACES = 2,
            Neutral = 3
        }

        /// <summary>色调映射参数。</summary>
        [Serializable]
        public class TonemappingSettings
        {
            public bool enabled = true;
            public TonemapMode mode = TonemapMode.ACES;
            [Range(0.1f, 5f)] public float exposure = 1.05f;
            [Range(0.2f, 2f)] public float contrast = 1.05f;
            [Range(0f, 2f)] public float saturation = 1.1f;
            public bool IsActive => enabled;
        }
    }
}
