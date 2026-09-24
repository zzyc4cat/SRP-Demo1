using UnityEngine;
using UnityEngine.InputSystem;

/// <summary>
/// 简易飞行相机：WASD / 方向键移动，鼠标控制视角。
/// 本项目 Player Settings 为 Input System Only，因此直接使用新 Input System。
/// </summary>
[DisallowMultipleComponent]
[RequireComponent(typeof(Camera))]
[DefaultExecutionOrder(100)]
public class SimpleFlyCamera : MonoBehaviour
{
    [Tooltip("移动速度（米/秒）")]
    public float moveSpeed = 5f;

    [Tooltip("按住 Shift 时的速度倍率")]
    public float sprintMultiplier = 2.5f;

    [Tooltip("鼠标灵敏度（基于 Mouse.delta 像素）")]
    public float mouseSensitivity = 0.15f;

    [Tooltip("是否锁定并隐藏光标")]
    public bool lockCursor = true;

    [Tooltip("俯仰角限制（度）")]
    public float pitchMin = -89f;
    public float pitchMax = 89f;

    [Tooltip("启用时自动关闭同物体上的 CinemachineBrain，防止抢控制权")]
    public bool disableCinemachineBrain = true;

    float _yaw;
    float _pitch;
    Behaviour _cinemachineBrain;
    bool _brainWasEnabled;

    void OnEnable()
    {
        Vector3 e = transform.eulerAngles;
        _yaw = e.y;
        _pitch = e.x;
        if (_pitch > 180f) _pitch -= 360f;

        if (disableCinemachineBrain)
            SetCinemachineBrainEnabled(false);
    }

    void Start()
    {
        if (lockCursor)
            ApplyCursorLock(true);
    }

    void OnDisable()
    {
        ApplyCursorLock(false);

        if (disableCinemachineBrain && _cinemachineBrain != null && _brainWasEnabled)
            _cinemachineBrain.enabled = true;
    }

    static void ApplyCursorLock(bool locked)
    {
        Cursor.lockState = locked ? CursorLockMode.Locked : CursorLockMode.None;
        Cursor.visible = !locked;
    }

    void SetCinemachineBrainEnabled(bool enabled)
    {
        if (_cinemachineBrain == null)
        {
            var comps = GetComponents<Behaviour>();
            for (int i = 0; i < comps.Length; i++)
            {
                var c = comps[i];
                if (c != null && c.GetType().Name == "CinemachineBrain")
                {
                    _cinemachineBrain = c;
                    break;
                }
            }
        }

        if (_cinemachineBrain == null)
            return;

        if (!enabled)
        {
            _brainWasEnabled = _cinemachineBrain.enabled;
            _cinemachineBrain.enabled = false;
        }
        else
        {
            _cinemachineBrain.enabled = true;
        }
    }

    void Update()
    {
        var keyboard = Keyboard.current;
        var mouse = Mouse.current;

        if (keyboard != null && keyboard.escapeKey.wasPressedThisFrame)
            ApplyCursorLock(false);
        if (lockCursor && mouse != null && mouse.leftButton.wasPressedThisFrame)
            ApplyCursorLock(true);

        bool looking = !lockCursor || Cursor.lockState == CursorLockMode.Locked;
        if (looking && mouse != null)
        {
            Vector2 delta = mouse.delta.ReadValue();
            _yaw += delta.x * mouseSensitivity;
            _pitch -= delta.y * mouseSensitivity;
            _pitch = Mathf.Clamp(_pitch, pitchMin, pitchMax);
            transform.rotation = Quaternion.Euler(_pitch, _yaw, 0f);
        }

        float h = 0f;
        float v = 0f;
        if (keyboard != null)
        {
            if (keyboard.aKey.isPressed || keyboard.leftArrowKey.isPressed) h -= 1f;
            if (keyboard.dKey.isPressed || keyboard.rightArrowKey.isPressed) h += 1f;
            if (keyboard.wKey.isPressed || keyboard.upArrowKey.isPressed) v += 1f;
            if (keyboard.sKey.isPressed || keyboard.downArrowKey.isPressed) v -= 1f;
        }

        Vector3 dir = transform.right * h + transform.forward * v;
        if (dir.sqrMagnitude > 1e-6f)
            dir.Normalize();

        float speed = moveSpeed;
        if (keyboard != null && (keyboard.leftShiftKey.isPressed || keyboard.rightShiftKey.isPressed))
            speed *= sprintMultiplier;

        transform.position += dir * (speed * Time.deltaTime);
    }

    void LateUpdate()
    {
        if (_cinemachineBrain != null && _cinemachineBrain.enabled)
            SetCinemachineBrainEnabled(false);
    }
}