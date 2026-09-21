using UnityEngine;
using UnityEngine.Rendering;

namespace FFTOcean
{
    /// <summary>
    /// GPU FFT 海洋总控（gasgiant / Tessendorf 三频带）。
    /// <para>效果管线：</para>
    /// <list type="bullet">
    /// <item>[Init] 高斯噪声 + 三频带 InitialSpectrum（JONSWAP）</item>
    /// <item>[PerFrame] TimeSpectrum → Stockham IFFT → Displace/Deriv/Turbulence</item>
    /// <item>[Bind] 把三套 RT 绑到 ZZY/03.gpu_FFT_Ocean/FFTOcean 材质</item>
    /// <item>[Mesh] 运行时生成平面网格（顶点位移在 Shader）</item>
    /// </list>
    /// </summary>
    [ExecuteAlways]
    [RequireComponent(typeof(MeshFilter), typeof(MeshRenderer))]
    public class FFTOceanSimulator : MonoBehaviour
    {
        [Header("Compute")]
        [SerializeField] ComputeShader fftShader;
        [SerializeField] ComputeShader initialSpectrumShader;
        [SerializeField] ComputeShader timeDependentSpectrumShader;
        [SerializeField] ComputeShader texturesMergerShader;

        [Header("Settings")]
        [SerializeField] WavesSettings wavesSettings;
        [SerializeField] Material oceanMaterial;
        [SerializeField, Range(6, 9)] int fftPow = 8; // N = 2^fftPow
        [SerializeField] bool alwaysRecalculateInitials;
        [SerializeField] float lengthScale0 = 250f; // 大浪周期尺度
        [SerializeField] float lengthScale1 = 17f;  // 中频
        [SerializeField] float lengthScale2 = 5f;   // 高频细浪
        [SerializeField] float timeScale = 1f;

        [Header("Mesh")]
        [SerializeField] int meshSize = 256;
        [SerializeField] float meshLength = 200f;

        [Header("Debug")]
        [SerializeField] bool simulateInEditMode = true;

        public WavesCascade Cascade0 => cascade0;
        public WavesCascade Cascade1 => cascade1;
        public WavesCascade Cascade2 => cascade2;
        public WavesSettings Settings => wavesSettings;
        public Material OceanMaterial => oceanMaterial;
        public float LengthScale0 => lengthScale0;
        public float LengthScale1 => lengthScale1;
        public float LengthScale2 => lengthScale2;

        WavesCascade cascade0;
        WavesCascade cascade1;
        WavesCascade cascade2;
        FastFourierTransform fft;
        Texture2D gaussianNoise;
        int noiseSize = -1;
        bool initialized;
        int lastSize = -1;
        float lastMeshLength = -1f;
        int lastMeshSize = -1;

        static readonly int Disp0 = Shader.PropertyToID("_Displacement_c0");
        static readonly int Disp1 = Shader.PropertyToID("_Displacement_c1");
        static readonly int Disp2 = Shader.PropertyToID("_Displacement_c2");
        static readonly int Der0 = Shader.PropertyToID("_Derivatives_c0");
        static readonly int Der1 = Shader.PropertyToID("_Derivatives_c1");
        static readonly int Der2 = Shader.PropertyToID("_Derivatives_c2");
        static readonly int Turb0 = Shader.PropertyToID("_Turbulence_c0");
        static readonly int Turb1 = Shader.PropertyToID("_Turbulence_c1");
        static readonly int Turb2 = Shader.PropertyToID("_Turbulence_c2");
        static readonly int Len0 = Shader.PropertyToID("_LengthScale0");
        static readonly int Len1 = Shader.PropertyToID("_LengthScale1");
        static readonly int Len2 = Shader.PropertyToID("_LengthScale2");

        void OnEnable()
        {
            TryInitialize();
        }

        void OnDisable()
        {
            DisposeRuntime();
        }

        void OnDestroy()
        {
            DisposeRuntime();
        }

        void Update()
        {
            if (!Application.isPlaying && !simulateInEditMode)
                return;

            if (!initialized || NeedsRebuild())
                TryInitialize();

            if (!initialized)
                return;

            // ----- [Init optional] 参数热更时重算 H0 -----
            if (alwaysRecalculateInitials)
                InitialiseCascades();

            // ----- [PerFrame] 三频带时变 → IFFT → 合并贴图 -----
            float t = Application.isPlaying ? Time.time * timeScale : Time.realtimeSinceStartup * timeScale;
            cascade0.CalculateWavesAtTime(t);
            cascade1.CalculateWavesAtTime(t);
            cascade2.CalculateWavesAtTime(t);
            BindMaterialTextures();
        }

        public void ForceReinitialize()
        {
            DisposeRuntime();
            TryInitialize();
            if (initialized)
                TickWaves();
        }

        public void TickWaves(float? fixedTime = null)
        {
            if (!initialized || cascade0 == null) return;
            float t = fixedTime ?? (Application.isPlaying ? Time.time * timeScale : Time.realtimeSinceStartup * timeScale);
            cascade0.CalculateWavesAtTime(t);
            cascade1.CalculateWavesAtTime(t);
            cascade2.CalculateWavesAtTime(t);
            BindMaterialTextures();
        }

        bool NeedsRebuild()
        {
            int size = 1 << Mathf.Clamp(fftPow, 6, 9);
            return size != lastSize || meshSize != lastMeshSize || !Mathf.Approximately(meshLength, lastMeshLength);
        }

        void TryInitialize()
        {
            if (fftShader == null || initialSpectrumShader == null ||
                timeDependentSpectrumShader == null || texturesMergerShader == null)
                return;
            if (wavesSettings == null)
                return;

            DisposeRuntime();

            int size = 1 << Mathf.Clamp(fftPow, 6, 9);
            lastSize = size;
            lastMeshSize = meshSize;
            lastMeshLength = meshLength;

            // ----- [Init] FFT 旋转因子 + Box-Muller 噪声 + 三级联 -----
            fft = new FastFourierTransform(size, fftShader);
            if (gaussianNoise == null || noiseSize != size)
            {
                if (gaussianNoise != null)
                {
                    if (Application.isPlaying) Destroy(gaussianNoise);
                    else DestroyImmediate(gaussianNoise);
                }
                gaussianNoise = GenerateNoiseTexture(size);
                noiseSize = size;
            }
            cascade0 = new WavesCascade(size, initialSpectrumShader, timeDependentSpectrumShader, texturesMergerShader, fft, gaussianNoise);
            cascade1 = new WavesCascade(size, initialSpectrumShader, timeDependentSpectrumShader, texturesMergerShader, fft, gaussianNoise);
            cascade2 = new WavesCascade(size, initialSpectrumShader, timeDependentSpectrumShader, texturesMergerShader, fft, gaussianNoise);

            InitialiseCascades();
            BuildMesh();
            BindMaterialTextures();
            initialized = true;
        }

        /// <summary>
        /// [Spectrum] 按波数环带切分三级联，避免频带重叠造成能量重复。
        /// </summary>
        void InitialiseCascades()
        {
            float boundary1 = 2f * Mathf.PI / lengthScale1 * 6f;
            float boundary2 = 2f * Mathf.PI / lengthScale2 * 6f;
            cascade0.CalculateInitials(wavesSettings, lengthScale0, 0.0001f, boundary1);
            cascade1.CalculateInitials(wavesSettings, lengthScale1, boundary1, boundary2);
            cascade2.CalculateInitials(wavesSettings, lengthScale2, boundary2, 9999f);

            Shader.SetGlobalFloat("LengthScale0", lengthScale0);
            Shader.SetGlobalFloat("LengthScale1", lengthScale1);
            Shader.SetGlobalFloat("LengthScale2", lengthScale2);
        }

        /// <summary>
        /// [Bind] Displacement / Derivatives / Turbulence × 3 → 表面材质。
        /// </summary>
        void BindMaterialTextures()
        {
            if (oceanMaterial == null || cascade0 == null)
                return;

            oceanMaterial.SetTexture(Disp0, cascade0.Displacement);
            oceanMaterial.SetTexture(Der0, cascade0.Derivatives);
            oceanMaterial.SetTexture(Turb0, cascade0.Turbulence);
            oceanMaterial.SetTexture(Disp1, cascade1.Displacement);
            oceanMaterial.SetTexture(Der1, cascade1.Derivatives);
            oceanMaterial.SetTexture(Turb1, cascade1.Turbulence);
            oceanMaterial.SetTexture(Disp2, cascade2.Displacement);
            oceanMaterial.SetTexture(Der2, cascade2.Derivatives);
            oceanMaterial.SetTexture(Turb2, cascade2.Turbulence);
            oceanMaterial.SetFloat(Len0, lengthScale0);
            oceanMaterial.SetFloat(Len1, lengthScale1);
            oceanMaterial.SetFloat(Len2, lengthScale2);

            var mr = GetComponent<MeshRenderer>();
            if (mr != null && mr.sharedMaterial != oceanMaterial)
                mr.sharedMaterial = oceanMaterial;
        }

        /// <summary>
        /// [Mesh] 平面网格；实际起伏由顶点 Shader 采样 Displacement。
        /// </summary>
        void BuildMesh()
        {
            int n = Mathf.Max(8, meshSize);
            float length = Mathf.Max(1f, meshLength);
            var mesh = new Mesh { name = "FFTOceanMesh" };
            if ((n + 1) * (n + 1) > 65000)
                mesh.indexFormat = IndexFormat.UInt32;

            var verts = new Vector3[(n + 1) * (n + 1)];
            var uvs = new Vector2[(n + 1) * (n + 1)];
            var norms = new Vector3[(n + 1) * (n + 1)];
            var tris = new int[n * n * 6];

            float half = length * 0.5f;
            for (int z = 0; z <= n; z++)
            for (int x = 0; x <= n; x++)
            {
                int i = z * (n + 1) + x;
                float fx = x / (float)n;
                float fz = z / (float)n;
                verts[i] = new Vector3(fx * length - half, 0f, fz * length - half);
                uvs[i] = new Vector2(fx, fz);
                norms[i] = Vector3.up;
            }

            int t = 0;
            for (int z = 0; z < n; z++)
            for (int x = 0; x < n; x++)
            {
                int i = z * (n + 1) + x;
                tris[t++] = i;
                tris[t++] = i + n + 1;
                tris[t++] = i + 1;
                tris[t++] = i + 1;
                tris[t++] = i + n + 1;
                tris[t++] = i + n + 2;
            }

            mesh.vertices = verts;
            mesh.uv = uvs;
            mesh.normals = norms;
            mesh.triangles = tris;
            mesh.RecalculateBounds();
            // 扩大 bounds，避免顶点位移后被视锥裁切
            var b = mesh.bounds;
            b.Expand(new Vector3(20f, 40f, 20f));
            mesh.bounds = b;

            GetComponent<MeshFilter>().sharedMesh = mesh;
        }

        /// <summary>[Noise] Box-Muller → RG 高斯纹理，驱动初始频谱。</summary>
        static Texture2D GenerateNoiseTexture(int size)
        {
            var noise = new Texture2D(size, size, TextureFormat.RGFloat, false, true)
            {
                filterMode = FilterMode.Point,
                wrapMode = TextureWrapMode.Repeat,
                name = $"GaussianNoise_{size}"
            };
            for (int y = 0; y < size; y++)
            for (int x = 0; x < size; x++)
                noise.SetPixel(x, y, new Color(NormalRandom(), NormalRandom(), 0f, 1f));
            noise.Apply(false, false);
            return noise;
        }

        static float NormalRandom()
        {
            float u1 = Mathf.Max(1e-6f, Random.value);
            float u2 = Random.value;
            return Mathf.Cos(2f * Mathf.PI * u2) * Mathf.Sqrt(-2f * Mathf.Log(u1));
        }

        void DisposeRuntime()
        {
            cascade0?.Dispose();
            cascade1?.Dispose();
            cascade2?.Dispose();
            fft?.Dispose();
            cascade0 = cascade1 = cascade2 = null;
            fft = null;
            // 保留 gaussianNoise，避免 ForceReinitialize 时频谱种子抖动
            initialized = false;
        }

        void OnApplicationQuit()
        {
            if (gaussianNoise != null)
            {
                if (Application.isPlaying) Destroy(gaussianNoise);
                else DestroyImmediate(gaussianNoise);
                gaussianNoise = null;
                noiseSize = -1;
            }
        }

    }
}
