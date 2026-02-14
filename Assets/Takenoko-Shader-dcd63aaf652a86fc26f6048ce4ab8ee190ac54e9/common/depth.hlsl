#ifndef _DEPTH_HLSL
#define _DEPTH_HLSL

///把裁剪空间深度（Clip Space Z） 转换为线性深度或 NDC 深度。
/// OpenGL/GLSL 平台：深度范围 0~1
///DirectX 平台：深度范围 -1~1
///clippos 裁剪空间位置
float ComputeDepth(float4 clippos)
{
#if defined(SHADER_TARGET_GLSL) || defined(SHADER_API_GLES) || defined(SHADER_API_GLES3)
        return (clippos.z / clippos.w) * 0.5 + 0.5;
#else
    return clippos.z / clippos.w;
#endif
}

#define PM UNITY_MATRIX_P
//从投影矩阵（UNITY_MATRIX_P）计算深度反投影的校正参数，用于从屏幕深度重建世界位置。
//https://github.com/keijiro/DepthInverseProjection/blob/master/Assets/InverseProjection/Resources/InverseProjection.shader
inline float4 CalculateFrustumCorrection()
{
    float x1 = -PM._31 / (PM._11 * PM._34);
    float x2 = -PM._32 / (PM._22 * PM._34);
    return float4(x1, x2, 0, PM._33 / PM._34 + x1 * PM._13 + x2 * PM._23);
}

inline float CorrectedLinearEyeDepth(float z, float B)
{
    return 1.0 / (z / PM._34 + B);
}

#endif