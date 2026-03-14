Shader "PostProcessing/Outline"
{
    Properties
    {
        _GradientScale ("Gradient Scale", Float) = 1.0
        _TexelSize ("TexelSize ", Float) = 1.0
        _Sensitivity ("Sensitivity", Float) = 1.0
        _Strength ("Strength", Float) = 1.0
        _ShakeSpeed("Shake Speed",Range(0.0, 3.0)) = 1
        _ShakeAmplitude("Shake Amplitude",Range(0.1, 1.0)) = 0.1
        _DepthStrength("Depth Power",Range(0.0, 10.0)) = 0.1
        _Threshold("Outline Bold Threashold",Range(0.0, 0.1)) = 0.1
        _OutlineColor ("Outline Color", Color) = (1,1,1,1)

        _ShadowTexture ("ShadowTexture",2D) = "white" {}

        _RingIntervalScreen ("RingIntervalScreen", Range(0.0, 1.0)) = 0.1
        _BaseThicknessScreen ("BaseThicknessScreen",Range(0.0, 10.0)) = 1
        _NoiseScale ("NoiseScale", Float) = 1.0
        _NoiseStrength ("NoiseStrength", Float) = 1.0
        _ThicknessScaleByDepth ("ThicknessScaleByDepth", Float) = 1.0
           
    }
    SubShader
    {
        Tags 
        {  
            "RenderType" = "Opaque"
            "RenderPipeline" = "UniversalPipeline"
           // "Queue" = "Transparent+100" 
        }

       
        LOD 100
        ZTest Always
        ZWrite Off
        Cull Off
        HLSLINCLUDE
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"            
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareNormalsTexture.hlsl" // SampleSceneNormals
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            SAMPLER(sampler_BlitTexture);
            int _Width;
            int _Height;
            TEXTURE2D(_ShadowTexture);             
            SAMPLER(samplerLinearRepeat); 
            float4 _ShadowTexture_ST;

            float _GradientScale;
            float _TexelSize;
            float  _Sensitivity;
            float _Strength;
            float4 _OutlineColor;
            float _RingIntervalScreen;
            float _BaseThicknessScreen;
            float _NoiseScale ;
            float _NoiseStrength ;
            float _ThicknessScaleByDepth ;
            float _ShakeAmplitude;
            float _ShakeSpeed;
            float _Threshold;
            float _DepthStrength;

            float3 _CenterPos;
            float4x4 _InverseProjectionMatrix;//从cam到clip的逆
            float4x4 _InverseViewMatrix;//从cam到world
            //==============================================================================================================================
            //noise 生成
            //==============================================================================================================================
            // 方向函数（伪随机梯度）
            float2 unity_gradientNoise_dir(float2 p)
            {
                p = p % 289;
                float x = (34 * p.x + 1) * p.x % 289 + p.y;
                x = (34 * x + 1) * x % 289;
                x = frac(x / 41) * 2 - 1;
                return normalize(float2(x - floor(x + 0.5), abs(x) - 0.5));
            }

            // 核心 gradient noise 函数（范围 ≈ -0.5 ~ 0.5）
            float unity_gradientNoise(float2 p)
            {
                float2 i = floor(p);
                float2 f = frac(p);

                float2 u = f * f * (3.0 - 2.0 * f);   // smoothstep 插值

                float n00 = dot(unity_gradientNoise_dir(i + float2(0.0, 0.0)), f - float2(0.0, 0.0));
                float n01 = dot(unity_gradientNoise_dir(i + float2(0.0, 1.0)), f - float2(0.0, 1.0));
                float n10 = dot(unity_gradientNoise_dir(i + float2(1.0, 0.0)), f - float2(1.0, 0.0));
                float n11 = dot(unity_gradientNoise_dir(i + float2(1.0, 1.0)), f - float2(1.0, 1.0));

                return lerp(lerp(n00, n10, u.x), lerp(n01, n11, u.x), u.y);
            }   
            
            //根据当前uv获取对应世界坐标
            float4 GetWorldSpacePosition(float depth, float2 uv)
            {                 
                 float4 view_vector = mul(_InverseProjectionMatrix, float4(2.0 * uv - 1.0, depth, 1.0));
                 view_vector.xyz /= view_vector.w;
                 
                 float4x4 l_matViewInv = _InverseViewMatrix;
                 float4 world_vector = mul(l_matViewInv, float4(view_vector.xyz, 1));
                 return world_vector;
             }

            //==============================================================================================================================
            //绘制同心圆
            //==============================================================================================================================
            float DrawWorldCenteredRings(
                      // 指定圆心的世界位置
                float3 CameraWorldPos,          // 当前相机世界位置
                float2 ScreenUV,                // 当前像素 uv (0~1)
                float RingRadiusStart,          // 第一环的屏幕半径（归一化 0~1，或像素单位需配合 ScreenSize）
                float RingIntervalScreen,       // 每环间隔（屏幕空间，归一化单位 0~1 推荐）
                float BaseThicknessScreen,      // 基础厚度（屏幕空间，归一化或像素）
                float ThicknessScaleByDepth,    // 厚度随深度缩放系数（depth * 这个值）
                float MaxRingCount,             // 最多绘制多少环（防止性能爆炸）
                float NoiseScale,               // 噪声频率
                float NoiseStrength,            // 噪声扰动强度（相对 thickness）
                float depth)            // 噪声对位置的扰动强度（像素单位）
            {
               // 1. 计算圆心在屏幕上的投影坐标
                // 把世界位置转到裁剪空间，再转到 NDC (0~1)
                
                float4 centerClip = mul(UNITY_MATRIX_VP, float4(_CenterPos, 1.0));
    
                // 如果在相机背后或超出视锥，直接退出
                if (centerClip.w <= 0.0001) return 0;

                float2 centerNDC = centerClip.xy / centerClip.w;          // -1 ~ 1
                float2 centerUV  = centerNDC * 0.5 + 0.5;                 // 0 ~ 1
                float3 worldPos = GetWorldSpacePosition(depth,ScreenUV);
                //一个像素的尺寸
                float2 texelSize = float2(1.0/_Width, 1.0/_Height);
                float gradientNoise = unity_gradientNoise(ScreenUV * _GradientScale) + 0.5;
                float noise = step(gradientNoise,0.8);
                //float2 centerUV = float2 (0.48,0.3);
                // 2. 当前像素到圆心的屏幕距离（归一化单位）
                //float2 delta = ScreenUV - centerUV;
                float dis = length(worldPos - _CenterPos);
                float eyeDis = length(worldPos - _WorldSpaceCameraPos);
                //float r = length(float2(delta.x,delta.y*_Height/_Width))+gradientNoise/_Width*_Strength;                                  // 屏幕空间径向距离 (0~√2，大约0~1.4)
               // depth 是 0~1 的归一化深度（近=0，远=1）
               // float depthFactor = lerp(1.0, 200.0, 1-depth+0.01);   // 近处1.0，远处放大到 _DepthMaxScale
               // float depthFactor = pow(1.0 + depth * _DepthStrength, _DepthPower);
                // 或更简单：
                float linear01 = Linear01Depth(depth, _ZBufferParams);
                float depthFactor =1.0 / pow(1.0 - linear01-0.01, _DepthStrength); // 二次曲线，更平滑

                
                float baseInterval = length(_CenterPos - _WorldSpaceCameraPos) * RingIntervalScreen;
                // 或固定 baseInterval = 你的某个常量，比如 0.05 ~ 0.2

                float interval = baseInterval * depthFactor;
                
                //float interval = length(_CenterPos-_WorldSpaceCameraPos) * RingIntervalScreen;
                //float interval = 20;
                float phase = fmod(dis, interval);
                if (phase >(0.5 *interval) ) phase = interval - phase;
                float dynamicThickness = BaseThicknessScreen * (1.0 - ThicknessScaleByDepth * depth);
                float ring = step(phase, dynamicThickness)*noise;//*abs(1-r)/0.5
               
                /*
                //DistToCenterScreen = r;
                float phase = fmod(r, RingIntervalScreen);
                if (phase >(0.5 *RingIntervalScreen) ) phase = RingIntervalScreen - phase;
                // 4. 根据深度动态调整厚度（远处的环更细）
                float dynamicThickness = BaseThicknessScreen/_Height * max(0.1, 1.0 - ThicknessScaleByDepth * depth)+gradientNoise /_Height;
                float ring = step(phase, dynamicThickness)*noise*abs(1-r)/0.5;
                //float distToNearestRingCenter = min(phase, RingIntervalScreen - phase);
                //float ring = step(dynamicThickness, dynamicThickness * 0.4, distToNearestRingCenter);
                */
                return ring;

            }

            
        ENDHLSL

        Pass
        {
            Name "Outline"
            Stencil
                {
                    Ref 0
                    Comp Equal
                }
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag
             
            half4 Frag(Varyings input) : SV_Target
            {
                //基本信息
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
                float2 uv = input.texcoord; 
                float zdepth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, sampler_CameraDepthTexture, uv);
                half4 color = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_BlitTexture, uv);
                //float linear01 = Linear01Depth(zdepth, _ZBufferParams);
                //return half4((linear01)*half4(1,1,1,1));
                //float4 worldPos = GetWorldSpacePosition(depth, uv);
                float3 camPos = _WorldSpaceCameraPos;                
                //float3 worldViewDir = normalize(worldPos.xyz - camPos.xyz);
                float time = _Time.y * _ShakeSpeed;
                float2 jitter = float2(
                            sin(time * 17.3) * _ShakeAmplitude,
                            cos(time * 23.7) * _ShakeAmplitude
                        ) * 0.01;

                float gradientNoise = unity_gradientNoise((uv+jitter) * _GradientScale) + 0.5;
               // float time = gradientNoise * _ShakeSpeed;           // _ShakeSpeed 控制速度，比如 1.0 ~ 3.0
                float shake = sin(gradientNoise) * _ShakeAmplitude ;  // 振幅比如 0.1 ~ 0.4
                float2 texelSize = 1.0 / _ScaledScreenParams.xy*_TexelSize* shake + _Threshold;
                //Roberts 算子
                // 4 个对角采样点
                float2 offsets[4] = {
                    float2(-1, -1),
                    float2( 1, -1),
                    float2(-1,  1),
                    float2( 1,  1)
                };

                float depth[4];
                for(int j = 0; j < 4; j++)
                {
                    depth[j] = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, sampler_CameraDepthTexture,uv + offsets[j] * texelSize);
                }
                float3 normal[4];
                for(int k = 0; k < 4; k++)
                {
                    normal[k] = SampleSceneNormals(uv + offsets[k] * texelSize * 1.0);
                }
                float normalEdge = 
                    (1.0 - saturate(dot(normal[0], normal[3]))) +
                    (1.0 - saturate(dot(normal[1], normal[2])));

                // 计算深度差（对角交叉差分）
                float depthEdge = 
                    abs(depth[0] - depth[3]) + 
                    abs(depth[1] - depth[2]);

                float edge = depthEdge + normalEdge;
                
                //depthEdge  * _DepthSensitivity +
               // normalEdge * _NormalSensitivity;
              
                edge = saturate(edge * _Sensitivity);//- _Threshold


               //中心绘制圆环
                 float4 shadedTexture =  SAMPLE_TEXTURE2D_X(_ShadowTexture, samplerLinearRepeat,  uv*_ShadowTexture_ST.x);

                float circle = DrawWorldCenteredRings(camPos, uv,0.01,_RingIntervalScreen, _BaseThicknessScreen,_ThicknessScaleByDepth,5,_NoiseScale,_NoiseStrength,zdepth);
                //debug检查数值
                half4 debugColor = (edge +circle) * half4(1,1,1,1);
                debugColor = lerp(color, debugColor*_OutlineColor, debugColor);

                
                
                return debugColor*shadedTexture.r;
            }
            ENDHLSL
        }
    }    
}
