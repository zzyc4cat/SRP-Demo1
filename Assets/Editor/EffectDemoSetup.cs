using System.IO;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.SceneManagement;

/// <summary>
/// 06.effect 工具：仅为当前保留的 5 个效果维护贴图 / 材质。
/// <para>
/// 保留效果：流光(FlowTranslucent)、管道流水(FlowPipe)、溶解(DissolveFlow)、
/// 真实火焰(FireRealistic)、护盾(Shield)。
/// </para>
/// <para>
/// 菜单默认 <b>不会</b> 重建演示场景，以免覆盖手工调好的场景内容。
/// 场景恢复请使用「Rebuild Scene」子菜单（会覆盖对应场景文件）。
/// </para>
/// </summary>
public static class EffectDemoSetup
{
    const string Root = "Assets/Resources/06.effect";
    const string TexFolder = Root + "/Textures";
    const string MatFolder = Root + "/Materials";
    const string ModelFolder = Root + "/Models";
    const string SceneFolder = "Assets/Scenes";
    const string CharacterPath = "Assets/Resources/01.Character/Model/Funingna/FuFu.fbx";

    // Shared / per-effect textures
    const string NoisePath = TexFolder + "/EffectNoise.png";
    const string FlowPath = TexFolder + "/EffectFlow.png";
    const string HexPath = TexFolder + "/EffectHex.png";
    const string DissolveNoisePath = TexFolder + "/EffectDissolveNoise.png";
    const string FireSrcPath = TexFolder + "/fire_src_1.png";
    const string PipeFlowPath = TexFolder + "/EffectPipeLiquidFlow.png";

    // -------------------------------------------------------------------------
    // Menus
    // -------------------------------------------------------------------------

    [MenuItem("SRP Demo/Effect/Setup Materials & Textures")]
    public static void SetupMaterialsAndTextures()
    {
        EnsureFolders();
        GenerateTextures();
        AssetDatabase.Refresh();
        CreateMaterials();
        AssetDatabase.SaveAssets();
        AssetDatabase.Refresh();
        Debug.Log("[06.effect] Materials & textures updated (scenes untouched).");
    }

    [MenuItem("SRP Demo/Effect/Generate Textures Only")]
    public static void GenerateTexturesMenu()
    {
        EnsureFolders();
        GenerateTextures();
        AssetDatabase.Refresh();
        Debug.Log("[06.effect] Textures generated.");
    }

    [MenuItem("SRP Demo/Effect/Rebuild Scene/FlowTranslucent")]
    public static void MenuRebuildFlowTranslucent() => InvokeSceneRebuild(CreateFlowTranslucentScene);

    [MenuItem("SRP Demo/Effect/Rebuild Scene/FlowPipe")]
    public static void MenuRebuildFlowPipe() => InvokeSceneRebuild(CreateFlowPipeScene);

    [MenuItem("SRP Demo/Effect/Rebuild Scene/DissolveFlow")]
    public static void MenuRebuildDissolve() => InvokeSceneRebuild(CreateDissolveScene);

    [MenuItem("SRP Demo/Effect/Rebuild Scene/FireRealistic")]
    public static void MenuRebuildFire() => InvokeSceneRebuild(CreateFireRealisticScene);

    [MenuItem("SRP Demo/Effect/Rebuild Scene/Shield")]
    public static void MenuRebuildShield() => InvokeSceneRebuild(CreateShieldScene);

    static void InvokeSceneRebuild(System.Action builder)
    {
        builder();
        Debug.Log("[06.effect] Scene rebuilt. Previous scene content for that file was overwritten.");
    }

    // -------------------------------------------------------------------------
    // Folders / IO
    // -------------------------------------------------------------------------

    static void EnsureFolders()
    {
        Directory.CreateDirectory(Abs(TexFolder));
        Directory.CreateDirectory(Abs(MatFolder));
        Directory.CreateDirectory(Abs(ModelFolder));
        Directory.CreateDirectory(Abs(Root + "/Shaders/Library"));
        Directory.CreateDirectory(Abs(Root + "/Scripts"));
        Directory.CreateDirectory(Abs(SceneFolder));
    }

    static string Abs(string assetPath) =>
        Path.GetFullPath(Path.Combine(Application.dataPath, "..", assetPath));

    static Texture2D LoadTex(string path) => AssetDatabase.LoadAssetAtPath<Texture2D>(path);

    // -------------------------------------------------------------------------
    // Textures (shared + dissolve / flow / shield helpers)
    // -------------------------------------------------------------------------

    static void GenerateTextures()
    {
        WritePng(NoisePath, BuildNoise(256));
        WritePng(DissolveNoisePath, BuildDissolveNoise(256));
        WritePng(FlowPath, BuildFlow(256));
        WritePng(HexPath, BuildHex(256));

        ConfigureTexture(NoisePath, true);
        ConfigureTexture(DissolveNoisePath, true);
        ConfigureTexture(FlowPath, true);
        ConfigureTexture(HexPath, true);

        if (File.Exists(Abs(FireSrcPath)))
            ConfigureFireFlipbook(FireSrcPath);
        if (File.Exists(Abs(PipeFlowPath)))
            ConfigureTexture(PipeFlowPath, true);
    }

    static Texture2D BuildNoise(int size)
    {
        var tex = new Texture2D(size, size, TextureFormat.RGBA32, false, true);
        var px = new Color[size * size];
        for (int y = 0; y < size; y++)
        for (int x = 0; x < size; x++)
        {
            float n = Mathf.PerlinNoise(x * 0.07f, y * 0.07f) * 0.55f
                    + Mathf.PerlinNoise(x * 0.21f + 10, y * 0.21f) * 0.3f
                    + Mathf.PerlinNoise(x * 0.55f + 3, y * 0.55f + 7) * 0.15f;
            px[y * size + x] = new Color(n, n, n, 1);
        }
        tex.SetPixels(px);
        tex.Apply(false, false);
        return tex;
    }

    static Texture2D BuildDissolveNoise(int size)
    {
        var tex = new Texture2D(size, size, TextureFormat.RGBA32, false, true);
        var px = new Color[size * size];
        for (int y = 0; y < size; y++)
        for (int x = 0; x < size; x++)
        {
            float n = Mathf.Pow(Mathf.PerlinNoise(x * 0.045f, y * 0.045f), 1.2f);
            px[y * size + x] = new Color(n, n, n, 1);
        }
        tex.SetPixels(px);
        tex.Apply(false, false);
        return tex;
    }

    /// <summary>无缝水平条带流光图（U/V 可 tile），供流光 / 溶解边缘流动使用。</summary>
    static Texture2D BuildFlow(int size)
    {
        var tex = new Texture2D(size, size, TextureFormat.RGBA32, false, true);
        var px = new Color[size * size];
        const float bandsV = 3f;
        for (int y = 0; y < size; y++)
        for (int x = 0; x < size; x++)
        {
            float u = x / (float)size;
            float v = y / (float)size;
            float streak = Mathf.Sin(v * bandsV * Mathf.PI * 2f) * 0.5f + 0.5f;
            streak = Mathf.Pow(streak, 5.5f);
            float wobble = 0.85f + 0.15f * (Mathf.Sin(u * Mathf.PI * 2f) * 0.5f + 0.5f);
            float a = Mathf.Clamp01(streak * wobble);
            px[y * size + x] = new Color(a, a, a, a);
        }
        tex.SetPixels(px);
        tex.Apply(false, false);
        return tex;
    }

    static Texture2D BuildHex(int size)
    {
        var tex = new Texture2D(size, size, TextureFormat.RGBA32, false, true);
        var px = new Color[size * size];
        float cell = size / 8f;
        for (int y = 0; y < size; y++)
        for (int x = 0; x < size; x++)
        {
            float fx = x / cell;
            float fy = y / cell;
            float sx = fx + fy * 0.5f;
            float cx = Mathf.Abs(Frac(sx) - 0.5f);
            float cy = Mathf.Abs(Frac(fy) - 0.5f);
            float edge = Mathf.Max(cx * 1.2f, cy);
            float line = 1f - Mathf.SmoothStep(0.42f, 0.48f, edge);
            float pulse = Mathf.PerlinNoise(fx * 0.4f, fy * 0.4f);
            float v = Mathf.Clamp01(line * 0.9f + pulse * 0.15f);
            px[y * size + x] = new Color(v, v, v, v);
        }
        tex.SetPixels(px);
        tex.Apply(false, false);
        return tex;
    }

    static float Frac(float v) => v - Mathf.Floor(v);

    static void WritePng(string assetPath, Texture2D tex)
    {
        File.WriteAllBytes(Abs(assetPath), tex.EncodeToPNG());
        Object.DestroyImmediate(tex);
        AssetDatabase.ImportAsset(assetPath);
    }

    static void ConfigureTexture(string assetPath, bool linear)
    {
        var importer = AssetImporter.GetAtPath(assetPath) as TextureImporter;
        if (importer == null) return;
        importer.sRGBTexture = !linear;
        importer.wrapMode = TextureWrapMode.Repeat;
        importer.mipmapEnabled = true;
        importer.alphaSource = TextureImporterAlphaSource.FromInput;
        importer.SaveAndReimport();
    }

    static void ConfigureFireFlipbook(string assetPath)
    {
        var importer = AssetImporter.GetAtPath(assetPath) as TextureImporter;
        if (importer == null) return;
        importer.sRGBTexture = true;
        importer.wrapMode = TextureWrapMode.Clamp;
        importer.filterMode = FilterMode.Bilinear;
        importer.mipmapEnabled = false;
        importer.alphaSource = TextureImporterAlphaSource.FromInput;
        importer.alphaIsTransparency = true;
        importer.SaveAndReimport();
    }

    // -------------------------------------------------------------------------
    // Materials — 5 kept effects only
    // -------------------------------------------------------------------------

    static void CreateMaterials()
    {
        var noise = LoadTex(NoisePath);
        var flow = LoadTex(FlowPath);
        var hex = LoadTex(HexPath);
        var dissolveNoise = LoadTex(DissolveNoisePath);
        var fireSrc = LoadTex(FireSrcPath);
        var pipeFlow = LoadTex(PipeFlowPath);

        // --- 流光 FlowTranslucent ---
        var translucent = CreateMat("FlowTranslucent", "ZZY/06.effect/FlowTranslucent");
        translucent.SetTexture("_BaseMap", noise);
        translucent.SetTexture("_FlowMap", flow);
        translucent.SetColor("_RimColor", new Color(0.3f, 0.9f, 1.2f, 1f));
        translucent.SetVector("_FlowTiling", new Vector4(0.35f, 0.35f, 0f, 0f));
        translucent.SetVector("_FlowSpeed", new Vector4(0f, 0.12f, 0f, 0f));
        translucent.SetFloat("_FlowIntensity", 1.25f);
        translucent.SetFloat("_FlowPower", 1.8f);

        // --- 管道流水 FlowPipe + Glass ---
        var pipe = CreateMat("FlowPipe", "ZZY/06.effect/FlowPipe");
        if (pipeFlow != null) pipe.SetTexture("_FlowMap", pipeFlow);
        pipe.SetColor("_BaseColor", new Color(0.08f, 0.42f, 0.92f, 0.36f));
        pipe.SetColor("_HighlightColor", new Color(0.7f, 0.96f, 1.25f, 1f));
        pipe.SetVector("_FlowScale", new Vector4(2.2f, 1.0f, 0f, 0f));
        pipe.SetVector("_FlowSpeed", new Vector4(0f, 0.28f, 0f, 0f));
        pipe.SetFloat("_WaveAmp", 0.008f);
        pipe.SetFloat("_FlowIntensity", 0.7f);

        var pipeGlass = CreateMat("FlowPipeGlass", "ZZY/06.effect/FlowPipeGlass");
        pipeGlass.SetColor("_BaseColor", new Color(0.75f, 0.9f, 1f, 0.05f));

        // --- 溶解 DissolveFlow ---
        var dissolve = CreateMat("DissolveFlow", "ZZY/06.effect/DissolveFlow");
        dissolve.SetTexture("_NoiseMap", dissolveNoise);
        dissolve.SetTexture("_FlowMap", flow);

        // --- 真实火焰 FireRealistic ---
        var fireReal = CreateMat("FireRealistic", "ZZY/06.effect/FireRealistic");
        fireReal.SetTexture("_NoiseMap", noise);
        if (fireSrc != null) fireReal.SetTexture("_MainTex", fireSrc);
        fireReal.SetColor("_CoreColor", new Color(2.4f, 2.05f, 1.2f, 1f));
        fireReal.SetColor("_MidColor", new Color(1.85f, 0.52f, 0.06f, 1f));
        fireReal.SetColor("_TipColor", new Color(0.45f, 0.06f, 0.01f, 1f));
        fireReal.SetFloat("_Columns", 12f);
        fireReal.SetFloat("_Rows", 6f);
        fireReal.SetFloat("_FPS", 26f);
        fireReal.SetFloat("_Intensity", 3.2f);

        var fireRealB = CreateMat("FireRealistic_B", "ZZY/06.effect/FireRealistic");
        fireRealB.CopyPropertiesFromMaterial(fireReal);
        fireRealB.SetFloat("_TimeOffset", 1.7f);
        fireRealB.SetFloat("_Intensity", 2.4f);
        fireRealB.SetFloat("_Distort", 0.11f);
        fireRealB.SetFloat("_FPS", 22f);

        // --- 护盾 Shield ---
        var shield = CreateMat("Shield", "ZZY/06.effect/Shield");
        shield.SetTexture("_FlowMap", hex);
        var blink = LoadTex(TexFolder + "/EffectBlinkChecker.png");
        if (blink != null) shield.SetTexture("_BlinkMap", blink);

        EditorUtility.SetDirty(translucent);
        EditorUtility.SetDirty(pipe);
        EditorUtility.SetDirty(pipeGlass);
        EditorUtility.SetDirty(dissolve);
        EditorUtility.SetDirty(fireReal);
        EditorUtility.SetDirty(fireRealB);
        EditorUtility.SetDirty(shield);
    }

    static Material CreateMat(string name, string shaderName)
    {
        string path = $"{MatFolder}/{name}.mat";
        var shader = Shader.Find(shaderName);
        if (shader == null)
        {
            Debug.LogError($"[06.effect] Shader not found: {shaderName}");
            shader = Shader.Find("Universal Render Pipeline/Lit");
        }

        var mat = AssetDatabase.LoadAssetAtPath<Material>(path);
        if (mat == null)
        {
            mat = new Material(shader);
            AssetDatabase.CreateAsset(mat, path);
        }
        else
        {
            mat.shader = shader;
        }
        return mat;
    }

    // -------------------------------------------------------------------------
    // Scene helpers
    // -------------------------------------------------------------------------

    static Scene NewScene(string sceneName)
    {
        var scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
        var camGo = new GameObject("Main Camera");
        var cam = camGo.AddComponent<Camera>();
        camGo.tag = "MainCamera";
        camGo.AddComponent<AudioListener>();
        cam.clearFlags = CameraClearFlags.SolidColor;
        cam.backgroundColor = new Color(0.05f, 0.06f, 0.08f);
        cam.allowHDR = true;
        cam.fieldOfView = 40f;
        cam.depthTextureMode |= DepthTextureMode.Depth;
        cam.transform.SetPositionAndRotation(new Vector3(0, 1.2f, -3.5f), Quaternion.Euler(10, 0, 0));

        var lightGo = new GameObject("Directional Light");
        var light = lightGo.AddComponent<Light>();
        light.type = LightType.Directional;
        light.intensity = 1.1f;
        lightGo.transform.rotation = Quaternion.Euler(50, -30, 0);

        EnsureFloor();
        EditorSceneManager.SaveScene(scene, $"{SceneFolder}/{sceneName}.unity");
        return scene;
    }

    static void SaveActiveScene()
    {
        var scene = SceneManager.GetActiveScene();
        EditorSceneManager.MarkSceneDirty(scene);
        EditorSceneManager.SaveScene(scene, scene.path);
    }

    static void EnsureMainCamera(Vector3 pos, Quaternion rot)
    {
        var cam = Camera.main;
        if (cam == null)
        {
            var go = new GameObject("Main Camera");
            cam = go.AddComponent<Camera>();
            go.tag = "MainCamera";
            go.AddComponent<AudioListener>();
        }
        cam.transform.SetPositionAndRotation(pos, rot);
        cam.clearFlags = CameraClearFlags.SolidColor;
        cam.backgroundColor = new Color(0.05f, 0.06f, 0.08f);
        cam.allowHDR = true;
    }

    static void EnsureFloor()
    {
        var floor = GameObject.CreatePrimitive(PrimitiveType.Plane);
        floor.name = "Floor";
        floor.transform.position = Vector3.zero;
        var r = floor.GetComponent<Renderer>();
        r.sharedMaterial = new Material(Shader.Find("Universal Render Pipeline/Lit"))
        {
            color = new Color(0.12f, 0.12f, 0.14f)
        };
    }

    static Font LoadChineseFont(int size = 48)
    {
        var font = AssetDatabase.LoadAssetAtPath<Font>("Assets/Resources/Fonts/SimHei.ttf");
        if (font != null) return font;
        return Font.CreateDynamicFontFromOSFont(
            new[] { "Microsoft YaHei", "Microsoft YaHei UI", "SimHei", "SimSun" }, size);
    }

    static void PlaceLabel(string text, Vector3 pos)
    {
        var go = new GameObject("Label_" + text.Split('\n')[0]);
        go.transform.position = pos;
        var tm = go.AddComponent<TextMesh>();
        tm.text = text;
        tm.fontSize = 48;
        tm.characterSize = 0.055f;
        tm.anchor = TextAnchor.MiddleCenter;
        tm.alignment = TextAlignment.Center;
        tm.color = Color.white;
        var font = LoadChineseFont(48);
        if (font != null)
        {
            tm.font = font;
            var mr = tm.GetComponent<MeshRenderer>();
            if (mr != null) mr.sharedMaterial = font.material;
            font.RequestCharactersInTexture(text, tm.fontSize, tm.fontStyle);
        }
    }

    static void FrameFocus(params GameObject[] focus)
    {
        var cam = Camera.main;
        if (cam == null || focus == null) return;
        var list = new System.Collections.Generic.List<Renderer>();
        foreach (var go in focus)
        {
            if (go == null) continue;
            list.AddRange(go.GetComponentsInChildren<Renderer>(true));
        }
        // 把说明文字也纳入取景，避免标题飞出画面
        foreach (var tm in Object.FindObjectsOfType<TextMesh>(true))
        {
            var r = tm.GetComponent<Renderer>();
            if (r != null) list.Add(r);
        }
        if (list.Count == 0) return;
        var b = list[0].bounds;
        for (int i = 1; i < list.Count; i++) b.Encapsulate(list[i].bounds);
        float radius = Mathf.Max(b.extents.magnitude, 0.8f);
        float dist = Mathf.Clamp(radius * 2.75f, 2.8f, 11f);
        cam.transform.position = b.center + new Vector3(0, radius * 0.15f, -dist);
        cam.transform.LookAt(b.center);
        cam.fieldOfView = Mathf.Clamp(cam.fieldOfView, 40f, 55f);
    }

    static GameObject SpawnCharacter(Material overrideMat, Vector3 pos, float scale)
    {
        var model = AssetDatabase.LoadAssetAtPath<GameObject>(CharacterPath);
        GameObject root;
        if (model != null)
        {
            root = Object.Instantiate(model);
            root.name = "Character";
            root.transform.position = pos;
            root.transform.localScale = Vector3.one * scale;
            if (PrefabUtility.IsPartOfPrefabInstance(root))
                PrefabUtility.UnpackPrefabInstance(root, PrefabUnpackMode.Completely, InteractionMode.AutomatedAction);
            if (overrideMat != null)
            {
                foreach (var r in root.GetComponentsInChildren<Renderer>(true))
                    r.sharedMaterial = overrideMat;
            }
        }
        else
        {
            root = new GameObject("CharacterFallback");
            root.transform.position = pos;
            var body = GameObject.CreatePrimitive(PrimitiveType.Capsule);
            body.transform.SetParent(root.transform, false);
            body.transform.localScale = new Vector3(0.7f, 1f, 0.7f) * scale;
            if (overrideMat != null)
                body.GetComponent<Renderer>().sharedMaterial = overrideMat;
        }
        return root;
    }

    static GameObject CreateFireQuad(string name, Material mat, Vector3 pos, Vector2 size)
    {
        var go = GameObject.CreatePrimitive(PrimitiveType.Quad);
        Object.DestroyImmediate(go.GetComponent<Collider>());
        go.name = name;
        go.transform.position = pos;
        go.transform.localScale = new Vector3(size.x, size.y, 1);
        go.GetComponent<Renderer>().sharedMaterial = mat;
        return go;
    }

    static void CreateLog(Transform parent, Vector3 pos, Vector3 scale, float yaw, Material mat)
    {
        var log = GameObject.CreatePrimitive(PrimitiveType.Cylinder);
        Object.DestroyImmediate(log.GetComponent<Collider>());
        log.name = "Log";
        log.transform.SetParent(parent, false);
        log.transform.localPosition = pos;
        log.transform.localRotation = Quaternion.Euler(0f, yaw, 90f);
        log.transform.localScale = scale;
        log.GetComponent<Renderer>().sharedMaterial = mat;
    }

    static void EnsureTag(string tag)
    {
        var asset = AssetDatabase.LoadAllAssetsAtPath("ProjectSettings/TagManager.asset");
        if (asset == null || asset.Length == 0) return;
        var so = new SerializedObject(asset[0]);
        var tags = so.FindProperty("tags");
        for (int i = 0; i < tags.arraySize; i++)
        {
            if (tags.GetArrayElementAtIndex(i).stringValue == tag)
                return;
        }
        tags.InsertArrayElementAtIndex(tags.arraySize);
        tags.GetArrayElementAtIndex(tags.arraySize - 1).stringValue = tag;
        so.ApplyModifiedProperties();
    }

    // -------------------------------------------------------------------------
    // Scene builders (optional recovery only)
    // -------------------------------------------------------------------------

    static void CreateFlowTranslucentScene()
    {
        NewScene("06.effect_FlowTranslucent");
        var mat = AssetDatabase.LoadAssetAtPath<Material>($"{MatFolder}/FlowTranslucent.mat");
        var ch = SpawnCharacter(mat, Vector3.zero, 1f);
        PlaceLabel("流光半透明", new Vector3(0, 2.05f, 0));
        FrameFocus(ch);
        SaveActiveScene();
    }

    static void CreateFlowPipeScene()
    {
        NewScene("06.effect_FlowPipe");
        var liqMat = AssetDatabase.LoadAssetAtPath<Material>($"{MatFolder}/FlowPipe.mat");
        var glassMat = AssetDatabase.LoadAssetAtPath<Material>($"{MatFolder}/FlowPipeGlass.mat");
        var model = AssetDatabase.LoadAssetAtPath<GameObject>($"{ModelFolder}/FlowPipe.fbx");

        GameObject root;
        if (model != null)
        {
            root = Object.Instantiate(model);
            root.name = "FlowPipe";
            root.transform.position = new Vector3(0f, 0.05f, 0f);
            if (PrefabUtility.IsPartOfPrefabInstance(root))
                PrefabUtility.UnpackPrefabInstance(root, PrefabUnpackMode.Completely, InteractionMode.AutomatedAction);
            foreach (var r in root.GetComponentsInChildren<Renderer>(true))
            {
                string n = r.gameObject.name.ToLowerInvariant();
                if (n.Contains("glass") && glassMat != null)
                    r.sharedMaterial = glassMat;
                else if (liqMat != null)
                    r.sharedMaterial = liqMat;
            }
        }
        else
        {
            root = new GameObject("FlowPipe");
        }

        PlaceLabel("管道流水（玻璃 + 软液体）", new Vector3(0, 2.35f, 0));
        EnsureMainCamera(new Vector3(0.15f, 1.45f, -6.6f), Quaternion.Euler(8f, -3f, 0f));
        if (Camera.main != null) Camera.main.fieldOfView = 50f;
        SaveActiveScene();
    }

    static void CreateDissolveScene()
    {
        NewScene("06.effect_DissolveFlow");
        var mat = AssetDatabase.LoadAssetAtPath<Material>($"{MatFolder}/DissolveFlow.mat");
        var sphere = GameObject.CreatePrimitive(PrimitiveType.Sphere);
        sphere.name = "DissolveSphere";
        sphere.transform.position = new Vector3(0, 1f, 0);
        sphere.transform.localScale = Vector3.one * 1.6f;
        sphere.GetComponent<Renderer>().sharedMaterial = mat;
        PlaceLabel("溶解流光 + 边缘光", new Vector3(0, 2.15f, 0));
        EnsureMainCamera(new Vector3(0, 1.25f, -3.5f), Quaternion.Euler(8, 0, 0));
        if (Camera.main != null) Camera.main.fieldOfView = 42f;
        SaveActiveScene();
    }

    static void CreateFireRealisticScene()
    {
        NewScene("06.effect_FireRealistic");
        var key = Object.FindObjectOfType<Light>();
        if (key != null && key.type == LightType.Directional)
        {
            key.intensity = 0.18f;
            key.color = new Color(0.35f, 0.42f, 0.55f);
        }
        if (Camera.main != null)
            Camera.main.backgroundColor = new Color(0.015f, 0.02f, 0.035f);

        var matA = AssetDatabase.LoadAssetAtPath<Material>($"{MatFolder}/FireRealistic.mat");
        var matB = AssetDatabase.LoadAssetAtPath<Material>($"{MatFolder}/FireRealistic_B.mat");
        if (matB == null) matB = matA;

        var root = new GameObject("Campfire");
        var q0 = CreateFireQuad("Flame_A", matA, new Vector3(0f, 1.05f, 0f), new Vector2(1.55f, 2.35f));
        q0.transform.SetParent(root.transform, true);
        var q1 = CreateFireQuad("Flame_B", matB, new Vector3(0.02f, 1.0f, 0.02f), new Vector2(1.35f, 2.15f));
        q1.transform.SetParent(root.transform, true);
        q1.transform.rotation = Quaternion.Euler(0f, 55f, 0f);
        var q2 = CreateFireQuad("Flame_C", matB, new Vector3(-0.03f, 0.98f, -0.01f), new Vector2(1.15f, 1.95f));
        q2.transform.SetParent(root.transform, true);
        q2.transform.rotation = Quaternion.Euler(0f, -40f, 0f);

        var woodMat = new Material(Shader.Find("Universal Render Pipeline/Lit")) { color = new Color(0.12f, 0.07f, 0.04f) };
        CreateLog(root.transform, new Vector3(0.28f, 0.08f, 0.05f), new Vector3(0.55f, 0.12f, 0.14f), 25f, woodMat);
        CreateLog(root.transform, new Vector3(-0.22f, 0.07f, -0.08f), new Vector3(0.5f, 0.11f, 0.13f), -35f, woodMat);
        CreateLog(root.transform, new Vector3(0.05f, 0.06f, 0.22f), new Vector3(0.42f, 0.1f, 0.12f), 80f, woodMat);

        var ash = GameObject.CreatePrimitive(PrimitiveType.Cylinder);
        Object.DestroyImmediate(ash.GetComponent<Collider>());
        ash.name = "AshRing";
        ash.transform.SetParent(root.transform, false);
        ash.transform.localPosition = new Vector3(0f, 0.02f, 0f);
        ash.transform.localScale = new Vector3(0.85f, 0.02f, 0.85f);
        ash.GetComponent<Renderer>().sharedMaterial = new Material(Shader.Find("Universal Render Pipeline/Lit"))
        {
            color = new Color(0.18f, 0.16f, 0.14f)
        };

        var glow = new GameObject("FireGlow");
        glow.transform.SetParent(root.transform, false);
        glow.transform.localPosition = new Vector3(0f, 0.45f, 0f);
        var pl = glow.AddComponent<Light>();
        pl.type = LightType.Point;
        pl.color = new Color(1f, 0.45f, 0.12f);
        pl.intensity = 4.5f;
        pl.range = 5.5f;

        PlaceLabel("写实火焰（无烟雾）", new Vector3(0, 2.35f, 0));
        EnsureMainCamera(new Vector3(0.1f, 1.35f, -3.7f), Quaternion.Euler(8f, -2f, 0f));
        if (Camera.main != null) Camera.main.fieldOfView = 42f;
        SaveActiveScene();
    }

    static void CreateShieldScene()
    {
        NewScene("06.effect_Shield");
        EnsureTag("CollisionShield");

        var mat = AssetDatabase.LoadAssetAtPath<Material>($"{MatFolder}/Shield.mat");
        var runtimeMesh = AssetDatabase.LoadAssetAtPath<Mesh>($"{ModelFolder}/ShieldHexSphere_Runtime.asset");

        var cube = GameObject.CreatePrimitive(PrimitiveType.Cube);
        cube.name = "Obstacle";
        cube.transform.position = new Vector3(0, 0.7f, 0);
        cube.transform.localScale = new Vector3(0.65f, 1.2f, 0.65f);
        cube.GetComponent<Renderer>().sharedMaterial = new Material(Shader.Find("Universal Render Pipeline/Lit"))
        {
            color = new Color(0.25f, 0.25f, 0.28f)
        };

        GameObject shield;
        if (runtimeMesh != null)
        {
            shield = new GameObject("EnergyShield");
            shield.AddComponent<MeshFilter>().sharedMesh = runtimeMesh;
            shield.AddComponent<MeshRenderer>();
        }
        else
        {
            shield = GameObject.CreatePrimitive(PrimitiveType.Sphere);
        }

        shield.name = "EnergyShield";
        shield.tag = "CollisionShield";
        shield.transform.localScale = Vector3.one * 1.6f;
        foreach (var r in shield.GetComponentsInChildren<Renderer>())
        {
            r.sharedMaterial = mat;
            r.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
        }

        foreach (var c in shield.GetComponentsInChildren<Collider>())
            Object.DestroyImmediate(c);
        var mf = shield.GetComponentInChildren<MeshFilter>();
        if (mf != null)
        {
            var mc = mf.gameObject.AddComponent<MeshCollider>();
            mc.sharedMesh = mf.sharedMesh;
        }

        PlaceLabel("等尺寸六边形护盾", new Vector3(0, 2.45f, 0));
        FrameFocus(shield, cube);
        if (Camera.main != null)
        {
            Camera.main.fieldOfView = 42f;
            Camera.main.depthTextureMode |= DepthTextureMode.Depth;
        }
        SaveActiveScene();
    }
}
