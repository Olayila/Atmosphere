Shader "GZH/Skin"
{
    Properties
    {
        [Header(Textures)]
        _MainTex ("MainTexture", 2D) = "white" {}
        _MainNormalTex ("NormalTex", 2D) = "bump" {}
        _NormalIntensity("NormalIntensity",Range(0,1)) = 1.0
        _SubTex ("SubTex", 2D) = "white" {}        
        _lightintensity("LT", Float) = 1
       
        [Header(Skin Options)]
        _SmoothTex ("SmoothTex", 2D) = "white" {}
        _CurveTex ("CurveTex", 2D) = "white" {}
        _SSSLUT ("SSS LUT", 2D) = "white" {}
        _KelemenLUT ("Kelemen LUT", 2D) = "white" {}
        [KeywordEnum(OFF,ON)] SSS ("SSS Mode", Float) = 1
        [KeywordEnum(Const,Calu,Tex)] Curve("Use Curve Tex", Float) = 1
        _CurveFactor("Curve Factor", Range(0,5)) = 1

        [KeywordEnum(Off,BlinPhong,Kelemen)] Spec("Specular Mode",Float) = 1
        _SpecularScale("Specular Scale", Range(0,5)) = 1

    //RampShadow

        [Header(Ramp Shadow Options)]
        _RampTex ("Ramp Tex", 2D) = "white" {}
        [Toggle(_USE_RAMP_SHADOW)] _UseRampShadow("Use Ramp Shadow", Range(0,1)) = 1
        _ShadowRampWidth ("Shadow Ramp Width", Float) = 1
        _ShadowPosition("Shadow Position", Float) = 0.55
        _ShadowSoftness ("Shadow Softnes", Float) = 0.5
        [Toggle] _UseRampShadow2 ("Use Ramp Shadow 2", Range(0,1)) = 1
        [Toggle] _UseRampShadow3 ("Use Ramp Shadow 3", Range(0,1)) = 1
        [Toggle] _UseRampShadow4 ("Use Ramp Shadow 4", Range(0,1)) = 1
        [Toggle] _UseRampShadow5 ("Use Ramp Shadow 5", Range(0,1)) = 1
        
        _DayOrNight ("Day or Night", Range(0,1)) = 0
    //边缘光
        [Header(Rim Highlight color)] 
        _RimLeftColor ("Left Rim Color", Color) = (0,0,1,1)  
        _RimRightColor ("Right Rim Color", Color) = (1,0,0,1) 
        _RimPower ("Rim Power", Range(0.1, 10)) = 2.0  
        _RimIntensity ("Rim Intensity", Range(0, 5)) = 1.0

    //高光
        _HighlightColor ("Highlight Color", Color) = (1,1,1,1)  
        
        _HighlightIntensity ("Highlight Intensity", Range(0, 5)) = 1.0
        _MetallicPower ("Highlight Power", Range(0.1, 20)) = 5.0 
        _MetallicIntensity ("Metallic Intensity", Range(0, 20)) = 1.0

        

        [KeywordEnum(None,Curve,Specular)] Debug("Debug", Float) = 0
    }

    SubShader
    {
        Tags
        {
            "RenderPipeline"="UniversalPipeline"
            "RenderType"="Opaque"
        }

        Pass
        {
            Name "ForwardLit"
            Tags{ "LightMode"="UniversalForward" }

            Stencil
            {
                Ref 1
                Comp Always
                Pass Replace
            }

            HLSLPROGRAM
            #pragma target 3.0
            
            #pragma vertex vert
            #pragma fragment frag

            #pragma multi_compile SSS_OFF SSS_ON
            #pragma multi_compile CURVE_CONST CURVE_CALU CURVE_TEX
            #pragma multi_compile SPEC_OFF SPEC_BLINPHONG SPEC_KELEMEN
            #pragma multi_compile DEBUG_NONE DEBUG_CURVE DEBUG_SPECULAR


            #pragma multi_compile _MAIN_LIGHT_SHADOWS // 主光源阴影
            #pragma multi_compile _MAIN_LIGHT_SHADOWS_CASCADE // 主光源阴影级联
            #pragma multi_compile _MAIN_LIGHT_SHADOWS_SCREEN // 主光源阴影屏幕空间

            #pragma multi_compile_fragment _LIGHT_LAYERS // 光照层
            #pragma multi_compile_fragment _LIGHT_COOKIES // 光照饼干
            #pragma multi_compile_fragment _SCREEN_SPACE_OCCLUSION // 屏幕空间遮挡
            #pragma multi_compile_fragment _ADDITIONAL_LIGHT_SHADOWS // 额外光源阴影
            #pragma multi_compile_fragment _SHADOWS_SOFT // 阴影软化
            #pragma multi_compile_fragment _REFLECTION_PROBE_BLENDING // 反射探针混合
            //#pragma multi_compile_fragment _REFLECTION_PROBE_BOX_PROJECTION // 反射探针盒投影
            //#pragma shader_feature_local _USE_LIGHTMAP_AO 
            #pragma  shader_feature_local _USE_RAMP_SHADOW

            //--------------------------------
            // URP Includes
            //--------------------------------
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            //--------------------------------
            // Textures
            //--------------------------------
            TEXTURE2D(_MainTex);         SAMPLER(sampler_MainTex);
            TEXTURE2D(_MainNormalTex);   SAMPLER(sampler_MainNormalTex);
            TEXTURE2D(_SubTex);   SAMPLER(sampler_SubTex);
            TEXTURE2D(_SmoothTex);       SAMPLER(sampler_SmoothTex);
            TEXTURE2D(_CurveTex);        SAMPLER(sampler_CurveTex);
            TEXTURE2D(_SSSLUT);          SAMPLER(sampler_SSSLUT);
            TEXTURE2D(_KelemenLUT);      SAMPLER(sampler_KelemenLUT);

           CBUFFER_START(UnityPerMaterial)

                //float4 _BaseMap_ST;
                //float4 _BaseColor;
                float4 _RimLeftColor;
                float4 _RimRightColor;

                float4 _SpotShadowColor;
                float _lightintensity;

                float _RimPower;
                float _RimIntensity;
                float4 _HighlightColor;
                float _MetallicPower;
                float _HighlightIntensity;
                float _MetallicIntensity;
                float _MainLightIntensity;
                float4 _MainTex_ST;
                float4 _MainNormalTex_ST;
                float _CurveFactor;
                float _SpecularScale;
                float _NormalIntensity;

                sampler2D _RampTex;
                float _ShadowPosition;
                float _ShadowRampWidth;
                float _ShadowSoftness;
                float _UseRampShadow2;
                float _UseRampShadow3;
                float _UseRampShadow4;
                float _UseRampShadow5;
                float _DayOrNight;



                float3 _BoundsMin;     // 等价于 float3(minX, minY, minZ)
                float3 _BoundsMax;     // 等价于 float3(maxX, maxY, maxZ)
                float3 _BoundsCenter;  // 包围盒中心 = (_BoundsMin + _BoundsMax) * 0.5
                float3 _BoundsExtents; // 半尺寸 = (_BoundsMax - _BoundsMin) * 0.5

            CBUFFER_END

            //--------------------------------
            // Structs
            //--------------------------------
            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float4 tangentOS  : TANGENT;
                float2 uv         : TEXCOORD0;
            };

            struct Varyings
            {
                float4 objectPos   :  TEXCOORD6;
                float4 positionHCS : SV_POSITION;
                float2 uv0         : TEXCOORD0;
                float2 uv1         : TEXCOORD1;

                float3 worldPos    : TEXCOORD2;
                float3 T           : TEXCOORD3;
                float3 B           : TEXCOORD4;
                float3 N           : TEXCOORD5;
            };

            
            //--------------------------------
            // Ramp Function
            //--------------------------------
            float RampShadowID(float input, float useShadow2, float useShadow3, float useShadow4, float useShadow5, 
            float shadowValue1, float shadowValue2, float shadowValue3, float shadowValue4, float shadowValue5)
            {
                // 根据input值将模型分为5个区域
                float v1 = step(0.6, input) * step(input, 0.8); // 0.6-0.8区域
                float v2 = step(0.4, input) * step(input, 0.6); // 0.4-0.6区域
                float v3 = step(0.2, input) * step(input, 0.4); // 0.2-0.4区域
                float v4 = step(input, 0.2);                    // 0-0.2区域

                // 根据开关控制是否使用不同材质的值
                float blend12 = lerp(shadowValue1, shadowValue2, useShadow2);
                float blend15 = lerp(shadowValue1, shadowValue5, useShadow5);
                float blend13 = lerp(shadowValue1, shadowValue3, useShadow3);
                float blend14 = lerp(shadowValue1, shadowValue4, useShadow4);

                // 根据区域选择对应的材质值
                float result = blend12;                // 默认使用材质1或2
                result = lerp(result, blend15, v1);    // 0.6-0.8区域使用材质5
                result = lerp(result, blend13, v2);    // 0.4-0.6区域使用材质3
                result = lerp(result, blend14, v3);    // 0.2-0.4区域使用材质4
                result = lerp(result, shadowValue1, v4); // 0-0.2区域使用材质1

                return result;
            }



            //--------------------------------
            // Vertex
            //--------------------------------
            Varyings vert(Attributes v)
            {
                Varyings o;

                o.objectPos = v.positionOS;
                o.positionHCS = TransformObjectToHClip(v.positionOS);

                o.uv0 = TRANSFORM_TEX(v.uv, _MainTex);
                o.uv1 = TRANSFORM_TEX(v.uv, _MainNormalTex);

                float3 worldPos = TransformObjectToWorld(v.positionOS.xyz);
                float3 worldNormal = TransformObjectToWorldNormal(v.normalOS);
                float3 worldTangent = TransformObjectToWorldDir(v.tangentOS.xyz);
                float3 worldBitangent = cross(worldNormal, worldTangent) * v.tangentOS.w;

                o.worldPos = worldPos;
                o.T = worldTangent;
                o.B = worldBitangent;
                o.N = worldNormal;

                return o;
            }

            //--------------------------------
            // Fragment
            //--------------------------------
            half4 frag(Varyings i) : SV_Target
            {
                // Light
                Light light = GetMainLight();
                float3 lightDir = normalize(light.direction);
                float3 viewDir = normalize(_WorldSpaceCameraPos - i.worldPos);                
               float height01 = saturate((i.objectPos.y - _BoundsCenter.y) / _BoundsExtents.y + 0.5);

                //------------------------------------
                // Normal mapping
                //------------------------------------
                
                float3 tnormal = UnpackNormal(SAMPLE_TEXTURE2D(_MainNormalTex, sampler_MainNormalTex, i.uv1));
                float3 worldNormal = normalize(
                    i.T * tnormal.x +
                    i.B * tnormal.y +
                    i.N * tnormal.z
                );
                worldNormal = normalize(lerp(i.N, worldNormal, _NormalIntensity));
                //------------------------------------
                // Curve
                //------------------------------------
                float cuv = 1;

                #if defined(CURVE_CONST)
                    cuv = _CurveFactor;
                #elif defined(CURVE_TEX)
                    cuv = SAMPLE_TEXTURE2D(_CurveTex, sampler_CurveTex, i.uv1).r;
                #else
                    float3 rawNormal = normalize(i.N);
                    cuv = saturate(_CurveFactor * 0.01 * (length(fwidth(rawNormal)) / length(fwidth(i.worldPos))));
                #endif

                //------------------------------------
                // Diffuse with SSS
                //------------------------------------
                float NoL = saturate(dot(worldNormal, lightDir));

                float3 diffuse;
                #if defined(SSS_OFF)
                    diffuse = NoL.xxx;
                #else
                    float2 lutUV = float2(NoL * 0.5 + 0.5, 0.75);
                    diffuse = SAMPLE_TEXTURE2D(_SSSLUT, sampler_SSSLUT, lutUV).rgb;
                #endif

                //------------------------------------
                // Specular
                //------------------------------------
                float3 h = normalize(lightDir + viewDir);
                float NoH = saturate(dot(worldNormal, h));

                float smooth = SAMPLE_TEXTURE2D(_SmoothTex, sampler_SmoothTex, i.uv1).r;

                float3 specular = 0;

                #if defined(SPEC_BLINPHONG)
                    specular = pow(NoH, 10.0) * smooth * _SpecularScale;
                #elif defined(SPEC_KELEMEN)
                    float PH = pow(2.0 * SAMPLE_TEXTURE2D(_KelemenLUT, sampler_KelemenLUT, float2(NoH, smooth)), 10.0);
                    float F = 0.028;
                    specular = max(PH * F / dot(h, h), 0) * _SpecularScale;
                #endif
               
                float3 albedo = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv0).rgb;
                float4 lightmap = SAMPLE_TEXTURE2D(_SubTex, sampler_SubTex, i.uv0);
                float skinUV = lightmap.r;

                //------------------------------------------------------------------------
                // Rim color
                //------------------------------------------------------------------------

                float rimLeft = 0;
                float rimRight = 0;
                float rimMid = 0;
                float edgebias = 0.01;
                float rimBase = 1.0 - saturate(dot( worldNormal, viewDir));
                rimBase = pow(rimBase, _RimPower);
                if(worldNormal.x <0+edgebias)
                {
                    rimLeft = rimBase * _RimIntensity;
                }

                else if (worldNormal.x > 0 - edgebias) 
                {
                    rimRight = rimBase * _RimIntensity;
                }

                else
                {
                     rimMid = rimBase * _RimIntensity;
                }

                float colorRamp = (worldNormal.x + edgebias)/(edgebias*2);
                float fresnel = 1.0 - saturate(dot(worldNormal, viewDir));  
               half highlightLambert = smoothstep(0.8, 0.9, dot(worldNormal, lightDir)) * lightmap.g;
               float glowlight =lightmap.b *  saturate(dot(worldNormal, viewDir)); 
                glowlight = pow(glowlight, _MetallicPower) *_MetallicIntensity;  
               highlightLambert += glowlight;
               
                //float highlight = fresnel * highlightLambert; 
                //highlight = pow(highlight, _HighlightPower) * _HighlightIntensity;  
                
                // 叠加所有效果
                float3 finalRim = (rimLeft * _RimLeftColor.rgb) + (rimRight * _RimRightColor.rgb) + ( highlightLambert * _HighlightIntensity * albedo.rgb) + rimMid*lerp(_RimRightColor.rgb, _HighlightColor.rgb,colorRamp);

               albedo.rgb += finalRim;

               

               //------------------------------------------------------------------------
               // BodyShadow Ramp color
               //------------------------------------------------------------------------

               half halflambert = NoL * 0.5 + 0.5;
               halflambert  = halflambert * halflambert;
               half lambertStep = smoothstep(0.01,0.4,halflambert);
               half shadowFactor  = lerp(0,halflambert, lambertStep);
               half ambient = halflambert;            
               half shadow = (ambient +halflambert)*0.5;

               shadow = lerp(shadow, 1, step(0.95, ambient));
               shadow = lerp(shadow,0, step( ambient,0.05));
               half isShadowArea = step (shadow, _ShadowPosition);
               half shadowDepth = saturate((_ShadowPosition-shadow)/_ShadowPosition);
               shadowDepth = pow(shadowDepth, _ShadowSoftness);
               shadowDepth = min(shadowDepth,1);
               half rampWidthFactor = albedo.g * 2 * _ShadowRampWidth;
               half shadowPosition = (_ShadowPosition - shadowFactor)/_ShadowPosition;

               half rampU = 1 - saturate(shadowDepth/rampWidthFactor);
               half ramID = RampShadowID(lightmap.a, _UseRampShadow2, _UseRampShadow3, _UseRampShadow4, _UseRampShadow5, 1, 2, 3, 4, 5);
               half rampV = 0.45 - (ramID - 1)*0.1;

               half2 rampDayUV = half2(rampU, rampV + 0.5);
               half3 rampDayColor = tex2D(_RampTex, rampDayUV);
                
               half2 rampNightUV = half2(rampU, rampV);
               half3 rampNightColor = tex2D(_RampTex, rampNightUV);

               half3 rampCol = lerp(rampDayColor, rampNightColor, _DayOrNight);

               #if _USE_RAMP_SHADOW
                half3 bodycol = albedo.rgb *rampCol*(isShadowArea ? 1:1.2);
                #else
                half3 bodycol = albedo.rgb * halflambert * (shadow + 0.2);
                #endif
               

               //------------------------------------------------------------------------
               // Skin color
               //------------------------------------------------------------------------
               float3 color = (diffuse + specular) * light.color * light.distanceAttenuation *2.0;
               color = color * albedo * skinUV;


               //------------------------------------
               // Debug
               //------------------------------------
               #if defined(DEBUG_CURVE)
                    return float4(cuv, cuv, cuv, 1);
               #elif defined(DEBUG_SPECULAR)
                    return float4(specular, 1);
               #endif
               if(skinUV>=0.01)
               {
                  // color = i.worldPos.zzz;
                    return float4(color , 1);

               }
               else
               {
                     // bodycol = lerp(bodycol, _SpotShadowColor, saturate(height01));
                    return float4(bodycol, 1);
               }
                
            }

            ENDHLSL
        }
        Pass
        {
            Name "ShadowCaster"
            Tags{
                "LightMode" = "ShadowCaster"
                }

                ZWrite On
                ZTest LEqual
                ColorMask 0
                Cull off

                HLSLPROGRAM
                #pragma multi_compile_instancing // 启用GPU实例化编译
                #pragma multi_compile _ DOTS_INSTANCING_ON // 启用DOTS实例化编译
                #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW // 启用点光源阴影

                #pragma vertex ShadowVS
                #pragma fragment ShadowFS

                // float3 _LightDirection;
                // float3 _LightPosition;

                struct Attributes
                {
                    float4 positionOS : POSITION;
                    float3 normalOS :NORMAL;
                    
                    };

               struct Varyings
                {
                    float4 positionCS : SV_POSITION;
                    //float3 positionWS : INTERNALTESSPOS;
                   
                    //float4 tangentWS : TANGENT;
                         
    
                };


                // 将阴影的世界空间顶点位置转换为适合阴影投射的裁剪空间位置
                float4 GetShadowPositionHClip(Attributes input)
                {
                    float3 positionWS = TransformObjectToWorld(input.positionOS.xyz); // 将本地空间顶点坐标转换为世界空间顶点坐标
                    float3 normalWS = TransformObjectToWorldNormal(input.normalOS); // 将本地空间法线转换为世界空间法线

                    //#if _CASTING_PUNCTUAL_LIGHT_SHADOW // 点光源
                    //   float3 lightDirectionWS = normalize(_LightPosition - positionWS); // 计算光源方向
                   // #else // 平行光
                   //     float3 lightDirectionWS = _LightDirection; // 使用预定义的光源方向
                   // #endif
                    // Light
                    Light light = GetMainLight();
                    float3 lightDir = normalize(light.direction);
                    float3 lightdistan
                    float4 positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, lightDir)); // 应用阴影偏移

                    // 根据平台的Z缓冲区方向调整Z值
                    #if UNITY_REVERSED_Z // 反转Z缓冲区
                        positionCS.z = min(positionCS.z, UNITY_NEAR_CLIP_VALUE); // 限制Z值在近裁剪平面以下
                    #else // 正向Z缓冲区
                        positionCS.z = max(positionCS.z, UNITY_NEAR_CLIP_VALUE); // 限制Z值在远裁剪平面以上
                    #endif

                    return positionCS; // 返回裁剪空间顶点坐标
                }



                Varyings ShadowVS(Attributes input)
                {
                    Varyings output;
                    
                    output.positionCS = GetShadowPositionHClip(input);

                    return output;
                }

                half4 ShadowFS(Varyings input):SV_TARGET{
                    return 0;
                    }

                ENDHLSL
    }
}
}