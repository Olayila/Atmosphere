using UnityEngine;

public class CinematicBreathingWithDrift : MonoBehaviour
{
    [Header("呼吸参数")]
    public float breathSpeed = 0.3f;
    public float breathAmplitudeY = 0.05f;

    [Header("漂移参数")]
    public float driftSpeed = 0.18f;          // 整体漂移频率（比呼吸慢）
    public float driftAmplitude = 0.08f;      // 水平/前后漂移幅度（米）

    private Vector3 originalPosition;

    void Start()
    {
        originalPosition = transform.localPosition;
    }

    void LateUpdate()
    {
        // 呼吸：只影响 Y 轴
        float breath = Mathf.Sin(Time.time * breathSpeed) * breathAmplitudeY;

        // 漂移：用 Perlin noise 模拟缓慢随机移动
        float time = Time.time * driftSpeed;
        float driftX = (Mathf.PerlinNoise(time, 0f) * 2f - 1f) * driftAmplitude;
        float driftZ = (Mathf.PerlinNoise(time + 100f, 0f) * 2f - 1f) * driftAmplitude * 0.7f; // Z 轴幅度稍小

        Vector3 offset = new Vector3(driftX, breath, driftZ);
        transform.localPosition = originalPosition + offset;
    }
}