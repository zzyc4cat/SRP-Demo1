#if UNITY_EDITOR
using System.IO;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.SceneManagement;

namespace CustomPP.Editor
{
    /// <summary>
    /// 编辑器安装工具：挂 Feature、改造测试场景。
    /// </summary>
    public static class CustomPostProcessInstaller
    {
        const string RendererPath = "Assets/Pipelines/New Universal Render Pipeline Asset_Renderer.asset";
        const string ScenePath = "Assets/Scenes/05.PostProcessing.unity";
        const string ShaderFolder = "Assets/Resources/05.renderfeature/Shaders";

        /// <summary>Bloom 演示默认 Layer：Bloom（TagManager index 13）</summary>
        const int BloomDemoLayer = 13;

        [MenuItem("SRP Demo/Post Processing/Install Custom RenderFeature")]
        public static void InstallFeature()
        {
            var renderer = AssetDatabase.LoadAssetAtPath<ScriptableRendererData>(RendererPath);
            if (renderer == null)
            {
                Debug.LogError($"[CustomPP] Missing renderer: {RendererPath}");
                return;
            }

            for (int i = renderer.rendererFeatures.Count - 1; i >= 0; i--)
            {
                var f = renderer.rendererFeatures[i];
                if (f == null || f is CustomPostProcessFeature ||
                    (f != null && f.GetType().Name.Contains("CustomPostProcess")))
                {
                    renderer.rendererFeatures.RemoveAt(i);
                    if (f != null)
                        Object.DestroyImmediate(f, true);
                }
            }

            var feature = ScriptableObject.CreateInstance<CustomPostProcessFeature>();
            feature.name = "CustomPostProcessFeature";
            feature.settings.injectionPoint = CustomPostProcessFeature.InjectionPoint.BeforePostProcessing;
            feature.settings.gameAndSceneOnly = true;

            var ov = feature.settings.shaderOverrides;
            ov.copy = LoadShader("05.renderfeature_Copy.shader", "ZZY/05.renderfeature/Copy");
            ov.heightFog = LoadShader("05.renderfeature_HeightFog.shader", "ZZY/05.renderfeature/HeightFog");
            ov.depthFog = LoadShader("05.renderfeature_DepthFog.shader", "ZZY/05.renderfeature/DepthFog");
            ov.depthOfField = LoadShader("05.renderfeature_DepthOfField.shader", "ZZY/05.renderfeature/DepthOfField");
            ov.bloom = LoadShader("05.renderfeature_Bloom.shader", "ZZY/05.renderfeature/Bloom");
            ov.outline = LoadShader("05.renderfeature_Outline.shader", "ZZY/05.renderfeature/Outline");
            ov.chromaticAberration = LoadShader("05.renderfeature_ChromaticAberration.shader", "ZZY/05.renderfeature/ChromaticAberration");
            ov.tonemapping = LoadShader("05.renderfeature_Tonemapping.shader", "ZZY/05.renderfeature/Tonemapping");

            AssetDatabase.AddObjectToAsset(feature, renderer);
            renderer.rendererFeatures.Add(feature);
            feature.Create();

            EditorUtility.SetDirty(renderer);
            AssetDatabase.SaveAssets();
            Debug.Log("[CustomPP] Feature installed (HeightFog / DepthFog / LayerBloom).");
        }

        [MenuItem("SRP Demo/Post Processing/Upgrade Test Scene To Manager")]
        public static void UpgradeTestScene()
        {
            InstallFeature();

            if (!File.Exists(Path.GetFullPath(Path.Combine(Application.dataPath, "..", ScenePath))))
            {
                Debug.LogError($"[CustomPP] Scene missing: {ScenePath}");
                return;
            }

            var scene = EditorSceneManager.OpenScene(ScenePath, OpenSceneMode.Single);

            foreach (var volume in Object.FindObjectsOfType<Volume>())
                Object.DestroyImmediate(volume.gameObject);

            var manager = Object.FindObjectOfType<CustomPostProcessManager>();
            if (manager == null)
            {
                var go = new GameObject("CustomPostProcessManager");
                manager = go.AddComponent<CustomPostProcessManager>();
            }

            manager.enablePostProcess = true;
            manager.heightFog.enabled = true;
            manager.depthFog.enabled = true;
            manager.depthOfField.enabled = true;
            manager.bloom.enabled = true;
            manager.bloom.layerMask = 1 << BloomDemoLayer; // Bloom
            manager.outline.enabled = true;
            manager.chromaticAberration.enabled = true;
            manager.tonemapping.enabled = true;

            // Bloom 源物体放到 Bloom Layer，其它物体不在该层 → 不受 Bloom 提取
            var bloomGo = GameObject.Find("BloomEmitter");
            if (bloomGo != null)
            {
                bloomGo.layer = BloomDemoLayer;
                Debug.Log($"[CustomPP] BloomEmitter → layer Bloom ({BloomDemoLayer})");
            }

            var cam = Camera.main;
            if (cam != null)
            {
                var data = cam.GetComponent<UniversalAdditionalCameraData>();
                if (data == null)
                    data = cam.gameObject.AddComponent<UniversalAdditionalCameraData>();
                data.renderPostProcessing = false;
                data.requiresDepthOption = CameraOverrideOption.On;
                data.requiresColorOption = CameraOverrideOption.On;
            }

            EditorSceneManager.MarkSceneDirty(scene);
            EditorSceneManager.SaveScene(scene);
            Debug.Log("[CustomPP] Test scene updated.");
        }

        [MenuItem("SRP Demo/Post Processing/Setup All (Custom RF)")]
        public static void SetupAll()
        {
            InstallFeature();
            UpgradeTestScene();
        }

        static Shader LoadShader(string fileName, string shaderName)
        {
            var s = AssetDatabase.LoadAssetAtPath<Shader>($"{ShaderFolder}/{fileName}");
            if (s == null)
                s = Shader.Find(shaderName);
            return s;
        }
    }
}
#endif
