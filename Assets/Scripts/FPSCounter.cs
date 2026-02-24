using UnityEngine;
using TMPro;  // 如果用TextMeshPro，导入这个；否则用UnityEngine.UI;
[ExecuteInEditMode]
public class FPSCounter : MonoBehaviour
{
    [Header("FPS设置")]
    public TextMeshProUGUI fpsText;  // 拖拽你的TMP Text组件到这里
    public float updateInterval = 0.5f;  // 更新间隔（秒），0.5s平衡精度和性能

    private int frames = 0;
    private float lastInterval;
    private float fps;

    void Start()
    {
        lastInterval = Time.realtimeSinceStartup;  // 游戏真实时间开始计时
        fpsText ??= GetComponent<TextMeshProUGUI>();  // 如果没赋值，自动获取自身组件
    }

    void Update()
    {
        ++frames;  // 每帧计数+1

        float timeNow = Time.realtimeSinceStartup;

        if (timeNow > lastInterval + updateInterval)
        {
            fps = frames / (timeNow - lastInterval);  // 计算平均FPS
            fpsText.text = $"FPS: {fps:F0} ({(1f / fps * 1000):F0}ms)"; // 显示整数FPS（F0无小数）

            frames = 0;  // 重置计数
            lastInterval = timeNow;
        }
    }
}