using UnityEngine;

/// <summary>
/// 绕 Y 轴自动旋转（默认可设为俯视顺时针）。通用演示脚本，可挂任意物体。
/// </summary>
[DisallowMultipleComponent]
public class AutoRotateY : MonoBehaviour
{
    [Tooltip("旋转速度（度/秒），始终为正数")]
    public float degreesPerSecond = 30f;

    [Tooltip("俯视时是否顺时针旋转")]
    public bool clockwise = true;

    [Tooltip("true = 世界空间 Y 轴；false = 物体本地 Y 轴")]
    public bool worldSpace = true;

    void Update()
    {
        float signed = clockwise ? -degreesPerSecond : degreesPerSecond;
        float delta = signed * Time.deltaTime;
        if (Mathf.Abs(delta) < 1e-6f)
            return;

        Space space = worldSpace ? Space.World : Space.Self;
        transform.Rotate(0f, delta, 0f, space);
    }
}