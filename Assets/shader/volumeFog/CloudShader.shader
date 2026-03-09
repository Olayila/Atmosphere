Shader "PostProcessing/Cloud"
{
    Properties
    {
        [KeywordEnum(Volumetric, Atmospheric)]
        _CloudMode ("Cloud Mode", Float) = 0
        _TransmittanceLut ("Transmittance LUT", 2D) = "white" {}
        _lightAbsorptionTowardSun("absorbtion", Float) = 1.0
        _Stride("Stride of One Step", Float) = 1.0
        _BaseSpeed("Base Speed", Float) = 1.0

        [Header(Cloud Settings)]
        _DensityMultiplier ("Density Multiplier", Float) = 1.0
        _HeightMin ("Cloud Height Min", Range(1500.0, 2500.0)) = 1500.0
        _HeightMax ("Cloud Height Max", Range(2500.0, 4000.0)) = 2500.0
        _DarknessThreshold ("Darkness Threshold", Float) = 0.001

        [Header(Color  Lighting)]
         _ColA ("Color A (Tint)", Color) = (1,1,1,1)
         _ColB ("Color B (Tint)", Color) = (0.5,0.5,0.5,1)    
        _ColorOffset1 ("Color Offset 1", Float) = 0.0
        _ColorOffset2 ("Color Offset 2", Float) = 0.0

        [Header(2D Textures)]
        _WeatherMap ("Weather Map(2D)", 2D) = "white" {}     
        _WeatherFactor ("Weather Factor", Range(0.0, 1.0)) = 0.5

        _BlueNoise ("Blue Noise (2D)", 2D) = "white" {}
        _BlueNoiseEffect ("Blue Noise Effect", Range(0.0, 250.0)) = 1.0

        [Header(Shape Textures)]
        [Tooltip(Shape Noise Texture (3D))]
        _ShapeNoise ("Shape Noise", 3D) = "white" {}

        [KeywordEnum(NoSDF,UseSDF)]
        _SDFMode ("NoSDF Mode", Float) = 0

        [HideInInspector]_ShapeNoiseTiling ("基础形状纹理平铺", Range(0.1, 5)) = 1//参考
        _ShapeOffset("Shape Offset", Float) = 1.0

        [Tooltip(Detail Noise Texture (3D))]
        _DetailShapeTex ("Detail Noise", 3D) = "white" {}
        [HideInInspector]_DetailShapeTexTiling ("细节形状纹理平铺", Range(0.1, 3)) = 1
        _DetialWeight ("Detail Noise Sharpness", Range(0.0, 10.0)) = 1.0
        _DetailNoiseWeight("Detail Noise Weight", Range(0.0, 1.0)) = 1.0
    }
    SubShader
    {

        Tags 
        { 
            "RenderType" = "Opaque"
            "RenderPipeline" = "UniversalPipeline"
            //"Queue" = "Transparent+100"
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

             
             #define EPS 0.001
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
            int _Width;
            int _Height;
            int _FrameCount;
            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);
            //蓝噪音
            TEXTURE2D(_BlueNoise);
            SAMPLER(sampler_BlueNoiseTex); 
            float4 _BlueNoise_ST;
            //float2 _BlueNoiseTexUV;
            float _BlueNoiseEffect;



            float _BlendMultiply;
            float4 _Color;
            float4 _PhaseParams;//天空透射系数
            // float4 _ShapeNoiseWeights;//shapeNoiseWeights暂用0.5, 0.25, 0.125
            float _DetialWeight; 
            float _DetailNoiseWeight;
            float _WeatherFactor;
            float _BaseSpeed;

            float4x4 _InverseProjectionMatrix;//从cam到clip的逆
            float4x4 _InverseViewMatrix;//从cam到world
           
            float4x4 _InverseCamToWorldMatrix;
            
            float4x4 _InversePrevProjMatrix;
            

            float3 _boundsMin;
            float3 _boundsMax;

           
            float _HeightMin;
            float _HeightMax;
            float _DensityMultiplier;
            float _ShapeOffset;
            float _Stride;
            float _DarknessThreshold;
            float4 _ColA;
            float4 _ColB;
            float _ColorOffset1;
            float _ColorOffset2;
            float _lightAbsorptionTowardSun;
            //float _lightAbsorptionThroughCloud;

            TEXTURE3D(_ShapeNoise);
            float4 _ShapeNoise_ST;
            TEXTURE3D(_DetailShapeTex);
            SAMPLER(sampler_ShapeNoise);
            float _texScale;

            TEXTURE2D(_TransmittanceLut);
            TEXTURE2D(_WeatherMap);     
            SAMPLER(samplerLinearClamp);  
            SAMPLER(samplerLinearRepeat);  

            //GradientNoise shadergraph中的生成逻辑
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

            //分帧渲染时的顺序索引
            int GetIndex(float2 uv, int width, int height, int iterationCount)
            {
                
                int FrameOrder_2x2[] = {
                    0, 2, 3, 1
                };
                int FrameOrder_4x4[] = {
                    0, 8, 2, 10,
                    12, 4, 14, 6,
                    3, 11, 1, 9,
                    15, 7, 13, 5
                };
    
                int x = floor(uv.x * width / 8) % iterationCount;
                int y = floor(uv.y * height / 8) % iterationCount;
                int index = x + y * iterationCount;
    
                if (iterationCount == 2)
                {
                    index = FrameOrder_2x2[index];
                }
                if(iterationCount == 4)
                {
                    index = FrameOrder_4x4[index];
                }
                return index;
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

             //根据当前像素对应的世界坐标获取其前一帧uv，方便复用
             float2 GetPrevUVFromWorldPos(float3 worldPos)
            {               
                float4 prevViewPos = mul(_InverseCamToWorldMatrix,  float4(worldPos.xyz, 1));
                float4 prevClipPos = mul(_InversePrevProjMatrix, prevViewPos);
               
                float3 ndc = prevClipPos.xyz / prevClipPos.w;
               
                float2 prevUV = ndc.xy * 0.5 + 0.5;
                return prevUV;
            }

            float InterleavedGradientNoise(float2 uv) 
            {
                float3 m = float3(0.06711056f, 0.00583715f, 52.9829189f);
                uv = floor(uv);
                return frac(m.z * frac(dot(uv.xy + _Time.y * float2(17.3, 59.7), m.xy)));  // 加 temporal 偏移
                // 或用 frame index: frac(m.z * frac(dot(uv + frame * float2(113.0, 17.0), m.xy)))
            }


            //求点与球面交点，大于0有交点，小于0无交点
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
            //求视线与云层上下边界、地球表面的交点，返回float2（与内层交点，与外层交点），都为0则与地面相交
            float2 RayCloudLayerDst(float heightMin, float heightMax, float3 eyePos, float3 rayDir, bool isShape = true)
            {
                float3 origin = float3(0,_PLANETRADIUS+eyePos.y,0);
                float innerDst = RayIntersectSphere(origin, rayDir, float3(0,0,0),_PLANETRADIUS+heightMin);
                float outerDst = RayIntersectSphere(origin, rayDir, float3(0,0,0),_PLANETRADIUS+heightMax);
                float landDst =  RayIntersectSphere(origin, rayDir, float3(0,0,0),_PLANETRADIUS);
                float2 dstInfo = float2(0,0);
                if (outerDst > 0.0)
                {
                    if (innerDst > 0.0)
                    {
                        // 内外都有交点 → 取两个正值中最小的作为进入点
                        if (landDst>0&&landDst<innerDst){
                            dstInfo = float2(0.0, 0.0);
                            }
                        else{dstInfo = float2(min(innerDst, outerDst), max(innerDst, outerDst));}
                    }
                    else
                    {
                        // 只有外层交点 → 从相机到外层
                        dstInfo = float2(0.0, outerDst);
                    }
                }
      
                 return dstInfo;                
            }
            //获取透射率辅助函数
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
            //根据视线方向求uv，待优化
            float2 ViewToUV(float3 viewDir)
            {                
                float2 uv = float2(atan2(viewDir.z, viewDir.x), acos(viewDir.y));
                uv /= float2(2.0 * PI, PI);
                uv += float2(0.5, 0);
                return uv; 
            }


            //获取当前点的透射率
            float3 TransmittanceToAtmosphere(float3 p, float3 dir)
            {
                //采样图单位以km，故该部分有单位转换
                float bottomRadius =63600;
                float topRadius = 63680;
    
                float3 upVector = normalize(p);
                float cos_theta = dot(upVector, dir);
                float r = length(p) * 1e-3;
    
                float2 uv = GetTransmittanceLutUv(bottomRadius, topRadius, cos_theta, r);
                return SAMPLE_TEXTURE2D_X(_TransmittanceLut, samplerLinearClamp,  uv);
    
            }
            /*
            //debuggingfunction
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
            */
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

            float3 GetCenteredUVW(float3 samplePos, float3 boundsCentre, float3 boundsSize)
            {                
                float3 localPos = samplePos - boundsCentre;

                float3 norm = localPos / (boundsSize * 0.5f);               
                float3 uvw = norm * 0.5f + 0.5f;
                if (any(uvw < 0.0) || any(uvw > 1.0))
                {
                  
                    return float3(0,0,0);   // 或 clip(-1);
                }

                return uvw;
            }


            //==============================================================================================================================
            //采样Texture
            //==============================================================================================================================
            float2 sampleDensity(float3 rayPos) 
            {
                 float speedShape = _Time.y * 0.01;
            #if _CLOUDMODE_VOLUMETRIC
                float3 boundsCentre = (_boundsMax + _boundsMin) * 0.5;
                float3 size = _boundsMax - _boundsMin;
                float2 uv = (size.xz * 0.5f + (rayPos.xz - boundsCentre.xz) ) /max(size.x,size.z);
                #if _SDFMODE_NOSDF
                    //float3 uvw = rayPos  * _ShapeNoise_ST.x*EPS;
                    //float3 uvw = GetCenteredUVW(rayPos, boundsCentre, size);
                    float3 uvw =float3 (uv, (size.y* 0.5 + rayPos.y-boundsCentre.y)/size.y);
                     //边缘衰减
                    const float containerEdgeFadeDst = 20;
                    float dstFromEdgeX = min(containerEdgeFadeDst, min(rayPos.x - _boundsMin.x, _boundsMax.x - rayPos.x));
                    float dstFromEdgeZ = min(containerEdgeFadeDst, min(rayPos.z - _boundsMin.z, _boundsMax.z - rayPos.z));
                    float edgeWeight = min(dstFromEdgeZ, dstFromEdgeX) / containerEdgeFadeDst;
                    float heightPercent = (rayPos.y - _boundsMin.y) / size.y;
                #elif _SDFMODE_USESDF
                    float3 uvw = float3 (uv, (size.y* 0.5 + rayPos.y-boundsCentre.y)/size.y);
                #endif                
            #elif _CLOUDMODE_ATMOSPHERIC   
                float heightPercent = (rayPos.y - _HeightMin) /( _HeightMax-_HeightMin+EPS);
                float2 uv = ViewToUV(normalize(rayPos-_WorldSpaceCameraPos));
                // float2 uv =float2( rayPos.xz*_ShapeNoise_ST.x*EPS);
                //float2 uv = float2(u,v);                
                // float3 uvw = rayPos  * _ShapeNoise_ST.x*EPS;
                float3 uvw = float3(uv.xy, heightPercent);
            #endif
                //采样天气2D纹理（r：g:b:a:）、云团形状纹理（3D）、细节纹理（3D）
                float4 weatherMap =  SAMPLE_TEXTURE2D_X(_WeatherMap, samplerLinearRepeat,  uv*_ShapeNoise_ST.x+speedShape.xx*_BaseSpeed);//
                float4 shapeNoise = SAMPLE_TEXTURE3D(_ShapeNoise, sampler_ShapeNoise, uvw*_ShapeNoise_ST.x+speedShape.xxx*_BaseSpeed);//
                float4 detailNoise =  SAMPLE_TEXTURE3D( _DetailShapeTex, sampler_ShapeNoise, uvw*_ShapeNoise_ST.x+speedShape.xxx*_BaseSpeed);//
            #if _SDFMODE_NOSDF
                float gMin = remap(weatherMap.x, 0, 1, 0.1, 0.6);
                float gMax = remap(weatherMap.x, 0, 1, gMin, 0.8);
                
                float heightGradient = saturate(remap(heightPercent, 0.0, gMin, 0, 1)) * saturate(remap(heightPercent, 1, gMax, 0, 1));
                float heightGradient2 = saturate(remap(heightPercent, 0.0, weatherMap.r, 1, 0)) * saturate(remap(heightPercent, 0.0, gMin, 0, 1));
                heightGradient = saturate(lerp(heightGradient, heightGradient2,_WeatherFactor));
            #endif
                //debug
                //return float2(heightGradient, 1);
            #if _CLOUDMODE_VOLUMETRIC
                #if _SDFMODE_NOSDF
                    heightGradient *= edgeWeight;
                #endif
            #endif
                //控制云整体形状的纹理,使用反转的perlin-worley叠加纹理，以及不同尺寸的纹理（gba中存储是不同尺寸的该纹理）控制云
                
            #if _SDFMODE_NOSDF
                float3 shapeNoiseWeights = float3(0.5, 0.25, 0.125);
                float3 normalizedShapeWeights = shapeNoiseWeights / dot(shapeNoiseWeights, 1);
                //float shapeFBM = dot(float3(1,1,1)-shapeNoise.rgb, normalizedShapeWeights) * heightGradient;
                float shapeFBM =( 1-shapeNoise.r)* heightGradient;
                //debug 显示shape形状
                //float shapeFBM = shapeNoise.r;
                float baseShapeDensity = shapeFBM + _ShapeOffset* 0.01;
                //return float2(baseShapeDensity,shapeNoise.g/(_ShapeNoise_ST.x*EPS));
                
                //在形状采样密度有值的位置增加细节
                if (baseShapeDensity > 0)
                {
                    float detailFBM = pow(detailNoise.a, _DetialWeight);
                    float oneMinusShape = 1 - baseShapeDensity;
                    float detailErodeWeight = oneMinusShape * oneMinusShape * oneMinusShape;
                    float cloudDensity = baseShapeDensity- detailFBM * detailErodeWeight *_DetailNoiseWeight; // *;
   
                   return float2(saturate(cloudDensity * abs(_DensityMultiplier)),1); //
                   // return float2(saturate(baseShapeDensity * abs(_DensityMultiplier)),shapeNoise.g/(_ShapeNoise_ST.x*EPS)); 
                }
                return 0;         
            #elif _SDFMODE_USESDF
                float cloudDensity = shapeNoise.r;
                return float2(saturate(cloudDensity * abs(_DensityMultiplier)),shapeNoise.g*size.x*(_ShapeNoise_ST.x));
            #endif
                       
            }
            //计算散射相关函数
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

            float3 Scattering(float3 p, float3 inDir, float3 outDir)
            {
                float cos_theta = dot(inDir, outDir);
                float h = p.y + 1500;
                float3 rayleigh = RayleighCoefficient(h);             
                float3 mie = MieCoefficient(h) ;            
                return rayleigh + mie;
            }

            //===========================================================================================================================
            //内部对光步进
            //===========================================================================================================================
            float3 lightmarch(float3 position ,float dstTravelled)
            {
                Light mainLight = GetMainLight();
                float3 dirToLight = mainLight.direction;
                //体积云内点向太阳步进到体积边界的距离
            #if _CLOUDMODE_VOLUMETRIC 
               float dstInsideBox = rayBoxDst(_boundsMin, _boundsMax, position, 1 / dirToLight).y;
            #elif _CLOUDMODE_ATMOSPHERIC
               float2 rayToContainerInfo = RayCloudLayerDst(_HeightMin,_HeightMax,position,dirToLight,true);               
               float dstInsideBox = rayToContainerInfo.y;
            #endif
               float stepSize = dstInsideBox / 8;
               float totalDensity = 0;
               float currentDist = stepSize;
               //累计密度值
               for (int step = 0; step < 8; step++)
               {
                    position += dirToLight * stepSize; //向灯光步进   
                    //获取云密度值
                    float2 densitySample = sampleDensity(position) * stepSize;
                    totalDensity += max(0,densitySample .x);                     
               }
               //float3 lightTransmittance = TransmittanceToAtmosphere(float3(position.x,position.y+6360000.0,position.z) ,dirToLight);
               float transmittance_t1 = exp(-totalDensity * _lightAbsorptionTowardSun);
               //float3 transmittance_t1 = exp(-totalDensity )*lightTransmittance;
               //将重亮到暗映射为 3段颜色 ,亮->灯光颜色 中->ColorA 暗->ColorB
               //return lightTransmittance;
               // return transmittance_t1* mainLight.color;
               float3 cloudColor = lerp(_ColA.xyz, mainLight.color, saturate(transmittance_t1 * _ColorOffset1));
               cloudColor = lerp(_ColB.xyz, cloudColor, saturate(pow(transmittance_t1 * _ColorOffset2, 3)));
               return _DarknessThreshold + transmittance_t1 * (1 - _DarknessThreshold) * cloudColor;//
            }
 
 

        ENDHLSL
        Pass
        {
             Name "ColorTint"
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag
            #pragma shader_feature _CLOUDMODE_VOLUMETRIC _CLOUDMODE_ATMOSPHERIC
            #pragma shader_feature _SDFMODE_NOSDF _SDFMODE_USESDF
            #pragma multi_compile _OFF _2X2 _4X4
            #pragma multi_compile _ SCENE_DENSE_CLOUD SCENE_THIN_MIST SCENE_OCEAN SCENE_SIMPLE
            half4 Frag(Varyings input) : SV_Target
            {
                 
                    
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
                float2 uv = input.texcoord; 
                half4 color = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_BlitTexture, uv);
                float depth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, sampler_CameraDepthTexture, uv);
                float4 worldPos = GetWorldSpacePosition(depth, uv);
                float3 rayPos = _WorldSpaceCameraPos;                
                float3 worldViewDir = normalize(worldPos.xyz - rayPos.xyz) ;        
                
            #if _CLOUDMODE_ATMOSPHERIC
                if(depth >0.001) return color;
            #endif
            #ifndef _OFF              
                float2 prevUV = GetPrevUVFromWorldPos(worldPos);         
                half4 prevColor = SAMPLE_TEXTURE2D_X(_MainTex, sampler_MainTex, prevUV);
       
                //分帧渲染部分
                int iterationCount = 4;
                int frameOrder = GetIndex(uv, _Width, _Height, iterationCount);
                //debug 结果为不同灰度的棋盘格，4*4一组
                // return half4((frameOrder / 15.0).xxx, 0);
                if (frameOrder != _FrameCount)  return prevColor;             
            #ifdef _2X2                        
            #endif
            #endif             
                Light mainLight = GetMainLight();
                float3 dirToLight = mainLight.direction;               
                float depthEyeLinear = length(worldPos.xyz - _WorldSpaceCameraPos);  
                
            #if _CLOUDMODE_VOLUMETRIC
            //=========================================
            //容器中计算云体积包围盒
            //=========================================
                float2 rayToContainerInfo = rayBoxDst(_boundsMin, _boundsMax, rayPos, (1 / worldViewDir));
                float dstToBox = rayToContainerInfo.x; //相机到容器的距离
                float dstInsideBox = rayToContainerInfo.y; //返回光线是否在容器中，若为0则在内，不为零则为在内部的路程长度
                //内部路程：物体深度 - volume深度，大于零，雾可见；这里跟 光线是否在容器中 取最小，过滤掉一些无效值
                float dstLimit = min(depthEyeLinear - dstToBox, dstInsideBox);
                //视线进入到volume时的世界坐标
                float3 entryPoint = rayPos + worldViewDir * dstToBox;  
            #elif _CLOUDMODE_ATMOSPHERIC
            //=========================================
            //球面上计算云包围球
            //=========================================
                
                 float2 rayToContainerInfo = RayCloudLayerDst(_HeightMin,_HeightMax,rayPos,worldViewDir,true);
                 float dstToBox = rayToContainerInfo.x;
                 float dstInsideBox = length(worldViewDir * rayToContainerInfo.y-worldViewDir);
                 float dstLimit = min(depthEyeLinear - dstToBox, dstInsideBox);
                 if (dstLimit <= 0.0) return color;
                  float3 entryPoint;
                 if(dstToBox<0.1) entryPoint = rayPos;
                 else entryPoint = rayPos + worldViewDir * dstToBox; 
                 //if (entryPoint.y<-0.1) return color;
            #endif

                float cosAngle = dot(worldViewDir, dirToLight);
                float phaseVal = phase(cosAngle);
               
                float sumDensity = 1;
                float3 lightEnergy = 0;
            #if _CLOUDMODE_VOLUMETRIC
                const float sizeLoop = 24;
            #elif _CLOUDMODE_ATMOSPHERIC
                  const float sizeLoop = 16;
            #endif
                float density = 0;
                //控制步进步幅相关参数
                float prevDensity = 0;
                int densityZeroCount = 0;
                float3 opticalDepth = float3(0, 0, 0);
                //指数加速采样，当前光线在云内的距离增长
                //float stepSize = exp(_step)*_rayStep;
                float3 boundsCentre = (_boundsMax + _boundsMin) * 0.5;
                float3 size = _boundsMax - _boundsMin;
                float2 uvblue = (size.xz * 0.5f + (entryPoint.xz - boundsCentre.xz) ) /max(size.x,size.z);
                //float noise = InterleavedGradientNoise(uv);
                half blueNoise = SAMPLE_TEXTURE2D(_BlueNoise, samplerLinearRepeat, uv *_BlueNoise_ST.xy+_BlueNoise_ST.zw).r;

                float gradientNoise = unity_gradientNoise(uv * _BlueNoise_ST.xy+_BlueNoise_ST.zw) + 0.5;

                //float dstTravelled =fmod(blueNoise*_BlueNoiseEffect,dstLimit);
                float dstTravelled =gradientNoise*_BlueNoiseEffect*_Stride;
                //增加参数，按距离将步子分为8分
                float maxStride = _Stride*10;
                float currentStride = _Stride;
                //*先把接近地平线的直接扣掉
                 
                for (int j = 0; j <sizeLoop; j++)
                {          

                    //当前点是否还在云中
                    if(dstLimit-dstTravelled>0.01 )
                    { 
                        //步进到达的位置
                        rayPos = entryPoint + (worldViewDir * dstTravelled);
                        float2 densitySample =  sampleDensity(rayPos);
                        density =densitySample.x;
                        //判断当前采样值是否为0，不为零则正常采样，为0，则计数+1，步长为2倍
                      
                        //densitySample的rgb通道分别存储大中小三个形状图纹理
                        if (density > 0)
                        {
                       
                            densityZeroCount = 0;
                            currentStride = _Stride;                        
                        
                            //float3 s = Scattering(rayPos, dirToLight, worldViewDir);                            
                            float3 lightTransmittance_t1 = lightmarch(rayPos, dstTravelled); //类似t2
                            sumDensity *= exp(-density * _Stride );
                            lightEnergy +=phaseVal * lightTransmittance_t1* _Stride *  density * sumDensity * 2;// 
                               
                            if (sumDensity < 0.01)  break;
                        }
                        else
                        {
                        #if _CLOUDMODE_ATMOSPHERIC
                            densityZeroCount ++;
                            currentStride = max(currentStride *2,maxStride);
                       
                        #elif _CLOUDMODE_VOLUMETRIC
                           #if _SDFMODE_USESDF  
                                if (densitySample.y>0)
                                {
                                    currentStride = densitySample.y; 
                                }
                                else  currentStride = _Stride;  
                            #endif    
                        #endif
                        }
                        dstTravelled += currentStride;
                    }
                    else break;
                 } 
                 //debug show steps count
                 //return half4((j-1) * half3(1,1,1)/24,1);
                 return color*sumDensity+half4(lightEnergy,1);     
            }
            ENDHLSL
        }
    }
}

                         