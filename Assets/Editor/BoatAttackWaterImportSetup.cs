using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace SRPDemo.EditorTools
{
    /// <summary>
    /// 将移植自 BoatAttack 的 03.Water 场景接到 URP（含 WaterSystemPass 焦散 / WaterFX）。
    /// </summary>
    public static class BoatAttackWaterImportSetup
    {
        const string ScenePath = "Assets/Scenes/03.Water.unity";
        const string PipelinePath = "Assets/Resources/03.water/Data/UniversalRP/PipelineAsset_High.asset";
        const string OriginalPipelinePath = "Assets/Pipelines/New Universal Render Pipeline Asset.asset";

        [MenuItem("SRP Demo/Water/Open 03.Water (BoatAttack Pipeline)")]
        public static void OpenWaterSceneWithPipeline()
        {
            ApplyBoatAttackPipeline();
            if (EditorSceneManager.SaveCurrentModifiedScenesIfUserWantsTo())
                EditorSceneManager.OpenScene(ScenePath);
            CleanupMissingScriptsInOpenScenes();
            Debug.Log("[03.Water] Opened with BoatAttack PipelineAsset_High (WaterFX + Caustics renderer feature).");
        }

        [MenuItem("SRP Demo/Water/Apply BoatAttack URP Pipeline")]
        public static void ApplyBoatAttackPipeline()
        {
            var pipe = AssetDatabase.LoadAssetAtPath<UniversalRenderPipelineAsset>(PipelinePath);
            if (pipe == null)
            {
                Debug.LogError("[03.Water] Missing pipeline: " + PipelinePath);
                return;
            }

            GraphicsSettings.defaultRenderPipeline = pipe;
            var q = QualitySettings.GetQualityLevel();
            QualitySettings.renderPipeline = pipe;
            // Also stamp all quality levels so Play Mode does not fall back.
            for (int i = 0; i < QualitySettings.names.Length; i++)
            {
                QualitySettings.SetQualityLevel(i, false);
                QualitySettings.renderPipeline = pipe;
            }
            QualitySettings.SetQualityLevel(q, true);
            EditorUtility.SetDirty(pipe);
            AssetDatabase.SaveAssets();
            Debug.Log("[03.Water] Active URP pipeline -> PipelineAsset_High");
        }

        [MenuItem("SRP Demo/Water/Restore Project URP Pipeline")]
        public static void RestoreProjectPipeline()
        {
            var pipe = AssetDatabase.LoadAssetAtPath<UniversalRenderPipelineAsset>(OriginalPipelinePath);
            if (pipe == null)
            {
                Debug.LogError("[03.Water] Missing original pipeline: " + OriginalPipelinePath);
                return;
            }
            GraphicsSettings.defaultRenderPipeline = pipe;
            var q = QualitySettings.GetQualityLevel();
            for (int i = 0; i < QualitySettings.names.Length; i++)
            {
                QualitySettings.SetQualityLevel(i, false);
                QualitySettings.renderPipeline = pipe;
            }
            QualitySettings.SetQualityLevel(q, true);
            Debug.Log("[03.Water] Restored project URP pipeline.");
        }

        [MenuItem("SRP Demo/Water/Cleanup Missing Scripts In Open Scenes")]
        public static void CleanupMissingScriptsInOpenScenes()
        {
            int removed = 0;
            for (int s = 0; s < EditorSceneManager.sceneCount; s++)
            {
                var scene = EditorSceneManager.GetSceneAt(s);
                if (!scene.isLoaded) continue;
                foreach (var root in scene.GetRootGameObjects())
                    removed += RemoveMissingRecursive(root);
            }
            if (removed > 0)
            {
                EditorSceneManager.MarkAllScenesDirty();
                Debug.Log($"[03.Water] Removed {removed} missing scripts.");
            }
        }

        static int RemoveMissingRecursive(GameObject go)
        {
            int count = GameObjectUtility.RemoveMonoBehavioursWithMissingScript(go);
            foreach (Transform child in go.transform)
                count += RemoveMissingRecursive(child.gameObject);
            return count;
        }
    }
}
