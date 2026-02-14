using System;
using System.Collections;
using System.Collections.Generic;
using Unity.Mathematics;
using Unity.VisualScripting;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

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
        public Texture3D exampleNoise;
        public Texture2D transmittanceLut;
        public Texture2D weatherMap;
        public float scale;
        public float step = 8.0f;
        public float rayStep = 8.0f;
        public float darknessThreshold;
        public Color colA;
        public Color colB;
        public float colorOffset1;
        public float colorOffset2;
        public float lightAbsorptionTowardSun;
        public float lightAbsorptionThroughCloud;
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

    private Vector3 boundsMin;
    private Vector3 boundsMax;

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
        pass.Setup(settings.postProcessMaterial, settings.renderPassEvent, settings.exampleNoise, settings.scale,boundsMin, boundsMax);
        // 根据预设设置 phase params
        Vector4 phaseParams;

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
        settings.postProcessMaterial.SetFloat("_step", settings.step);
        settings.postProcessMaterial.SetFloat("_rayStep", settings.rayStep);
        settings.postProcessMaterial.SetFloat("_darknessThreshold", settings.darknessThreshold);
        settings.postProcessMaterial.SetFloat("_colorOffset1", settings.colorOffset1);
        settings.postProcessMaterial.SetFloat("_colorOffset2", settings.colorOffset2);
        settings.postProcessMaterial.SetFloat("_lightAbsorptionTowardSun", settings.lightAbsorptionTowardSun);
        settings.postProcessMaterial.SetColor("_colA", settings.colA);
        settings.postProcessMaterial.SetTexture("_transmittanceLut", settings.transmittanceLut);
        settings.postProcessMaterial.SetTexture("_weatherMap", settings.weatherMap);
        settings.postProcessMaterial.SetFloat("_lightAbsorptionThroughCloud", settings.lightAbsorptionThroughCloud);

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
        private Texture3D exampleNoise;
        private float scale;

        public void Setup(Material mat,RenderPassEvent renderPassEvent,Texture3D texture3D, float scale,Vector3 boundsMin, Vector3 boundsMax)
        {
            this.material = mat;
            this.renderPassEvent = renderPassEvent;
            this.boundsMin = boundsMin;
            this.boundsMax = boundsMax;
            this.exampleNoise = texture3D;
            this.scale = scale;
        }

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
        public void SetSource(RTHandle src) => source = src;

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            #region 执行前
            // ==========================================================================
            // 执行前准备工作
            // ==========================================================================
            var stack = VolumeManager.instance.stack;
            var settings = stack.GetComponent<ColorTintVolume>();
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
            RenderingUtils.ReAllocateIfNeeded(ref tempTexture, desc, FilterMode.Bilinear, TextureWrapMode.Clamp, name: "_TempFog");

            if (tempTexture == null || tempTexture.rt == null)
            {
                Debug.LogWarning("VolumeFogPass: tempTexture allocation failed");
                CommandBufferPool.Release(cmd);
                return;
            }
            #endregion 
            // ==========================================================================
            // 设定材质属性
            // ==========================================================================
            // 从 Volume 取值
            material.SetColor("_Color", settings.color.value);
            material.SetFloat("_BlendMultiply", settings.blend.value);
            material.SetVector("_boundsMin", boundsMin);
            material.SetVector("_boundsMax", boundsMax);
            material.SetTexture("_noiseTex",exampleNoise);
            material.SetFloat("_texScale", scale);
            // 再设置矩阵（类似你原来的逻辑）
            Camera cam = renderingData.cameraData.camera;

            // GPU 投影矩阵（注意：第三个参数 false 表示不翻转 Y，URP 通常这样用）
            Matrix4x4 proj = GL.GetGPUProjectionMatrix(cam.projectionMatrix, false);
            material.SetMatrix("_InverseProjectionMatrix", proj.inverse);

            // 视图逆矩阵（cameraToWorldMatrix 就是 view 的逆）
            material.SetMatrix("_InverseViewMatrix", cam.cameraToWorldMatrix);
            // ==========================================================================
            // Blit：用material把cameratarget写到temptexture中，cmd作为一个命令收集器收集这次指令
            // ==========================================================================
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
