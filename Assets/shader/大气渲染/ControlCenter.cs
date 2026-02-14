using System.Collections;
using System.Collections.Generic;
using System.IO;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class ControlCenter : MonoBehaviour
{
    [Header("保存天空盒设置")]
    public string saveFileName = "SavedSkybox";
    public bool saveAsHDR = true;
    public int saveWidth = 1024;
    public int saveHeight = 512;

    [Header("透射率采样表预计算")]
    [SerializeField] private ComputeShader transmittanceCS;
    [SerializeField] public RenderTexture transmittanceLutRT;

    [Header("天空盒材质生成")]
    public ComputeShader skyScatterCS;
    public RenderTexture skyScatterRT;
    [SerializeField] private Material skyboxMat;

    [Header("大气雾采样")]
    public ComputeShader aerialFogCS;
    [SerializeField] public RenderTexture aerialLutRT;
    public Material aerialFogPostMat;

   
    [Header("场景基本信息")]
    public Camera cam;
    public Light directionalLight;
    [Header("光源调整")]
    [Range(0.01f, 23.99f)]
    public float dayTime = 10.0f;  //调整时间    
    public float SunLightIntensity = 31.4f;
    public Color SunLightColor = Color.white;//可选
    //可选
    public float MoonIntensity = 2.4f;
    public Color NightColor = Color.blue;//可选

    [Range(0.0f, 1.0f)]
    public float G_mieAnisotropy = 0.8f;//各项异性参数
    [Header("日月纹理设置")]
    public Texture2D moonTexture;    
    public float SunDiskAngle = 9.0f;
    public float MoonDiskAngle = 9.0f;
    //全局使用静态参数
   
    //地球基础信息
    static private float SeaLevel = 0.0f;
    static private float planetRadius = 6360000.0f;
    static private float atmosphereHeight = 80000.0f;

    //瑞利、米氏散射基本参数
    static private Vector3 rayleighScattering = new Vector3(5.8e-6f, 13.5e-6f, 33.1e-6f);
    static private Vector3 mieScattering = new Vector3(2e-5f, 2e-5f, 2e-5f);
    static private float rayleighHeight = 8500f;
    static private float mieHeight = 1200f;

    //臭氧层基本参数
    static private float ozoneCenter = 25000.0f;
    static private float ozoneWidth = 15000.0f;
    
    //RT基本尺寸
    static private int width = 256;
    static private int height = 128;


    //计算大气雾 推荐参数（可调）
    //计算雾最远距离
    static private float aerialDistance = 10000.0f;
    private static int voxelW = 128;    // 方向 u 分辨率
    private static int voxelH = 64;     // 方向 v 分辨率
    private static int voxelD = 32;     // distance slices（深度分辨率）
    private int outW = voxelW * voxelD; //输出2D纹理时采用width
    private int outH = voxelH;

    //全局使用参数
    private int kernel;
    private int kernel_aerialPers;

    private Vector3 sunDir;
    private Vector3 eyePos;

    //需要监测变化的参数：更新RT，避免逐帧调用
    private Vector3 lastSunDir;
    private Vector3 lastEyePos;
    private float lastDayTime;   
    private bool isDirty = true;

    //获取RendererFeature部分
    [SerializeField]
    private UniversalRendererData rendererData;
    private AerialFogRendererFeature aerialFogFeature;

    void OnValidate()
    {
        isDirty = true;
        FindFeature();
    }


    // Start is called before the first frame update
    void Start()
    {
        Func_ComputeTransmittanceLut();
    }

    // Update is called once per frame
    void Update()
    {
        //逐帧更新太阳角度
        Vector3 sunRot = new Vector3((dayTime - 6.0f) * 15.0f, directionalLight.transform.rotation.y, directionalLight.transform.rotation.z);
        directionalLight.transform.rotation = Quaternion.Euler(sunRot);
        if (dayTime >= 0f && dayTime < 6f)
        {
            // 夜晚 -> dawn
            float t = dayTime / 6f; // 0-1                                    
        }
        else if (dayTime >= 6f && dayTime < 12f)
        {
            // dawn -> day
            float t = (dayTime - 6f) / 6f; // 0-1                                           
        }
        else if (dayTime >= 12f && dayTime < 18f)
        {
            float t = (dayTime - 12f) / 6f; // 0-1                                           
        }

        else // 18 -> 24
        {
            // day -> dawn/night
            float t = (dayTime - 18f) / 6f; // 0-1            
        }

        directionalLight.color = SunLightColor;
        sunDir = -directionalLight.transform.forward;
        eyePos = new Vector3(0f, planetRadius + cam.transform.position.y, 0f);//在当前坐标基础上增加地球半径

        bool changed = false;
        if (sunDir != lastSunDir) changed = true;
        if (eyePos != lastEyePos) changed = true;
        if (!Mathf.Approximately(dayTime, lastDayTime)) changed = true;
       
        if (changed || isDirty)
        {
            Func_ComputeSkyScatterRT();
            Func_ComputeAerialLutRT();

            // 更新上次值
            lastSunDir = sunDir;
            lastEyePos = eyePos;
            lastDayTime = dayTime;
            isDirty = false;
        }
    }
    public void Func_ComputeTransmittanceLut()
    {
        //预计算部分
        StartCoroutine(ComputeTransmittanceLutCoroutine());
    }
    private IEnumerator ComputeTransmittanceLutCoroutine()
    {
        #region 透射率采样表预计算
        transmittanceLutRT = new RenderTexture(width * 2, height, 0, RenderTextureFormat.ARGBFloat);
        transmittanceLutRT.enableRandomWrite = true;
        transmittanceLutRT.Create();

        int kernel_Post = transmittanceCS.FindKernel("CSTransmittanceLut");

        transmittanceCS.SetTexture(kernel_Post, "_TransmittanceLut", transmittanceLutRT);
        transmittanceCS.Dispatch(kernel_Post, width / 4, height / 8, 1);
        #endregion 透射率采样表预计算
        Shader.SetGlobalTexture("_transmittanceLut", transmittanceLutRT);
        //保存透射率采样表
        SaveSpecificRT(transmittanceLutRT, $"{saveFileName}_TransmittanceLUT");
        yield return null;
    }

    public void Func_ComputeSkyScatterRT()
    {
        StartCoroutine(ComputeSkyScatterRTCoroutine());
    }
    private IEnumerator ComputeSkyScatterRTCoroutine()
    {
        #region 天空盒计算
        skyScatterRT = new RenderTexture(width, height, 0, RenderTextureFormat.ARGBHalf);
        skyScatterRT.enableRandomWrite = true;
        skyScatterRT.Create();
        kernel = skyScatterCS.FindKernel("CSMain");
        skyScatterCS.SetTexture(kernel, "Result", skyScatterRT);

        skyScatterCS.SetVector("eyePos", eyePos);
        skyScatterCS.SetVector("SunDir", sunDir);
        skyScatterCS.SetVector("sunLuminance", SunLightIntensity * SunLightColor);
        skyScatterCS.SetVector("_GradientNight", MoonIntensity * NightColor);

        skyScatterCS.SetTexture(kernel, "_transmittanceLut", transmittanceLutRT);
        //skyScatterCS.SetTexture(kernel,"_MultiScatteringLut", multiScatLut);

        skyScatterCS.SetFloat("PlanetRadius", planetRadius);
        skyScatterCS.SetFloat("AtmosphereHeight", atmosphereHeight);
        skyScatterCS.SetFloat("RayleighScatteringScalarHeight", rayleighHeight);
        skyScatterCS.SetFloat("MieScatteringScalarHeight", mieHeight);
        skyScatterCS.SetFloat("MieAnisotropy", G_mieAnisotropy);
        skyScatterCS.SetFloat("OzoneLevelCenterHeight", ozoneCenter);
        skyScatterCS.SetFloat("OzoneLevelWidth", ozoneWidth);
       
        //Dispatch
        skyScatterCS.Dispatch(kernel, skyScatterRT.width / 8, skyScatterRT.height / 8, 1);
        #endregion

        #region 天空盒材质设置
        RenderSettings.skybox.SetTexture("_SkyScatterTex", skyScatterRT);
        skyboxMat.SetTexture("_SkyScatterTex", skyScatterRT);
        skyboxMat.SetVector("_LightDir", sunDir);
        skyboxMat.SetVector("_EyePos", eyePos);
        skyboxMat.SetVector("_MoonDir", -sunDir);

        skyboxMat.SetFloat("_SunDiskAngle", SunDiskAngle);
        skyboxMat.SetFloat("_PlanetRadius", planetRadius);
        skyboxMat.SetFloat("_AtmosphereHeight", atmosphereHeight);
        skyboxMat.SetVector("_SunLuminance", SunLightIntensity * SunLightColor);
        skyboxMat.SetVector("_MoonLuminance", SunLightIntensity * SunLightColor * 0.75f);
        skyboxMat.SetFloat("_MoonDiskAngle", MoonDiskAngle);
        skyboxMat.SetTexture("_MoonTex", moonTexture);
        skyboxMat.SetTexture("_transmittanceLut", transmittanceLutRT);
        #endregion
        yield return null;
    }
    public void Func_ComputeAerialLutRT()
    {
        StartCoroutine(ComputeAerialLutRTCoroutine());
    }
    private IEnumerator ComputeAerialLutRTCoroutine()
    {
        #region 大气雾采样计算
        aerialLutRT = new RenderTexture(outW, outH, 0, RenderTextureFormat.ARGBFloat);
        aerialLutRT.enableRandomWrite = true;
        aerialLutRT.useMipMap = false;
        aerialLutRT.Create();

        kernel_aerialPers = aerialFogCS.FindKernel("CSFogMain");

        // 计算逆视图投影矩阵（注意 GPU 投影矩阵修正）
        // 1. GPU 修正后的投影矩阵（必须用这个！）
        Matrix4x4 projGPU = GL.GetGPUProjectionMatrix(cam.projectionMatrix, false);

        // 2. 视图矩阵（世界 → 相机）
        Matrix4x4 view = cam.worldToCameraMatrix;

        // 3. 视图投影矩阵
        Matrix4x4 vp = projGPU * view;

        // 4. 逆视图投影矩阵（用于重建方向/位置）
        Matrix4x4 invVP = vp.inverse;

        // 5. 逆视图矩阵（只旋转部分，用于方向转换）
        Matrix4x4 invView = view.inverse;

        aerialFogCS.SetInt("WIDTH", outW);
        aerialFogCS.SetInt("HEIGHT", outH);
        aerialFogCS.SetInt("VOXEL_W", voxelW);
        aerialFogCS.SetInt("VOXEL_H", voxelH);
        aerialFogCS.SetInt("VOXEL_D", voxelD);
        aerialFogCS.SetFloat("_AerialPerspectiveDistance", aerialDistance);
        aerialFogCS.SetMatrix("_InvViewProjMatrix", invVP);
        aerialFogCS.SetMatrix("_InvProjMatrix", projGPU.inverse);     // 逆投影矩阵
        aerialFogCS.SetMatrix("_InvViewMatrix", invView);
        // other shared params (eyePos, SunDir, sunLuminance, PlanetRadius, AtmosphereHeight)
        aerialFogCS.SetVector("eyePos", eyePos);
        aerialFogCS.SetVector("SunDir", sunDir);
        aerialFogCS.SetVector("sunLuminance", new Vector4(SunLightColor.r * SunLightIntensity, SunLightColor.g * SunLightIntensity, SunLightColor.b * SunLightIntensity, 0));
        aerialFogCS.SetFloat("PlanetRadius", planetRadius);
        aerialFogCS.SetFloat("AtmosphereHeight", atmosphereHeight);

        aerialFogCS.SetFloat("RayleighScatteringScalarHeight", rayleighHeight);
        aerialFogCS.SetFloat("MieScatteringScalarHeight", mieHeight);
        aerialFogCS.SetFloat("MieAnisotropy", G_mieAnisotropy);
        aerialFogCS.SetFloat("OzoneLevelCenterHeight", ozoneCenter);
        aerialFogCS.SetFloat("OzoneLevelWidth", ozoneWidth);



        // 如果你的 transmittanceLut 是 RenderTexture 或 Texture2D:
        aerialFogCS.SetTexture(kernel_aerialPers, "_transmittanceLut", transmittanceLutRT);

        // 设置输出 UAV
        aerialFogCS.SetTexture(kernel_aerialPers, "Result", aerialLutRT);

        //aerialPersRT = aerialLut;

        // Dispatch（分组）
        int threadX = Mathf.CeilToInt((float)outW / 8.0f);
        int threadY = Mathf.CeilToInt((float)outH / 8.0f);
        aerialFogCS.Dispatch(kernel, threadX, threadY, 1);
        #endregion

        //aerialFogPostMat.SetTexture("_skyViewLut", skyScatterRT);
        //aerialFogPostMat.SetTexture("_aerialPerspectiveLut", aerialLutRT);
        //aerialFogPostMat.SetVector("_AerialPerspectiveVoxelSize", new Vector4(voxelW, voxelH, voxelD, 0));
        //aerialFogPostMat.SetTexture("_transmittanceLut", transmittanceLutRT);
        //aerialFogPostMat.SetFloat("_AerialPerspectiveDistance", aerialDistance);

        RTHandle skyRTH = RTtoRTHandler(skyScatterRT);
        RTHandle aerialRTH = RTtoRTHandler(aerialLutRT);
        RTHandle transmittanceRTH = RTtoRTHandler(transmittanceLutRT);

        aerialFogFeature.UpdateDynamicTextures(
           skyRTH, aerialRTH, transmittanceRTH, new Vector4(voxelW, voxelH, voxelD, 0), aerialDistance);
        yield return null;
    }
    private void FindFeature()
    {
        if (rendererData == null) return;

        foreach (var feature in rendererData.rendererFeatures)
        {
            if (feature is AerialFogRendererFeature vf)
            {
                aerialFogFeature = vf;
                return;
            }
        }

        Debug.LogWarning("在 RendererData 中找不到 VolumeFogRendererFeature", this);
    }

    #region 文件保存部分
    /// <summary>
    /// 将rendertexture转换为RTHandle格式，方便scritablerenderfeature传参
    /// </summary>
    /// <returns></returns>
    public RTHandle RTtoRTHandler(RenderTexture renderTexture)
    {
        if (renderTexture == null)
        {
            Debug.LogError("RenderTexture 未初始化");
            return null;
        }

        return RTHandles.Alloc(renderTexture);
    }

   




    public void SaveSkyboxTexture()
    {
        StartCoroutine(SaveSkyboxCoroutine());
    }

    private IEnumerator SaveSkyboxCoroutine()
    {
        yield return null;

        // 创建临时RenderTexture用于保存
        RenderTexture tempRT = new RenderTexture(saveWidth, saveHeight, 0,
            saveAsHDR ? RenderTextureFormat.ARGBHalf : RenderTextureFormat.ARGB32);
        tempRT.Create();

        // 使用一个临时相机来渲染天空盒
        Camera tempCam = new GameObject("TempSkyboxCamera").AddComponent<Camera>();
        tempCam.clearFlags = CameraClearFlags.Skybox;
        tempCam.targetTexture = tempRT;

        // 渲染一帧
        tempCam.Render();

        // 转换为Texture2D
        RenderTexture.active = tempRT;
        Texture2D tex = new Texture2D(saveWidth, saveHeight,
            saveAsHDR ? TextureFormat.RGBAHalf : TextureFormat.RGBA32, false);
        tex.ReadPixels(new Rect(0, 0, saveWidth, saveHeight), 0, 0);
        tex.Apply();
        RenderTexture.active = null;

        // 保存为文件
        byte[] bytes;
        string extension;

        if (saveAsHDR)
        {
            bytes = tex.EncodeToEXR();
            extension = "exr";
        }
        else
        {
            bytes = tex.EncodeToPNG();
            extension = "png";
        }

        string directoryPath = Path.Combine(Application.dataPath, "SavedSkyboxes");
        if (!Directory.Exists(directoryPath))
        {
            Directory.CreateDirectory(directoryPath);
        }

        string filePath = Path.Combine(directoryPath, $"{saveFileName}.{extension}");
        File.WriteAllBytes(filePath, bytes);

        Debug.Log($"天空盒已保存到: {filePath}");

        // 清理
        DestroyImmediate(tempCam.gameObject);
        DestroyImmediate(tex);
        tempRT.Release();

#if UNITY_EDITOR
        UnityEditor.AssetDatabase.Refresh();
#endif
    }

    // 保存特定的RenderTexture
    public void SaveSpecificRT(RenderTexture rt, string name)
    {
        if (rt == null)
        {
            Debug.LogError("RenderTexture为空！");
            return;
        }

        StartCoroutine(SaveRTCoroutine(rt, name));
    }

    private IEnumerator SaveRTCoroutine(RenderTexture rt, string name)
    {
        yield return null;

        RenderTexture.active = rt;
        Texture2D tex = new Texture2D(rt.width, rt.height,
            saveAsHDR ? TextureFormat.RGBAHalf : TextureFormat.RGBA32, false);
        tex.ReadPixels(new Rect(0, 0, rt.width, rt.height), 0, 0);
        tex.Apply();
        RenderTexture.active = null;

        byte[] bytes;
        string extension = saveAsHDR ? "exr" : "png";
        bytes = saveAsHDR
                ? tex.EncodeToEXR(Texture2D.EXRFlags.OutputAsFloat | Texture2D.EXRFlags.None)  // 明確指定 32-bit float
                : tex.EncodeToPNG();

        string directoryPath = Path.Combine(Application.dataPath, "SavedSkyboxes");
        if (!Directory.Exists(directoryPath))
        {
            Directory.CreateDirectory(directoryPath);
        }

        string filePath = Path.Combine(directoryPath, $"{name}.{extension}");
        File.WriteAllBytes(filePath, bytes);

        Debug.Log($"RenderTexture已保存到: {filePath}");

        DestroyImmediate(tex);

#if UNITY_EDITOR
        UnityEditor.AssetDatabase.Refresh();
#endif
    }
    public void Func_LoadPrecomputeTex(string name, int expectedWidth, int expectedHeight,
    System.Action<RenderTexture> onLoaded)
    {
        //预计算部分
        Debug.Log("进入预计算部分");
        StartCoroutine(LoadPrecomputeTexCoroutine(name, expectedWidth, expectedHeight, onLoaded));
    }

    private IEnumerator LoadPrecomputeTexCoroutine(string name, int expectedWidth, int expectedHeight,
    System.Action<RenderTexture> onLoaded)
    {
        yield return new WaitForEndOfFrame();   // 可选：确保在渲染帧后执行

        RenderTexture rt = LoadSavedRenderTexture(name, expectedWidth, expectedHeight);
        //保存采样表


        onLoaded?.Invoke(rt);
    }

    /// <summary>
    /// 从 SavedSkyboxes 文件夹加载指定的 RenderTexture
    /// 支持 .exr (HDR) 和 .png 两种格式
    /// </summary>
    /// <param name="name">文件名（不含扩展名，例如 "transmittance"）</param>
    /// <param name="width">目标 RenderTexture 宽度</param>
    /// <param name="height">目标 RenderTexture 高度</param>
    /// <param name="format">目标 RenderTexture 格式（建议与保存时一致）</param>
    /// <returns>加载成功的 RenderTexture，或 null（失败）</returns>
    public RenderTexture LoadSavedRenderTexture(string name, int width, int height, RenderTextureFormat format = RenderTextureFormat.ARGBFloat)
    {
        string directoryPath = Path.Combine(Application.dataPath, "SavedSkyboxes");
        string exrPath = Path.Combine(directoryPath, $"{name}.exr");
        string pngPath = Path.Combine(directoryPath, $"{name}.png");

        string filePath = null;
        TextureFormat texFormat = TextureFormat.RGBA32;

        if (File.Exists(exrPath))
        {
            filePath = exrPath;
            texFormat = TextureFormat.RGBAFloat;   // 或 RGBAFloat，看你需求
            Debug.Log("存在exr文件");
        }
        else if (File.Exists(pngPath))
        {
            filePath = pngPath;
            texFormat = TextureFormat.RGBA32;
            Debug.Log("存在png文件");
        }
        else
        {
            Debug.LogWarning($"找不到文件：{name}.exr 或 {name}.png 在 {directoryPath}");
            return null;
        }

        try
        {
            byte[] bytes = File.ReadAllBytes(filePath);

            Texture2D tex = new Texture2D(2, 2);
            //if (!ImageConversion.LoadImage(tex, bytes, false))
            //{
            //    Debug.LogError($"加载图像失败：{filePath}");
            //    Destroy(tex);
            //    return null;
            //}

            //// 尺寸校验（强烈建议）
            //if (tex.width != width || tex.height != height)
            //{
            //    Debug.LogError($"加载的纹理尺寸不匹配！文件：{tex.width}x{tex.height}，期望：{width}x{height}");
            //    Destroy(tex);
            //    return null;
            //}
            bool success = ImageConversion.LoadImage(tex, bytes, false);

            if (!success)
            {
                Debug.LogError($"LoadImage 失敗：{filePath}，大小 {bytes.Length} bytes");

                // 降級嘗試（某些舊檔案可能是 half）
                Destroy(tex);
                tex = new Texture2D(2, 2, TextureFormat.RGBAHalf, false);
                success = ImageConversion.LoadImage(tex, bytes, false);

                if (!success)
                {
                    Debug.LogError("即使降級 RGBAHalf 也失敗，很可能是檔案格式不被支援");
                    Destroy(tex);
                    return null;
                }
                else
                {
                    Debug.Log("降級到 RGBAHalf 成功載入（可能是 half-float EXR）");
                }
            }
            else
            {
                Debug.Log($"成功載入！格式：{tex.format}，尺寸：{tex.width}x{tex.height}");
            }

            // 尺寸檢查
            if (tex.width != width || tex.height != height)
            {
                Debug.LogError($"尺寸不符：檔案 {tex.width}x{tex.height}，期望 {width}x{height}");
                Destroy(tex);
                return null;
            }




            // 创建目标 RenderTexture
            RenderTexture rt = new RenderTexture(width, height, 0, format);
            rt.enableRandomWrite = true;           // 如果后续要用 compute shader
            rt.Create();

            // 把 Texture2D 数据拷贝到 RenderTexture
            Graphics.Blit(tex, rt);

            Debug.Log($"成功从 {filePath} 加载 RenderTexture ({width}x{height})");

            Destroy(tex);
            return rt;
        }
        catch (System.Exception e)
        {
            Debug.LogError($"加载 RenderTexture 异常：{e.Message}\n路径：{filePath}");
            return null;
        }
    }
    #endregion
}
