using UnityEngine;
using UnityEngine.Rendering;

[RequireComponent(typeof(Camera))]
public class LegacyStencilOutlineController : MonoBehaviour
{
    [Header("描边材质")]
    public Material StencilProcessMaterial;     // 用于 stencil 处理的材质（可选）
    public Material EdgeDetectionMaterial;       // 最终描边材质（必须有 _StencilTex 参数）

    [Header("调试")]
    public bool debugShowStencilBuffer = false;  // 按 F1 切换全屏显示 stencilRT

    private Camera mainCamera;
    public RenderTexture CameraRenderTexture;
    public RenderTexture Buffer;

    private RTHandle stencilRTHandle;  // 用于传给 Render Feature 的句柄

    private bool showDebug = false;

    void Awake()
    {
        mainCamera = GetComponent<Camera>();
        if (mainCamera == null)
        {
            Debug.LogError("必须挂载在 Camera 上");
            enabled = false;
            return;
        }
    }

    void Start()
    {
        int w = mainCamera.pixelWidth;
        int h = mainCamera.pixelHeight;

        if (w <= 0 || h <= 0)
        {
            Debug.LogError("相机分辨率无效");
            return;
        }

        // 主渲染 RT（带深度）
        CameraRenderTexture = new RenderTexture(w, h, 24, RenderTextureFormat.ARGB32);
        CameraRenderTexture.name = "CameraRenderTex";
        CameraRenderTexture.Create();

        // Stencil Buffer（只需要单通道）
        Buffer = new RenderTexture(w, h, 0, RenderTextureFormat.R8);
        Buffer.name = "StencilBuffer";
        Buffer.Create();

        // 绑定给描边材质
        if (EdgeDetectionMaterial != null)
        {
            EdgeDetectionMaterial.SetTexture("_StencilTex", Buffer);
        }
        else
        {
            Debug.LogWarning("EdgeDetectionMaterial 未赋值");
        }

        // 创建 RTHandle（用于传给 Render Feature）
        stencilRTHandle = RTHandles.Alloc(Buffer);

        Debug.Log("Legacy Stencil Outline 初始化完成");
    }

    private void OnPreRender()
    {
        if (mainCamera.targetTexture != CameraRenderTexture)
        {
            mainCamera.targetTexture = CameraRenderTexture;
        }
    }

    void OnPostRender()
    {
        mainCamera.targetTexture = null;

        // 1. 清空 Buffer
        Graphics.SetRenderTarget(Buffer);
        GL.Clear(true, true, new Color(0, 0, 0, 0));

        // 2. 共享深度 + stencil 处理
        Graphics.SetRenderTarget(Buffer.colorBuffer, CameraRenderTexture.depthBuffer);

        // 可选：用 StencilprocessMaterial 进行过滤/标记
        if (StencilProcessMaterial != null)
        {
            Graphics.Blit(CameraRenderTexture, StencilProcessMaterial);
        }

        // 3. 描边（直接写回屏幕）
        Graphics.Blit(CameraRenderTexture, null as RenderTexture, EdgeDetectionMaterial);

        // 调试：按 F1 显示 stencil buffer
        if (Input.GetKeyDown(KeyCode.F4))
        {
            showDebug = !showDebug;
            Debug.Log($"Stencil Buffer Debug: {(showDebug ? "ON" : "OFF")}");
        }

        if (showDebug)
        {
            // 全屏显示 Buffer（调试用）
            Graphics.Blit(Buffer, null as RenderTexture);
        }
    }

    void OnDestroy()
    {
        if (CameraRenderTexture != null)
        {
            CameraRenderTexture.Release();
            CameraRenderTexture = null;
        }

        if (Buffer != null)
        {
            Buffer.Release();
            Buffer = null;
        }

        if (stencilRTHandle != null)
        {
            RTHandles.Release(stencilRTHandle);
            stencilRTHandle = null;
        }
    }

    /// <summary>
    /// 外部 Render Feature 调用此方法获取 stencilRT 的 RTHandle
    /// </summary>
    public RTHandle GetStencilBufferRTHandle()
    {
        return stencilRTHandle;
    }
}