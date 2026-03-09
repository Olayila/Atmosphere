using System;
using System.Collections;
using System.Collections.Generic;
using Unity.Mathematics;
using Unity.VisualScripting;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using static UnityEditor.ShaderGraph.Internal.KeywordDependentCollection;

//控制 Volume Profile 的 Add Override 下拉菜单菜单在 Olayila → Color Tint
[VolumeComponentMenuForRenderPipeline("Olayila/Color Tint", typeof(UniversalRenderPipeline))]
[Serializable]
public class ColorTintVolume : VolumeComponent, IPostProcessComponent
{
    public ColorParameter color = new(Color.white, true);  // true = 可 override
    public ClampedFloatParameter blend = new(0.5f, 0f, 1f, true);

    public bool IsActive() => blend.value > 0f;  // IPostProcessComponent中，用于判断是否要执行 pass
    public bool IsTileCompatible() => false;
}

// 2. Renderer Feature（只负责注入 pass，不存参数）

public class VolumeFogRendererFeature : ScriptableRendererFeature
{
    // ==========================================================================
    //  设置部分：设置材质、渲染顺序
    // ==========================================================================
    [System.Serializable]
    public class Settings
    {
        //inspector中的参数
        public Material postProcessMaterial;
        public RenderPassEvent renderPassEvent = RenderPassEvent.AfterRenderingSkybox;

        //控制渲染分辨率部分分辨率缩放
        [Header("控制渲染分辨率部分")]
        [Tooltip("分辨率缩放")]
        [Range(0.1f, 1)]
        public float RTScale = 0.5f;

        [Tooltip("分帧渲染")]      
        public FrameBlock FrameBlocking = FrameBlock._4x4;

        [Tooltip("屏蔽相机分辨率宽度(受纹理缩放影响)")]
        [Range(100, 600)]
        public int ShieldWidth = 400;

        [Tooltip("是否开启分帧测试")]
        public bool IsFrameDebug = false;

        [Tooltip("分帧测试")]
        [Range(1, 16)]
        public int FrameDebug = 1;        

        
        //不同场景对应的phaseParam
        public enum FogScenePreset
        {
            Custom = 0,           // 使用材质面板手动调
            DenseVolumetricCloud, // 浓密体积云
            ThinMistHaze,         // 薄雾/霾
            OceanAtmosphere,      // 海面大气
            SimpleForwardOnly     // 简单测试（单 lobe 前向）
        }
        [Tooltip("选择典型场景预设，会自动覆盖 PhaseParams")]
        public FogScenePreset scenePreset = FogScenePreset.Custom;
        [Tooltip("仅在 Custom 模式下生效")]
        public Vector4 customPhaseParams = new Vector4(0.8f, 0.0f, 0.0f, 1.0f);
    }
    //全局声明settings和VolumeFogPass
    [SerializeField]
    public Settings settings = new Settings();
    private VolumeFogPass pass;
    public enum FrameBlock
    {
        _Off = 1,
        _2x2 = 4,
        _4x4 = 16
    }

    private Vector3 boundsMin;
    private Vector3 boundsMax;
    private int _frameCount_sceneView;
    // ==========================================================================
    //  创建渲染的pass
    // ==========================================================================
    public override void Create()
    {
        pass = new VolumeFogPass();
    }
    // ==========================================================================
    //  添加渲染的pass到管线中
    // ==========================================================================
    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        //需要在此处传入渲染pass的参数
        //settings.postProcessMaterial = 
        //
        if (   // 排除预览等
        renderingData.cameraData.renderType != CameraRenderType.Base) // 关键：只 Base 执行
        {
            return;  // Overlay 或其他类型相机直接跳过
        }
        pass.Setup(settings,settings.postProcessMaterial, settings.renderPassEvent,boundsMin, boundsMax);
        // 根据预设设置 phase params
        Vector4 phaseParams;
        int width = (int)(renderingData.cameraData.cameraTargetDescriptor.width * settings.RTScale);
        int height = (int)(renderingData.cameraData.cameraTargetDescriptor.height * settings.RTScale);
        pass.width = width;
        pass.height = height;
        switch (settings.scenePreset)
        {
            case Settings.FogScenePreset.DenseVolumetricCloud:
                
                Shader.EnableKeyword("SCENE_DENSE_CLOUD");
                Shader.DisableKeyword("SCENE_THIN_MIST");
                Shader.DisableKeyword("SCENE_OCEAN");
                Shader.DisableKeyword("SCENE_SIMPLE");
                break;

            case Settings.FogScenePreset.ThinMistHaze:
                
                Shader.EnableKeyword("SCENE_THIN_MIST");
                Shader.DisableKeyword("SCENE_DENSE_CLOUD");
                Shader.DisableKeyword("SCENE_OCEAN");
                Shader.DisableKeyword("SCENE_SIMPLE");
                break;

            case Settings.FogScenePreset.OceanAtmosphere:
                
                Shader.EnableKeyword("SCENE_OCEAN");
                Shader.DisableKeyword("SCENE_DENSE_CLOUD");
                Shader.DisableKeyword("SCENE_THIN_MIST");
                Shader.DisableKeyword("SCENE_SIMPLE");
                break;

            case Settings.FogScenePreset.SimpleForwardOnly:
               
                Shader.EnableKeyword("SCENE_SIMPLE");
                Shader.DisableKeyword("SCENE_DENSE_CLOUD");
                Shader.DisableKeyword("SCENE_THIN_MIST");
                Shader.DisableKeyword("SCENE_OCEAN");
                break;

            case Settings.FogScenePreset.Custom:
            default:
                phaseParams = settings.customPhaseParams;
                // Custom 模式下关闭所有预设宏，让 shader 用 _PhaseParams
                Shader.DisableKeyword("SCENE_DENSE_CLOUD");
                Shader.DisableKeyword("SCENE_THIN_MIST");
                Shader.DisableKeyword("SCENE_OCEAN");
                Shader.DisableKeyword("SCENE_SIMPLE");
                settings.postProcessMaterial.SetVector("_PhaseParams", phaseParams);
                break;
        }

        if (settings.FrameBlocking == FrameBlock._Off)
        {
            Shader.EnableKeyword("_OFF");
            Shader.DisableKeyword("_2X2");
            Shader.DisableKeyword("_4X4");
           
        }
        if (settings.FrameBlocking == FrameBlock._2x2)
        {
            Shader.DisableKeyword("_OFF");
            Shader.EnableKeyword("_2X2");
            Shader.DisableKeyword("_4X4");
           
        }
        if (settings.FrameBlocking == FrameBlock._4x4)
        {
            Shader.DisableKeyword("_OFF");
            Shader.DisableKeyword("_2X2");
            Shader.EnableKeyword("_4X4");
            
        }

        if (settings.IsFrameDebug)
        {
            settings.postProcessMaterial.SetInt("_FrameCount", settings.FrameDebug);
        }
        else
        {
            _frameCount_sceneView = (++_frameCount_sceneView) % (int)settings.FrameBlocking;
            settings.postProcessMaterial.SetInt("_FrameCount", _frameCount_sceneView);
        }
        
       
       
        renderer.EnqueuePass(pass);
    }
    // ==========================================================================
    //  额外：可以添加自定义函数供外部调用
    // ==========================================================================
    public void SetFogBounds(Vector3 min, Vector3 max)
    {        
        boundsMin = min;
        boundsMax = max;        
    }
    class VolumeFogPass : ScriptableRenderPass
    {
        // ==========================================================================
        // pass的properties部分,可以通过setup设置或pubilc在外部（较少
        // ==========================================================================
        private Material material;
        private RTHandle source;//保存“当前要处理的画面”
        private RTHandle tempTexture;//一个临时中间纹理

        private Vector3 boundsMin;
        private Vector3 boundsMax;

        //云纹理的宽度
        public int width;
        //云纹理的高度
        public int height;

        private int frameCount;
        //纹理切换
        public int rtSwitch;
        private Vector2Int lastResolution = Vector2Int.zero;
        private CameraType lastCameraType = CameraType.Game;


        private Settings settings;
        private RTHandle accumA;
        private RTHandle accumB;
        private RTHandle currentRead;   // 上一帧累积结果
        private RTHandle currentWrite;  // 本帧要写的新累积结果

        private Matrix4x4 prevViewMatrix = Matrix4x4.identity;
        private Matrix4x4 prevProjMatrix = Matrix4x4.identity;
        private Matrix4x4 iPrevViewMatrix = Matrix4x4.identity;
        private Matrix4x4 iPrevProjMatrix = Matrix4x4.identity;
        private Vector3 prevCameraPos = Vector3.zero;
        private Quaternion prevCameraRot = Quaternion.identity;
        public void Setup(Settings settings,Material mat,RenderPassEvent renderPassEvent, Vector3 boundsMin, Vector3 boundsMax)
        {
            this.material = mat;
            this.renderPassEvent = renderPassEvent;

            this.boundsMin = boundsMin;
            this.boundsMax = boundsMax;  

            this.settings = settings;
           
            //this,height = height;
            //this.width = width;
            //this.frameCount = 0;
        }

        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            // 获取相机目标纹理           
            var desc = renderingData.cameraData.cameraTargetDescriptor;
            desc.depthBufferBits = 0;
            desc.colorFormat = RenderTextureFormat.ARGBHalf;  // 推荐 half 或 float
            //RenderingUtils.ReAllocateIfNeeded(ref tempTexture, cameraTargetDescriptor, name: "_TempPixelate");
            RenderingUtils.ReAllocateIfNeeded(ref accumA, desc, FilterMode.Bilinear, TextureWrapMode.Clamp, name: "_CloudAccumA");
            RenderingUtils.ReAllocateIfNeeded(ref accumB, desc, FilterMode.Bilinear, TextureWrapMode.Clamp, name: "_CloudAccumB");
            if (currentRead == null || renderingData.cameraData.cameraType != lastCameraType)
            {
                currentRead = accumA;
                currentWrite = accumB;
                // cmd.ClearRenderTarget(false, true, Color.black);  // 可选
            }
            lastCameraType = renderingData.cameraData.cameraType;
        }
       // public void SetSource(RTHandle src) => source = src;

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            #region 执行前
            // ==========================================================================
            // 执行前准备工作
            // ==========================================================================
            //var stack = VolumeManager.instance.stack;
            //var settings = stack.GetComponent<ColorTintVolume>();
            if (material == null) return;
            // 2. 只对 Game 主相机执行（避免 Scene视图/预览/Overlay 崩溃）
            //if (renderingData.cameraData.cameraType != CameraType.Game ||
            //    renderingData.cameraData.camera == null)
            //{
            //    Debug.Log("VolumeFogPass skipped: not a main Game camera");
            //    return;
            //}
            CommandBuffer cmd = CommandBufferPool.Get("Pixelate FullScreen");
            // 3. 获取相机目标
            RTHandle cameraTarget = renderingData.cameraData.renderer.cameraColorTargetHandle;
            // 关键防护：检查 cameraTarget 是否有效
            if (cameraTarget == null || cameraTarget.rt == null)
            {
                Debug.LogWarning($"VolumeFogPass: cameraColorTargetHandle invalid for camera '{renderingData.cameraData.camera?.name}'");
                CommandBufferPool.Release(cmd);
                return;
            }
            var desc = renderingData.cameraData.cameraTargetDescriptor;
            if (desc.width <= 0 || desc.height <= 0)
            {
                Debug.LogWarning("VolumeFogPass: invalid camera descriptor");
                CommandBufferPool.Release(cmd);
                return;
            }

           desc.depthBufferBits = 0;  // 后处理不需要深度
           // RenderingUtils.ReAllocateIfNeeded(ref tempTexture, desc, FilterMode.Bilinear, TextureWrapMode.Clamp, name: "_TempFog");

            var temp = currentRead;
            currentRead = currentWrite;
            currentWrite = temp;
            cmd.SetGlobalTexture("_MainTex", currentRead);
            //if (tempTexture == null || tempTexture.rt == null)
            //{
            //    Debug.LogWarning("VolumeFogPass: tempTexture allocation failed");
            //    CommandBufferPool.Release(cmd);
            //    return;
            //}
            #endregion 
            // ==========================================================================
            // 设定材质属性
            // ==========================================================================
            // 从 Volume 取值
            //material.SetColor("_Color", settings.color.value);
           // material.SetFloat("_BlendMultiply", settings.blend.value);
            material.SetVector("_boundsMin", boundsMin);
            material.SetVector("_boundsMax", boundsMax);
           // material.SetInt("_FrameCount", settings.FrameDebug);
            material.SetInt("_Width", width-1);
            material.SetInt("_Height", height-1);

            // 再设置矩阵（类似你原来的逻辑）
            Camera cam = renderingData.cameraData.camera;            
            // GPU 投影矩阵（注意：第三个参数 false 表示不翻转 Y，URP 通常这样用）
            Matrix4x4 proj = GL.GetGPUProjectionMatrix(cam.projectionMatrix, false);
            Matrix4x4 iProj = proj.inverse;
            Matrix4x4 camToWorld = cam.cameraToWorldMatrix;
            material.SetMatrix("_InverseProjectionMatrix", iProj);          
            material.SetMatrix("_InverseViewMatrix", camToWorld);
            //上一帧相机位置
         
            material.SetMatrix("_InverseCamToWorldMatrix", iPrevViewMatrix);          
            material.SetMatrix("_InversePrevProjMatrix", iPrevProjMatrix);
          

            // ==========================================================================
            // Blit：用material把cameratarget写到temptexture中，cmd作为一个命令收集器收集这次指令
            // ==========================================================================


            Blitter.BlitCameraTexture(cmd, cameraTarget, currentWrite, material, 0);
            Blitter.BlitCameraTexture(cmd, currentWrite, cameraTarget);
            //保存当前帧的rotation和pos供下一帧采样用
            prevCameraPos = cam.transform.position;
            prevCameraRot = cam.transform.rotation;

            prevViewMatrix = camToWorld;
            prevProjMatrix = iProj ;
            iPrevViewMatrix = camToWorld.inverse ;
            iPrevProjMatrix = proj;
            // 7. 执行并释放
            context.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
           
            

        }
    }

}
