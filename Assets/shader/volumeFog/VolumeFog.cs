using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class VolumeFog : MonoBehaviour
{
    public struct FogSettings
    {
        // ================================================
        // 核心雾效参数
        // ================================================
        
        public float density;

        public Color fogColor;

        public float maxPlane;

        public float baseHeight;
    
        public float heightFalloff;

        public Vector2 tempJitter;

        public Vector3Int dimension;

        public Vector3 volumePosition;

        public Vector3 volumeScale;

        public int rayMarchSteps;

        public float minStepSize;

        public bool enableTemporalJitter;

        public float temporalJitterScale;

        public int jitterSequenceLength;


    }

        public ComputeShader volumeFogCS;
    public RenderTexture transmittanceLut;

    // Start is called before the first frame update
    void Start()
    {
        
    }

    // Update is called once per frame
    void Update()
    {
        
    }

    private void SetVolumeFogComputeParameters(Camera camera, FogSettings fogSetting, ComputeShader volumeFogCS, int kernelIndex)
    {
        // 1. 获取基本相机参数
        float nearClip = camera.nearClipPlane;
        float farClip = fogSetting.maxPlane;  // 雾效最远距离（自定义）

        // 2. 计算 ZParam（用于深度反投影）
        Vector4 zParam = GetZParam(nearClip, farClip);

        // 3. 计算抖动相关的逆 VP（如果有 temporal jitter）
        Matrix4x4 vp;
        Matrix4x4 inverseDitherVP;
        GetInverseDitherVP(camera, nearClip, farClip, fogSetting.tempJitter, out inverseDitherVP, out vp);

        // 4. 计算对数深度编码/解码参数
        float c = 0.5f;  // 你代码中的 c 值，可调（建议 5~20，这里保持原值）
        Vector4 logarithmicDepthDecodingParams = ComputeLogarithmicDepthDecodingParams(nearClip, farClip, c);
        Vector4 logarithmicDepthEncodingParams = ComputeLogarithmicDepthEncodingParams(nearClip, farClip, c);

        // 5. 计算 WorldToVolume 矩阵（假设你有 fogSetting.dimension 等）
        Matrix4x4 world2Volume = Matrix4x4.TRS(fogSetting.volumePosition, Quaternion.identity, fogSetting.volumeScale);

        // 6. 设置所有 Compute Shader 参数
        // 注意：kernelIndex 是你通过 volumeFogCS.FindKernel("VolumeFogMain") 得到的索引
        int kernel = kernelIndex;  // 假设已提前获取

        // 矩阵参数
        volumeFogCS.SetMatrix("_World2Volume", world2Volume);
        volumeFogCS.SetMatrix("_InverseVP", vp.inverse);               // 如果 shader 需要逆矩阵
        volumeFogCS.SetMatrix("_InverseDitherVP", inverseDitherVP);

        // 向量参数
        volumeFogCS.SetVector("_ZParam", zParam);
        volumeFogCS.SetVector("_VolumeSize", new Vector4(
            fogSetting.dimension.x,
            fogSetting.dimension.y,
            fogSetting.dimension.z,
            1.0f
        ));
        volumeFogCS.SetVector("_LogarithmicDepthDecodingParams", logarithmicDepthDecodingParams);
        volumeFogCS.SetVector("_LogarithmicDepthEncodingParams", logarithmicDepthEncodingParams);

        // 浮点参数
        volumeFogCS.SetFloat("_FrameCount", Time.frameCount % 1024);  // 或 data.GetFrameCount()
                                                                      // 如果有其他浮点（如密度、强度等）
                                                                      // volumeFogCS.SetFloat("_FogDensity", fogSetting.density);

        // 整数参数（如果需要）
        // volumeFogCS.SetInt("_SomeIntParam", someValue);

        // 可选：绑定纹理（如果 VolumeFogMain 需要采样）
        // volumeFogCS.SetTexture(kernel, "_NoiseTex", fogSetting.noiseTexture);
        // volumeFogCS.SetTexture(kernel, "_CameraDepthTexture", Shader.GetGlobalTexture("_CameraDepthTexture"));
    }



    void GetInverseDitherVP(
     Camera camera,
     float nearClip,
     float farClip,
     Vector2 jitter,         // 当前帧抖动偏移（通常由 Halton 或 blue noise 生成）
    
     out Matrix4x4 inverseDitherVP,
     out Matrix4x4 vp)
    {
        // 基础投影矩阵（用雾效远裁剪面）
        Matrix4x4 proj = Matrix4x4.Perspective(
            camera.fieldOfView,
            camera.aspect,
            nearClip,
            farClip
        );

        // 基础世界到相机矩阵
        Matrix4x4 worldToCam = camera.worldToCameraMatrix;

        // ================================================
        // 方式1：投影矩阵 sub-pixel jitter（TAA 风格，最常用）
        // ================================================
        // 将 jitter 缩放到像素级偏移（通常 jitter 在 [-0.5, 0.5] 像素范围内）
        float jitterScale = 1.0f / camera.pixelWidth; // 或根据分辨率调整
        //proj.m02 += jitter.x * jitterScale;           // x 方向偏移（投影矩阵第 0 行第 2 列）
        //proj.m12 += jitter.y * jitterScale;           // y 方向偏移（第 1 行第 2 列）

        // ================================================
        // 方式2：直接偏移相机位置（worldToCameraMatrix 平移，更适合体积雾）
        // ================================================
        // 根据帧号或 jitter 生成世界空间偏移（通常很小，0.01~0.1 米量级）
        // 这里示例用 jitter + 帧号伪随机
        float scale = 0.05f; // 偏移幅度（可调，0.01~0.2 米常见）
        Vector3 jitterOffsetWS = new Vector3(
            jitter.x * scale,
            jitter.y * scale,
            0f
        );

        // 可加一点基于帧号的随机方向（避免固定偏移方向）
        // float angle = (frameCount % 64) * Mathf.PI * 2.0f / 64.0f;
        // jitterOffsetWS = Quaternion.Euler(0, angle * Mathf.Rad2Deg, 0) * jitterOffsetWS;

        // 应用偏移到相机位置（worldToCameraMatrix 的平移部分）
        Vector4 camPosColumn = worldToCam.GetColumn(3);
        camPosColumn += new Vector4(jitterOffsetWS.x, jitterOffsetWS.y, jitterOffsetWS.z, 0f);
        worldToCam.SetColumn(3, camPosColumn);

        // ================================================
        // 计算最终 VP 和逆矩阵
        // ================================================
        vp = proj * worldToCam;
        inverseDitherVP = vp.inverse;

        // 如果你只想用方式1（投影偏移），可以注释掉方式2的部分
        // 如果只想用方式2，可以注释掉方式1的 proj.m02 / m12 修改
    }


    /// </summary>
    /// <param name="nearPlane">近裁剪面距离（米）</param>
    /// <param name="farPlane">远裁剪面距离（米）</param>
    /// <param name="c">- c 越大，近处精度越高，远处压缩越强
    ///               - 常见取值范围：2.0 ~ 100.0（推荐 5~20）</param>
    /// <returns>用于着色器编码的对数深度参数 Vector4(E, F, G, 0)</returns>
    static Vector4 ComputeLogarithmicDepthEncodingParams(float nearPlane, float farPlane, float c)
    {
        Vector4 depthParams = new Vector4();

        float n = nearPlane;
        float f = farPlane;

        // F = 1 / log2(c * (f - n) + 1)
        depthParams.y = 1.0f / Mathf.Log(c * (f - n) + 1, 2);
        // E = log2(c) * F
        depthParams.x = Mathf.Log(c, 2) * depthParams.y;
        // G = n - 1/c
        depthParams.z = n - 1.0f / c;
        depthParams.w = 0.0f;

        return depthParams;
    }
    //farPlane是自定义的雾效最远距离
    /// </summary>
    /// <param name="nearPlane">近裁剪面距离（米）</param>
    /// <param name="farPlane">远裁剪面距离（米）</param>
    /// <param name="c">深度曲线控制常数（>0，与编码时相同）</param>
    /// <returns>用于着色器解码的对数深度参数 Vector4(L, M, N, 0), 解码回真实的线性眼空间深度（单位：米）</returns>

    // See DecodeLogarithmicDepthGeneralized().
    static Vector4 ComputeLogarithmicDepthDecodingParams(float nearPlane, float farPlane, float c)
    {
        Vector4 depthParams = new Vector4();

        float n = nearPlane;
        float f = farPlane;

        depthParams.x = 1.0f / c;
        depthParams.y = Mathf.Log(c * (f - n) + 1, 2);
        depthParams.z = n - 1.0f / c; // Same
        depthParams.w = 0.0f;

        return depthParams;
    }
    /// </summary>
    /// <param name="nearClip">近裁剪面距离（米，与相机一致）</param>
    /// <param name="farClip">雾效计算使用的远距离（米，通常远大于相机 farClip）
    /// 该函数根据 Unity 当前平台的深度缓冲是否使用反向 Z（Reversed-Z）来生成一组参数，
    /// 用于将硬件深度值（0~1）转换为线性眼空间深度，或进行深度相关的反投影计算。</param>
    /// <returns>ZBufferParams 等效的 Vector4(x, y, z, w)</returns>

    //farClip是自定义的雾效最远距离 
    static Vector4 GetZParam(float nearClip, float farClip)
    {
        bool reZ = SystemInfo.usesReversedZBuffer;
        Vector4 zParam;
        if (reZ)
        {
            zParam.x = -1 + farClip / nearClip;
            zParam.y = 1;
            zParam.z = zParam.x / farClip;
            zParam.w = 1 / farClip;
        }
        else
        {
            zParam.x = 1 - farClip / nearClip;
            zParam.y = farClip / nearClip;
            zParam.z = zParam.x / farClip;
            zParam.w = zParam.y / farClip;
        }
        return zParam;
    }
    /// <summary>
    ///
    /// 计算用于深度反投影的逆视图投影矩阵（Inverse View-Projection Matrix）。
    /// 
    /// 该函数基于给定的相机参数和自定义雾效远裁剪面，生成一个专用于雾效/大气透视计算的逆 VP 矩阵。
    /// </summary>
    /// <param name="camera"></param>
    /// <param name="nearClip"></param>
    /// <param name="fogFarClip"></param>
    /// <param name="vp"></param>
    static void GetInverseVP(Camera camera, float nearClip, float fogFarClip, out Matrix4x4 vp)
    {
        Matrix4x4 proj = Matrix4x4.Perspective(camera.fieldOfView, camera.aspect, nearClip, fogFarClip);
        Matrix4x4 worldToCmaera = camera.worldToCameraMatrix;
        vp = proj * worldToCmaera;
    }


   
}
