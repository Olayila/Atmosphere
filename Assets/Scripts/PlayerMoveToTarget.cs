using UnityEngine;

public class PlayerMoveToTarget : MonoBehaviour
{
    [Header("移动参数")]
    [Tooltip("移动速度（单位：米/秒）")]
    public float speed = 5f;

    [Tooltip("终点位置（世界坐标）")]
    public Transform target;  // 在 Inspector 拖入终点 GameObject

    [Header("调试与选项")]
    [Tooltip("是否开始移动（可在 Inspector 勾选或代码控制）")]
    public bool startMoving = false;

    [Tooltip("到达终点后是否停止")]
    public bool stopAtTarget = true;

    private Vector3 startPosition;
    private bool isMoving = false;

    void Start()
    {
        startPosition = transform.position;

        // 如果你希望游戏开始就自动移动，可以在这里设置
        // isMoving = true;
        // startMoving = true;
    }

    void Update()
    {
        // Inspector 控制开关 + 运行时判断
        if (!startMoving || target == null)
        {
            return;
        }

        if (!isMoving)
        {
            isMoving = true;
        }

        // 计算方向和距离
        Vector3 direction = (target.position - transform.position).normalized;
        float distanceToTarget = Vector3.Distance(transform.position, target.position);

        // 移动
        if (distanceToTarget > 0.01f) // 避免浮点误差导致抖动
        {
            float moveDistance = speed * Time.deltaTime;

            // 如果这一步会超过终点，就只移动到终点
            if (moveDistance >= distanceToTarget && stopAtTarget)
            {
                transform.position = target.position;
                isMoving = false;
                startMoving = false; // 到达后自动停止（可根据需求修改）
            }
            else
            {
                transform.position += direction * moveDistance;
            }
        }
        else
        {
            // 已到达终点
            if (stopAtTarget)
            {
                isMoving = false;
                startMoving = false;
            }
        }
    }

    // 可选：外部代码控制开始/停止
    public void StartMoving()
    {
        startMoving = true;
    }

    public void StopMoving()
    {
        startMoving = false;
        isMoving = false;
    }

    public void ResetToStart()
    {
        transform.position = startPosition;
        startMoving = false;
        isMoving = false;
    }
}