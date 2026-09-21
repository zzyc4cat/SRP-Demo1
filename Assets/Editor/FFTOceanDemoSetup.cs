using System.IO;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.Rendering.Universal;
using FFTOcean;

namespace SRPDemo.EditorTools
{
    /// <summary>
    /// 编辑器工具：重建纯 GPU FFT 海洋场景 / 预设 / 四方连续泡沫噪声。
    /// <para>
    /// [Scene] 无地形、无岸线 Shore；仅 Camera + Light + FFTOcean。<br/>
    /// [FoamNoise] 程序化 tileable fBm+Worley → T_FoamNoise.png，供浪尖絮状调制。
    /// </para>
    /// </summary>
    public static class FFTOceanDemoSetup
    {
        const string Root = "Assets/Resources/03.gpu_FFT_Ocean";
        const string ScenePath = "Assets/Scenes/03.FFTOcean.unity";
        const string MatPath = Root + "/Materials/FFTOcean.mat";
        const string FoamPath = Root + "/Textures/T_FoamNoise.png";
        const string WavesSettingsPath = Root + "/Settings/WavesSettings.asset";

        const string FftCompute = Root + "/Shaders/Compute/FastFourierTransform.compute";
        const string InitCompute = Root + "/Shaders/Compute/InitialSpectrum.compute";
        const string TimeCompute = Root + "/Shaders/Compute/TimeDependentSpectrum.compute";
        const string MergeCompute = Root + "/Shaders/Compute/WavesTexturesMerger.compute";

        const float OceanMeshLength = 200f;
        const float OceanCenterZ = -5f;

        [MenuItem("SRP Demo/FFT Ocean/Rebuild Scene (03.FFTOcean)")]
        public static void RebuildScene()
        {
            EnsureFolders();
            GenerateFoamNoise();
            var waves = EnsureWavesSettings();
            var mat = EnsureMaterial();
            ApplyMaterialDefaults(mat);

            var scene = EditorSceneManager.NewScene(NewSceneSetup.DefaultGameObjects, NewSceneMode.Single);
            BuildEnvironment();
            BuildOcean(mat, waves);
            // Remove any leftover beach from older scenes if opened additively later
            var beach = GameObject.Find("BeachTerrain");
            if (beach != null) Object.DestroyImmediate(beach);
            FrameCamera();

            Directory.CreateDirectory(Path.GetDirectoryName(Abs(ScenePath)));
            EditorSceneManager.SaveScene(scene, ScenePath);
            AssetDatabase.SaveAssets();
            Debug.Log("[03.FFTOcean] Pure GPU FFT ocean rebuilt (no terrain / shore).");
        }

        [MenuItem("SRP Demo/FFT Ocean/Regenerate Seamless Foam Noise")]
        public static void RegenerateFoamNoiseMenu()
        {
            EnsureFolders();
            GenerateFoamNoise();
            var mat = AssetDatabase.LoadAssetAtPath<Material>(MatPath);
            if (mat != null)
            {
                var foam = AssetDatabase.LoadAssetAtPath<Texture2D>(FoamPath);
                if (foam != null) mat.SetTexture("_FoamNoise", foam);
                mat.SetFloat("_FoamNoiseScale", 0.06f);
                EditorUtility.SetDirty(mat);
            }
            AssetDatabase.SaveAssets();
            Debug.Log("[03.FFTOcean] Seamless foam noise regenerated (512², tileable fBm+Worley).");
        }

        [MenuItem("SRP Demo/FFT Ocean/Apply Calm Preset")]
        public static void PresetCalm() => ApplyPreset(0.2f, 5f, 0.7f, 0.6f);

        [MenuItem("SRP Demo/FFT Ocean/Apply Storm Preset")]
        public static void PresetStorm() => ApplyPreset(0.55f, 14f, 1f, 1f);

        static void ApplyPreset(float localScale, float wind, float lambda, float timeScale)
        {
            var sim = Object.FindObjectOfType<FFTOceanSimulator>();
            var waves = AssetDatabase.LoadAssetAtPath<WavesSettings>(WavesSettingsPath);
            if (waves != null)
            {
                waves.lambda = lambda;
                waves.local.scale = localScale;
                waves.local.windSpeed = wind;
                EditorUtility.SetDirty(waves);
            }
            if (sim != null)
            {
                var so = new SerializedObject(sim);
                so.FindProperty("timeScale").floatValue = timeScale;
                so.FindProperty("alwaysRecalculateInitials").boolValue = true;
                so.ApplyModifiedPropertiesWithoutUndo();
                sim.ForceReinitialize();
            }
            Debug.Log($"[03.FFTOcean] Preset localScale={localScale} wind={wind} λ={lambda}");
        }

        static void EnsureFolders()
        {
            Directory.CreateDirectory(Abs(Root + "/Textures"));
            Directory.CreateDirectory(Abs(Root + "/Materials"));
            Directory.CreateDirectory(Abs(Root + "/Models"));
            Directory.CreateDirectory(Abs(Root + "/Settings"));
            Directory.CreateDirectory(Abs("Assets/Scenes"));
        }

        static string Abs(string assetPath) =>
            Path.GetFullPath(Path.Combine(Application.dataPath, "..", assetPath));

        static WavesSettings EnsureWavesSettings()
        {
            var asset = AssetDatabase.LoadAssetAtPath<WavesSettings>(WavesSettingsPath);
            if (asset == null)
            {
                asset = ScriptableObject.CreateInstance<WavesSettings>();
                AssetDatabase.CreateAsset(asset, WavesSettingsPath);
            }
            asset.g = 9.81f;
            asset.depth = 20f;
            asset.lambda = 1.15f;
            asset.local = new DisplaySpectrumSettings
            {
                scale = 0.35f,
                windSpeed = 8f,
                windDirection = 45f,
                fetch = 100000f,
                spreadBlend = 1f,
                swell = 0.25f,
                peakEnhancement = 3.3f,
                shortWavesFade = 0.01f
            };
            asset.swell = new DisplaySpectrumSettings
            {
                scale = 0.2f,
                windSpeed = 12f,
                windDirection = 25f,
                fetch = 300000f,
                spreadBlend = 1f,
                swell = 0.85f,
                peakEnhancement = 3.3f,
                shortWavesFade = 0.01f
            };
            EditorUtility.SetDirty(asset);
            return asset;
        }

        static void GenerateFoamNoise()
        {
            // ----- [FoamNoise] 四方连续 fBm + Worley；整数周期保证贴边无缝 -----
            const int size = 512;
            var tex = new Texture2D(size, size, TextureFormat.RGBA32, true, true);
            var pixels = new Color[size * size];

            for (int y = 0; y < size; y++)
            for (int x = 0; x < size; x++)
            {
                float u = x / (float)size;
                float v = y / (float)size;

                // Soft fBm — integer frequencies ⇒ seamless
                float fbmA = TileableFbm(u, v, 3, 0.52f, 11u);
                float fbmB = TileableFbm(u + 0.17f, v - 0.09f, 4, 0.55f, 29u);
                float fbmC = TileableFbm(u - 0.31f, v + 0.23f, 5, 0.5f, 47u);

                // Tileable Worley for irregular foam lace (cells wrap)
                float worley = 1f - TileableWorley(u, v, 7, 73u);
                float worley2 = 1f - TileableWorley(u + 0.41f, v + 0.19f, 11, 101u);

                float soft = Mathf.SmoothStep(0.2f, 0.9f, fbmA * 0.45f + fbmB * 0.3f + worley * 0.25f);
                float mid = Mathf.SmoothStep(0.15f, 0.95f, fbmB * 0.5f + worley2 * 0.5f);
                float detail = Mathf.SmoothStep(0.1f, 0.9f, fbmC * 0.65f + worley * 0.35f);
                pixels[y * size + x] = new Color(soft, mid, detail, 1f);
            }

            tex.SetPixels(pixels);
            tex.Apply(true, false);
            File.WriteAllBytes(Abs(FoamPath), tex.EncodeToPNG());
            Object.DestroyImmediate(tex);
            AssetDatabase.ImportAsset(FoamPath);
            var importer = AssetImporter.GetAtPath(FoamPath) as TextureImporter;
            if (importer != null)
            {
                importer.sRGBTexture = false;
                importer.wrapMode = TextureWrapMode.Repeat;
                importer.filterMode = FilterMode.Bilinear;
                importer.anisoLevel = 4;
                importer.mipmapEnabled = true;
                importer.SaveAndReimport();
            }
        }

        // --- Seamless noise helpers (period = 1 in UV space) ---

        static uint Hash(uint x)
        {
            x ^= 2747636419u;
            x *= 2654435769u;
            x ^= x >> 16;
            x *= 2654435769u;
            x ^= x >> 16;
            return x;
        }

        static float Hash01(int ix, int iy, uint seed)
        {
            uint h = Hash((uint)ix * 374761393u + (uint)iy * 668265263u + seed);
            return (h & 0xFFFFFF) / 16777215f;
        }

        static Vector2 HashDir(int ix, int iy, uint seed)
        {
            float a = Hash01(ix, iy, seed) * Mathf.PI * 2f;
            return new Vector2(Mathf.Cos(a), Mathf.Sin(a));
        }

        static float Fade(float t) => t * t * t * (t * (t * 6f - 15f) + 10f);

        /// <summary>Tileable 2D gradient noise. <paramref name="freq"/> must be positive integer.</summary>
        static float TileableGradientNoise(float u, float v, int freq, uint seed)
        {
            u = Mathf.Repeat(u, 1f) * freq;
            v = Mathf.Repeat(v, 1f) * freq;
            int x0 = Mathf.FloorToInt(u);
            int y0 = Mathf.FloorToInt(v);
            int x1 = (x0 + 1) % freq;
            int y1 = (y0 + 1) % freq;
            float fx = u - x0;
            float fy = v - y0;
            float ux = Fade(fx);
            float uy = Fade(fy);

            float n00 = Vector2.Dot(HashDir(x0, y0, seed), new Vector2(fx, fy));
            float n10 = Vector2.Dot(HashDir(x1, y0, seed), new Vector2(fx - 1f, fy));
            float n01 = Vector2.Dot(HashDir(x0, y1, seed), new Vector2(fx, fy - 1f));
            float n11 = Vector2.Dot(HashDir(x1, y1, seed), new Vector2(fx - 1f, fy - 1f));

            float nx0 = Mathf.Lerp(n00, n10, ux);
            float nx1 = Mathf.Lerp(n01, n11, ux);
            return Mathf.Lerp(nx0, nx1, uy) * 0.5f + 0.5f;
        }

        static float TileableFbm(float u, float v, int octaves, float persistence, uint seed)
        {
            float sum = 0f, amp = 1f, norm = 0f;
            int freq = 2;
            for (int i = 0; i < octaves; i++)
            {
                sum += TileableGradientNoise(u, v, freq, seed + (uint)(i * 97)) * amp;
                norm += amp;
                amp *= persistence;
                freq *= 2;
            }
            return sum / Mathf.Max(norm, 1e-5f);
        }

        /// <summary>Tileable Worley (cellular) noise. <paramref name="cells"/> = grid resolution.</summary>
        static float TileableWorley(float u, float v, int cells, uint seed)
        {
            u = Mathf.Repeat(u, 1f);
            v = Mathf.Repeat(v, 1f);
            float gx = u * cells;
            float gy = v * cells;
            int ix = Mathf.FloorToInt(gx);
            int iy = Mathf.FloorToInt(gy);
            float minD2 = 1e6f;
            for (int oy = -1; oy <= 1; oy++)
            for (int ox = -1; ox <= 1; ox++)
            {
                int nx = ix + ox;
                int ny = iy + oy;
                int cx = ((nx % cells) + cells) % cells;
                int cy = ((ny % cells) + cells) % cells;
                // Hash from wrapped cell; place feature in unwrapped neighbor space so edges match
                float px = nx + Hash01(cx, cy, seed);
                float py = ny + Hash01(cx, cy, seed + 19u);
                float dx = gx - px;
                float dy = gy - py;
                minD2 = Mathf.Min(minD2, dx * dx + dy * dy);
            }
            return Mathf.Clamp01(Mathf.Sqrt(minD2));
        }

        static Material EnsureMaterial()
        {
            var shader = Shader.Find("ZZY/03.gpu_FFT_Ocean/FFTOcean");
            if (shader == null)
            {
                Debug.LogError("[03.FFTOcean] Shader ZZY/03.gpu_FFT_Ocean/FFTOcean not found. Wait for compile.");
                return null;
            }
            var mat = AssetDatabase.LoadAssetAtPath<Material>(MatPath);
            if (mat == null)
            {
                mat = new Material(shader) { name = "FFTOcean" };
                AssetDatabase.CreateAsset(mat, MatPath);
            }
            else mat.shader = shader;
            return mat;
        }

        static void ApplyMaterialDefaults(Material mat)
        {
            if (mat == null) return;
            var foam = AssetDatabase.LoadAssetAtPath<Texture2D>(FoamPath);
            if (foam != null) mat.SetTexture("_FoamNoise", foam);

            mat.SetColor("_OceanColorShallow", new Color(0.40f, 0.78f, 0.72f, 1f));
            mat.SetColor("_OceanColorMid", new Color(0.04f, 0.38f, 0.52f, 1f));
            mat.SetColor("_OceanColorDeep", new Color(0.01f, 0.10f, 0.26f, 1f));
            mat.SetColor("_FoamColor", new Color(0.97f, 0.99f, 1f, 1f));
            mat.SetColor("_SSSColor", new Color(0.28f, 0.85f, 0.78f, 1f));
            mat.SetFloat("_ShallowDistance", 1.5f);
            mat.SetFloat("_DeepDistance", 18f);
            mat.SetFloat("_Absorption", 1.4f);
            mat.SetFloat("_Opacity", 0.92f);
            mat.SetFloat("_SpecularIntensity", 2.5f);
            mat.SetFloat("_Gloss", 180f);
            mat.SetFloat("_FresnelPower", 5f);
            mat.SetFloat("_FresnelBias", 0.04f);
            mat.SetFloat("_EnvIntensity", 0.75f);
            mat.SetFloat("_SSSIntensity", 1.1f);
            mat.SetFloat("_SSSPower", 4f);
            mat.SetFloat("_LOD_scale", 8f);
            mat.SetFloat("_FoamBias", 2.85f);
            mat.SetFloat("_FoamScale", 1.35f);
            mat.SetFloat("_CrestFoam", 1.6f);
            mat.SetFloat("_ContactFoam", 0.2f);
            mat.SetFloat("_FoamNoiseScale", 0.08f);
            mat.SetFloat("_RefractionStrength", 0.12f);
            mat.SetFloat("_LengthScale0", 250f);
            mat.SetFloat("_LengthScale1", 17f);
            mat.SetFloat("_LengthScale2", 5f);
            EditorUtility.SetDirty(mat);
        }

        static void BuildEnvironment()
        {
            var cam = Camera.main;
            if (cam != null)
            {
                cam.clearFlags = CameraClearFlags.Skybox;
                cam.allowHDR = true;
                cam.depthTextureMode |= DepthTextureMode.Depth;
                var urp = cam.GetComponent<UniversalAdditionalCameraData>();
                if (urp == null) urp = cam.gameObject.AddComponent<UniversalAdditionalCameraData>();
                urp.requiresDepthOption = CameraOverrideOption.On;
                urp.requiresColorOption = CameraOverrideOption.On;
            }

            var lightGo = GameObject.Find("Directional Light") ?? new GameObject("Directional Light");
            if (lightGo.GetComponent<Light>() == null) lightGo.AddComponent<Light>();
            lightGo.transform.rotation = Quaternion.Euler(48f, -30f, 0f);
            var light = lightGo.GetComponent<Light>();
            light.type = LightType.Directional;
            light.color = new Color(1f, 0.97f, 0.9f);
            light.intensity = 1.55f;
            light.shadows = LightShadows.Soft;
        }

        static FFTOceanSimulator BuildOcean(Material mat, WavesSettings waves)
        {
            var go = new GameObject("FFTOcean");
            go.transform.position = new Vector3(0f, 0f, OceanCenterZ);
            go.AddComponent<MeshFilter>();
            go.AddComponent<MeshRenderer>();
            var sim = go.AddComponent<FFTOceanSimulator>();

            var so = new SerializedObject(sim);
            so.FindProperty("fftShader").objectReferenceValue =
                AssetDatabase.LoadAssetAtPath<ComputeShader>(FftCompute);
            so.FindProperty("initialSpectrumShader").objectReferenceValue =
                AssetDatabase.LoadAssetAtPath<ComputeShader>(InitCompute);
            so.FindProperty("timeDependentSpectrumShader").objectReferenceValue =
                AssetDatabase.LoadAssetAtPath<ComputeShader>(TimeCompute);
            so.FindProperty("texturesMergerShader").objectReferenceValue =
                AssetDatabase.LoadAssetAtPath<ComputeShader>(MergeCompute);
            so.FindProperty("wavesSettings").objectReferenceValue = waves;
            so.FindProperty("oceanMaterial").objectReferenceValue = mat;
            so.FindProperty("fftPow").intValue = 8;
            so.FindProperty("meshSize").intValue = 256;
            so.FindProperty("meshLength").floatValue = OceanMeshLength;
            so.FindProperty("lengthScale0").floatValue = 250f;
            so.FindProperty("lengthScale1").floatValue = 17f;
            so.FindProperty("lengthScale2").floatValue = 5f;
            so.FindProperty("timeScale").floatValue = 1f;
            so.FindProperty("simulateInEditMode").boolValue = true;
            so.FindProperty("alwaysRecalculateInitials").boolValue = false;
            so.ApplyModifiedPropertiesWithoutUndo();

            sim.ForceReinitialize();
            return sim;
        }

        static void FrameCamera()
        {
            var cam = Camera.main;
            if (cam == null) return;
            cam.fieldOfView = 48f;
            cam.transform.position = new Vector3(-18f, 5.5f, 28f);
            cam.transform.LookAt(new Vector3(8f, -0.2f, 4f));
            cam.depthTextureMode |= DepthTextureMode.Depth;
        }
    }
}
