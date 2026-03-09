using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class OutlineRendererFeature : ScriptableRendererFeature
{
    [System.Serializable]
    public class Settings
    {
        //inspector中的参数
        public Material postProcessMaterial;
        public RenderPassEvent renderPassEvent = RenderPassEvent.AfterRenderingSkybox;//决定渲染顺序        

    }
    [SerializeField]
    public Settings settings = new Settings();
    private OutlinePass pass;




    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        if (   // 排除预览等
         renderingData.cameraData.renderType != CameraRenderType.Base) // 关键：只 Base 执行
        {
            return;  // Overlay 或其他类型相机直接跳过
        }
        pass.Setup(
           settings.postProcessMaterial, settings.renderPassEvent

       );
        int width = (int)(renderingData.cameraData.cameraTargetDescriptor.width);
        int height = (int)(renderingData.cameraData.cameraTargetDescriptor.height);
        pass.width = width;
        pass.height = height;

        renderer.EnqueuePass(pass);
    }

    public override void Create()
    {
        pass = new OutlinePass();
    }


    class OutlinePass : ScriptableRenderPass
    {
        private Material material;
        private RTHandle source;//保存“当前要处理的画面”
        private RTHandle tempTexture;//一个临时中间纹理

        //云纹理的宽度
        public int width;
        //云纹理的高度
        public int height;

        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            // 获取相机目标纹理
            var cameraTargetDescriptor = renderingData.cameraData.cameraTargetDescriptor;                       
            RenderingUtils.ReAllocateIfNeeded(ref tempTexture, cameraTargetDescriptor, name: "_TempPixelate");
        }
        public void Setup(Material mat, RenderPassEvent renderPassEvent)
        {
            this.material = mat;
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

            CommandBuffer cmd = CommandBufferPool.Get("Outline FullScreen");
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
                Debug.LogWarning("OutlinePass: invalid camera descriptor");
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
            material.SetInt("_Width", width - 1);
            material.SetInt("_Height", height - 1);


            // Blit：源 → temp → 屏幕
            // 第一步：相机 → temp（应用材质）
            Blitter.BlitCameraTexture(cmd, cameraTarget, tempTexture, material, 0);

            // 第二步：temp → 相机（纯拷贝，无材质）
            Blitter.BlitCameraTexture(cmd, tempTexture, cameraTarget);

            // 7. 执行并释放
            context.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);

        }
    }

}
