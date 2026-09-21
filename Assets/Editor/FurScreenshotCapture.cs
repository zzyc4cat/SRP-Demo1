using System.IO;
using UnityEditor;
using UnityEngine;

public static class FurScreenshotCapture
{
    [MenuItem("SRP Demo/Fur/Capture Baseline Screenshot")]
    public static void CaptureBaseline()
    {
        Capture("FurBall_Baseline", "Assets/04.Fur/Screenshots/Baseline_Effect.png");
    }

    [MenuItem("SRP Demo/Fur/Capture Optimized Screenshot")]
    public static void CaptureOptimized()
    {
        Capture("FurBall_Optimized", "Assets/04.Fur/Screenshots/Optimized_Effect.png");
    }

    public static void Capture(string objectName, string assetPath)
    {
        var go = GameObject.Find(objectName);
        if (go == null)
        {
            Debug.LogError($"[04.Fur] GameObject not found: {objectName}");
            return;
        }

        // 触发本帧 DrawMeshInstanced

        var optimized = go.GetComponent<FurInstancedRendererOptimized>();
        if (optimized != null)
            optimized.RenderNow();

        var camGo = new GameObject("__FurCaptureCam");
        var cam = camGo.AddComponent<Camera>();
        cam.clearFlags = CameraClearFlags.SolidColor;
        cam.backgroundColor = new Color(0.72f, 0.62f, 0.48f, 1f);
        cam.fieldOfView = 35f;
        cam.allowHDR = false;
        cam.transform.position = go.transform.position + new Vector3(0f, 0.3f, -3.1f);
        cam.transform.LookAt(go.transform.position + Vector3.up * 0.05f);

        const int w = 1280;
        const int h = 720;
        var rt = new RenderTexture(w, h, 24, RenderTextureFormat.ARGB32);
        cam.targetTexture = rt;

        // 再次提交绘制，确保 Render 前指令已进入本帧队列
        if (optimized != null)
            optimized.RenderNow();

        cam.Render();

        RenderTexture.active = rt;
        var tex = new Texture2D(w, h, TextureFormat.RGB24, false);
        tex.ReadPixels(new Rect(0, 0, w, h), 0, 0);
        tex.Apply();
        RenderTexture.active = null;
        cam.targetTexture = null;

        var absDir = Path.GetFullPath(Path.Combine(Application.dataPath, "04.Fur/Screenshots"));
        Directory.CreateDirectory(absDir);
        var absPath = Path.GetFullPath(Path.Combine(Application.dataPath, "..", assetPath));
        File.WriteAllBytes(absPath, tex.EncodeToPNG());

        UnityEngine.Object.DestroyImmediate(tex);
        UnityEngine.Object.DestroyImmediate(rt);
        UnityEngine.Object.DestroyImmediate(camGo);

        AssetDatabase.ImportAsset(assetPath);
        Debug.Log($"[04.Fur] Screenshot saved: {assetPath}");
    }
}
