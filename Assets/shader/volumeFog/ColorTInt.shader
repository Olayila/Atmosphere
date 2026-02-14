Shader "Hidden/PostProcessing/ColorTint"
{
    SubShader
    {

        Tags 
        { 
            "RenderType" = "Opaque"
            "RenderPipeline" = "UniversalPipeline"
            "Queue" = "Transparent+100"    // 或 Transparent，根据需求
        }
        LOD 100
        ZTest Always
        ZWrite Off
        Cull Off
        HLSLINCLUDE
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"            
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
             #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
             #define _RAYSTEP 2
             // 定义宏对应的预设值（硬编码，性能最好）
            #if defined(SCENE_DENSE_CLOUD)
                #define PHASE_PARAMS float4(0.85, 0.35, 0.02, 1.2)
            #elif defined(SCENE_THIN_MIST)
                #define PHASE_PARAMS float4(0.6, -0.2, 0.05, 0.8)
            #elif defined(SCENE_OCEAN)
                #define PHASE_PARAMS float4(0.92, 0.1, 0.01, 1.5)
            #elif defined(SCENE_SIMPLE)
                #define PHASE_PARAMS float4(0.8, 0.0, 0.0, 1.0)
            #else
                #define PHASE_PARAMS _PhaseParams   // Custom 模式用材质属性
            #endif
            #define _PLANETRADIUS 6360000
            
             SAMPLER(sampler_BlitTexture);
            float _BlendMultiply;
            float4 _Color;
            float4 _PhaseParams;
            float4x4 _InverseProjectionMatrix;//教程中指出，但shader应该可以自动获取
            float4x4 _InverseViewMatrix;
            float3 _boundsMin;
            float3 _boundsMax;

            float _step;
            float _rayStep;
            float _darknessThreshold;
            float4 _colA;
            float4 _colB;
            float _colorOffset1;
            float _colorOffset2;
            float _lightAbsorptionTowardSun;
            float _lightAbsorptionThroughCloud;
            TEXTURE3D(_noiseTex);
            SAMPLER(sampler_noiseTex);
            float _texScale;

            TEXTURE2D(_transmittanceLut);
             TEXTURE2D(_weatherMap);
            SAMPLER(samplerLinearClamp);  
            SAMPLER(samplerLinearRepeat);  

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

            float3 GetViewDirectionWS(float2 uv)
            {
               
               
                float2 ndc = uv * 2.0 - 1.0;
              
                float4 clipPos = float4(ndc.x, ndc.y, 1.0, 1.0);

                
                float4 viewPos = mul(UNITY_MATRIX_I_P, clipPos);
                viewPos.xyz /= viewPos.w;   

                float3 viewDirWS = mul((float3x3)UNITY_MATRIX_I_V, viewPos.xyz);
                viewDirWS = normalize(viewDirWS);

                return viewDirWS;
            }
            float RayIntersectSphere(float3 rayOrigin, float3 rayDir, float3 sphereCenter, float sphereRadius)
            {
                rayDir = normalize(rayDir);
                float3 oc = rayOrigin - sphereCenter;
                float b = dot(oc, rayDir);
                float c = dot(oc, oc) - sphereRadius * sphereRadius;
                float discriminant = b * b - c;

                if (discriminant < 0)
                    return -1.0;

                float sqrtD = sqrt(discriminant);
                float t1 = -b - sqrtD;
                float t2 = -b + sqrtD;

    
                if (t1 > 0)
                    return t1;
                if (t2 > 0)
                    return t2;
                return -1.0;
            }

            float2 RayCloudLayerDst(float heightMin, float heightMax, float3 eyePos, float3 rayDir, bool isShape = true)
            {
                float3 origin = float3(0,_PLANETRADIUS+eyePos.y,0);
                float innerDst = RayIntersectSphere(origin, rayDir, float3(0,0,0),_PLANETRADIUS+heightMin);
                float outerDst = RayIntersectSphere(origin, rayDir, float3(0,0,0),_PLANETRADIUS+heightMax);
                float2 dstInfo = float2(0,0);
                if (outerDst > 0.0)
                {
                    if (innerDst > 0.0)
                    {
                        // 内外都有交点 → 取两个正值中最小的作为进入点
                        dstInfo = float2(min(innerDst, outerDst), max(innerDst, outerDst));
                    }
                    else
                    {
                        // 只有外层交点 → 从相机到外层
                        dstInfo = float2(0.0, outerDst);
                    }
                }
      
                 return dstInfo;
                
            }

            float2 GetTransmittanceLutUv(float bottomRadius, float topRadius, float mu, float r)
            {
                float H = sqrt(topRadius * topRadius - bottomRadius * bottomRadius);
                float rho = sqrt(r * r - bottomRadius * bottomRadius);
    
                float discriminant = r * r * (mu * mu - 1.0) + topRadius * topRadius;
                float d = max(0.0, (-r * mu + sqrt(discriminant)));
    
                float d_min = topRadius - r;
                float d_max = rho + H;
                float x_mu = (d - d_min) / (d_max - d_min);
                float x_r = rho / H;
    
                return float2(x_mu, x_r);
            }

            float3 TransmittanceToAtmosphere(float3 p, float3 dir)
            {
                float bottomRadius =63600;
                float topRadius = 63680;
    
                float3 upVector = normalize(p);
                float cos_theta = dot(upVector, dir);
                float r = length(p) * 1e-3;
    
                float2 uv = GetTransmittanceLutUv(bottomRadius, topRadius, cos_theta, r);
                return SAMPLE_TEXTURE2D_X(_transmittanceLut, samplerLinearClamp,  uv);
    
            }

            float cloudRayMarching(float3 startPoint, float3 direction) 
            {
                float3 testPoint = startPoint;
                float sum = 0.0;
                direction *= 0.5;//每次步进间隔
                for (int i = 0; i < 256; i++)//步进总长度
                {
                    testPoint += direction;
                    if (testPoint.x < 10.0 && testPoint.x > -10.0 &&
                    testPoint.z < 10.0 && testPoint.z > -10.0 &&
                    testPoint.y < 10.0 && testPoint.y > -10.0)
                    sum += 0.01;
                }
                return sum;
            }

                             //边界框最小值       边界框最大值         
            float2 rayBoxDst(float3 boundsMin, float3 boundsMax, 
                            //世界相机位置      光线方向倒数
                            float3 rayOrigin, float3 invRaydir) 
            {
                float3 t0 = (boundsMin - rayOrigin) * invRaydir;//与三个最小值组成的平面相交的t，类似相似三角形的求法
                float3 t1 = (boundsMax - rayOrigin) * invRaydir;//与三个最小值组成的平面相交的t
                float3 tmin = min(t0, t1);
                float3 tmax = max(t0, t1);

                float dstA = max(max(tmin.x, tmin.y), tmin.z); //进入点
                float dstB = min(tmax.x, min(tmax.y, tmax.z)); //出去点

                float dstToBox = max(0, dstA);//若为0，则摄像机在内部
                float dstInsideBox = max(0, dstB - dstToBox);//在内部的路程
                return float2(dstToBox, dstInsideBox);
            }

              float remap(float original_value, float original_min, float original_max, float new_min, float new_max)
            {
                return new_min + (((original_value - original_min) / (original_max - original_min)) * (new_max - new_min));
            }


            //采样3DTexture
            float sampleDensity(float3 rayPos) 
            {
                /*
                float3 boundsCentre = (_boundsMax + _boundsMin) * 0.5;
                float3 size = _boundsMax - _boundsMin;
                float2 uv = (size.xz * 0.5f + (rayPos.xz - boundsCentre.xz) ) /max(size.x,size.z);
                float3 uvw = rayPos  * _texScale;
                */
                //=================================

                //采样天空球
                //=================================
                float2 uv =float2( rayPos.xz*_texScale);
                
                float4 weatherMap =  SAMPLE_TEXTURE2D_X(_weatherMap, samplerLinearRepeat,  uv);
                /*
                float gMin = remap(weatherMap.x, 0, 1, 0.1, 0.6);
                 float gMax = remap(weatherMap.x, 0, 1, gMin, 0.9);
                 float heightPercent = (rayPos.y - 1500.0) / 2500.0;
                float heightGradient = saturate(remap(heightPercent, 0.0, gMin, 0, 1)) * saturate(remap(heightPercent, 1, gMax, 0, 1));
                float heightGradient2 = saturate(remap(heightPercent, 0.0, weatherMap.r, 1, 0)) * saturate(remap(heightPercent, 0.0, gMin, 0, 1));
                heightGradient = saturate(lerp(heightGradient, heightGradient2,1));
                
                  //边缘衰减
                const float containerEdgeFadeDst = 50;
                float dstFromEdgeX = min(containerEdgeFadeDst, min(rayPos.x - _boundsMin.x, _boundsMax.x - rayPos.x));
                float dstFromEdgeZ = min(containerEdgeFadeDst, min(rayPos.z - _boundsMin.z, _boundsMax.z - rayPos.z));
                float edgeWeight = min(dstFromEdgeZ, dstFromEdgeX) / containerEdgeFadeDst;
                

                 // float4 shapeNoise = SAMPLE_TEXTURE3D(_noiseTex, sampler_noiseTex, uvw);
                 // return shapeNoise.r*_darknessThreshold;
                 heightGradient *= edgeWeight;
                  return heightGradient;
                  */
                  return weatherMap.x;
                
             }
             //计算散射
            float hg(float a, float g) 
            {
              float g2 = g * g;
              return (1 - g2) / (4 * 3.1415 * pow(1 + g2 - 2 * g * (a), 1.5));
            }
            float phase(float a) 
            {
              float blend = 0.5;
              float hgBlend = hg(a, PHASE_PARAMS.x) * (1 - blend) + hg(a, -PHASE_PARAMS.y) * blend;
              return PHASE_PARAMS.z + hgBlend * PHASE_PARAMS.w;
            }
            float3 RayleighCoefficient(float h)
            {
                float3 sigma = float3(5.802, 13.558, 33.1) * 1e-6;
                float H_R = 8000.0;
                float rho_h = exp(-(h / H_R));
                return sigma * rho_h;
            }

            float3 MieCoefficient(float h)
            {
                float3 sigma = (3.996 * 1e-6).xxx;
                float H_M = 1200.0;
                float rho_h = exp(-(h / H_M));
                return sigma * rho_h;
            }

             float3 lightmarch(float3 position ,float dstTravelled)
            {
                Light mainLight = GetMainLight();
                float3 dirToLight = mainLight.direction;

                
               //灯光方向与边界框求交，超出部分不计算
               float dstInsideBox = rayBoxDst(_boundsMin, _boundsMax, position, 1 / dirToLight).y;
               float stepSize = dstInsideBox / 8;
               float totalDensity = 0;
               
              for (int step = 0; step < 8; step++) { //灯光步进次数
                    position += dirToLight * stepSize; //向灯光步进
                    //totalDensity += max(0, sampleDensity(position) * stepSize);                     totalDensity += max(0, sampleDensity(position) * stepSize);
                    totalDensity += max(0, sampleDensity(position));

                }
                float3 lightTransmittance = TransmittanceToAtmosphere(float3(position.x,position.y+6366000.0,position.z) ,dirToLight);
                //float transmittance = exp(-totalDensity * _lightAbsorptionTowardSun);
                float3 transmittance = exp(-totalDensity )*lightTransmittance;
                //将重亮到暗映射为 3段颜色 ,亮->灯光颜色 中->ColorA 暗->ColorB
                float3 cloudColor = lerp(_colA, mainLight.color, saturate(transmittance * _colorOffset1));
                cloudColor = lerp(_colB, cloudColor, saturate(pow(transmittance * _colorOffset2, 3)));
                return _darknessThreshold + transmittance * (1 - _darknessThreshold) * cloudColor;
            }
            
           



        ENDHLSL
        Pass
        {
             Name "ColorTint"
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag
           

            
            half4 Frag(Varyings input) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
                float2 uv = input.texcoord; 

                 float depth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, sampler_CameraDepthTexture, uv);
                 half4 color = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_BlitTexture, uv);
                // 采样屏幕深度
             
                 //世界空间坐标
                 float4 worldPos = GetWorldSpacePosition(depth, uv);
                 float3 rayPos = _WorldSpaceCameraPos;
                 //相机到每个像素的世界方向
                 float3 worldViewDir = normalize(worldPos.xyz - rayPos.xyz) ;            
                 
                Light mainLight = GetMainLight();
                float3 dirToLight = mainLight.direction;
               
                float depthEyeLinear = length(worldPos.xyz - _WorldSpaceCameraPos);  
                //=========================================
                //容器中计算云体积包围盒
                //=========================================
                /*
                float2 rayToContainerInfo = rayBoxDst(_boundsMin, _boundsMax, rayPos, (1 / worldViewDir));
                float dstToBox = rayToContainerInfo.x; //相机到容器的距离
                float dstInsideBox = rayToContainerInfo.y; //返回光线是否在容器中，若为0则在内，不为零则为在内部的路程长度
                //内部路程：物体深度 - volume深度，大于零，雾可见；这里跟 光线是否在容器中 取最小，过滤掉一些无效值
                float dstLimit = min(depthEyeLinear - dstToBox, dstInsideBox);
                //视线进入到volume时的世界坐标
                float3 entryPoint = rayPos + worldViewDir * dstToBox;  
                */
                //=========================================
                //球面上计算云包围球
                //=========================================
                 float2 rayToContainerInfo = RayCloudLayerDst(1500,4000,rayPos,worldViewDir,true);
                 float dstToBox = rayToContainerInfo.x;
                 float dstInsideBox = length(worldViewDir * rayToContainerInfo.y-worldViewDir);
                 float dstLimit = min(depthEyeLinear - dstToBox, dstInsideBox);
                  float3 entryPoint;
                 if(dstToBox<0.1) entryPoint = rayPos;
                 else entryPoint = rayPos + worldViewDir * dstToBox;  
                 //*全天空纹理映射
                 /*
                if(dstLimit < 0) return color;
                float cur = sampleDensity(entryPoint);
                return half4(cur*half3(1,1,1),1);
                 
                 */
                float cosAngle = dot(worldViewDir, dirToLight);
                float3 phaseVal = phase(cosAngle);
               
                float sumDensity = 1;
                float3 lightEnergy = 0;
                const float sizeLoop = 12;
                //指数加速采样，当前光线在云内的距离增长
                //float stepSize = exp(_step)*_rayStep;
               
                 float dstTravelled = 0;
                 //*先把接近地平线的直接扣掉
                 if (worldViewDir.y<0.1) return color;
                 for (int j = 0; j <sizeLoop; j++)
                {
                    //当前点是否还在云中
                     if(dstLimit-dstTravelled>0.01 )
                       { 
                           //在volume内当前的marching的位置
                           rayPos = entryPoint + (worldViewDir * dstTravelled);
                           //当前点雾密度
                           float density = sampleDensity(rayPos);
                            if (density > 0)
                           {
                               float3 lightTransmittance = lightmarch(rayPos, dstTravelled);
                               //lightEnergy += density * _rayStep * sumDensity * lightTransmittance * phaseVal;
                                lightEnergy +=phaseVal*lightTransmittance *  density * _rayStep * sumDensity;
                               //
                               sumDensity *= exp(-density * _rayStep );
                            if (sumDensity < 0.01)
                               break;
                            }
                           // if (density > 0)
                           // {
                           //    float3 lightTransmittance = lightmarch(rayPos, dstTravelled);                              
                           //    float3 s = RayleighCoefficient(rayPos.y)*phaseVal+MieCoefficient(rayPos.y);
                           //    float t2 = exp(-sumDensity);
                           
                           //  lightEnergy =lightTransmittance;
                           //   if (t2 < 0.01)
                           //       break;
                           //  }
                            //sumDensity+=density * _rayStep;
                        }
                        else break;
                         dstTravelled += _rayStep;
                         
           
                 }
                 
                 if (sumDensity> 0.9)
                { return color;}
                 else  {
                     half3 whiteOverlay = lerp(color.rgb+lightEnergy,color.rgb, sumDensity);
                         return half4(whiteOverlay, color.a);  // 保持原有 alpha
                     }
 
                 //return color + half4(cloud*half3(1,1,1),1);
                
                   
                
            }
            ENDHLSL
        }
    }
}