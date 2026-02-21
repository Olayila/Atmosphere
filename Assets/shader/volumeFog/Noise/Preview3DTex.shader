Shader "Debug/3DTexture Slice Viewer (URP)"
{
    Properties
    {
        [NoScaleOffset]_VolumeTex ("3D Texture", 3D) = "" {}
        
        [Enum(R,0,G,1,B,2,A,3,Luminance,4)]
        _Channel ("Channel", Float) = 0
        
        [Header(Slice Control)]
        _SliceZ ("Z Slice (0-1)", Range(0,1)) = 0.5
        
        [Header(Debug Options)]
        [Toggle]_LinearToGamma ("Linear → Gamma", Float) = 1
        _Brightness ("Brightness", Range(0.1, 5)) = 1
        _Contrast ("Contrast", Range(0.1, 3)) = 1
    }

    SubShader
    {
        Tags 
        { 
            "RenderType"="Opaque" 
            "RenderPipeline"="UniversalPipeline" 
            "Queue"="Geometry"
        }

        Pass
        {
            Name "Unlit"
            Tags { "LightMode" = "UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            // ────────────────────────────────
            //  Properties
            // ────────────────────────────────
            TEXTURE3D(_VolumeTex);          SAMPLER(sampler_VolumeTex);
            float4 _VolumeTex_TexelSize;

            CBUFFER_START(UnityPerMaterial)
                float  _Channel;
                float  _SliceZ;
                float  _LinearToGamma;
                float  _Brightness;
                float  _Contrast;
            CBUFFER_END

            // ────────────────────────────────
            //  Input / Output
            // ────────────────────────────────
            struct Attributes
            {
                float4 positionOS   : POSITION;
                float2 uv           : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS   : SV_POSITION;
                float3 uv           : TEXCOORD0;    // xyz 用于 3D 采样
            };

            // ────────────────────────────────
            //  Vertex
            // ────────────────────────────────
            Varyings vert(Attributes input)
            {
                Varyings output;
                
                VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS.xyz);
                output.positionCS = vertexInput.positionCS;

                // 把 object space [-0.5,0.5] 映射到 [0,1] UV 空间
                output.uv = input.positionOS.xyz + 0.5;

                return output;
            }

            // ────────────────────────────────
            //  Fragment - 主逻辑
            // ────────────────────────────────
            half4 frag(Varyings input) : SV_Target
            {
                // Z 切片：用滑块控制
                float z = saturate(_SliceZ);

                // 采样 3D 纹理（注意：Unity 的 3D Texture UV 是 [0,1]）
                float4 color = SAMPLE_TEXTURE3D(_VolumeTex, sampler_VolumeTex, float3(input.uv.xy, z));

                // 根据通道选择要显示的值
                float value;
                if (_Channel < 0.5)      value = color.r;
                else if (_Channel < 1.5) value = color.g;
                else if (_Channel < 2.5) value = color.b;
                else if (_Channel < 3.5) value = color.a;
                else                     value = dot(color.rgb, float3(0.299, 0.587, 0.114)); // Luminance

                // 可选：线性 → Gamma 校正（大多数 3D 纹理是线性空间）
                if (_LinearToGamma > 0.5)
                    value = pow(value, 1.0/2.2);

                // 亮度 & 对比度调整（方便看清细节）
                value = (value - 0.5) * _Contrast + 0.5;
                value *= _Brightness;

                // 输出灰度图（单通道可视化）
                half3 finalColor = value.xxx;

                return half4(finalColor, 1.0);
            }
            ENDHLSL
        }
    }

    FallBack "Hidden/Universal Render Pipeline/FallbackError"
}