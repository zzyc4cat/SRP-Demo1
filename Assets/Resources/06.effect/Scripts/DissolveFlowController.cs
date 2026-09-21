using UnityEngine;

/// <summary>
/// 【溶解 DissolveFlow】可选阈值动画驱动。
/// 挂在演示球体上，对 ZZY/06.effect/DissolveFlow 材质写入
/// <c>_DissolveAmount</c>；Play 模式下正弦往复，编辑模式下可用材质自带动画。
/// 场景：<c>06.effect_DissolveFlow</c>
/// </summary>
[ExecuteAlways]
public class DissolveFlowController : MonoBehaviour
{
    public Material targetMaterial;
    public string propertyName = "_DissolveAmount";
    public bool animate = true;
    public float speed = 0.25f;
    [Range(0f, 1f)] public float amount = 0.35f;

    void Update()
    {
        if (targetMaterial == null)
        {
            var r = GetComponent<Renderer>();
            if (r != null) targetMaterial = r.sharedMaterial;
        }
        if (targetMaterial == null || !targetMaterial.HasProperty(propertyName))
            return;

        float v = amount;
        if (animate && Application.isPlaying)
            v = 0.5f + 0.5f * Mathf.Sin(Time.time * speed * Mathf.PI * 2f);

        targetMaterial.SetFloat(propertyName, v);
        // Prefer shader self-animate; disable material animate flag when driven here
        if (targetMaterial.HasProperty("_Animate"))
            targetMaterial.SetFloat("_Animate", animate && !Application.isPlaying ? 1f : 0f);
    }
}
