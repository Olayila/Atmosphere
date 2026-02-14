Shader "Custom/PBR Template"
{
    Properties
    {
        //Menu FoldOut
        
        [Enum(Opaque, 0, Cutout, 1, Fade, 2, Transparent, 3)] _BlendMode ("Blend Mode", Float) = 0.0
        //Blend模式
        [HideInInspector] _SrcBlend ("__src", Float) = 1.0
        [HideInInspector] _DstBlend ("__dst", Float) = 0.0
        [HideInInspector] _ZWrite ("__zw", Float) = 1.0
        [HideInInspector] _Cull ("Cull", Float) = 2.0



        _MainCol ("漫反射颜色", Color) = (0.8, 0.6, 0.5, 1)
        _SpecCol ("高光颜色(RGB) 强度(A)", Color) = (1,1,1,0.8)
        _Rough   ("粗糙度", Range(0.02,1)) = 0.15
        
        _A ("A - 基础颜色 (底色)", Color) = (0.2, 0.0, 0.3, 1)     // 深紫色底色
        _B ("B - 变化幅度 (越大越亮/暗)", Color) = (0.5, 0.3, 0.6, 1)  // 控制明暗摆动强度
        _C ("C - 变化速度 (RGB 不同速度更炫)", Color) = (1.0, 1.3, 1.7, 0)  // 每个通道不同速度
        _D ("D - 初始相位 (颜色偏移)", Color) = (0.0, 0.33, 0.66, 0)       // 起始颜色偏移
        _Speed ("整体速度倍率", Float) = 1.0
    }

     //#define UNITY_SETUP_BRDF_INPUT MetallicSetup
     //该宏只在builtin管线中使用，控制surface shader为金属流，urp中直接在片元着色器中对surface直接定义，默认就是metallic
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }

        Pass
        {
            Tags { "LightMode"="UniversalForward" }
            Blend [_SrcBlend] [_DstBlend]
            ZWrite [_ZWrite]

            HLSLPROGRAM

            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_fog    
            // 基本必须的
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS                // 主光源阴影
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE        // 如果使用级联阴影
            #pragma multi_compile _ _ADDITIONAL_LIGHTS                 // 支持额外光源（强烈推荐开启）
            #pragma multi_compile _ _ADDITIONAL_LIGHT_SHADOWS          // 额外光源阴影

            // 根据功能可选
            #pragma multi_compile _ _SHADOWS_SOFT                     // 软阴影（PCF）
            #pragma multi_compile_fog                                 // 支持雾效
            #pragma multi_compile_instancing                           // GPU Instancing
            #pragma multi_compile _ DOTS_INSTANCING_ON                // 如果使用 DOTS/Hybrid Renderer

            // 如果有 Lightmap
            #pragma multi_compile _ LIGHTMAP_ON
            #pragma multi_compile _ DIRLIGHTMAP_COMBINED

            // 如果需要 Forward+（高配平台更多光源支持）
            #pragma multi_compile _ _CLUSTER_LIGHT_LOOP


            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"
            #include "matrix.hlsl"

            CBUFFER_START(UnityPerMaterial)
                half4 _MainCol;
                half4 _SpecCol;
                half _Rough;
                float4 _A;
                float4 _B;
                float4 _C;
                float4 _D;
                float _Speed;
                float _EmissionStrength;
            CBUFFER_END

            struct Attributes {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float3 normalWS : TEXCOORD1;
            };

            struct Varyings {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                float3 normalWS : TEXCOORD1;
                float fogFactor : TEXCOORD2;
            };

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                VertexPositionInputs pos = GetVertexPositionInputs(IN.positionOS.xyz);
                VertexNormalInputs norm = GetVertexNormalInputs(IN.normalOS);
                OUT.positionCS = pos.positionCS;
               
                OUT.positionWS = pos.positionWS;
                OUT.normalWS = norm.normalWS;
                OUT.fogFactor = ComputeFogFactor(pos.positionCS.z);
                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                // half3 N = normalize(IN.normalWS);
                // half3 V = normalize(GetWorldSpaceViewDir(IN.positionWS));
                // Light mainLight = GetMainLight();
                // half3 L = mainLight.direction;

                // half NdotL = max(dot(N, L), 0.001);
                // half3 H = normalize(V + L);
                // half VH = max(dot(V, H), 0.001);

                // half m2 = _Rough * _Rough + 1e-5;
                // half D = m2 / pow(dot(H,H)*(m2-1)+1, 2);
                // half F = lerp(0, 1, pow(1-VH, 5)) * _SpecCol.a + (1-_SpecCol.a);
                // half G = 1.0 / (VH * (NdotL + dot(N,V)) + 0.1);

                // half spec = D * F * G * 15.0;

                // half4 col = _MainCol * NdotL * half4(mainLight.color,1);
                // col.rgb += spec * _SpecCol.rgb * mainLight.color;

                // col.rgb = MixFog(col.rgb, IN.fogFactor);
                // 时间 t（随时间变化）
                float t = _Time.y * _Speed;
               
                // 调用 colorPalet 生成颜色
                float3 col = colorPalet(_A.rgb, _B.rgb, _C.rgb, _D.rgb, t);

                // 加强自发光效果（让颜色更亮）
                // col *= _EmissionStrength;

                //// 在片元着色器中手动填充
                //// URP 自动用 Metallic 工作流计算 BRDF（默认就是 Metallic）
                // SurfaceData surfaceData;
                // surfaceData.albedo = albedo.rgb;                    Base Color
                // surfaceData.metallic = metallic;                    金属度（0~1）
                // surfaceData.smoothness = smoothness;                光滑度
                // surfaceData.normalTS = normalTS;                    切线空间法线
                // surfaceData.emission = emission;
                // surfaceData.occlusion = ao;
                // surfaceData.alpha = alpha;

                



                return half4(col, 1.0);

                
            }
            ENDHLSL
        }
    }
}