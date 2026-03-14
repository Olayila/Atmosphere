Shader "Hidden/URP_StencilOutline"
{
    Properties
    {
        _OutlineColor ("Outline Color", Color) = (1,1,0,1)
        _OutlineWidth ("Outline Width", Range(0.001, 0.01)) = 0.005
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }

        Pass
        {
            Name "Stencil Outline Post"

            ZTest Always
            ZWrite Off
            Cull Off

            Stencil
            {
                Ref 1
                Comp Equal       // 只在 stencil == 2 的像素执行描边
            }

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

             SAMPLER(sampler_BlitTexture);
            float4 _OutlineColor;
            float _OutlineWidth;

            half4 frag(Varyings i) : SV_Target
            {
                float2 uv = i.texcoord;

                // 采样原图
                half4 col = SAMPLE_TEXTURE2D(_BlitTexture, sampler_BlitTexture, uv);

                // 简单 Sobel 边缘检测（基于深度或颜色，根据需求选）
                float2 texel = 1.0 / _ScaledScreenParams.xy * _OutlineWidth;

                float depthCenter = SampleSceneDepth(uv);
                float depthLeft   = SampleSceneDepth(uv + float2(-texel.x, 0));
                float depthRight  = SampleSceneDepth(uv + float2( texel.x, 0));
                float depthUp     = SampleSceneDepth(uv + float2(0, texel.y));
                float depthDown   = SampleSceneDepth(uv + float2(0, -texel.y));

                float edge = abs(depthCenter - depthLeft) +
                             abs(depthCenter - depthRight) +
                             abs(depthCenter - depthUp) +
                             abs(depthCenter - depthDown);

                edge = step(0.0001, edge);  // 阈值

                // 混合描边颜色
                col.rgb = lerp(col.rgb, _OutlineColor.rgb, edge * _OutlineColor.a);

                return col;
            }
            ENDHLSL
        }
    }
}