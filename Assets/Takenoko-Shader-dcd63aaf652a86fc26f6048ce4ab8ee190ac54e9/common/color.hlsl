#ifndef _COLOR_H
#define _COLOR_H
#include "./constant.hlsl"

//金属材质的物理准确模拟
//模拟了真实世界金属的复折射率（Complex Index of Refraction）模型


///艺术化的调色板函数。
///公式：a + b * cos(2π * (c * t + d))
//a:基础颜色
//b:颜色变化幅度
//c:变化速度
//d:初始相位（偏移）
//t: 时间或进度
float3 colorPalet(float3 a, float3 b, float3 c, float3 d, float t)
{
    return a + b * cos(TAU * (c * t + d));
}
///计算颜色的亮度（Luminance）：使用标准人眼敏感权重（0.2126 R + 0.7152 G + 0.0722 B）
static inline float colorToLuminance(float3 col)
{
    return dot(col, float3(0.2126, 0.7152, 0.0722));
}
///复折射率公式中的两个分支：n_min：较小的解（通常对应非金属）  n_max：较大的解（通常对应金属）
static inline float3 n_min(float3 r)
{
    return (1.0f - r) / (1.0f + r);
}
static inline float3 n_max(float3 r)
{
    return (1.0f + sqrt(r)) / (1.0f - sqrt(r));
}
//核心函数：从反射颜色 col（RGB 反射率）和tint 混合权重反推出IOR（折射率 n）——————————最主要的输出1:决定反射率
static inline float3 rToIOR(float3 col, float3 tint)
{
    return tint * n_min(col) + (1.0f - tint) * n_max(col);
}
//从反射颜色 col 和已知的 IOR 计算Kappa（消光系数 k）———————————————————————最主要的输出2：决定金属颜色
static inline float3 rToKappa(float3 col, float3 ior)
{
    float3 nr = (ior + 1.0f) * (ior + 1.0f) * col - (ior - 1.0f) * (ior - 1.0f);
    return sqrt(nr / (1.0f - col));
}
//计算G（ 可能是艺术家友好的颜色映射）
static inline float3 getR(float3 ior, float3 kappa)
{
    return ((ior - 1.0f) * (ior - 1.0f) + kappa * kappa) / ((ior + 1.0f) * (ior + 1.0f) + kappa * kappa);
}

static inline float3 getG(float3 ior, float3 kappa)
{
    float3 r = getR(ior, kappa);
    return (n_max(r) - ior) / (n_max(r) - n_min(r));
}
#endif
