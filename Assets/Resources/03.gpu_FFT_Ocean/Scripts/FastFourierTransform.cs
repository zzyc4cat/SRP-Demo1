using UnityEngine;

namespace FFTOcean
{
    /// <summary>
    /// Stockham GPU FFT / IFFT（gasgiant FFT-Ocean）。
    /// <para>效果段：</para>
    /// <list type="bullet">
    /// <item>[Precompute] 旋转因子与蝶形索引表</item>
    /// <item>[IFFT2D] 横→纵逆向蝶形（ping-pong）</item>
    /// <item>[Post] Permute 符号交替 + Scale 归一化</item>
    /// </list>
    /// </summary>
    public class FastFourierTransform
    {
        const int LocalX = 8;
        const int LocalY = 8;

        readonly int size;
        readonly ComputeShader fftShader;
        readonly RenderTexture precomputedData;

        readonly int kernelPrecompute;
        readonly int kernelHorizontalFft;
        readonly int kernelVerticalFft;
        readonly int kernelHorizontalIfft;
        readonly int kernelVerticalIfft;
        readonly int kernelScale;
        readonly int kernelPermute;

        static readonly int IdPrecomputeBuffer = Shader.PropertyToID("PrecomputeBuffer");
        static readonly int IdPrecomputedData = Shader.PropertyToID("PrecomputedData");
        static readonly int IdBuffer0 = Shader.PropertyToID("Buffer0");
        static readonly int IdBuffer1 = Shader.PropertyToID("Buffer1");
        static readonly int IdSize = Shader.PropertyToID("Size");
        static readonly int IdStep = Shader.PropertyToID("Step");
        static readonly int IdPingPong = Shader.PropertyToID("PingPong");

        public FastFourierTransform(int size, ComputeShader fftShader)
        {
            this.size = size;
            this.fftShader = fftShader;

            kernelPrecompute = fftShader.FindKernel("PrecomputeTwiddleFactorsAndInputIndices");
            kernelHorizontalFft = fftShader.FindKernel("HorizontalStepFFT");
            kernelVerticalFft = fftShader.FindKernel("VerticalStepFFT");
            kernelHorizontalIfft = fftShader.FindKernel("HorizontalStepInverseFFT");
            kernelVerticalIfft = fftShader.FindKernel("VerticalStepInverseFFT");
            kernelScale = fftShader.FindKernel("Scale");
            kernelPermute = fftShader.FindKernel("Permute");

            // ----- [Precompute] -----
            precomputedData = PrecomputeTwiddleFactorsAndInputIndices();
        }

        public static RenderTexture CreateRenderTexture(
            int size,
            RenderTextureFormat format = RenderTextureFormat.RGFloat,
            bool useMips = false)
        {
            var rt = new RenderTexture(size, size, 0, format, RenderTextureReadWrite.Linear)
            {
                useMipMap = useMips,
                autoGenerateMips = false,
                anisoLevel = 6,
                filterMode = FilterMode.Trilinear,
                wrapMode = TextureWrapMode.Repeat,
                enableRandomWrite = true
            };
            rt.Create();
            return rt;
        }

        /// <summary>
        /// [IFFT2D] 频域 → 空间域。海洋位移 / 导数四路缓冲共用此路径。
        /// </summary>
        public void IFFT2D(
            RenderTexture input,
            RenderTexture buffer,
            bool outputToInput = false,
            bool scale = true,
            bool permute = false)
        {
            int logSize = (int)Mathf.Log(size, 2);
            bool pingPong = false;

            // ----- 横向逆向蝶形 -----
            fftShader.SetTexture(kernelHorizontalIfft, IdPrecomputedData, precomputedData);
            fftShader.SetTexture(kernelHorizontalIfft, IdBuffer0, input);
            fftShader.SetTexture(kernelHorizontalIfft, IdBuffer1, buffer);
            for (int i = 0; i < logSize; i++)
            {
                pingPong = !pingPong;
                fftShader.SetInt(IdStep, i);
                fftShader.SetBool(IdPingPong, pingPong);
                fftShader.Dispatch(kernelHorizontalIfft, size / LocalX, size / LocalY, 1);
            }

            // ----- 纵向逆向蝶形 -----
            fftShader.SetTexture(kernelVerticalIfft, IdPrecomputedData, precomputedData);
            fftShader.SetTexture(kernelVerticalIfft, IdBuffer0, input);
            fftShader.SetTexture(kernelVerticalIfft, IdBuffer1, buffer);
            for (int i = 0; i < logSize; i++)
            {
                pingPong = !pingPong;
                fftShader.SetInt(IdStep, i);
                fftShader.SetBool(IdPingPong, pingPong);
                fftShader.Dispatch(kernelVerticalIfft, size / LocalX, size / LocalY, 1);
            }

            if (pingPong && outputToInput)
                Graphics.Blit(buffer, input);
            if (!pingPong && !outputToInput)
                Graphics.Blit(input, buffer);

            var result = outputToInput ? input : buffer;
            // ----- [Post] -----
            if (permute)
            {
                fftShader.SetInt(IdSize, size);
                fftShader.SetTexture(kernelPermute, IdBuffer0, result);
                fftShader.Dispatch(kernelPermute, size / LocalX, size / LocalY, 1);
            }

            if (scale)
            {
                fftShader.SetInt(IdSize, size);
                fftShader.SetTexture(kernelScale, IdBuffer0, result);
                fftShader.Dispatch(kernelScale, size / LocalX, size / LocalY, 1);
            }
        }

        RenderTexture PrecomputeTwiddleFactorsAndInputIndices()
        {
            int logSize = (int)Mathf.Log(size, 2);
            var rt = new RenderTexture(logSize, size, 0, RenderTextureFormat.ARGBFloat, RenderTextureReadWrite.Linear)
            {
                filterMode = FilterMode.Point,
                wrapMode = TextureWrapMode.Repeat,
                enableRandomWrite = true
            };
            rt.Create();

            fftShader.SetInt(IdSize, size);
            fftShader.SetTexture(kernelPrecompute, IdPrecomputeBuffer, rt);
            fftShader.Dispatch(kernelPrecompute, logSize, size / 2 / LocalY, 1);
            return rt;
        }

        public void Dispose()
        {
            if (precomputedData != null)
                precomputedData.Release();
        }
    }
}
