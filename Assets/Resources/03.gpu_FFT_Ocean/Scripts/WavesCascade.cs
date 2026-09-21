using System;
using UnityEngine;

namespace FFTOcean
{
    /// <summary>
    /// 单频带 FFT 级联。
    /// <para>效果段：</para>
    /// <list type="number">
    /// <item>[Initial] JONSWAP → H0 / WavesData</item>
    /// <item>[Time] 相位推进，打包 DxDz / Dy / 导数频谱</item>
    /// <item>[IFFT] 四路 Stockham 逆变换到空间域</item>
    /// <item>[Merge] Displace + Derivatives + Jacobian Turbulence（白沫）</item>
    /// </list>
    /// </summary>
    public class WavesCascade : IDisposable
    {
        public RenderTexture Displacement => displacement;
        public RenderTexture Derivatives => derivatives;
        public RenderTexture Turbulence => turbulence;

        readonly int size;
        readonly ComputeShader initialSpectrumShader;
        readonly ComputeShader timeDependentSpectrumShader;
        readonly ComputeShader texturesMergerShader;
        readonly FastFourierTransform fft;
        readonly Texture2D gaussianNoise;
        readonly ComputeBuffer paramsBuffer;

        readonly RenderTexture initialSpectrum;
        readonly RenderTexture precomputedData;
        readonly RenderTexture buffer;
        readonly RenderTexture DxDz;
        readonly RenderTexture DyDxz;
        readonly RenderTexture DyxDyz;
        readonly RenderTexture DxxDzz;
        readonly RenderTexture displacement;
        readonly RenderTexture derivatives;
        readonly RenderTexture turbulence;

        float lambda;

        const int LocalX = 8;
        const int LocalY = 8;

        readonly int kernelInitialSpectrum;
        readonly int kernelConjugateSpectrum;
        readonly int kernelTimeDependent;
        readonly int kernelResultTextures;

        static readonly int SizeProp = Shader.PropertyToID("Size");
        static readonly int LengthScaleProp = Shader.PropertyToID("LengthScale");
        static readonly int CutoffHighProp = Shader.PropertyToID("CutoffHigh");
        static readonly int CutoffLowProp = Shader.PropertyToID("CutoffLow");
        static readonly int NoiseProp = Shader.PropertyToID("Noise");
        static readonly int H0Prop = Shader.PropertyToID("H0");
        static readonly int H0KProp = Shader.PropertyToID("H0K");
        static readonly int WavesDataProp = Shader.PropertyToID("WavesData");
        static readonly int TimeProp = Shader.PropertyToID("Time");
        static readonly int DxDzProp = Shader.PropertyToID("Dx_Dz");
        static readonly int DyDxzProp = Shader.PropertyToID("Dy_Dxz");
        static readonly int DyxDyzProp = Shader.PropertyToID("Dyx_Dyz");
        static readonly int DxxDzzProp = Shader.PropertyToID("Dxx_Dzz");
        static readonly int LambdaProp = Shader.PropertyToID("Lambda");
        static readonly int DisplacementProp = Shader.PropertyToID("Displacement");
        static readonly int DerivativesProp = Shader.PropertyToID("Derivatives");
        static readonly int TurbulenceProp = Shader.PropertyToID("Turbulence");

        public WavesCascade(
            int size,
            ComputeShader initialSpectrumShader,
            ComputeShader timeDependentSpectrumShader,
            ComputeShader texturesMergerShader,
            FastFourierTransform fft,
            Texture2D gaussianNoise)
        {
            this.size = size;
            this.initialSpectrumShader = initialSpectrumShader;
            this.timeDependentSpectrumShader = timeDependentSpectrumShader;
            this.texturesMergerShader = texturesMergerShader;
            this.fft = fft;
            this.gaussianNoise = gaussianNoise;

            kernelInitialSpectrum = initialSpectrumShader.FindKernel("CalculateInitialSpectrum");
            kernelConjugateSpectrum = initialSpectrumShader.FindKernel("CalculateConjugatedSpectrum");
            kernelTimeDependent = timeDependentSpectrumShader.FindKernel("CalculateAmplitudes");
            kernelResultTextures = texturesMergerShader.FindKernel("FillResultTextures");

            initialSpectrum = FastFourierTransform.CreateRenderTexture(size, RenderTextureFormat.ARGBFloat);
            precomputedData = FastFourierTransform.CreateRenderTexture(size, RenderTextureFormat.ARGBFloat);
            displacement = FastFourierTransform.CreateRenderTexture(size, RenderTextureFormat.ARGBFloat);
            derivatives = FastFourierTransform.CreateRenderTexture(size, RenderTextureFormat.ARGBFloat, true);
            turbulence = FastFourierTransform.CreateRenderTexture(size, RenderTextureFormat.ARGBFloat, true);
            paramsBuffer = new ComputeBuffer(2, 8 * sizeof(float));

            buffer = FastFourierTransform.CreateRenderTexture(size);
            DxDz = FastFourierTransform.CreateRenderTexture(size);
            DyDxz = FastFourierTransform.CreateRenderTexture(size);
            DyxDyz = FastFourierTransform.CreateRenderTexture(size);
            DxxDzz = FastFourierTransform.CreateRenderTexture(size);

            ClearTurbulence();
        }

        public void Dispose()
        {
            paramsBuffer?.Release();
            Release(initialSpectrum);
            Release(precomputedData);
            Release(displacement);
            Release(derivatives);
            Release(turbulence);
            Release(buffer);
            Release(DxDz);
            Release(DyDxz);
            Release(DyxDyz);
            Release(DxxDzz);
        }

        static void Release(RenderTexture rt)
        {
            if (rt == null) return;
            rt.Release();
        }

        /// <summary>
        /// [Whitecaps] 初始 J 置为 1（白色）：平静海面；折叠后 J 下降才起沫。
        /// </summary>
        void ClearTurbulence()
        {
            var active = RenderTexture.active;
            RenderTexture.active = turbulence;
            GL.Clear(false, true, Color.white);
            RenderTexture.active = active;
        }

        /// <summary>
        /// [Initial] 按 LengthScale 与波数截断计算 H0。
        /// </summary>
        public void CalculateInitials(WavesSettings wavesSettings, float lengthScale, float cutoffLow, float cutoffHigh)
        {
            lambda = wavesSettings.lambda;

            initialSpectrumShader.SetInt(SizeProp, size);
            initialSpectrumShader.SetFloat(LengthScaleProp, lengthScale);
            initialSpectrumShader.SetFloat(CutoffHighProp, cutoffHigh);
            initialSpectrumShader.SetFloat(CutoffLowProp, cutoffLow);
            wavesSettings.SetParametersToShader(initialSpectrumShader, kernelInitialSpectrum, paramsBuffer);

            initialSpectrumShader.SetTexture(kernelInitialSpectrum, H0KProp, buffer);
            initialSpectrumShader.SetTexture(kernelInitialSpectrum, WavesDataProp, precomputedData);
            initialSpectrumShader.SetTexture(kernelInitialSpectrum, NoiseProp, gaussianNoise);
            initialSpectrumShader.Dispatch(kernelInitialSpectrum, size / LocalX, size / LocalY, 1);

            initialSpectrumShader.SetTexture(kernelConjugateSpectrum, H0Prop, initialSpectrum);
            initialSpectrumShader.SetTexture(kernelConjugateSpectrum, H0KProp, buffer);
            initialSpectrumShader.SetInt(SizeProp, size);
            initialSpectrumShader.Dispatch(kernelConjugateSpectrum, size / LocalX, size / LocalY, 1);
        }

        /// <summary>
        /// [Time → IFFT → Merge] 每帧刷新位移、法线导数与 Jacobian 湍流。
        /// </summary>
        public void CalculateWavesAtTime(float time)
        {
            // ----- [Time] -----
            timeDependentSpectrumShader.SetTexture(kernelTimeDependent, DxDzProp, DxDz);
            timeDependentSpectrumShader.SetTexture(kernelTimeDependent, DyDxzProp, DyDxz);
            timeDependentSpectrumShader.SetTexture(kernelTimeDependent, DyxDyzProp, DyxDyz);
            timeDependentSpectrumShader.SetTexture(kernelTimeDependent, DxxDzzProp, DxxDzz);
            timeDependentSpectrumShader.SetTexture(kernelTimeDependent, H0Prop, initialSpectrum);
            timeDependentSpectrumShader.SetTexture(kernelTimeDependent, WavesDataProp, precomputedData);
            timeDependentSpectrumShader.SetFloat(TimeProp, time);
            timeDependentSpectrumShader.Dispatch(kernelTimeDependent, size / LocalX, size / LocalY, 1);

            // ----- [IFFT] 四路空间域 -----
            fft.IFFT2D(DxDz, buffer, true, false, true);
            fft.IFFT2D(DyDxz, buffer, true, false, true);
            fft.IFFT2D(DyxDyz, buffer, true, false, true);
            fft.IFFT2D(DxxDzz, buffer, true, false, true);

            // ----- [Merge] Displace / Deriv / Whitecaps -----
            texturesMergerShader.SetFloat("DeltaTime", Time.deltaTime);
            texturesMergerShader.SetTexture(kernelResultTextures, DxDzProp, DxDz);
            texturesMergerShader.SetTexture(kernelResultTextures, DyDxzProp, DyDxz);
            texturesMergerShader.SetTexture(kernelResultTextures, DyxDyzProp, DyxDyz);
            texturesMergerShader.SetTexture(kernelResultTextures, DxxDzzProp, DxxDzz);
            texturesMergerShader.SetTexture(kernelResultTextures, DisplacementProp, displacement);
            texturesMergerShader.SetTexture(kernelResultTextures, DerivativesProp, derivatives);
            texturesMergerShader.SetTexture(kernelResultTextures, TurbulenceProp, turbulence);
            texturesMergerShader.SetFloat(LambdaProp, lambda);
            texturesMergerShader.Dispatch(kernelResultTextures, size / LocalX, size / LocalY, 1);

            derivatives.GenerateMips();
            turbulence.GenerateMips();
        }
    }
}
