#ifndef TK_STANDARD_FORWARD_UPR
#define TK_STANDARD_FORWARD_URP



#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"
#include "../common/matrix.hlsl"

CBUFFER_START(UnityPerMaterial)
//主要的材质相关基础信息
    float _Cutoff;

    float4 _Color;
    Texture2D _MainTex;
    SamplerState sampler_MainTex;
    float4 _MainTex_ST;

    float _Roughness;
    Texture2D _RoughnessMap;
    SamplerState sampler_RoughnessMap;
    float4 _RoughnessMap_ST;

    float _Metallic;
    Texture2D _MetallicGlossMap;
    SamplerState sampler_MetallicGlossMap;
    float4 _MetallicGlossMap_ST;

    Texture2D _BumpMap;
    SamplerState sampler_BumpMap;
    float _BumpScale;
    float4 _BumpMap_ST;

    float4 _EmissionColor;
    Texture2D _EmissionMap;
    SamplerState sampler_EmissionMap;
    float4 _EmissionMap_ST;

    float _PallaxScale;
    Texture2D _PallaxMap;
    SamplerState sampler_PallaxMap;
    float4 _PallaxMap_ST;

    float _LightmapPower;

    float _SpecularOcclusionPower;
#if defined(_TK_DETAIL_ON)
    float _DetailMaskFactor;
    Texture2D _DetailMaskMap;
    float4 _DetailMaskMap_ST;

    float3 _DetailAlbedo;
    Texture2D _DetailAlbedoMap;
    float4 _DetailAlbedoMap_ST;

    float _DetailRoughness;
    Texture2D _DetailRoughnessMap;
    float4 _DetailRoughnessMap_ST;

    float _DetailMetallic;
    Texture2D _DetailMetallicMap;
    float4 _DetailMetallicMap_ST;

    float _DetalNormalMapScale;
    Texture2D _DetailNormalMap;
    float4 _DetailNormalMap_ST;
#endif

#if defined(_TK_THINFILM_ON)
    Texture2D _ThinFilmMaskMap;
    float4 _ThinFilmMaskMap_ST;

    float _ThinFilmMiddleIOR;
    float _ThinFilmMiddleThickness;
    float _ThinFilmMiddleThicknessMin;
    float _ThinFilmMiddleThicknessMax;

    Texture2D _ThinFilmMiddleThicknessMap;
    float4 _ThinFilmMiddleThicknessMap_ST;
#endif

#if defined(_TK_CLOTH_ON)
    float4 _ClothAlbedo1;
    float4 _ClothAlbedo2;
    float _ClothIOR1;
    float _ClothIOR2;
    float _ClothKd1;
    float _ClothKd2;
    float _ClothGammaV1;
    float _ClothGammaV2;
    float _ClothGammaS1;
    float _ClothGammaS2;
    float _ClothAlpha1;
    float _ClothAlpha2;
    float _ClothTangentOffset1;
    float _ClothTangentOffset2;
#endif

#if defined(_ADDLIGHTMAP1_ON)
    Texture2D _AddLightmap1;
    float _AddLightmap1_Power;
#endif
#if defined(_ADDLIGHTMAP2_ON)
    Texture2D _AddLightmap2;
    float _AddLightmap2_Power;
#endif
#if defined(_ADDLIGHTMAP3_ON)
    Texture2D _AddLightmap3;
    float _AddLightmap3_Power;
#endif

CBUFFER_END

#include "StandardForwardLightmap.hlsl"
#include "StandardForwardBSDF.hlsl"
#include "StandardMaterial.hlsl"
#include "../common/noise.hlsl"
#include "../common/matrix.hlsl"
#include "../common/color.hlsl"
struct Attributes
{
    float4 positionOS : POSITION;
    float3 normalOS : NORMAL;
    float4 tangentOS : TANGENT;
    float2 texcoord0 : TEXCOORD0;
    float2 texcoord1 : TEXCOORD1; //网格的第二组 UV（TEXCOORD1），最常见用于静态光照贴图。
    float2 texcoord2 : TEXCOORD2; //网格的第三组 UV（TEXCOORD2），Unity 在导入模型时会自动生成或使用模型自带的作为动态光照贴图 UV。urp不支持动态光照
    UNITY_VERTEX_INPUT_INSTANCE_ID
};

struct Varyings
{
    float4 positionCS : SV_POSITION;
    float2 uv : TEXCOORD0;
    float3 positionWS : TEXCOORD1;
    half3 normalWS : TEXCOORD2; // 世界空间法线（替代 worldNormal）
    half4 tangentWS : TEXCOORD3; // 世界空间切线（xyz + w 分量手性）
    float2 lightmapUV : TEXCOORD4;
    half4 fogFactorAndVertexLight : TEXCOORD5;
    // 阴影坐标（主光源阴影）
    float4 shadowCoord : TEXCOORD6;

    // 可选：屏幕空间 UV（用于屏幕特效）
    float2 screenPos : TEXCOORD7;

    // 可选：物体空间位置和法线（如果你需要）
    float3 positionOS : TEXCOORD8;
    half3 normalOS : TEXCOORD9;

    // 可选：第二组 UV（如你需要 uv2）
    float2 uv2 : TEXCOORD10;
    //URP 不支持动态光照贴图，全部统一用这个宏处理静态 Lightmap 或 SH:在没有lightmap的时候使用球谐光 
    //在同一个位置（从 TEXCOORD4 开始的几个插值寄存器）里，预留空间，根据情况自动放两种不同的东西
    //DECLARE_LIGHTMAP_OR_SH(lmUV, vertexSH, 4);
    //UNITY_VERTEX_OUTPUT_STEREO      // 单眼/双眼立体渲染（保留，完全兼容）
};

Varyings vert(Attributes IN)
{
    Varyings OUT;
    UNITY_SETUP_INSTANCE_ID(IN);
    UNITY_TRANSFER_INSTANCE_ID(IN,OUT);
    UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(IN);
    
    
    VertexPositionInputs pos = GetVertexPositionInputs(IN.positionOS.xyz);
    VertexNormalInputs norm = GetVertexNormalInputs(IN.normalOS);
    
    OUT.positionCS = pos.positionCS;               
    OUT.positionWS = pos.positionWS;
    OUT.normalWS = norm.normalWS;
    OUT.screenPos = pos.positionNDC.xy / pos.positionNDC.w;
    OUT.positionOS = IN.positionOS.xyz;
    OUT.normalOS = IN.normalOS;
    OUT.uv = IN.texcoord0;
    OUT.uv2 = IN.texcoord1;
    OUT.normalWS = TransformObjectToWorldNormal(IN.normalOS);
    OUT.tangentWS = half4(TransformObjectToWorldDir(IN.tangentOS.xyz), IN.tangentOS.w);
    OUT.shadowCoord = TransformWorldToShadowCoord(OUT.positionWS);
    OUT.fogFactorAndVertexLight = ComputeFogFactor(OUT.positionCS.z);
    // 假设你的模型有第二组UV（texcoord1）用来做光照贴图
    #ifdef LIGHTMAP_ON
    // 这里放“有光照贴图时才执行”的代码
    OUT.lightmapUV = IN.texcoord1.xy * unity_LightmapST.xy + unity_LightmapST.zw;
    #endif
    
    
    
    return OUT;
}

half4 frag(Varyings i) : SV_Target
{
    float3 shade_color = 0;
    float3 worldPos = i.positionWS;
    float3 normalWorld = normalize(i.normalWS);
    float3 viewDirection = normalize(_WorldSpaceCameraPos - i.positionWS);
    
    MappingInfoTK mapInfo; //存储信息结构体，在TakenokoMaterial中定义
    mapInfo.pixelId = int2(i.screenPos.xy * _ScreenParams.xy); //是 Unity 内置的全局 Shader 变量（float4 类型），定义在 UnityCG.cginc（Built-in）或 URP 的 Core.hlsl 中。
    mapInfo.worldPos = i.positionWS;
    mapInfo.worldNormal = normalWorld;
    mapInfo.worldTangent = i.tangentWS;
    mapInfo.worldBinormal = cross(normalWorld, i.tangentWS.xyz) * i.tangentWS.w;;
    mapInfo.viewDir = viewDirection;
    mapInfo.uv = i.uv;
    
    //主纹理通常为第一套uv
    //细节纹理通常是作为增加高频细节，独立控制 Tiling（平铺密度），不受主纹理影响。
    #if defined(_MAPPINGMODE_UV2)
            mapInfo.uv = i.uv;
    #endif

    mapInfo.detail_uv = i.uv;
    #if defined(_TK_DETAIL_MAPPINGMODE_UV2)
        mapInfo.detail_uv = i.uv2;
    #endif
    
    MaterialParameter matParam;
    float3 shadingNormal;
    SetMaterialParameterTK(matParam, mapInfo, shadingNormal);
    normalWorld = shadingNormal;//根据bump贴图得到的表面法线
    //clip(x) 函数的作用：
       // Unity / HLSL内置函数。
    //如果x < 0，
        //当前像素被完全丢弃（ 不写入帧缓冲，不参与后续渲染）。
    //如果x >= 0，
        //像素正常继续（ 可能参与深度测试、颜色写入等）。
    #ifdef _ALPHATEST_ON
        clip(matParam.alpha - _Cutoff);
    #endif
    
    // 在 frag 函数里（片元着色器）
    Light mainLight = GetMainLight();

    // 主光源方向（已经归一化好了）
    float3 lightDir = mainLight.direction;

    // 主光源颜色
    float3 lightColor = mainLight.color;
    
    // 距离衰减和阴影衰减（URP 已经帮你算好了！）
    half attenuation = mainLight.distanceAttenuation * mainLight.shadowAttenuation;
    
    SurfaceData surfaceData = (SurfaceData) 0;
    

    // 先填必要的 normalTS（InitializeInputData 需要它）
    surfaceData.normalTS = normalWorld; // 你的法线采样

    // 调用初始化（此时其他字段可以是垃圾值，没关系）
    TK_GIInput giInput;
    
    
    giInput.mainLight = mainLight;
    giInput.worldPos = i.positionWS;
    giInput.worldViewDir = viewDirection;
    giInput.atten = attenuation;
    
    //lightmap
    #if defined(LIGHTMAP_ON)
            giInput.lightmapUV = i.lightmapUV;
    #else
        giInput.lightmapUV = 0.0;
    #endif
    
    //球谐光照
    #if UNITY_SHOULD_SAMPLE_SH && !UNITY_SAMPLE_FULL_SH_PER_PIXEL
        giInput.ambient = 0.0; //Vertex SH
    #else
        giInput.ambient.rgb = 0.0;
    #endif
    
    //TODO: AO图采样
    surfaceData.occlusion = 1.0;
    // 在你的自定义 BSDF 计算函数中（或 Frag 中）
    //half perceptualRoughness = PerceptualSmoothnessToPerceptualRoughness(1.0 - matParam.roughness);
    float perceptualRoughness = matParam.roughness * (1.7 - 0.7 * matParam.roughness);


    half3 reflectVector = reflect(-viewDirection, i.normalWS);
// ↑ 注意：用 inputData.viewDirectionWS（已归一化），inputData.normalWS（已归一化）

// 核心一行：全部交给 URP 处理（包括 Blending、Box Projection、HDR、MIP 自动选择）
    half3 indirectSpecular = GlossyEnvironmentReflection(
    reflectVector,
    perceptualRoughness,
    surfaceData.occlusion   // AO 遮挡（通常从材质采样）
);
    
    giInput.indirectSpecular = indirectSpecular;
    
    float3 main_diffuse;
    float3 main_specular;
    #if !defined(_TK_CLOTH_ON)
       EvaluateLighting_TK(main_diffuse, main_specular, normalWorld, giInput, matParam);
    #else
        float cosTheta = max(lightDir, normalWorld);
        float3 u, v, n;
        n = float3(0, 1, 0);// orthonormalBasis(normalWorld, u, v);
        v = float3(1, 0, 0);
        u = float3(0, 0, 1);
        main_diffuse = ClothBSDF_TK(u, v, n,
        viewDirection, lightDir, cosTheta, matParam);
        main_specular = 0;
        // main_specular = 0;
        // main_diffuse = v;
    #endif

#ifdef LIGHTMAP_ON
        float3 lightmapDiffuse = 0;
        float3 lightmapSpecular = 0;
        sample_lightmap(lightmapDiffuse, lightmapSpecular, normalWorld, i.lightmapUV, viewDirection, matParam);
        lightmapDiffuse *= matParam.basecolor;

        lightmapDiffuse *= _LightmapPower;
        lightmapSpecular *= _LightmapPower;

        float specular_occulusion = 1.0f;

#ifdef _SPECULAR_OCCLUSION
            specular_occulusion = pow(saturate(colorToLuminance(lightmapDiffuse) * 2.0f), _SpecularOcclusionPower);
#endif
        
        shade_color = (lightmapDiffuse + main_diffuse) * (1.0f - matParam.metallic) + (main_specular + lightmapSpecular) * specular_occulusion;

#else
    float3 sh = SampleSH(float4(normalWorld, 1.0)) * matParam.basecolor;
    shade_color = (main_diffuse + sh) * (1.0f - matParam.metallic) + main_specular;
    #endif
    
    
     #if defined(_EMISSION)
        shade_color += matParam.emission;
    #endif

    #if defined(_ADDLIGHTMAP1_ON)
        float3 addLightMap1 = lightMapEvaluate(_AddLightmap1, i.lightmapUV.xy);
        shade_color += addLightMap1 * _AddLightmap1_Power * matParam.basecolor;
    #endif
    #if defined(_ADDLIGHTMAP2_ON)
        float3 addLightMap2 = lightMapEvaluate(_AddLightmap2, i.lightmapUV.xy);
        shade_color += addLightMap2 * _AddLightmap2_Power * matParam.basecolor;
    #endif
    #if defined(_ADDLIGHTMAP3_ON)
        float3 addLightMap3 = lightMapEvaluate(_AddLightmap3, i.lightmapUV.xy);
        shade_color += addLightMap3 * _AddLightmap3_Power * matParam.basecolor;
    #endif
    
    
    
    //Debug
    #if defined(_DEBUGMODE_NORMAL)
        shade_color = normalWorld * 0.5 + 0.5;
    #elif defined(_DEBUGMODE_BASECOLOR)
        shade_color = matParam.basecolor;
    #elif defined(_DEBUGMODE_UV1)
        shade_color = float3(i.uv, 0);
    #elif defined(_DEBUGMODE_UV2)
        shade_color = float3(i.uv2, 0);
    #endif
    
    
   
    
    return half4(shade_color, matParam.alpha);

                
}
#endif