using UnityEngine;

/// <summary>
/// 绕指定点（默认世界原点）做水平环绕，并始终朝向目标。速度可调。
/// </summary>
[DisallowMultipleComponent]
public class OrbitLookAt : MonoBehaviour
{
    [Tooltip("环绕中心；为空则使用下方 center 世界坐标")]
    public Transform target;

    [Tooltip("无 target 时使用的世界坐标中心")]
    public Vector3 center = Vector3.zero;

    [Tooltip("环绕角速度（度/秒）")]
    public float degreesPerSecond = 20f;

    [Tooltip("是否顺时针（俯视）")]
    public bool clockwise = false;

    [Tooltip("到中心的水平半径；小于等于 0 则用当前距离")]
    public float radius = 0f;

    [Tooltip("勾选后保持启用时的相对高度；否则使用 heightOffset")]
    public bool keepCurrentHeight = true;

    [Tooltip("相对中心的固定高度偏移（仅 keepCurrentHeight = false 时生效）")]
    public float heightOffset = 1.5f;

    float _angle;
    float _radius;
    float _height;

    void OnEnable()
    {
        Vector3 c = GetCenter();
        Vector3 offset = transform.position - c;
        Vector3 flat = new Vector3(offset.x, 0f, offset.z);
        _radius = radius > 0f ? radius : Mathf.Max(flat.magnitude, 0.01f);
        _height = keepCurrentHeight ? offset.y : heightOffset;
        _angle = Mathf.Atan2(flat.x, flat.z) * Mathf.Rad2Deg;
        ApplyPose();
    }

    void Update()
    {
        float signed = clockwise ? -degreesPerSecond : degreesPerSecond;
        _angle += signed * Time.deltaTime;
        ApplyPose();
    }

    void ApplyPose()
    {
        Vector3 c = GetCenter();
        float rad = _angle * Mathf.Deg2Rad;
        Vector3 pos = c + new Vector3(Mathf.Sin(rad) * _radius, _height, Mathf.Cos(rad) * _radius);
        transform.position = pos;
        transform.LookAt(c, Vector3.up);
    }

    Vector3 GetCenter()
    {
        return target != null ? target.position : center;
    }
}