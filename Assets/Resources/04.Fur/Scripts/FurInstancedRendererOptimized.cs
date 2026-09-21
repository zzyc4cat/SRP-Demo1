using UnityEngine;

/// <summary>
/// 优化版 Shell Texturing 驱动：
/// 1) 相机距离动态 LOD，远距减少 shell 层数
/// 2) 材质强制开启 GPU Instancing
/// 3) 可选风力向量写入 MaterialPropertyBlock（驱动 shader 中的风场）
/// </summary>
[ExecuteAlways]
[DisallowMultipleComponent]
public class FurInstancedRendererOptimized : MonoBehaviour
{
    [Header("Render Assets")]
    public Mesh mesh;
    public Material furMaterial;

    [Header("Fur Settings")]
    [Range(1, 100)]
    public int maxShellCount = 48;

    [Range(1, 16)]
    public int minShellCount = 4;

    [Header("LOD")]
    [Tooltip("距离小于该值使用 maxShellCount")]
    public float lodNearDistance = 3f;

    [Tooltip("距离大于该值使用 minShellCount")]
    public float lodFarDistance = 18f;

    [Header("Wind")]
    public bool enableWind = true;
    public Vector3 windDirection = new Vector3(0.6f, 0f, 0.2f);
    public float windStrength = 0.15f;
    public float windFrequency = 1.2f;

    [Header("Debug")]
    public bool forceMaxShells;

    Matrix4x4[] matrices;
    float[] layerRatios;
    MaterialPropertyBlock propertyBlock;
    int allocatedCount = -1;
    int lastDrawnCount = -1;
    Camera cachedCamera;

    static readonly int LayerRatioId = Shader.PropertyToID("_LayerRatio");
    static readonly int WindVectorId = Shader.PropertyToID("_WindVector");

    void OnEnable()
    {
        EnsureBuffers(maxShellCount);
        ApplyMaterialFlags();
    }

    void OnValidate()
    {
        minShellCount = Mathf.Clamp(minShellCount, 1, maxShellCount);
        lodFarDistance = Mathf.Max(lodNearDistance + 0.01f, lodFarDistance);
        EnsureBuffers(maxShellCount);
        ApplyMaterialFlags();
    }

    void Update()
    {
        RenderNow();
    }

    /// <summary>供截图工具在同一帧内主动提交绘制。</summary>
    public void RenderNow()
    {
        if (mesh == null || furMaterial == null || maxShellCount <= 0)
            return;

        EnsureBuffers(maxShellCount);
        ApplyMaterialFlags();

        int shellCount = forceMaxShells ? maxShellCount : EvaluateShellCount();
        if (shellCount != lastDrawnCount)
        {
            FillLayerRatios(shellCount);
            lastDrawnCount = shellCount;
        }

        Matrix4x4 currentMatrix = transform.localToWorldMatrix;
        for (int i = 0; i < shellCount; i++)
            matrices[i] = currentMatrix;

        if (enableWind)
        {
            Vector3 dir = windDirection.sqrMagnitude > 1e-6f
                ? windDirection.normalized
                : Vector3.right;
            float phase = Time.time * windFrequency;
            Vector3 wind = dir * (windStrength * (0.65f + 0.35f * Mathf.Sin(phase)));
            propertyBlock.SetVector(WindVectorId, new Vector4(wind.x, wind.y, wind.z, phase));
        }
        else
        {
            propertyBlock.SetVector(WindVectorId, Vector4.zero);
        }

        Graphics.DrawMeshInstanced(mesh, 0, furMaterial, matrices, shellCount, propertyBlock);
    }

    int EvaluateShellCount()
    {
        Camera cam = ResolveCamera();
        if (cam == null)
            return maxShellCount;

        float distance = Vector3.Distance(cam.transform.position, transform.position);
        float t = Mathf.InverseLerp(lodNearDistance, lodFarDistance, distance);
        int count = Mathf.RoundToInt(Mathf.Lerp(maxShellCount, minShellCount, t));
        return Mathf.Clamp(count, minShellCount, maxShellCount);
    }

    Camera ResolveCamera()
    {
        if (cachedCamera != null)
            return cachedCamera;

        cachedCamera = Camera.main;
        if (cachedCamera == null && Camera.allCamerasCount > 0)
            cachedCamera = Camera.allCameras[0];

#if UNITY_EDITOR
        if (cachedCamera == null && !Application.isPlaying)
        {
            var sceneView = UnityEditor.SceneView.lastActiveSceneView;
            if (sceneView != null)
                cachedCamera = sceneView.camera;
        }
#endif
        return cachedCamera;
    }

    void EnsureBuffers(int count)
    {
        if (count <= 0)
            return;

        if (matrices != null && allocatedCount == count && propertyBlock != null)
            return;

        matrices = new Matrix4x4[count];
        layerRatios = new float[count];
        propertyBlock ??= new MaterialPropertyBlock();
        allocatedCount = count;
        lastDrawnCount = -1;
    }

    void FillLayerRatios(int shellCount)
    {
        float denom = Mathf.Max(1, shellCount - 1);
        for (int i = 0; i < shellCount; i++)
            layerRatios[i] = i / denom;

        // DrawMeshInstanced 会按 instanceCount 读取数组前 N 项
        propertyBlock.SetFloatArray(LayerRatioId, layerRatios);
    }

    void ApplyMaterialFlags()
    {
        if (furMaterial != null && !furMaterial.enableInstancing)
            furMaterial.enableInstancing = true;
    }
}
