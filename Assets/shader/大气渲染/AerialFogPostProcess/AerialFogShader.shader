// ================================================
//  URP 全屏后处理 Shader 模板（推荐写法）
//  适用于 URP 14.x ~ 17.x / Unity 2022.3 ~ 6000.x
// ================================================

Shader "Olayila/AerialFogPostProcess"
{
    SubShader
    {
        Tags 
        { 
            "RenderType" = "Opaque"
            "RenderPipeline" = "UniversalPipeline"
            "Queue" = "Geometry"    // 或 Transparent，根据需求
        }

        LOD 100
        ZTest Always
        ZWrite Off
        Cull Off

        HLSLINCLUDE
            //后处理shader通常用到这两个文件
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"            
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

            #define PLANET_RADIUS           6360000.0
            #define ATMOSPHERE_HEIGHT       80000.0
            #define SUN_LUMINANCE           float3(1.4, 1.13, 1.0)
            
            #define THRESHOLD               0.001
            
            #define N_SAMPLE 32

            SAMPLER(sampler_BlitTexture);
            SAMPLER(samplerLinearClamp);  

            TEXTURE2D(_transmittanceLut);
            TEXTURE2D(_skyViewLut);
            TEXTURE2D(_aerialPerspectiveLut);

          
           float4x4 _InverseProjectionMatrix;
           float4x4 _InverseViewMatrix;

            float4 _AerialPerspectiveVoxelSize;
            float _AerialPerspectiveDistance;
            float _fogDense;
           
             float2 ViewToUV(float3 viewDir)
            {
                
                float2 uv = float2(atan2(viewDir.z, viewDir.x), acos(viewDir.y));
                uv /= float2(2.0 * PI, PI);
                uv += float2(0.5, 0.5);
                return uv;               

            }

             float4 GetWorldSpacePosition(float depth, float2 uv)
            {
                 // 屏幕空间 --> 视锥空间
                 float4 view_vector = mul(_InverseProjectionMatrix, float4(2.0 * uv - 1.0, depth, 1.0));
                 view_vector.xyz /= view_vector.w;
                 //视锥空间 --> 世界空间
                 float4x4 l_matViewInv = _InverseViewMatrix;
                 float4 world_vector = mul(l_matViewInv, float4(view_vector.xyz, 1));
                 return world_vector;
             }
            
            // =====================================
            //  常用纹理声明（根据需求选择）
            // =====================================
            // TEXTURE2D_X(_BlitTexture);          URP 相机颜色目标（Blitter 自动绑定）
         
            // float PlanetRadius;
            // float AtmosphereHeight;
            // float3 sunLuminance;                    注意是 float3，不是 Vector3
           
            // float threash;
            // float4x4 CameraToWorld;

           

        ENDHLSL

        // --------------------
        //  Pass 0 - 主效果
        // --------------------
        Pass
        {
            Name "MyPostProcess"

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment frag

            half4 frag(Varyings input) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

                float2 uv = input.texcoord; 
                float depth01 = SampleSceneDepth(uv);
                // =====================================
                //  获取主颜色（相机渲染结果）
                // =====================================
                
               half4 ScreenCol = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_BlitTexture, uv);

                float depth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, sampler_CameraDepthTexture, uv);
                float4 worldPos = GetWorldSpacePosition(depth, uv);
                float3 camPos = _WorldSpaceCameraPos;
                 //相机到每个像素的世界方向
                 float3 worldViewDir = normalize(worldPos.xyz - camPos.xyz) ;
                
                 float distToCamera = length(worldPos.xyz - camPos.xyz);
                  float normalizedDist = min(distToCamera*_fogDense / max(_AerialPerspectiveDistance, 1e-5),1.0);
                float2 uv_aerialLut =ViewToUV( worldViewDir);

                //计算当前深度所在的aerial索引，以及下一个索引，并以小数值作为lerpfactor
                float lutIndex =floor( normalizedDist *(N_SAMPLE - 1));
                float lutIndex_next =min(lutIndex + 1,N_SAMPLE - 1);
                float lerpFactor = normalizedDist *(N_SAMPLE - 1) - lutIndex;

                float2 uv_cur = float2((uv_aerialLut.x + lutIndex)/N_SAMPLE,uv_aerialLut.y);
                float2 uv_next = float2((uv_aerialLut.x + lutIndex_next)/N_SAMPLE,uv_aerialLut.y);
                float4 curCol = SAMPLE_TEXTURE2D_X(_aerialPerspectiveLut, samplerLinearClamp,  uv_cur);
                float4 nextCol = SAMPLE_TEXTURE2D_X(_aerialPerspectiveLut, samplerLinearClamp,  uv_next);

                float4 col_aerial = lerp(curCol,nextCol,lerpFactor);
                 
                float3 col = ScreenCol*col_aerial.w+col_aerial.xyz;
                   //col = (step(1-7e-07,depth01))*ScreenCol +(1- step(1-7e-07,depth01))*col;
                // =====================================
                //  返回最终颜色
                // =====================================
                //return col;
                
               //return half4(col_aerial.xyz,1);
              return half4(col,1);

            }

          





            ENDHLSL
        }

    }


    Fallback Off
}
