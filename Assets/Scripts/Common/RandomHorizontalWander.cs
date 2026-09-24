using UnityEngine;

/// <summary>
/// 在水平面（XZ）内随机游走，并限制在矩形范围内。速度可在 Inspector 调整。
/// 默认可保持直立（只绕 Y 偏航，不倾倒）。
/// 用 bodyRadius 做边界内缩，避免靠物体 Scale 放大后贴边卡住。
/// </summary>
[DisallowMultipleComponent]
public class RandomHorizontalWander : MonoBehaviour
{
    [Tooltip("移动速度（米/秒）")]
    public float moveSpeed = 2f;

    [Tooltip("范围中心（世界坐标；Y 忽略）")]
    public Vector3 areaCenter = Vector3.zero;

    [Tooltip("范围半宽（X）与半深（Z）。略小于草坪外沿，避免贴边卡住")]
    public Vector2 areaHalfExtents = new Vector2(12f, 12f);

    [Tooltip("物体水平半径（世界单位）。边界与选点会按此内缩；应与碰撞体一致，不要靠根节点 Scale 放大")]
    public float bodyRadius = 1.25f;

    [Tooltip("进入该半径即视为到达目标，无需走到精确坐标")]
    public float arriveRadius = 1.25f;

    [Tooltip("新目标与当前位置的最小水平距离，过小会看起来像抖动")]
    public float minTargetDistance = 5f;

    [Tooltip("采样新目标的最大尝试次数")]
    public int maxPickAttempts = 24;

    [Tooltip("到达后稍作停顿再选下一点（秒）")]
    public float pauseAfterArrive = 0.15f;

    [Tooltip("保持直立：只绕 Y 轴转向，不因移动倾倒")]
    public bool keepUpright = true;

    [Tooltip("移动时是否绕 Y 轴朝向前进方向；关闭则完全不转")]
    public bool faceMoveDirection = true;

    Vector3 _target;
    float _fixedY;
    float _yaw;
    float _pauseUntil;
    bool _hasTarget;
    float _prevDist = float.MaxValue;
    int _stuckFrames;

    void OnEnable()
    {
        _fixedY = transform.position.y;
        _yaw = transform.eulerAngles.y;
        _hasTarget = false;
        _pauseUntil = 0f;
        _prevDist = float.MaxValue;
        _stuckFrames = 0;
        ApplyUprightRotation();

        var rb = GetComponent<Rigidbody>();
        if (rb != null)
        {
            rb.constraints |= RigidbodyConstraints.FreezeRotationX | RigidbodyConstraints.FreezeRotationZ | RigidbodyConstraints.FreezePositionY;
            if (keepUpright && !faceMoveDirection)
                rb.constraints |= RigidbodyConstraints.FreezeRotationY;
            rb.angularVelocity = Vector3.zero;
            rb.velocity = Vector3.zero;
        }

        PickNewTarget();
    }

    void Update()
    {
        if (!_hasTarget)
        {
            if (Time.time >= _pauseUntil)
                PickNewTarget();
            return;
        }

        Vector3 flat = Flat(transform.position);
        Vector3 flatTarget = Flat(_target);
        float dist = Vector3.Distance(flat, flatTarget);
        float radius = Mathf.Max(0.05f, arriveRadius);

        if (dist <= radius)
        {
            Arrive();
            return;
        }

        Vector3 dir = flatTarget - flat;
        if (dir.sqrMagnitude > 1e-8f)
            dir.Normalize();

        float step = moveSpeed * Time.deltaTime;
        if (dist - step <= radius)
        {
            Arrive();
            return;
        }

        Vector3 next = transform.position + dir * step;
        next = ClampToWalkable(next);
        next.y = _fixedY;

        float moved = Vector3.Distance(Flat(transform.position), Flat(next));
        transform.position = next;

        float newDist = Vector3.Distance(Flat(next), flatTarget);
        if (moved < 1e-5f || newDist >= _prevDist - 1e-4f)
            _stuckFrames++;
        else
            _stuckFrames = 0;
        _prevDist = newDist;

        if (_stuckFrames >= 3 || newDist <= radius)
        {
            Arrive();
            return;
        }

        if (keepUpright)
        {
            if (faceMoveDirection && dir.sqrMagnitude > 1e-8f)
                _yaw = Mathf.Atan2(dir.x, dir.z) * Mathf.Rad2Deg;
            ApplyUprightRotation();
        }
        else if (faceMoveDirection && dir.sqrMagnitude > 1e-8f)
        {
            Quaternion look = Quaternion.LookRotation(dir, Vector3.up);
            transform.rotation = Quaternion.Slerp(transform.rotation, look, 8f * Time.deltaTime);
        }
    }

    void LateUpdate()
    {
        if (keepUpright)
            ApplyUprightRotation();
    }

    void Arrive()
    {
        _hasTarget = false;
        _pauseUntil = Time.time + Mathf.Max(0f, pauseAfterArrive);
        _prevDist = float.MaxValue;
        _stuckFrames = 0;
    }

    void ApplyUprightRotation()
    {
        transform.rotation = Quaternion.Euler(0f, _yaw, 0f);
    }

    static Vector3 Flat(Vector3 v) => new Vector3(v.x, 0f, v.z);

    void GetWalkableHalf(out float halfX, out float halfZ)
    {
        float r = Mathf.Max(0f, bodyRadius);
        halfX = Mathf.Max(0.1f, areaHalfExtents.x - r);
        halfZ = Mathf.Max(0.1f, areaHalfExtents.y - r);
    }

    Vector3 ClampToWalkable(Vector3 p)
    {
        GetWalkableHalf(out float halfX, out float halfZ);
        p.x = Mathf.Clamp(p.x, areaCenter.x - halfX, areaCenter.x + halfX);
        p.z = Mathf.Clamp(p.z, areaCenter.z - halfZ, areaCenter.z + halfZ);
        return p;
    }

    void PickNewTarget()
    {
        Vector3 origin = Flat(transform.position);
        GetWalkableHalf(out float halfX, out float halfZ);

        float minDist = Mathf.Max(arriveRadius + 0.5f, minTargetDistance);
        float maxReach = Mathf.Min(halfX, halfZ) * 2f;
        if (minDist > maxReach * 0.9f)
            minDist = maxReach * 0.5f;

        float minSqr = minDist * minDist;
        Vector3 best = origin;
        float bestSqr = -1f;
        bool found = false;

        for (int i = 0; i < Mathf.Max(1, maxPickAttempts); i++)
        {
            float x = Random.Range(areaCenter.x - halfX, areaCenter.x + halfX);
            float z = Random.Range(areaCenter.z - halfZ, areaCenter.z + halfZ);
            Vector3 candidate = new Vector3(x, 0f, z);
            float sqr = (candidate - origin).sqrMagnitude;
            if (sqr >= minSqr)
            {
                SetTarget(x, z);
                return;
            }
            if (sqr > bestSqr)
            {
                bestSqr = sqr;
                best = candidate;
                found = true;
            }
        }

        if (found && bestSqr > arriveRadius * arriveRadius)
        {
            SetTarget(best.x, best.z);
            return;
        }

        float ang = Random.Range(0f, Mathf.PI * 2f);
        Vector3 push = new Vector3(Mathf.Cos(ang), 0f, Mathf.Sin(ang)) * minDist;
        float px = Mathf.Clamp(origin.x + push.x, areaCenter.x - halfX, areaCenter.x + halfX);
        float pz = Mathf.Clamp(origin.z + push.z, areaCenter.z - halfZ, areaCenter.z + halfZ);
        SetTarget(px, pz);
    }

    void SetTarget(float x, float z)
    {
        _target = new Vector3(x, _fixedY, z);
        _hasTarget = true;
        _prevDist = float.MaxValue;
        _stuckFrames = 0;
    }

    void OnDrawGizmosSelected()
    {
        Vector3 c = new Vector3(areaCenter.x, transform.position.y, areaCenter.z);
        Vector3 size = new Vector3(areaHalfExtents.x * 2f, 0.05f, areaHalfExtents.y * 2f);
        Gizmos.color = new Color(0.2f, 0.9f, 0.4f, 0.35f);
        Gizmos.DrawWireCube(c, size);

        GetWalkableHalf(out float halfX, out float halfZ);
        Gizmos.color = new Color(0.2f, 0.55f, 1f, 0.45f);
        Gizmos.DrawWireCube(c, new Vector3(halfX * 2f, 0.05f, halfZ * 2f));

        if (_hasTarget)
        {
            Gizmos.color = new Color(1f, 0.85f, 0.2f, 0.5f);
            Gizmos.DrawWireSphere(new Vector3(_target.x, transform.position.y, _target.z), Mathf.Max(0.05f, arriveRadius));
        }
    }
}