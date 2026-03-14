Shader "Hidden/SimpleUnlitMainLightWithNormalAndShadow"
{
    Properties
    {
        [MainTexture] _BaseMap("Base Map (Albedo)", 2D) = "white" {}
        [MainColor]   _BaseColor("Base Color", Color) = (1,1,1,1)
           _FarColor("Base Color", Color) = (1,1,1,1)

        [Normal] _BumpMap("Normal Map", 2D) = "bump" {}
        _BumpScale("Normal Scale", Float) = 1.0

        [Toggle(_RECEIVE_SHADOWS)] _ReceiveShadows("Receive Shadows", Float) = 1
    }

    SubShader
    {
        Tags 
        { 
            "RenderType" = "Opaque"
            "RenderPipeline" = "UniversalPipeline"
            //"UniversalMaterialType" = "Lit"
            //"IgnoreProjector" = "True"
        }

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }
            ZWrite On
            ZTest LEqual
            HLSLPROGRAM

            #pragma vertex vert
            #pragma fragment frag

            // 必须包含这些以支持主光源、阴影等
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _SHADOWS_SOFT

            // 是否接收阴影（材质开关）
            #pragma shader_feature_local _RECEIVE_SHADOWS

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

            // ────────────────────────────────────────────────
            //                  自定义主光函数（你提供的版本）
            // ────────────────────────────────────────────────
            void MainLight_half(float3 WorldPos, out half3 Direction, out half3 Color, out half DistanceAtten, out half ShadowAtten)
            {
            #if SHADERGRAPH_PREVIEW
                Direction    = half3(0.5, 0.5, 0);
                Color        = 1;
                DistanceAtten = 1;
                ShadowAtten  = 1;
            #else
            #if SHADOWS_SCREEN
                half4 clipPos    = TransformWorldToHClip(WorldPos);
                half4 shadowCoord = ComputeScreenPos(clipPos);
            #else
                half4 shadowCoord = TransformWorldToShadowCoord(WorldPos);
            #endif

                Light mainLight = GetMainLight(shadowCoord);
                Direction    = mainLight.direction;
                Color        = mainLight.color;
                DistanceAtten = mainLight.distanceAttenuation;
                ShadowAtten  = mainLight.shadowAttenuation;
            #endif
            }

            // ────────────────────────────────────────────────
            //                      输入/输出结构
            // ────────────────────────────────────────────────
            struct Attributes
            {
                float4 positionOS   : POSITION;
                float3 normalOS     : NORMAL;
                float4 tangentOS    : TANGENT;
                float2 uv           : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS   : SV_POSITION;
                float3 positionWS   : TEXCOORD0;
                float2 uv           : TEXCOORD1;
                float3 normalWS     : TEXCOORD2;
                float3 tangentWS    : TEXCOORD3;
                float3 bitangentWS  : TEXCOORD4;
            };

            // ────────────────────────────────────────────────
            //                      纹理与参数
            // ────────────────────────────────────────────────
            TEXTURE2D(_BaseMap);     SAMPLER(sampler_BaseMap);
            TEXTURE2D(_BumpMap);     SAMPLER(sampler_BumpMap);

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                half4  _BaseColor;
                half   _BumpScale;
            CBUFFER_END

            // ────────────────────────────────────────────────
            //                      顶点着色器
            // ────────────────────────────────────────────────
            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                VertexPositionInputs vertexInput = GetVertexPositionInputs(IN.positionOS.xyz);
                VertexNormalInputs normalInput = GetVertexNormalInputs(IN.normalOS, IN.tangentOS);

                OUT.positionCS    = vertexInput.positionCS;
                OUT.positionWS    = vertexInput.positionWS;
                OUT.uv            = TRANSFORM_TEX(IN.uv, _BaseMap);

                OUT.normalWS    = normalInput.normalWS;
                OUT.tangentWS   = normalInput.tangentWS;
                OUT.bitangentWS = normalInput.bitangentWS;

                return OUT;
            }

            // ────────────────────────────────────────────────
            //                      片元着色器
            // ────────────────────────────────────────────────
            half4 frag(Varyings IN) : SV_Target
            {
                // 1. 读取基础颜色
                half4 baseColor = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv) * _BaseColor;

                // 2. 计算切线空间 → 世界空间法线（使用 normal map）
                half3 normalTS = UnpackNormalScale(SAMPLE_TEXTURE2D(_BumpMap, sampler_BumpMap, IN.uv*10), _BumpScale);

                half3x3 tangentToWorld = half3x3(
                    IN.tangentWS,
                    IN.bitangentWS,
                    IN.normalWS
                );

                half3 normalWS = TransformTangentToWorld(normalTS, tangentToWorld);
                normalWS = NormalizeNormalPerPixel(normalWS);

                // 3. 获取主光信息（包含阴影）
                half3 lightDir, lightColor;
                half distanceAtten, shadowAtten;
                MainLight_half(IN.positionWS, lightDir, lightColor, distanceAtten, shadowAtten);

                // 4. N·L （半兰伯特或直接 Lambert，根据需求）
                half NdotL = saturate(dot(normalWS, lightDir));
                // half NdotL = max(0.0, dot(normalWS, lightDir));   // 纯 Lambert
                // half NdotL = NdotL * 0.5 + 0.5;                   // 半兰伯特（可选）

                // 5. 最终颜色 = 基础色 × 主光颜色 × N·L × 距离衰减 × 阴影
                half3 lighting = baseColor.rgb * NdotL * distanceAtten;

            #if _RECEIVE_SHADOWS
                lighting *= shadowAtten;
            #endif

                // 可选：加上环境光（非常简单的一点）
                //half3 ambient = SampleSH(normalWS) * 0.3; // 或直接固定值 half3(0.1,0.1,0.15)
                //lighting += ambient * baseColor.rgb;

                return half4(lighting, baseColor.a);
            }

            ENDHLSL
        }

        // ────────────────────────────────────────────────
        // 新增：DepthOnly Pass（只写深度，不写法线，用于某些优化/预通）
        // ────────────────────────────────────────────────
        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode" = "DepthOnly" }

            ZWrite On
            ColorMask 0
            Cull[_Cull]

            HLSLPROGRAM
            #pragma vertex DepthOnlyVertex
            #pragma fragment DepthOnlyFragment

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            // 输入结构（简化，只需位置）
            struct AttributesDepth
            {
                float4 positionOS   : POSITION;
            };

            struct VaryingsDepth
            {
                float4 positionCS   : SV_POSITION;
            };

            VaryingsDepth DepthOnlyVertex(AttributesDepth input)
            {
                VaryingsDepth output;
                VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS.xyz);
                output.positionCS = vertexInput.positionCS;
                return output;
            }

            half4 DepthOnlyFragment(VaryingsDepth input) : SV_Target
            {
                return 0; // 只写深度，不输出颜色
            }
            ENDHLSL
        }

        // ────────────────────────────────────────────────
        // 新增：DepthNormals Pass（关键！写深度 + 修改后的视图空间法线）
        // ────────────────────────────────────────────────
        Pass
        {
            Name "DepthNormals"
            Tags { "LightMode" = "DepthNormals" }

            ZWrite On
            Cull[_Cull]

            HLSLPROGRAM
            #pragma vertex DepthNormalsVertex
            #pragma fragment DepthNormalsFragment

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            // 复用你原有的 Attributes 和 Varyings（带 tangent/normal/uv）
            struct Attributes
            {
                float4 positionOS   : POSITION;
                float3 normalOS     : NORMAL;
                float4 tangentOS    : TANGENT;
                float2 uv           : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS   : SV_POSITION;
                float3 positionWS   : TEXCOORD0;
                float2 uv           : TEXCOORD1;
                float3 normalWS     : TEXCOORD2;
                float3 tangentWS    : TEXCOORD3;
                float3 bitangentWS  : TEXCOORD4;
            };

            TEXTURE2D(_BumpMap); SAMPLER(sampler_BumpMap);

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                half   _BumpScale;
            CBUFFER_END

            Varyings DepthNormalsVertex(Attributes input)
            {
                Varyings output;
                VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS.xyz);
                VertexNormalInputs normalInput = GetVertexNormalInputs(input.normalOS, input.tangentOS);

                output.positionCS    = vertexInput.positionCS;
                output.positionWS    = vertexInput.positionWS;
                output.uv            = TRANSFORM_TEX(input.uv, _BaseMap);

                output.normalWS    = normalInput.normalWS;
                output.tangentWS   = normalInput.tangentWS;
                output.bitangentWS = normalInput.bitangentWS;

                return output;
            }

            void DepthNormalsFragment(
                Varyings input,
                out half4 outNormal : SV_Target   // 输出到 _CameraNormalsTexture
                // depth 自动写入 depth buffer
            )
            {
                // 和 Forward pass 一样的 normal map 计算逻辑
                half3 normalTS = UnpackNormalScale(SAMPLE_TEXTURE2D(_BumpMap, sampler_BumpMap, input.uv), _BumpScale);

                half3x3 tangentToWorld = half3x3(
                    input.tangentWS,
                    input.bitangentWS,
                    input.normalWS
                );

                half3 normalWS = TransformTangentToWorld(normalTS, tangentToWorld);
                normalWS = NormalizeNormalPerPixel(normalWS);

                // 转到视图空间（URP DepthNormals 通常用视图空间法线）
                half3 normalVS = TransformWorldToViewDir(normalWS);

                // 打包 [ -1..1 ] → [0..1] 输出
                outNormal = half4(normalVS * 0.5 + 0.5, 0.0);
            }
            ENDHLSL
        }

        // 可选：ShadowCaster Pass（如果需要物体投射阴影）
        UsePass "Universal Render Pipeline/Lit/ShadowCaster"
    }

       



    FallBack "Hidden/Universal Render Pipeline/FallbackError"
}