using UnityEngine;

namespace FFTOcean
{
    /// <summary>写入 Compute 的频谱参数块（与 InitialSpectrum.SpectrumParameters 对齐）。</summary>
    public struct SpectrumSettings
    {
        public float scale;
        public float angle;
        public float spreadBlend;
        public float swell;
        public float alpha;
        public float peakOmega;
        public float gamma;
        public float shortWavesFade;
    }

    /// <summary>
    /// Inspector 友好的谱参数。
    /// [Local] 局地风浪；[Swell] 涌浪；二者在 InitialSpectrum 中叠加。
    /// </summary>
    [System.Serializable]
    public struct DisplaySpectrumSettings
    {
        [Range(0, 1)] public float scale;
        public float windSpeed;
        public float windDirection;
        public float fetch;
        [Range(0, 1)] public float spreadBlend;
        [Range(0, 1)] public float swell;
        public float peakEnhancement;
        public float shortWavesFade;
    }

    /// <summary>
    /// 海浪 ScriptableObject。
    /// <para>[JONSWAP] α / ωp 由风速与 fetch 推导；λ 控制水平位移强度（影响 Jacobian 白沫）。</para>
    /// </summary>
    [CreateAssetMenu(fileName = "WavesSettings", menuName = "FFTOcean/Waves Settings")]
    public class WavesSettings : ScriptableObject
    {
        public float g = 9.81f;
        public float depth = 20f;
        [Range(0, 1)] public float lambda = 1f; // Tessendorf 水平挤压系数
        public DisplaySpectrumSettings local = new DisplaySpectrumSettings
        {
            scale = 0.35f,
            windSpeed = 8f,
            windDirection = 45f,
            fetch = 100000f,
            spreadBlend = 1f,
            swell = 0.2f,
            peakEnhancement = 3.3f,
            shortWavesFade = 0.01f
        };
        public DisplaySpectrumSettings swell = new DisplaySpectrumSettings
        {
            scale = 0.25f,
            windSpeed = 12f,
            windDirection = 30f,
            fetch = 300000f,
            spreadBlend = 1f,
            swell = 0.8f,
            peakEnhancement = 3.3f,
            shortWavesFade = 0.01f
        };

        SpectrumSettings[] spectrums = new SpectrumSettings[2];

        static readonly int GProp = Shader.PropertyToID("GravityAcceleration");
        static readonly int DepthProp = Shader.PropertyToID("Depth");
        static readonly int SpectrumsProp = Shader.PropertyToID("Spectrums");

        public void SetParametersToShader(ComputeShader shader, int kernelIndex, ComputeBuffer paramsBuffer)
        {
            shader.SetFloat(GProp, g);
            shader.SetFloat(DepthProp, depth);
            FillSettingsStruct(local, ref spectrums[0]);
            FillSettingsStruct(swell, ref spectrums[1]);
            paramsBuffer.SetData(spectrums);
            shader.SetBuffer(kernelIndex, SpectrumsProp, paramsBuffer);
        }

        void FillSettingsStruct(DisplaySpectrumSettings display, ref SpectrumSettings settings)
        {
            settings.scale = display.scale;
            settings.angle = display.windDirection / 180f * Mathf.PI;
            settings.spreadBlend = display.spreadBlend;
            settings.swell = Mathf.Clamp(display.swell, 0.01f, 1f);
            settings.alpha = JonswapAlpha(g, display.fetch, display.windSpeed);
            settings.peakOmega = JonswapPeakFrequency(g, display.fetch, display.windSpeed);
            settings.gamma = display.peakEnhancement;
            settings.shortWavesFade = display.shortWavesFade;
        }

        static float JonswapAlpha(float g, float fetch, float windSpeed)
        {
            windSpeed = Mathf.Max(windSpeed, 0.1f);
            return 0.076f * Mathf.Pow(g * fetch / windSpeed / windSpeed, -0.22f);
        }

        static float JonswapPeakFrequency(float g, float fetch, float windSpeed)
        {
            windSpeed = Mathf.Max(windSpeed, 0.1f);
            return 22f * Mathf.Pow(windSpeed * fetch / g / g, -0.33f);
        }
    }
}
