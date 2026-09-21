using UnityEditor;
using UnityEngine;
using FFTOcean;

namespace SRPDemo.EditorTools
{
    /// <summary>
    /// 刷新 03.gpu_FFT_Ocean 材质，以及 fftPow 质量档（N = 2^fftPow）。
    /// </summary>
    public static class FFTOceanAssetGenerator
    {
        const string Root = "Assets/Resources/03.gpu_FFT_Ocean";
        const string MaterialPath = Root + "/Materials/FFTOcean.mat";
        const string ShaderName = "ZZY/03.gpu_FFT_Ocean/FFTOcean";

        [MenuItem("SRP Demo/FFT Ocean/Refresh Material")]
        public static void CreateOrRefreshMaterial()
        {
            var shader = Shader.Find(ShaderName);
            if (shader == null)
            {
                Debug.LogError($"[FFT Ocean] Shader not found: {ShaderName}");
                return;
            }

            var mat = AssetDatabase.LoadAssetAtPath<Material>(MaterialPath);
            if (mat == null)
            {
                mat = new Material(shader) { name = "FFTOcean" };
                AssetDatabase.CreateAsset(mat, MaterialPath);
            }
            else
            {
                mat.shader = shader;
            }

            EditorUtility.SetDirty(mat);
            AssetDatabase.SaveAssets();
            Debug.Log("[FFT Ocean] Material refreshed: " + MaterialPath);
        }

        [MenuItem("SRP Demo/FFT Ocean/Quality/High (256)")]
        public static void QualityHigh() => SetQuality(8);

        [MenuItem("SRP Demo/FFT Ocean/Quality/Medium (128)")]
        public static void QualityMedium() => SetQuality(7);

        [MenuItem("SRP Demo/FFT Ocean/Quality/Low (64)")]
        public static void QualityLow() => SetQuality(6);

        static void SetQuality(int fftPow)
        {
            var sim = Object.FindObjectOfType<FFTOceanSimulator>();
            if (sim != null)
            {
                var so = new SerializedObject(sim);
                so.FindProperty("fftPow").intValue = fftPow;
                so.ApplyModifiedPropertiesWithoutUndo();
                sim.ForceReinitialize();
            }
            Debug.Log($"[FFT Ocean] Quality fftPow={fftPow} size={1 << fftPow}");
        }
    }
}
