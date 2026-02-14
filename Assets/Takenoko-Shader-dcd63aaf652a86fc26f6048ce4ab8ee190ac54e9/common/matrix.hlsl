#ifndef _MATRIX_
#define _MATRIX_
//https://github.com/cnlohr/shadertrixx
// 一个高效的手写 4x4 矩阵求逆函数（基于伴随矩阵 + 转置除行列式）
float4x4 inverse(float4x4 input)
{
    // 辅助宏：计算 3x3 子矩阵的行列式
#define minor(a, b, c) determinant(float3x3(input.a, input.b, input.c))
    //determinant(float3x3(input._22_23_23, input._32_33_34, input._42_43_44))
    
    // 计算伴随矩阵（cofactor matrix）的每个元素（带正负号交替）伴随矩阵（Adjugate Matrix 或 Classical Adjoint Matrix）：求一个矩阵的逆矩阵
    //逆矩阵 = 伴随矩阵转置 ÷ 矩阵的行列式（一个数字）
    float4x4 cofactors = float4x4(
        minor(_22_23_24, _32_33_34, _42_43_44),
        -minor(_21_23_24, _31_33_34, _41_43_44),
        minor(_21_22_24, _31_32_34, _41_42_44),
        -minor(_21_22_23, _31_32_33, _41_42_43),

        -minor(_12_13_14, _32_33_34, _42_43_44),
        minor(_11_13_14, _31_33_34, _41_43_44),
        -minor(_11_12_14, _31_32_34, _41_42_44),
        minor(_11_12_13, _31_32_33, _41_42_43),

        minor(_12_13_14, _22_23_24, _42_43_44),
        -minor(_11_13_14, _21_23_24, _41_43_44),
        minor(_11_12_14, _21_22_24, _41_42_44),
        -minor(_11_12_13, _21_22_23, _41_42_43),

        -minor(_12_13_14, _22_23_24, _32_33_34),
        minor(_11_13_14, _21_23_24, _31_33_34),
        -minor(_11_12_14, _21_22_24, _31_32_34),
        minor(_11_12_13, _21_22_23, _31_32_33)
    );
#undef minor   // 删除辅助宏，避免污染
    return transpose(cofactors) / determinant(input);
}
// 世界空间 → 观察空间（视图矩阵）
float4x4 worldToView()
{
    return UNITY_MATRIX_V;
}
// 观察空间 → 世界空间（视图矩阵的逆）
float4x4 viewToWorld()
{
    return UNITY_MATRIX_I_V;
}
// 观察空间 → 裁剪空间（投影矩阵）
float4x4 viewToClip()
{
    return UNITY_MATRIX_P;
}
// 裁剪空间 → 观察空间（投影矩阵的逆，常用于深度重建）
float4x4 clipToView()
{
    return inverse(UNITY_MATRIX_P);
}
// 世界空间 → 裁剪空间（VP 矩阵）
float4x4 worldToClip()
{
    return UNITY_MATRIX_VP;
}
// 裁剪空间 → 世界空间（VP 矩阵的逆，常用于从深度重建世界位置）
float4x4 clipToWorld()
{
    return inverse(UNITY_MATRIX_VP);
}
//将世界空间坐标系转换到切线空间（TBN）坐标系
float3 worldToLocal(float3 x, float3 y, float3 z, float3 v)
{
    return float3(dot(x, v), dot(y, v), dot(z, v));
}
// 切线空间向量 → 世界空间（使用 TBN 矩阵）
float3 localToWorld(float3 x, float3 y, float3 z, float3 v)
{
    return x * v.x + y * v.y + z * v.z;
}
// 根据旋转轴 n 和角度 theta 生成四元数，四元数（Quaternion） 是一种专门用来表示旋转的数学工具
#define VectorToQuatunion(n, theta) float4(cos(0.5 * theta), n.x * sin(0.5 * theta), n.y * sin(0.5 * theta), n.z * sin(0.5 * theta))
// 用四元数旋转向量（标准四元数旋转公式）
float3 vector_quat_rotate(float3 v, float4 q)
{
    return v + 2.0 * cross(q.xyz, cross(q.xyz, v) + q.w * v);
}
// 辅助：copysign（保留绝对值，符号跟随 b）
#define copysignf(a, b) (b < 0.0 ? - a : a)
// 根据法线自动生成正交的切线和副切线（TBN 矩阵）
void orthonormalBasis(float3 normal, inout float3 tangent, inout float3 binormal)
{
    // float sign = copysignf(1.0f, normal.z);
    // float a = -1.0f / (sign + normal.z);
    // float b = normal.x * normal.y * a;
    // tangent = float3(1.0f + sign * normal.x * normal.x * a, sign * b,
    // - sign * normal.x);
    // binormal = float3(b, sign + normal.y * normal.y * a, -normal.y);
    if (abs(normal[1]) < 0.999f)
    {
        tangent = cross(normal, float3(0, 1, 0));
    }
    else
    {
        tangent = cross(normal, float3(0, 0, -1));
    }
    tangent = normalize(tangent);
    binormal = cross(tangent, normal);
    binormal = normalize(binormal);
}

#endif