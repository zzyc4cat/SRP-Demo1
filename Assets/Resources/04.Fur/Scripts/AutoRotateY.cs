using UnityEngine;

/// <summary>
/// 绕本地/世界 Y 轴缓慢自动旋转，供 FurBall 等演示物体使用。
/// </summary>
[DisallowMultipleComponent]
public class AutoRotateY : MonoBehaviour
{
    [Tooltip("绕 Y 轴旋转速度（度/秒）")]
    public float degreesPerSecond = 20f;

    [Tooltip("true = 世界空间 Y 轴；false = 物体本地 Y 轴")]
    public bool worldSpace = true;

    void Update()
    {
        float delta = degreesPerSecond * Time.deltaTime;
        if (Mathf.Abs(delta) < 1e-6f)
            return;

        Space space = worldSpace ? Space.World : Space.Self;
        transform.Rotate(0f, delta, 0f, space);
    }
}
