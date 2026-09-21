using UnityEditor;
using UnityEngine;
using System.IO;

/// <summary>
/// 一键生成 04.Fur 所需贴图、材质、场景物体。
/// 菜单：SRP Demo / Fur / Setup All
/// </summary>
public static class FurDemoSetup
{
    const string Root = "Assets/04.Fur";
    const string TexFolder = Root + "/Textures";
    const string MatFolder = Root + "/Materials";
    const string SceneFolder = Root + "/Scenes";
    const string PrefabFolder = Root + "/Prefabs";

    const string NoisePath = TexFolder + "/FurNoise.png";
    const string LengthPath = TexFolder + "/FurLengthMask.png";
    const string BaselineMatPath = MatFolder + "/Fur_Baseline.mat";
    const string OptimizedMatPath = MatFolder + "/Fur_Optimized.mat";
    const string BaselinePrefabPath = PrefabFolder + "/FurBall_Baseline.prefab";
    const string OptimizedPrefabPath = PrefabFolder + "/FurBall_Optimized.prefab";

    [MenuItem("SRP Demo/Fur/Setup All")]
    public static void SetupAll()
    {
        EnsureFolders();
        GenerateTextures();
        var baselineMat = CreateOrUpdateMaterial(BaselineMatPath, "Custom/URP_StaticInstancedFur");
        var optimizedMat = CreateOrUpdateMaterial(OptimizedMatPath, "ZZY/04.Fur/StaticInstancedFur");
        ApplyDefaultMaterialParams(baselineMat, false);
        ApplyDefaultMaterialParams(optimizedMat, true);
        CreatePrefabs(baselineMat, optimizedMat);
        AssetDatabase.SaveAssets();
        AssetDatabase.Refresh();
        Debug.Log("[04.Fur] Setup All completed.");
    }

    [MenuItem("SRP Demo/Fur/Generate Textures Only")]
    public static void GenerateTexturesMenu()
    {
        EnsureFolders();
        GenerateTextures();
        AssetDatabase.Refresh();
    }

    static void EnsureFolders()
    {
        Directory.CreateDirectory(ToAbsolute(TexFolder));
        Directory.CreateDirectory(ToAbsolute(MatFolder));
        Directory.CreateDirectory(ToAbsolute(SceneFolder));
        Directory.CreateDirectory(ToAbsolute(PrefabFolder));
    }

    static string ToAbsolute(string assetPath)
    {
        return Path.GetFullPath(Path.Combine(Application.dataPath, "..", assetPath));
    }

    static void GenerateTextures()
    {
        WritePng(NoisePath, BuildNoiseTexture(256));
        WritePng(LengthPath, BuildLengthMask(256));
        AssetDatabase.ImportAsset(NoisePath);
        AssetDatabase.ImportAsset(LengthPath);
        ConfigureTextureImporter(NoisePath, true);
        ConfigureTextureImporter(LengthPath, false);
    }

    static Texture2D BuildNoiseTexture(int size)
    {
        var tex = new Texture2D(size, size, TextureFormat.RGBA32, false, true);
        var pixels = new Color[size * size];
        for (int y = 0; y < size; y++)
        {
            for (int x = 0; x < size; x++)
            {
            // 多频值噪声 + 强尖峰：模拟发丝截面
            float n1 = Mathf.PerlinNoise(x * 0.12f, y * 0.12f);
            float n2 = Mathf.PerlinNoise(x * 0.45f + 17.3f, y * 0.45f + 9.1f);
            float n3 = Mathf.PerlinNoise(x * 1.6f + 3.7f, y * 1.6f + 5.9f);
            float n4 = Mathf.PerlinNoise(x * 3.1f + 8.2f, y * 3.1f + 1.4f);
            float baseN = Mathf.Clamp01(n1 * 0.35f + n2 * 0.30f + n3 * 0.20f + n4 * 0.15f);
            float spike = Mathf.Pow(Mathf.Max(n3, n4), 5.5f);
            float v = Mathf.Clamp01(baseN * 0.55f + spike * 0.85f);
            pixels[y * size + x] = new Color(v, v, v, 1f);
            }
        }
        tex.SetPixels(pixels);
        tex.Apply(false, false);
        return tex;
    }

    static Texture2D BuildLengthMask(int size)
    {
        var tex = new Texture2D(size, size, TextureFormat.RGBA32, false, true);
        var pixels = new Color[size * size];
        float cx = (size - 1) * 0.5f;
        float cy = (size - 1) * 0.5f;
        float maxR = size * 0.5f;
        for (int y = 0; y < size; y++)
        {
            for (int x = 0; x < size; x++)
            {
                float dx = (x - cx) / maxR;
                float dy = (y - cy) / maxR;
                float r = Mathf.Sqrt(dx * dx + dy * dy);
                // 球面式长度：中间略长，边缘略短，增加造型变化
                float len = Mathf.Clamp01(1.05f - r * 0.35f);
                float noise = Mathf.PerlinNoise(x * 0.05f, y * 0.05f);
                len = Mathf.Clamp01(len * (0.85f + noise * 0.25f));
                pixels[y * size + x] = new Color(len, len, len, 1f);
            }
        }
        tex.SetPixels(pixels);
        tex.Apply(false, false);
        return tex;
    }

    static void WritePng(string assetPath, Texture2D tex)
    {
        var abs = ToAbsolute(assetPath);
        File.WriteAllBytes(abs, tex.EncodeToPNG());
        Object.DestroyImmediate(tex);
    }

    static void ConfigureTextureImporter(string assetPath, bool isNoise)
    {
        var importer = AssetImporter.GetAtPath(assetPath) as TextureImporter;
        if (importer == null) return;
        importer.sRGBTexture = false;
        importer.mipmapEnabled = true;
        importer.wrapMode = TextureWrapMode.Repeat;
        importer.filterMode = FilterMode.Bilinear;
        importer.textureCompression = TextureImporterCompression.Uncompressed;
        importer.SaveAndReimport();
    }

    static Material CreateOrUpdateMaterial(string path, string shaderName)
    {
        var shader = Shader.Find(shaderName);
        if (shader == null)
        {
            Debug.LogError($"[04.Fur] Shader not found: {shaderName}");
            return null;
        }

        var mat = AssetDatabase.LoadAssetAtPath<Material>(path);
        if (mat == null)
        {
            mat = new Material(shader) { name = Path.GetFileNameWithoutExtension(path) };
            AssetDatabase.CreateAsset(mat, path);
        }
        else
        {
            mat.shader = shader;
        }

        mat.enableInstancing = true;
        return mat;
    }

    static void ApplyDefaultMaterialParams(Material mat, bool optimized)
    {
        if (mat == null) return;

        var noise = AssetDatabase.LoadAssetAtPath<Texture2D>(NoisePath);
        var length = AssetDatabase.LoadAssetAtPath<Texture2D>(LengthPath);
        if (noise != null) mat.SetTexture("_NoiseTex", noise);
        if (length != null) mat.SetTexture("_LengthMap", length);

        mat.SetColor("_BaseColor", new Color(0.25f, 0.12f, 0.05f, 1f));
        mat.SetColor("_FurColor", new Color(0.95f, 0.72f, 0.48f, 1f));
        mat.SetFloat("_NoiseTiling", optimized ? 22f : 20f);
        mat.SetFloat("_MaxDensity", 1f);
        mat.SetFloat("_Density", 0.95f);
        mat.SetFloat("_TipCutoff", optimized ? 0.78f : 0.75f);
        mat.SetFloat("_ThicknessCurve", optimized ? 1.25f : 1.3f);
        mat.SetFloat("_FurLength", 0.45f);
        mat.SetFloat("_Gravity", optimized ? 0.28f : 0.30f);
        mat.SetFloat("_Messiness", optimized ? 0.38f : 0.40f);
        mat.SetVector("_CombDir", new Vector4(0.08f, -0.65f, 0.40f, 0f));

        if (optimized)
        {
            mat.SetFloat("_AmbientStrength", 0.28f);
            mat.SetFloat("_SpecularStrength", 0.35f);
            mat.SetFloat("_SpecularPower", 32f);
        }

        EditorUtility.SetDirty(mat);
    }

    static void CreatePrefabs(Material baselineMat, Material optimizedMat)
    {
        CreateFurPrefab(BaselinePrefabPath, "FurBall_Baseline", baselineMat, false);
        CreateFurPrefab(OptimizedPrefabPath, "FurBall_Optimized", optimizedMat, true);
    }

    static void CreateFurPrefab(string path, string name, Material mat, bool optimized)
    {
        var go = GameObject.CreatePrimitive(PrimitiveType.Sphere);
        go.name = name;
        // 移除 MeshRenderer：由脚本接管绘制
        var mr = go.GetComponent<MeshRenderer>();
        if (mr != null) Object.DestroyImmediate(mr);
        var collider = go.GetComponent<Collider>();
        if (collider != null) Object.DestroyImmediate(collider);

        var mf = go.GetComponent<MeshFilter>();
        Mesh mesh = mf != null ? mf.sharedMesh : null;

        var comp = go.AddComponent<FurInstancedRendererOptimized>();
        comp.mesh = mesh;
        comp.furMaterial = mat;
        comp.maxShellCount = 64;
        comp.minShellCount = 6;
        comp.lodNearDistance = 3f;
        comp.lodFarDistance = 16f;
        comp.enableWind = true;
        comp.forceMaxShells = true; // Demo 默认满层，远景再关 force 看 LOD

        PrefabUtility.SaveAsPrefabAsset(go, path);
        Object.DestroyImmediate(go);
    }

    [MenuItem("SRP Demo/Fur/Populate Active Scene (Baseline)")]
    public static void PopulateBaselineScene()
    {
        SetupAll();
        PopulateScene(false);
    }

    [MenuItem("SRP Demo/Fur/Populate Active Scene (Optimized)")]
    public static void PopulateOptimizedScene()
    {
        SetupAll();
        PopulateScene(true);
    }

    static void PopulateScene(bool optimized)
    {
        // 清理旧物体
        DestroyIfExists("FurBall_Baseline");
        DestroyIfExists("FurBall_Optimized");
        DestroyIfExists("FurGround");
        DestroyIfExists("Fur comparision label");

        var cam = Camera.main;
        if (cam == null)
        {
            var camGo = new GameObject("Main Camera");
            cam = camGo.AddComponent<Camera>();
            cam.tag = "MainCamera";
            camGo.AddComponent<AudioListener>();
        }
        cam.transform.position = new Vector3(0f, 0.35f, -3.2f);
        cam.transform.rotation = Quaternion.Euler(8f, 0f, 0f);
        cam.backgroundColor = new Color(0.72f, 0.62f, 0.48f, 1f);
        cam.clearFlags = CameraClearFlags.SolidColor;

        if (Object.FindObjectOfType<Light>() == null)
        {
            var lightGo = new GameObject("Directional Light");
            var light = lightGo.AddComponent<Light>();
            light.type = LightType.Directional;
            light.color = new Color(1f, 0.96f, 0.90f);
            light.intensity = 1.15f;
            lightGo.transform.rotation = Quaternion.Euler(40f, -30f, 0f);
        }

        string prefabPath = optimized ? OptimizedPrefabPath : BaselinePrefabPath;
        var prefab = AssetDatabase.LoadAssetAtPath<GameObject>(prefabPath);
        if (prefab == null)
        {
            Debug.LogError($"[04.Fur] Prefab missing: {prefabPath}");
            return;
        }

        var instance = (GameObject)PrefabUtility.InstantiatePrefab(prefab);
        instance.transform.position = Vector3.zero;
        instance.name = optimized ? "FurBall_Optimized" : "FurBall_Baseline";

        // 简单地面参考（URP Lit，避免 Built-in Default 洋红报错材质）
        var ground = GameObject.CreatePrimitive(PrimitiveType.Plane);
        ground.name = "FurGround";
        ground.transform.position = new Vector3(0f, -0.55f, 0f);
        ground.transform.localScale = new Vector3(0.6f, 1f, 0.6f);
        var groundMr = ground.GetComponent<MeshRenderer>();
        if (groundMr != null)
        {
            var lit = Shader.Find("Universal Render Pipeline/Lit");
            if (lit != null)
            {
                var groundMat = new Material(lit)
                {
                    name = "FurGround_Runtime",
                    color = new Color(0.55f, 0.45f, 0.34f, 1f)
                };
                groundMr.sharedMaterial = groundMat;
            }
        }

        UnityEditor.SceneManagement.EditorSceneManager.MarkSceneDirty(
            UnityEditor.SceneManagement.EditorSceneManager.GetActiveScene());

        Selection.activeGameObject = instance;
        Debug.Log(optimized
            ? "[04.Fur] Optimized scene populated."
            : "[04.Fur] Baseline scene populated.");
    }

    static void DestroyIfExists(string name)
    {
        var go = GameObject.Find(name);
        if (go != null) Object.DestroyImmediate(go);
    }
}
