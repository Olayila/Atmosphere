using UnityEngine.Rendering.Universal;
using UnityEngine.Rendering;
using UnityEngine;
using UnityEngine.UI;

public class StencilOutlinePostFeature : ScriptableRendererFeature
{
    [System.Serializable]
    public class Settings
    {
        //public LayerMask layerMask = 1 << LayerMask.NameToLayer("PlayerMask");
        public Material outlineMaterial;          // 你的描边材质（带 Stencil Comp Equal）
        public Material stencilMaterial;          // 你的描边材质（带 Stencil Comp Equal）
        public RenderPassEvent stencilPassEvent = RenderPassEvent.AfterRenderingOpaques;
        public RenderPassEvent outlinePassEvent = RenderPassEvent.AfterRenderingPostProcessing;
        public string stencilRTName = "_StencilRT";  // 全局纹理名，后处理读取这个
        public RenderTextureFormat rtFormat = RenderTextureFormat.R8;  // 单通道就够
        public int stencilRef = 1;                // 与 Player 标记的 Ref 一致
    }

    public Settings settings = new Settings();
    private OutlinePostPass outlinePass;
    private StencilToRTPass stencilPass;
    public override void Create()
    {
        stencilPass = new StencilToRTPass();
        stencilPass.settings = settings;
        stencilPass.renderPassEvent = settings.stencilPassEvent;

        outlinePass = new OutlinePostPass();
        outlinePass.settings = settings;
        outlinePass.renderPassEvent = settings.outlinePassEvent;
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData data)
    {
        if (data.cameraData.cameraType != CameraType.Game) return;
        renderer.EnqueuePass(stencilPass);
        //renderer.EnqueuePass(outlinePass);
        
    }
    class OutlinePostPass : ScriptableRenderPass
    {
        public Settings settings;
        //private RTHandle StencilRT;

        public override void Execute(ScriptableRenderContext context, ref RenderingData data)
        {
            if (settings.outlineMaterial == null) return;

            CommandBuffer cmd = CommandBufferPool.Get("Stencil Outline Post");

            RTHandle cameraTarget = data.cameraData.renderer.cameraColorTargetHandle;
            cmd.SetRenderTarget(cameraTarget);
            cmd.SetViewProjectionMatrices(Matrix4x4.identity, Matrix4x4.identity);
            cmd.SetGlobalTexture("_BlitTexture", cameraTarget);
            Mesh fullscreenMesh = CreateFullscreenMesh();
            cmd.DrawMesh(fullscreenMesh, Matrix4x4.identity, settings.outlineMaterial, 0, 0);

            context.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
        }

        private Mesh CreateFullscreenMesh()
        {
            // 缓存静态 Mesh 更好，这里简单实现
            Mesh mesh = new Mesh();
            mesh.vertices = new Vector3[4] {
                new Vector3(-1,-1,0), new Vector3(1,-1,0),
                new Vector3(-1,1,0),  new Vector3(1,1,0)
            };
            mesh.uv = new Vector2[4] {
                new Vector2(0,0), new Vector2(1,0),
                new Vector2(0,1), new Vector2(1,1)
            };
            mesh.triangles = new int[] { 0, 2, 1, 1, 2, 3 };
            return mesh;
        }
    }

    class StencilToRTPass : ScriptableRenderPass
    {
        public Settings settings;
        private RTHandle stencilRT;

       

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            CommandBuffer cmd = CommandBufferPool.Get("Stencil To RT");
            RTHandle cameraTarget = renderingData.cameraData.renderer.cameraColorTargetHandle;
            // 1. 清空 stencilRT
            cmd.SetRenderTarget(stencilRT);
            cmd.ClearRenderTarget(false, true, Color.clear);  // 清颜色，不清深度
            
            // 2. 设置渲染状态，让只在 stencil != 0 的像素输出白色（或 1）
            cmd.SetGlobalInt("_StencilRef", 1);  // 假设你标记的是 Ref=1
            cmd.SetGlobalInt("_StencilComp", (int)CompareFunction.Equal);
            
            // 3. 用一个简单材质 Blit 全屏（输出固定值）
            // 这里我们用一个内置或简单材质，frag 直接 return 1
            //Material copyMat = new Material(Shader.Find("Hidden/CopyStencilToRT"));  // 你需要创建这个 shader
            if (settings.stencilMaterial == null)
            {
                Debug.LogError("CopyStencilToRT shader not found");
                CommandBufferPool.Release(cmd);
                return;
            }

            // Blit：把标记区域输出到 stencilRT
            Blitter.BlitCameraTexture(cmd, renderingData.cameraData.renderer.cameraColorTargetHandle, stencilRT, settings.stencilMaterial, 0);
            Blitter.BlitCameraTexture(cmd, stencilRT, cameraTarget);
            // 4. 绑定到全局纹理，让后处理能采样
            cmd.SetGlobalTexture(settings.stencilRTName, stencilRT);

            context.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
        }

        public override void OnCameraCleanup(CommandBuffer cmd)
        {
            // 可选：释放 stencilRT（但 ReAllocateIfNeeded 会自动管理）
        }
    }

   
}