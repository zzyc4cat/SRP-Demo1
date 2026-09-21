using UnityEngine;
using UnityEngine.InputSystem;

/// <summary>
/// 【护盾 Shield】鼠标点击命中涟漪控制器。
/// 对带 <c>CollisionShield</c> 标签的碰撞体射线检测，将命中点写入全局数组
/// <c>_HitPos</c> / <c>_HitSize</c> / <c>_HitAmount</c>，由 <c>ZZY/06.effect/Shield</c> 采样。
/// 依赖新 Input System。场景：<c>06.effect_Shield</c>
/// </summary>
[ExecuteAlways]
public class ShieldHitController : MonoBehaviour
{
    public string triggerTag = "CollisionShield";
    public float clicksPerSecond = 0.05f;
    public int affectorAmount = 20;
    public float emitSize = 0.15f;
    public float sizeGrowSpeed = 1.2f;
    public float lifeTime = 1.25f;

    struct Hit
    {
        public Vector3 position;
        public float size;
        public float age;
        public bool alive;
    }

    readonly Hit[] _hits = new Hit[20];
    readonly Vector4[] _positions = new Vector4[20];
    readonly float[] _sizes = new float[20];
    float _clickTimer;
    int _cursor;

    void OnEnable()
    {
        for (int i = 0; i < _hits.Length; i++)
            _hits[i].alive = false;
    }

    void Update()
    {
        float dt = Application.isPlaying ? Time.deltaTime : 0.016f;
        _clickTimer += dt;

        if (Application.isPlaying && IsPrimaryPressed() && _clickTimer > clicksPerSecond)
        {
            _clickTimer = 0f;
            DoRayCast();
        }

        int amount = Mathf.Clamp(affectorAmount, 1, 20);
        for (int i = 0; i < amount; i++)
        {
            if (!_hits[i].alive)
            {
                _positions[i] = Vector4.zero;
                _sizes[i] = 0f;
                continue;
            }

            _hits[i].age += dt;
            _hits[i].size += sizeGrowSpeed * dt;
            if (_hits[i].age >= lifeTime)
                _hits[i].alive = false;

            _positions[i] = _hits[i].position;
            _sizes[i] = _hits[i].alive ? _hits[i].size : 0f;
        }

        Shader.SetGlobalVectorArray("_HitPos", _positions);
        Shader.SetGlobalFloatArray("_HitSize", _sizes);
        Shader.SetGlobalFloat("_HitAmount", amount);
    }

    static bool IsPrimaryPressed()
    {
        var mouse = Mouse.current;
        return mouse != null && mouse.leftButton.isPressed;
    }

    static Vector2 GetPointerScreenPosition()
    {
        var mouse = Mouse.current;
        return mouse != null ? mouse.position.ReadValue() : Vector2.zero;
    }

    void DoRayCast()
    {
        Camera cam = Camera.main;
        if (cam == null) return;

        Ray ray = cam.ScreenPointToRay(GetPointerScreenPosition());
        if (!Physics.Raycast(ray, out RaycastHit hitInfo, 1000f))
            return;

        if (!string.IsNullOrEmpty(triggerTag) && !hitInfo.transform.CompareTag(triggerTag))
            return;

        Emit(hitInfo.point);
    }

    public void Emit(Vector3 worldPos)
    {
        int i = _cursor % Mathf.Clamp(affectorAmount, 1, 20);
        _cursor++;
        _hits[i].position = worldPos;
        _hits[i].size = emitSize;
        _hits[i].age = 0f;
        _hits[i].alive = true;
    }
}
