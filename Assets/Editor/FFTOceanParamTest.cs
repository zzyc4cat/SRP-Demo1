using System.Collections.Generic;
using System.IO;
using System.Text;
using UnityEditor;
using UnityEngine;

namespace SRPDemo.EditorTools
{
    /// <summary>
    /// Play 模式 MAD 回归：逐项扰动材质 / WavesSettings，检测位移能量与颜色响应。
    /// </summary>
    public static class FFTOceanParamTest
    {
        const float DeadMad = 0.0015f;
        const float DeadRel = 0.02f; // relative displacement energy
        const string ReportPath = "Temp_fft_ocean/param_test_report.txt";

        [MenuItem("SRP Demo/FFT Ocean/Test All Parameters (Play Mode)")]
        public static void MenuTest() => Debug.Log(Run());

        public static string Run()
        {
            if (!EditorApplication.isPlaying)
                return "NEED_PLAY";

            var ocean = GameObject.Find("FFTOcean");
            if (ocean == null) return "NO_OCEAN";
            var sim = ocean.GetComponent<FFTOcean.FFTOceanSimulator>();
            if (sim == null) return "NO_SIM";
            var mat = sim.OceanMaterial;
            if (mat == null) return "NO_MAT";
            var waves = sim.Settings;
            if (waves == null) return "NO_WAVES";

            var cam = Camera.main;
            if (cam == null) return "NO_CAM";
            cam.transform.position = new Vector3(-25f, 9f, 5f);
            cam.transform.LookAt(new Vector3(0f, 0.2f, -35f));

            var sb = new StringBuilder();
            int ok = 0, dead = 0;
            var baseline = Capture(cam);
            // Let GameView present at least one frame with current materials
            UnityEditorInternal.InternalEditorUtility.RepaintAllViews();

            // Material color / float params
            void TestColor(string prop, Color delta)
            {
                if (!mat.HasProperty(prop)) { sb.AppendLine($"SKIP missing {prop}"); return; }
                var orig = mat.GetColor(prop);
                mat.SetColor(prop, delta);
                WaitFrame();
                var shot = Capture(cam);
                float mad = Mad(baseline, shot, destroyB: true);
                mat.SetColor(prop, orig);
                WaitFrame();
                Report(sb, prop, mad, ref ok, ref dead);
            }

            void TestFloat(string prop, float value)
            {
                if (!mat.HasProperty(prop)) { sb.AppendLine($"SKIP missing {prop}"); return; }
                float orig = mat.GetFloat(prop);
                mat.SetFloat(prop, value);
                WaitFrame();
                var shot = Capture(cam);
                float mad = Mad(baseline, shot, destroyB: true);
                mat.SetFloat(prop, orig);
                WaitFrame();
                Report(sb, prop, mad, ref ok, ref dead);
            }

            TestColor("_OceanColorShallow", Color.magenta);
            TestColor("_OceanColorMid", Color.yellow);
            TestColor("_OceanColorDeep", Color.red);
            TestColor("_FoamColor", Color.green);
            TestColor("_SSSColor", Color.cyan);
            TestFloat("_ShallowDistance", 25f);
            TestFloat("_DeepDistance", 3f);
            TestFloat("_Absorption", 6f);
            TestFloat("_Opacity", 0.2f);
            TestFloat("_SpecularIntensity", 0f);
            TestFloat("_Gloss", 16f);
            TestFloat("_FresnelPower", 1.2f);
            TestFloat("_FresnelBias", 0.4f);
            TestFloat("_EnvIntensity", 0f);
            TestFloat("_SSSIntensity", 0f);
            TestFloat("_SSSPower", 1f);
            TestFloat("_LOD_scale", 0.5f);
            TestFloat("_FoamBias", 4f);
            TestFloat("_FoamScale", 0.05f);
            TestFloat("_ContactFoam", 0f);
            TestFloat("_FoamNoiseScale", 0.02f);
            TestFloat("_RefractionStrength", 0.5f);

            // Waves: relative displacement energy vs baseline energy
            const float ProbeTime = 12.5f;
            float energyBase = 0f;
            {
                sim.ForceReinitialize();
                sim.TickWaves(ProbeTime);
                energyBase = DisplacementMad(sim);
            }

            float TestWave(System.Action apply, System.Action restore)
            {
                apply();
                sim.ForceReinitialize();
                sim.TickWaves(ProbeTime);
                float e = DisplacementMad(sim);
                restore();
                sim.ForceReinitialize();
                sim.TickWaves(ProbeTime);
                return Mathf.Abs(e - energyBase) / Mathf.Max(energyBase, 1e-4f);
            }

            float g0 = waves.g, d0 = waves.depth, l0 = waves.lambda;
            var local0 = waves.local;
            var swell0 = waves.swell;

            Report(sb, "waves.g", TestWave(() => waves.g = 2f, () => waves.g = g0), ref ok, ref dead, true);
            Report(sb, "waves.depth", TestWave(() => waves.depth = 2f, () => waves.depth = d0), ref ok, ref dead, true);
            Report(sb, "waves.lambda", TestWave(() => waves.lambda = 0.1f, () => waves.lambda = l0), ref ok, ref dead, true);
            Report(sb, "local.scale", TestWave(() => { var s = waves.local; s.scale = 0.05f; waves.local = s; }, () => waves.local = local0), ref ok, ref dead, true);
            Report(sb, "local.windSpeed", TestWave(() => { var s = waves.local; s.windSpeed = 20f; waves.local = s; }, () => waves.local = local0), ref ok, ref dead, true);
            Report(sb, "local.windDirection", TestWave(() => { var s = waves.local; s.windDirection = 200f; waves.local = s; }, () => waves.local = local0), ref ok, ref dead, true);
            Report(sb, "local.fetch", TestWave(() => { var s = waves.local; s.fetch = 1000f; waves.local = s; }, () => waves.local = local0), ref ok, ref dead, true);
            Report(sb, "local.spreadBlend", TestWave(() => { var s = waves.local; s.spreadBlend = 0f; waves.local = s; }, () => waves.local = local0), ref ok, ref dead, true);
            Report(sb, "local.swell", TestWave(() => { var s = waves.local; s.swell = 1f; waves.local = s; }, () => waves.local = local0), ref ok, ref dead, true);
            Report(sb, "local.peakEnhancement", TestWave(() => { var s = waves.local; s.peakEnhancement = 1f; waves.local = s; }, () => waves.local = local0), ref ok, ref dead, true);
            Report(sb, "local.shortWavesFade", TestWave(() => { var s = waves.local; s.shortWavesFade = 0.2f; waves.local = s; }, () => waves.local = local0), ref ok, ref dead, true);
            Report(sb, "swell.scale", TestWave(() => { var s = waves.swell; s.scale = 0f; waves.swell = s; }, () => waves.swell = swell0), ref ok, ref dead, true);

            // Simulator serialized fields via SerializedObject
            var so = new SerializedObject(sim);
            float TestSim(string prop, float value)
            {
                so.Update();
                var p = so.FindProperty(prop);
                if (p == null) { sb.AppendLine($"SKIP sim.{prop}"); return -1f; }
                float orig = p.floatValue;
                p.floatValue = value;
                so.ApplyModifiedPropertiesWithoutUndo();
                sim.ForceReinitialize();
                Object.DestroyImmediate(Capture(cam));
                float mad = prop == "timeScale"
                    ? Mad(baseline, Capture(cam), destroyB: true)
                    : Mathf.Abs(DisplacementMad(sim) - energyBase) / Mathf.Max(energyBase, 1e-4f);
                p.floatValue = orig;
                so.ApplyModifiedPropertiesWithoutUndo();
                sim.ForceReinitialize();
                Object.DestroyImmediate(Capture(cam));
                return mad;
            }

            Report(sb, "sim.lengthScale0", TestSim("lengthScale0", 80f), ref ok, ref dead, true);
            Report(sb, "sim.lengthScale1", TestSim("lengthScale1", 40f), ref ok, ref dead, true);
            Report(sb, "sim.lengthScale2", TestSim("lengthScale2", 12f), ref ok, ref dead, true);
            Report(sb, "sim.timeScale", TestSim("timeScale", 0f), ref ok, ref dead, false);

            // freeze check for timeScale
            so.Update();
            var ts = so.FindProperty("timeScale");
            float tsOrig = ts.floatValue;
            ts.floatValue = 0f;
            so.ApplyModifiedPropertiesWithoutUndo();
            var a = Capture(cam);
            var b = Capture(cam);
            float freezeMad = Mad(a, b, destroyB: true);
            Object.DestroyImmediate(a);
            ts.floatValue = tsOrig;
            so.ApplyModifiedPropertiesWithoutUndo();
            sb.AppendLine($"INFO freezeMad(timeScale=0)={freezeMad:F4}");

            Object.DestroyImmediate(baseline);
            string header = $"[FFTOceanParamTest] ok={ok} dead={dead}\n";
            string report = header + sb;
            Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(ReportPath)));
            File.WriteAllText(ReportPath, report);
            return report;
        }

        static void Report(StringBuilder sb, string name, float mad, ref int ok, ref int dead, bool relative = false)
        {
            if (mad < 0) return;
            float thr = relative ? DeadRel : DeadMad;
            bool isDead = mad < thr;
            if (isDead) dead++; else ok++;
            sb.AppendLine($"{(isDead ? "DEAD" : "OK  ")} {(relative ? "rel" : "mad")}={mad:F4}  {name}");
        }

        static void WaitFrame()
        {
            UnityEditorInternal.InternalEditorUtility.RepaintAllViews();
            EditorApplication.QueuePlayerLoopUpdate();
            System.Threading.Thread.Sleep(200);
            UnityEditorInternal.InternalEditorUtility.RepaintAllViews();
            EditorApplication.QueuePlayerLoopUpdate();
            System.Threading.Thread.Sleep(50);
        }

        static Texture2D Capture(Camera cam)
        {
            // Discard one stale frame then grab.
            var stale = CaptureGameView();
            if (stale != null) Object.DestroyImmediate(stale);
            WaitFrame();
            var tex = CaptureGameView();
            if (tex != null) return tex;

            int w = 320, h = 180;
            var rt = RenderTexture.GetTemporary(w, h, 24, RenderTextureFormat.ARGB32);
            var prev = cam.targetTexture;
            cam.targetTexture = rt;
            cam.Render();
            RenderTexture.active = rt;
            tex = new Texture2D(w, h, TextureFormat.RGB24, false);
            tex.ReadPixels(new Rect(0, 0, w, h), 0, 0);
            tex.Apply(false);
            cam.targetTexture = prev;
            RenderTexture.active = null;
            RenderTexture.ReleaseTemporary(rt);
            return tex;
        }

        static Texture2D CaptureGameView()
        {
            try
            {
                var bytes = UnityEngine.ScreenCapture.CaptureScreenshotAsTexture();
                if (bytes == null) return null;
                // Downscale for MAD speed
                int w = Mathf.Max(160, bytes.width / 4);
                int h = Mathf.Max(90, bytes.height / 4);
                var rt = RenderTexture.GetTemporary(w, h, 0);
                Graphics.Blit(bytes, rt);
                RenderTexture.active = rt;
                var tex = new Texture2D(w, h, TextureFormat.RGB24, false);
                tex.ReadPixels(new Rect(0, 0, w, h), 0, 0);
                tex.Apply(false);
                RenderTexture.active = null;
                RenderTexture.ReleaseTemporary(rt);
                Object.DestroyImmediate(bytes);
                return tex;
            }
            catch
            {
                return null;
            }
        }

        static float DisplacementMad(FFTOcean.FFTOceanSimulator sim)
        {
            // Baseline: current cascade0 displacement stats after default restore path is awkward;
            // instead measure mean |disp| and compare to a known zero-ish by using two settings via caller.
            // Here we return mean absolute displacement as a proxy "energy" — caller compares by
            // measuring before/after energy difference.
            var rt = sim.Cascade0?.Displacement;
            if (rt == null) return 0f;
            var prev = RenderTexture.active;
            var tmp = RenderTexture.GetTemporary(rt.width, rt.height, 0, RenderTextureFormat.ARGBFloat);
            Graphics.Blit(rt, tmp);
            RenderTexture.active = tmp;
            var tex = new Texture2D(rt.width, rt.height, TextureFormat.RGBAFloat, false);
            tex.ReadPixels(new Rect(0, 0, rt.width, rt.height), 0, 0);
            tex.Apply(false);
            RenderTexture.active = prev;
            RenderTexture.ReleaseTemporary(tmp);
            var px = tex.GetPixels();
            double sum = 0;
            for (int i = 0; i < px.Length; i++)
                sum += Mathf.Abs(px[i].r) + Mathf.Abs(px[i].g) + Mathf.Abs(px[i].b);
            Object.DestroyImmediate(tex);
            return (float)(sum / (px.Length * 3.0));
        }

        static float Mad(Texture2D a, Texture2D b, bool destroyB)
        {
            var pa = a.GetPixels32();
            var pb = b.GetPixels32();
            int n = Mathf.Min(pa.Length, pb.Length);
            double sum = 0;
            for (int i = 0; i < n; i++)
            {
                sum += Mathf.Abs(pa[i].r - pb[i].r) / 255.0;
                sum += Mathf.Abs(pa[i].g - pb[i].g) / 255.0;
                sum += Mathf.Abs(pa[i].b - pb[i].b) / 255.0;
            }
            if (destroyB) Object.DestroyImmediate(b);
            return (float)(sum / (n * 3.0));
        }
    }
}
