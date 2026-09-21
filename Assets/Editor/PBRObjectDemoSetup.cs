using System.IO;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.SceneManagement;

/// <summary>
/// 07.PBR_object 一键搭建：
/// - 5×5 金属-粗糙度梯度球阵列
/// - SpecularTest
/// - Normal-Tangent Mirror Test
/// - TransmissionRoughnessTest
/// 菜单：SRP Demo / PBR Object / Setup Scene
/// </summary>
public static class PBRObjectDemoSetup
{
    const string Root = "Assets/Resources/07.PBR_object";
    const string TexFolder = Root + "/Textures";
    const string MatFolder = Root + "/Materials";
    const string ScenePath = "Assets/Scenes/07.PBR_object.unity";

    const string ShaderOpaque = "ZZY/07.PBR_object/glTFPBR";
    const string ShaderTransmission = "ZZY/07.PBR_object/glTFPBRTransmission";

    const string BaseColorPath = TexFolder + "/PBR_BaseColor.png";
    const string MetallicRoughnessPath = TexFolder + "/PBR_MetallicRoughness.png";
    const string NormalPath = TexFolder + "/PBR_Normal.png";
    const string OcclusionPath = TexFolder + "/PBR_Occlusion.png";
    const string CheckerPath = TexFolder + "/PBR_Checker.png";
    const string FlatMRPath = TexFolder + "/PBR_FlatMR_White.png";
    const string FlatNormalPath = TexFolder + "/PBR_FlatNormal.png";

    [MenuItem("SRP Demo/PBR Object/Setup Scene")]
    public static void SetupScene()
    {
        EnsureFolders();
        GenerateTextures();
        AssetDatabase.Refresh();

        ConfigureTextureImporters();
        AssetDatabase.Refresh();

        var scene = EditorSceneManager.NewScene(NewSceneSetup.DefaultGameObjects, NewSceneMode.Single);
        CleanupDefaultLightIfNeeded();

        BuildEnvironment();
        BuildMetalRoughnessGrid();
        BuildSpecularTest();
        BuildNormalTangentMirrorTest();
        BuildTransmissionRoughnessTest();
        FrameCamera();

        Directory.CreateDirectory(Path.GetFullPath(Path.Combine(Application.dataPath, "Scenes")));
        EditorSceneManager.SaveScene(scene, ScenePath);
        AssetDatabase.SaveAssets();
        AssetDatabase.Refresh();
        Debug.Log("[07.PBR_object] Scene setup completed → " + ScenePath);
    }

    [MenuItem("SRP Demo/PBR Object/Generate Textures Only")]
    public static void GenerateTexturesMenu()
    {
        EnsureFolders();
        GenerateTextures();
        AssetDatabase.Refresh();
        ConfigureTextureImporters();
        AssetDatabase.Refresh();
        Debug.Log("[07.PBR_object] Textures generated.");
    }

    static void EnsureFolders()
    {
        Directory.CreateDirectory(Abs(TexFolder));
        Directory.CreateDirectory(Abs(MatFolder));
        Directory.CreateDirectory(Abs(Root + "/Shaders/Library"));
        Directory.CreateDirectory(Abs(Root + "/Scripts"));
        Directory.CreateDirectory(Abs(Root + "/Prefabs"));
        Directory.CreateDirectory(Abs("Assets/Scenes"));
    }

    static string Abs(string assetPath)
    {
        return Path.GetFullPath(Path.Combine(Application.dataPath, "..", assetPath));
    }

    static void CleanupDefaultLightIfNeeded()
    {
        // Keep Directional Light & Main Camera from DefaultGameObjects; rename for clarity.
        var cam = Camera.main;
        if (cam != null)
        {
            cam.name = "Main Camera";
            cam.transform.position = new Vector3(2.5f, 4.5f, -11f);
            cam.transform.rotation = Quaternion.Euler(18f, -8f, 0f);
            cam.clearFlags = CameraClearFlags.Skybox;
            cam.fieldOfView = 50f;
        }
    }

    // -------------------------------------------------------------------------
    // Textures (glTF channel layout)
    // -------------------------------------------------------------------------
    static void GenerateTextures()
    {
        WritePng(BaseColorPath, BuildBaseColor(512));
        WritePng(MetallicRoughnessPath, BuildMetallicRoughness(512));
        WritePng(NormalPath, BuildNormalMap(512));
        WritePng(OcclusionPath, BuildOcclusion(512));
        WritePng(CheckerPath, BuildChecker(256));
        WritePng(FlatMRPath, BuildSolid(4, new Color(1f, 1f, 1f, 1f))); // G=1,B=1 → factor 控参
        WritePng(FlatNormalPath, BuildFlatNormal(4));
    }

    static Texture2D BuildBaseColor(int size)
    {
        var tex = new Texture2D(size, size, TextureFormat.RGBA32, true, false);
        var pixels = new Color[size * size];
        for (int y = 0; y < size; y++)
        for (int x = 0; x < size; x++)
        {
            float u = x / (float)(size - 1);
            float v = y / (float)(size - 1);
            // 柔和棋盘 + 径向渐变，便于观察漫反射衰减与贴图贡献
            int cx = (x / 32) & 1;
            int cy = (y / 32) & 1;
            float checker = (cx ^ cy) == 0 ? 0.92f : 0.78f;
            float radial = 1f - 0.25f * Mathf.Sqrt((u - 0.5f) * (u - 0.5f) + (v - 0.5f) * (v - 0.5f)) * 2f;
            float warm = 0.55f + 0.35f * u;
            pixels[y * size + x] = new Color(checker * warm * radial, checker * 0.72f * radial, checker * 0.58f * radial, 1f);
        }
        tex.SetPixels(pixels);
        tex.Apply(true, false);
        return tex;
    }

    /// <summary>G=roughness, B=metallic（中心金属高、边缘粗糙变化）</summary>
    static Texture2D BuildMetallicRoughness(int size)
    {
        var tex = new Texture2D(size, size, TextureFormat.RGBA32, true, true);
        var pixels = new Color[size * size];
        float cx = (size - 1) * 0.5f;
        float cy = (size - 1) * 0.5f;
        float maxR = size * 0.5f;
        for (int y = 0; y < size; y++)
        for (int x = 0; x < size; x++)
        {
            float dx = (x - cx) / maxR;
            float dy = (y - cy) / maxR;
            float r = Mathf.Sqrt(dx * dx + dy * dy);
            float metallic = Mathf.Clamp01(1.1f - r);          // 中心偏金属
            float roughness = Mathf.Clamp01(0.15f + r * 0.75f); // 边缘更粗糙
            float noise = Mathf.PerlinNoise(x * 0.04f, y * 0.04f);
            roughness = Mathf.Clamp01(roughness * (0.85f + noise * 0.3f));
            // R unused, G roughness, B metallic
            pixels[y * size + x] = new Color(1f, roughness, metallic, 1f);
        }
        tex.SetPixels(pixels);
        tex.Apply(true, false);
        return tex;
    }

    static Texture2D BuildNormalMap(int size)
    {
        // 高度场 → 法线（砖块凹凸，用于 Normal-Tangent 测试）
        var height = new float[size * size];
        for (int y = 0; y < size; y++)
        for (int x = 0; x < size; x++)
        {
            float brickU = (x % 64) / 64f;
            float brickV = (y % 64) / 64f;
            float mortar = (brickU < 0.08f || brickV < 0.08f) ? 0.15f : 1f;
            float n = Mathf.PerlinNoise(x * 0.08f, y * 0.08f);
            height[y * size + x] = mortar * (0.55f + n * 0.45f);
        }

        var tex = new Texture2D(size, size, TextureFormat.RGBA32, true, true);
        var pixels = new Color[size * size];
        for (int y = 0; y < size; y++)
        for (int x = 0; x < size; x++)
        {
            int xl = (x + size - 1) % size;
            int xr = (x + 1) % size;
            int yd = (y + size - 1) % size;
            int yu = (y + 1) % size;
            float dx = height[y * size + xr] - height[y * size + xl];
            float dy = height[yu * size + x] - height[yd * size + x];
            Vector3 nrm = new Vector3(-dx * 4f, -dy * 4f, 1f).normalized;
            // Unity / OpenGL tangent-space normal encoding
            pixels[y * size + x] = new Color(nrm.x * 0.5f + 0.5f, nrm.y * 0.5f + 0.5f, nrm.z * 0.5f + 0.5f, 1f);
        }
        tex.SetPixels(pixels);
        tex.Apply(true, false);
        return tex;
    }

    static Texture2D BuildOcclusion(int size)
    {
        var tex = new Texture2D(size, size, TextureFormat.RGBA32, true, true);
        var pixels = new Color[size * size];
        for (int y = 0; y < size; y++)
        for (int x = 0; x < size; x++)
        {
            float brickU = (x % 64) / 64f;
            float brickV = (y % 64) / 64f;
            float ao = (brickU < 0.1f || brickV < 0.1f) ? 0.45f : 1f;
            float n = Mathf.PerlinNoise(x * 0.05f + 3f, y * 0.05f + 7f);
            ao *= 0.85f + n * 0.15f;
            pixels[y * size + x] = new Color(ao, ao, ao, 1f);
        }
        tex.SetPixels(pixels);
        tex.Apply(true, false);
        return tex;
    }

    static Texture2D BuildChecker(int size)
    {
        var tex = new Texture2D(size, size, TextureFormat.RGBA32, true, false);
        var pixels = new Color[size * size];
        for (int y = 0; y < size; y++)
        for (int x = 0; x < size; x++)
        {
            bool c = ((x / 16) & 1) == ((y / 16) & 1);
            pixels[y * size + x] = c ? Color.white : new Color(0.15f, 0.15f, 0.18f, 1f);
        }
        tex.SetPixels(pixels);
        tex.Apply(true, false);
        return tex;
    }

    static Texture2D BuildSolid(int size, Color c)
    {
        var tex = new Texture2D(size, size, TextureFormat.RGBA32, false, true);
        var pixels = new Color[size * size];
        for (int i = 0; i < pixels.Length; i++) pixels[i] = c;
        tex.SetPixels(pixels);
        tex.Apply(false, false);
        return tex;
    }

    static Texture2D BuildFlatNormal(int size)
    {
        return BuildSolid(size, new Color(0.5f, 0.5f, 1f, 1f));
    }

    static void WritePng(string assetPath, Texture2D tex)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(Abs(assetPath))!);
        File.WriteAllBytes(Abs(assetPath), tex.EncodeToPNG());
        Object.DestroyImmediate(tex);
    }

    static void ConfigureTextureImporters()
    {
        SetImporter(BaseColorPath, isNormal: false, sRGB: true, linear: false);
        SetImporter(MetallicRoughnessPath, isNormal: false, sRGB: false, linear: true);
        SetImporter(NormalPath, isNormal: true, sRGB: false, linear: true);
        SetImporter(OcclusionPath, isNormal: false, sRGB: false, linear: true);
        SetImporter(CheckerPath, isNormal: false, sRGB: true, linear: false);
        SetImporter(FlatMRPath, isNormal: false, sRGB: false, linear: true);
        SetImporter(FlatNormalPath, isNormal: true, sRGB: false, linear: true);
    }

    static void SetImporter(string path, bool isNormal, bool sRGB, bool linear)
    {
        AssetDatabase.ImportAsset(path, ImportAssetOptions.ForceUpdate);
        var importer = AssetImporter.GetAtPath(path) as TextureImporter;
        if (importer == null) return;
        importer.sRGBTexture = sRGB;
        importer.textureType = isNormal ? TextureImporterType.NormalMap : TextureImporterType.Default;
        importer.mipmapEnabled = true;
        importer.anisoLevel = 8;
        importer.wrapMode = TextureWrapMode.Repeat;
        importer.filterMode = FilterMode.Bilinear;
        if (isNormal)
            importer.textureType = TextureImporterType.NormalMap;
        EditorUtility.SetDirty(importer);
        importer.SaveAndReimport();
    }

    // -------------------------------------------------------------------------
    // Scene building
    // -------------------------------------------------------------------------
    static void BuildEnvironment()
    {
        // Ground
        var ground = GameObject.CreatePrimitive(PrimitiveType.Plane);
        ground.name = "Ground";
        ground.transform.position = new Vector3(1f, 0f, 3f);
        ground.transform.localScale = new Vector3(2.2f, 1f, 1.8f);
        var groundMat = CreateMaterial(MatFolder + "/M_Ground.mat", ShaderOpaque);
        ApplyMaps(groundMat, LoadTex(CheckerPath), LoadTex(FlatMRPath), LoadTex(FlatNormalPath), LoadTex(OcclusionPath));
        groundMat.SetColor("_BaseColorFactor", new Color(0.65f, 0.66f, 0.68f, 1f));
        groundMat.SetFloat("_MetallicFactor", 0f);
        groundMat.SetFloat("_RoughnessFactor", 0.85f);
        groundMat.SetFloat("_BumpScale", 0f);
        ground.GetComponent<MeshRenderer>().sharedMaterial = groundMat;

        // Lighting
        var lightGo = GameObject.Find("Directional Light");
        if (lightGo == null)
        {
            lightGo = new GameObject("Directional Light");
            lightGo.AddComponent<Light>();
        }
        lightGo.transform.rotation = Quaternion.Euler(45f, -35f, 0f);
        var light = lightGo.GetComponent<Light>();
        light.type = LightType.Directional;
        light.color = new Color(1f, 0.97f, 0.92f);
        light.intensity = 1.35f;
        light.shadows = LightShadows.Soft;

        // Fill light
        var fill = new GameObject("Fill Light");
        var fillL = fill.AddComponent<Light>();
        fillL.type = LightType.Directional;
        fillL.color = new Color(0.55f, 0.65f, 0.9f);
        fillL.intensity = 0.35f;
        fillL.shadows = LightShadows.None;
        fill.transform.rotation = Quaternion.Euler(20f, 140f, 0f);

        // Reflection probe for env specular / transmission
        var probeGo = new GameObject("Reflection Probe");
        probeGo.transform.position = new Vector3(1f, 2f, 3f);
        var probe = probeGo.AddComponent<ReflectionProbe>();
        probe.mode = ReflectionProbeMode.Realtime;
        probe.refreshMode = ReflectionProbeRefreshMode.ViaScripting;
        probe.size = new Vector3(40f, 20f, 40f);
        probe.resolution = 256;
        probe.intensity = 1.1f;
        probe.RenderProbe();

        // Labels root（中文说明，标题靠前减少遮挡）
        var labels = new GameObject("Labels");
        CreateLabel(labels.transform, "金属-粗糙度 5×5\n金属度→ · 粗糙度↓",
            new Vector3(-3.5f, 6.35f, -1.2f));
        CreateLabel(labels.transform, "高光测试", new Vector3(4.8f, 4.15f, -1.2f));
        CreateLabel(labels.transform, "法线-切线测试", new Vector3(-3.5f, 4.0f, 4.0f));
        CreateLabel(labels.transform, "透射粗糙度测试", new Vector3(4.8f, 4.0f, 4.0f));
    }

    static void BuildMetalRoughnessGrid()
    {
        var root = new GameObject("MetalRoughnessGrid_5x5");
        root.transform.position = new Vector3(-5.6f, 1.0f, 0f);

        const int n = 5;
        const float spacing = 1.15f;
        Texture2D flatMR = LoadTex(FlatMRPath);
        Texture2D flatN = LoadTex(FlatNormalPath);
        Texture2D whiteOcc = LoadTex(OcclusionPath);

        // Neutral mid-grey dielectric/metal base — 便于观察能量守恒与高光
        Color baseColor = new Color(0.92f, 0.92f, 0.92f, 1f);

        for (int row = 0; row < n; row++)
        {
            float roughness = row / (float)(n - 1); // top(row0)=0 → bottom=1
            for (int col = 0; col < n; col++)
            {
                float metallic = col / (float)(n - 1); // left=0 → right=1
                var sphere = CreateSphere(
                    $"MR_m{metallic:0.00}_r{roughness:0.00}",
                    root.transform,
                    new Vector3(col * spacing, (n - 1 - row) * spacing, 0f));

                string matPath = $"{MatFolder}/M_Grid_m{col}_r{row}.mat";
                var mat = CreateMaterial(matPath, ShaderOpaque);
                ApplyMaps(mat, Texture2D.whiteTexture, flatMR, flatN, Texture2D.whiteTexture);
                mat.SetColor("_BaseColorFactor", baseColor);
                mat.SetFloat("_MetallicFactor", metallic);
                mat.SetFloat("_RoughnessFactor", roughness);
                mat.SetFloat("_BumpScale", 0f);
                mat.SetFloat("_OcclusionStrength", 0f);
                mat.SetFloat("_EnvironmentIntensity", 1.15f);
                mat.SetFloat("_DebugMode", 0f);
                sphere.GetComponent<MeshRenderer>().sharedMaterial = mat;
            }
        }

        // Axis markers
        CreateLabel(root.transform, "金属度=0", new Vector3(-0.15f, -0.55f, 0f));
        CreateLabel(root.transform, "金属度=1", new Vector3((n - 1) * spacing, -0.55f, 0f));
        CreateLabel(root.transform, "粗糙度=0", new Vector3(-0.95f, (n - 1) * spacing, 0f));
        CreateLabel(root.transform, "粗糙度=1", new Vector3(-0.95f, 0f, 0f));
    }

    static void BuildSpecularTest()
    {
        var root = new GameObject("SpecularTest");
        root.transform.position = new Vector3(2.4f, 1.0f, 0f);

        Texture2D flatMR = LoadTex(FlatMRPath);
        Texture2D flatN = LoadTex(FlatNormalPath);

        // Row A: Chrome metallic roughness sweep — 高光形状 / 强度 / 边缘
        float[] roughnesses = { 0.0f, 0.15f, 0.35f, 0.6f, 1.0f };
        for (int i = 0; i < roughnesses.Length; i++)
        {
            var s = CreateSphere($"Spec_Metal_R{roughnesses[i]:0.00}", root.transform, new Vector3(i * 1.2f, 1.2f, 0f));
            var mat = CreateMaterial($"{MatFolder}/M_Spec_Metal_{i}.mat", ShaderOpaque);
            ApplyMaps(mat, Texture2D.whiteTexture, flatMR, flatN, Texture2D.whiteTexture);
            mat.SetColor("_BaseColorFactor", new Color(1f, 0.85f, 0.55f, 1f)); // 金
            mat.SetFloat("_MetallicFactor", 1f);
            mat.SetFloat("_RoughnessFactor", roughnesses[i]);
            mat.SetFloat("_BumpScale", 0f);
            mat.SetFloat("_DebugMode", 0f);
            mat.SetFloat("_SpecularIntensity", 1f);
            s.GetComponent<MeshRenderer>().sharedMaterial = mat;
        }

        // Row B: Dielectric white — Fresnel 边缘衰减是否物理
        for (int i = 0; i < roughnesses.Length; i++)
        {
            var s = CreateSphere($"Spec_Dielectric_R{roughnesses[i]:0.00}", root.transform, new Vector3(i * 1.2f, 0f, 0f));
            var mat = CreateMaterial($"{MatFolder}/M_Spec_Diel_{i}.mat", ShaderOpaque);
            ApplyMaps(mat, Texture2D.whiteTexture, flatMR, flatN, Texture2D.whiteTexture);
            mat.SetColor("_BaseColorFactor", new Color(0.95f, 0.95f, 0.95f, 1f));
            mat.SetFloat("_MetallicFactor", 0f);
            mat.SetFloat("_RoughnessFactor", roughnesses[i]);
            mat.SetFloat("_BumpScale", 0f);
            mat.SetFloat("_DebugMode", 0f);
            s.GetComponent<MeshRenderer>().sharedMaterial = mat;
        }

        // Row C: Debug D-term / Specular-only 对照球
        var debugModes = new[] { 1, 3, 4 }; // Spec only / D / Fresnel
        string[] names = { "Debug_SpecularOnly", "Debug_D_GGX", "Debug_Fresnel" };
        for (int i = 0; i < debugModes.Length; i++)
        {
            var s = CreateSphere(names[i], root.transform, new Vector3(i * 1.2f, 2.4f, 0f));
            var mat = CreateMaterial($"{MatFolder}/M_Spec_Debug_{i}.mat", ShaderOpaque);
            ApplyMaps(mat, Texture2D.whiteTexture, flatMR, flatN, Texture2D.whiteTexture);
            mat.SetColor("_BaseColorFactor", Color.white);
            mat.SetFloat("_MetallicFactor", 1f);
            mat.SetFloat("_RoughnessFactor", 0.2f);
            mat.SetFloat("_BumpScale", 0f);
            mat.SetFloat("_DebugMode", debugModes[i]);
            s.GetComponent<MeshRenderer>().sharedMaterial = mat;
        }

        CreateLabel(root.transform, "金属金 · 粗糙度→", new Vector3(2.2f, 0.55f, -0.6f));
        CreateLabel(root.transform, "电介质 · 粗糙度→", new Vector3(2.2f, -0.55f, -0.6f));
    }

    static void BuildNormalTangentMirrorTest()
    {
        var root = new GameObject("NormalTangentMirrorTest");
        root.transform.position = new Vector3(-5.6f, 1.0f, 5.0f);

        Texture2D baseMap = LoadTex(BaseColorPath);
        Texture2D mr = LoadTex(MetallicRoughnessPath);
        Texture2D nrm = LoadTex(NormalPath);
        Texture2D ao = LoadTex(OcclusionPath);
        Texture2D flatN = LoadTex(FlatNormalPath);
        Texture2D flatMR = LoadTex(FlatMRPath);

        float[] scales = { 0f, 0.5f, 1f, 2f };
        for (int i = 0; i < scales.Length; i++)
        {
            var s = CreateSphere($"NormalScale_{scales[i]:0.0}", root.transform, new Vector3(i * 1.25f, 0f, 0f));
            var mat = CreateMaterial($"{MatFolder}/M_Normal_{i}.mat", ShaderOpaque);
            ApplyMaps(mat, baseMap, mr, scales[i] <= 0.001f ? flatN : nrm, ao);
            mat.SetColor("_BaseColorFactor", Color.white);
            mat.SetFloat("_MetallicFactor", 0.15f);
            mat.SetFloat("_RoughnessFactor", 0.45f);
            mat.SetFloat("_BumpScale", scales[i]);
            mat.SetFloat("_OcclusionStrength", 1f);
            mat.SetFloat("_DebugMode", 0f);
            s.GetComponent<MeshRenderer>().sharedMaterial = mat;
        }

        // Mirror plane behind — 验证切线空间扰动后反射方向
        var mirror = GameObject.CreatePrimitive(PrimitiveType.Quad);
        mirror.name = "TangentMirrorPlane";
        mirror.transform.SetParent(root.transform, false);
        mirror.transform.localPosition = new Vector3(1.8f, 1.2f, 2.2f);
        mirror.transform.localRotation = Quaternion.Euler(0f, 180f, 0f);
        mirror.transform.localScale = new Vector3(6f, 3.5f, 1f);
        var mirrorMat = CreateMaterial(MatFolder + "/M_Mirror.mat", ShaderOpaque);
        ApplyMaps(mirrorMat, Texture2D.whiteTexture, flatMR, flatN, Texture2D.whiteTexture);
        mirrorMat.SetColor("_BaseColorFactor", new Color(0.95f, 0.95f, 0.98f, 1f));
        mirrorMat.SetFloat("_MetallicFactor", 1f);
        mirrorMat.SetFloat("_RoughnessFactor", 0.02f);
        mirrorMat.SetFloat("_BumpScale", 0f);
        mirrorMat.SetFloat("_EnvironmentIntensity", 1.4f);
        mirror.GetComponent<MeshRenderer>().sharedMaterial = mirrorMat;

        // Debug normal visualization sphere
        var nDebug = CreateSphere("Debug_WorldNormal", root.transform, new Vector3(5.2f, 0f, 0f));
        var nMat = CreateMaterial(MatFolder + "/M_Normal_Debug.mat", ShaderOpaque);
        ApplyMaps(nMat, baseMap, flatMR, nrm, ao);
        nMat.SetFloat("_MetallicFactor", 0f);
        nMat.SetFloat("_RoughnessFactor", 0.5f);
        nMat.SetFloat("_BumpScale", 1.5f);
        nMat.SetFloat("_DebugMode", 7f); // world normal
        nDebug.GetComponent<MeshRenderer>().sharedMaterial = nMat;

        CreateLabel(root.transform, "法线强度 0 / 0.5 / 1 / 2 + 镜面", new Vector3(1.8f, 2.05f, 0f));
    }

    static void BuildTransmissionRoughnessTest()
    {
        var root = new GameObject("TransmissionRoughnessTest");
        root.transform.position = new Vector3(2.4f, 1.0f, 5.0f);

        Texture2D flatMR = LoadTex(FlatMRPath);
        Texture2D flatN = LoadTex(FlatNormalPath);
        Texture2D checker = LoadTex(CheckerPath);

        // 背景棋盘墙，便于观察透射模糊
        var wall = GameObject.CreatePrimitive(PrimitiveType.Quad);
        wall.name = "TransmissionBackdrop";
        wall.transform.SetParent(root.transform, false);
        wall.transform.localPosition = new Vector3(2.4f, 1.2f, 2.5f);
        wall.transform.localRotation = Quaternion.Euler(0f, 180f, 0f);
        wall.transform.localScale = new Vector3(7f, 3.5f, 1f);
        var wallMat = CreateMaterial(MatFolder + "/M_Trans_Backdrop.mat", ShaderOpaque);
        ApplyMaps(wallMat, checker, flatMR, flatN, Texture2D.whiteTexture);
        wallMat.SetFloat("_MetallicFactor", 0f);
        wallMat.SetFloat("_RoughnessFactor", 0.9f);
        wallMat.SetFloat("_BumpScale", 0f);
        wall.GetComponent<MeshRenderer>().sharedMaterial = wallMat;

        float[] transmissions = { 0.25f, 0.5f, 0.75f, 1.0f };
        float[] roughnesses = { 0.0f, 0.2f, 0.5f, 0.85f };

        // Grid: X = transmission, Y = roughness
        for (int r = 0; r < roughnesses.Length; r++)
        for (int t = 0; t < transmissions.Length; t++)
        {
            var s = CreateSphere(
                $"Trans_T{transmissions[t]:0.00}_R{roughnesses[r]:0.00}",
                root.transform,
                new Vector3(t * 1.2f, (roughnesses.Length - 1 - r) * 1.15f, 0f));

            var mat = CreateMaterial($"{MatFolder}/M_Trans_t{t}_r{r}.mat", ShaderTransmission);
            ApplyMaps(mat, Texture2D.whiteTexture, flatMR, flatN, Texture2D.whiteTexture);
            mat.SetColor("_BaseColorFactor", new Color(0.85f, 0.95f, 1f, 0.05f));
            mat.SetFloat("_MetallicFactor", 0f);
            mat.SetFloat("_RoughnessFactor", roughnesses[r]);
            mat.SetFloat("_BumpScale", 0f);
            mat.SetFloat("_TransmissionFactor", transmissions[t]);
            mat.SetFloat("_ThicknessFactor", 1.2f);
            mat.SetColor("_AttenuationColor", new Color(0.75f, 0.92f, 0.88f, 1f));
            mat.SetFloat("_AttenuationDistance", 1.4f);
            mat.SetFloat("_IOR", 1.45f);
            mat.SetFloat("_RefractionStrength", 0.045f);
            mat.SetFloat("_EnvironmentIntensity", 1.2f);
            mat.renderQueue = (int)RenderQueue.Transparent;
            s.GetComponent<MeshRenderer>().sharedMaterial = mat;
        }

        // Liquid-ish tinted ball
        var liquid = CreateSphere("Liquid_Green", root.transform, new Vector3(5.2f, 0.6f, 0f));
        liquid.transform.localScale = Vector3.one * 1.35f;
        var liqMat = CreateMaterial(MatFolder + "/M_Trans_Liquid.mat", ShaderTransmission);
        ApplyMaps(liqMat, Texture2D.whiteTexture, flatMR, flatN, Texture2D.whiteTexture);
        liqMat.SetColor("_BaseColorFactor", new Color(0.4f, 0.9f, 0.55f, 0.1f));
        liqMat.SetFloat("_MetallicFactor", 0f);
        liqMat.SetFloat("_RoughnessFactor", 0.08f);
        liqMat.SetFloat("_TransmissionFactor", 0.95f);
        liqMat.SetFloat("_ThicknessFactor", 2.0f);
        liqMat.SetColor("_AttenuationColor", new Color(0.3f, 0.85f, 0.45f, 1f));
        liqMat.SetFloat("_AttenuationDistance", 0.8f);
        liqMat.SetFloat("_IOR", 1.33f);
        liquid.GetComponent<MeshRenderer>().sharedMaterial = liqMat;

        CreateLabel(root.transform, "透射→0.25..1   粗糙度↓0..0.85", new Vector3(2.0f, -0.55f, 0f));
    }

    static void FrameCamera()
    {
        var cam = Camera.main;
        if (cam == null) return;
        cam.fieldOfView = 50f;
        cam.transform.position = new Vector3(0.2f, 11.5f, -14.5f);
        cam.transform.LookAt(new Vector3(-0.5f, 1.8f, 2.0f));
    }

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------
    static GameObject CreateSphere(string name, Transform parent, Vector3 localPos)
    {
        var go = GameObject.CreatePrimitive(PrimitiveType.Sphere);
        go.name = name;
        go.transform.SetParent(parent, false);
        go.transform.localPosition = localPos;
        go.transform.localScale = Vector3.one;
        Object.DestroyImmediate(go.GetComponent<Collider>());
        return go;
    }

    static void CreateLabel(Transform parent, string text, Vector3 localPos)
    {
        var go = new GameObject("Label_" + text.Split('\n')[0]);
        go.transform.SetParent(parent, false);
        go.transform.localPosition = localPos;
        var tm = go.AddComponent<TextMesh>();
        tm.text = text;
        tm.fontSize = 32;
        tm.characterSize = 0.048f;
        tm.anchor = TextAnchor.MiddleCenter;
        tm.alignment = TextAlignment.Center;
        tm.color = new Color(0.08f, 0.08f, 0.1f, 1f);
        var font = AssetDatabase.LoadAssetAtPath<Font>("Assets/Resources/Fonts/SimHei.ttf");
        if (font == null)
        {
            font = Font.CreateDynamicFontFromOSFont(
                new[] { "Microsoft YaHei", "Microsoft YaHei UI", "SimHei", "SimSun" }, 32);
        }
        if (font != null)
        {
            tm.font = font;
            var mr = tm.GetComponent<MeshRenderer>();
            if (mr != null) mr.sharedMaterial = font.material;
            font.RequestCharactersInTexture(text, tm.fontSize, tm.fontStyle);
        }
    }

    static Material CreateMaterial(string path, string shaderName)
    {
        var shader = Shader.Find(shaderName);
        if (shader == null)
        {
            Debug.LogError("Shader not found: " + shaderName);
            shader = Shader.Find("Universal Render Pipeline/Lit");
        }

        var existing = AssetDatabase.LoadAssetAtPath<Material>(path);
        if (existing != null)
        {
            existing.shader = shader;
            EditorUtility.SetDirty(existing);
            return existing;
        }

        var mat = new Material(shader) { name = Path.GetFileNameWithoutExtension(path) };
        AssetDatabase.CreateAsset(mat, path);
        return mat;
    }

    static void ApplyMaps(Material mat, Texture baseMap, Texture mr, Texture normal, Texture ao)
    {
        if (mat.HasProperty("_BaseMap")) mat.SetTexture("_BaseMap", baseMap);
        if (mat.HasProperty("_MetallicRoughnessMap")) mat.SetTexture("_MetallicRoughnessMap", mr);
        if (mat.HasProperty("_BumpMap")) mat.SetTexture("_BumpMap", normal);
        if (mat.HasProperty("_OcclusionMap")) mat.SetTexture("_OcclusionMap", ao);
        if (mat.HasProperty("_EmissionMap")) mat.SetTexture("_EmissionMap", Texture2D.whiteTexture);
        if (mat.HasProperty("_EmissionColor")) mat.SetColor("_EmissionColor", Color.black);
    }

    static Texture2D LoadTex(string path)
    {
        return AssetDatabase.LoadAssetAtPath<Texture2D>(path);
    }
}
