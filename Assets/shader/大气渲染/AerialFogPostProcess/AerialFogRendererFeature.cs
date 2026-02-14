using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class AerialFogRendererFeature : ScriptableRendererFeature
{
    [System.Serializable]
    public class Settings
    {
        //inspector中的参数
        public Material postProcessMaterial;
        public RenderPassEvent renderPassEvent = RenderPassEvent.AfterRenderingSkybox;//决定渲染顺序
        public float fogDense;

    }
    [SerializeField]
    public Settings settings = new Settings();
    private AerialFogPass pass;

    // 这些是动态的，每帧更新的字段（放在 Feature 上）
    private RTHandle skyScatterRT;
    private RTHandle aerialLutRT;
    private RTHandle transmittanceLutRT;
    private Vector4 aerialVoxelSize;//?
    private float aerialDis;
    public override void Create()
    {
        pass = new AerialFogPass();
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        pass.Setup(
           settings.postProcessMaterial,
           skyScatterRT,
           aerialLutRT,
           transmittanceLutRT,
           aerialVoxelSize,
           aerialDis,
           settings.renderPassEvent

       );
        settings.postProcessMaterial.SetFloat("_fogDense", settings.fogDense);
        renderer.EnqueuePass(pass);
    }

    public void UpdateDynamicTextures(
         RTHandle skyScatterRT,
         RTHandle aerialLutRT,
         RTHandle transmittanceLutRT,
         Vector4 voxelSize,
         float aerialDistance)
    {
        this.skyScatterRT = skyScatterRT;
        this.aerialLutRT = aerialLutRT;
        this.transmittanceLutRT = transmittanceLutRT;
        aerialVoxelSize = voxelSize;
        aerialDis = aerialDistance;

    }

}
class AerialFogPass : ScriptableRenderPass
{
    private Material material;
    private RTHandle source;//保存“当前要处理的画面”
    private RTHandle tempTexture;//一个临时中间纹理


    // 每帧动态的输入
    private RTHandle skyViewLut;
    private RTHandle aerialPerspectiveLut;
    private RTHandle transmittanceLut;

    // 向量参数（如果每帧变，就放这里）
    private Vector4 aerialVoxelSize;

    private float aerialDistance;
    public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
    {
        // 获取相机目标纹理
        var cameraTargetDescriptor = renderingData.cameraData.cameraTargetDescriptor;
        // 如果需要降采样可以改这里
        // cameraTargetDescriptor.width /= 4; cameraTargetDescriptor.height /= 4;

        //如果当前的 tempTexture 不存在、尺寸/格式/设置跟传入的 cameraTargetDescriptor 不匹配，或者根本没分配过 → 就（重新）创建一个新的 RenderTexture，并用 RTHandle 包装它；
        //如果已经匹配 → 什么都不做，直接复用现有的。
        RenderingUtils.ReAllocateIfNeeded(ref tempTexture, cameraTargetDescriptor, name: "_TempPixelate");
    }
    public void Setup(Material mat,
       RTHandle skyLut,
       RTHandle aerialLut,
       RTHandle transLut,
       Vector4 voxelSize,
       float aerialDis,
       RenderPassEvent renderPassEvent)
    {
        this.material = mat;
        skyViewLut = skyLut;
        aerialPerspectiveLut = aerialLut;
        transmittanceLut = transLut;
        aerialVoxelSize = voxelSize;
        aerialDistance = aerialDis;
        this.renderPassEvent = renderPassEvent;
    }

    public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
    {
        if (material == null) return;
        // 2. 只对 Game 主相机执行（避免 Scene视图/预览/Overlay 崩溃）
        if (renderingData.cameraData.cameraType != CameraType.Game ||
            renderingData.cameraData.camera == null)
        {
            Debug.Log("FogPass skipped: not a main Game camera");
            return;
        }

        CommandBuffer cmd = CommandBufferPool.Get("Pixelate FullScreen");
        // 3. 获取相机目标
        RTHandle cameraTarget = renderingData.cameraData.renderer.cameraColorTargetHandle;
        // 关键防护：检查 cameraTarget 是否有效
        if (cameraTarget == null || cameraTarget.rt == null)
        {
            Debug.LogWarning($"FogPass: cameraColorTargetHandle invalid for camera '{renderingData.cameraData.camera?.name}'");
            CommandBufferPool.Release(cmd);
            return;
        }
        var desc = renderingData.cameraData.cameraTargetDescriptor;
        if (desc.width <= 0 || desc.height <= 0)
        {
            Debug.LogWarning("FogPass: invalid camera descriptor");
            CommandBufferPool.Release(cmd);
            return;
        }

        desc.depthBufferBits = 0;  // 后处理不需要深度
        RenderingUtils.ReAllocateIfNeeded(ref tempTexture, desc, FilterMode.Bilinear, TextureWrapMode.Clamp, name: "_TempFog");

        if (tempTexture == null || tempTexture.rt == null)
        {
            Debug.LogWarning("FogPass: tempTexture allocation failed");
            CommandBufferPool.Release(cmd);
            return;
        }

        // 设置材质属性（可以在这里传更多参数）
        material.SetTexture("_skyViewLut", skyViewLut);
        material.SetTexture("_aerialPerspectiveLut", aerialPerspectiveLut);
        material.SetTexture("_transmittanceLut", transmittanceLut);
        material.SetVector("_AerialPerspectiveVoxelSize", aerialVoxelSize); 
        material.SetFloat("_AerialPerspectiveDistance", aerialDistance); 
       

        // 两个转换矩阵
        Camera cam = renderingData.cameraData.camera;                                                                // GPU 投影矩阵（注意：第三个参数 false 表示不翻转 Y，URP 通常这样用）
        Matrix4x4 proj = GL.GetGPUProjectionMatrix(cam.projectionMatrix, false);
        material.SetMatrix("_InverseProjectionMatrix", proj.inverse);
        material.SetMatrix("_InverseViewMatrix", cam.cameraToWorldMatrix);

        // Blit：源 → temp → 屏幕
        // 第一步：相机 → temp（应用材质）
        Blitter.BlitCameraTexture(cmd, cameraTarget, tempTexture, material, 0);

        // 第二步：temp → 相机（纯拷贝，无材质）
        Blitter.BlitCameraTexture(cmd, tempTexture, cameraTarget);

        // 7. 执行并释放
        context.ExecuteCommandBuffer(cmd);
        CommandBufferPool.Release(cmd);
    }

    public override void OnCameraCleanup(CommandBuffer cmd)
    {
        // 可选：如果不希望常驻RT可以在这里释放
    }

}
