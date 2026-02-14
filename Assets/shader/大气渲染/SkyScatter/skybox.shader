// Upgrade NOTE: replaced '_Object2World' with 'unity_ObjectToWorld'

Shader "Custom/SkyboxScatter"
{
    Properties
    {
        _SkyScatterTex("Sky Scatter Texture", 2D) = "white" {}
        _MoonTex("Moon Texture", 2D) = "white" {}
        _EyePos("Eye Position",Vector) = (0,0,1,0)
        _ViewDir("View Direction", Vector) =  (0,0,1,0)
        _LightDir("Light Direction", Vector) =  (0,0,1,0)


          [Header(Planet Info)]
        _SunLuminance("Sun Luminance", Color) = (1,0.87,0.87,1)
        _PlanetRadius("PlanetRadius",Float) = 6360000.0
        _AtmosphereHeight("AtmosphereHeight", Float) = 80000.0
        _transmittanceLut("_transmittanceLut",2D) = "white" {}
        _MoonFeather("Moon Feather",Float) = -32.4


    }
    SubShader
    {
        Tags { "Queue"="Background" "RenderType"="Background" }
        Cull Off
        ZWrite Off
        ZTest LEqual
        Fog { Mode Off }

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"

            sampler2D _SkyScatterTex;
            float4 _SkyScatterTex_TexelSize;
            SamplerState samplerLinearClamp;

            Texture2D    _MoonTex;                 // moon texture (high-res recommended)
            Texture2D    _transmittanceLut;        // transmittance LUT
            SamplerState samplerPointClamp;        // if needed (we use linear sampler below)

            // Properties (bound from Properties)
            float4 _EyePos;
            float4 _ViewDir;
            float4 _LightDir;
            float4 _MoonDir;

            float4 _SunLuminance;
            float4 _MoonLuminance;
            float _SunDiskAngle;   // degrees
            float _MoonDiskAngle;  // degrees
            float _MoonFeather;

            float _PlanetRadius;
            float _AtmosphereHeight;


            struct appdata
            {
                float4 vertex : POSITION;
            };

            struct v2f
            {
                float4 pos : SV_POSITION;
                float3 worldDir : TEXCOORD0;
            };


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

            float3 TransmittanceToAtmosphere(float3 p, float3 dir, Texture2D lut, SamplerState spl)
            {
                float bottomRadius = _PlanetRadius*1e-3;
                float topRadius = _PlanetRadius * 1e-3 + _AtmosphereHeight * 1e-3;
    
                float3 upVector = normalize(p);
                float cos_theta = dot(upVector, dir);
                float r = length(p);
    
                float2 uv = GetTransmittanceLutUv(bottomRadius, topRadius,cos_theta,r);
                return lut.SampleLevel(spl,uv,0).rgb;
    
            }

            float3 GetSunDisk(float3 eyePos, float3 viewDir,float3 lightDir)
            {
               float3 sunDir = normalize(lightDir);
                // Use cosine threshold to avoid acos
                float cosTheta = dot(viewDir, -sunDir); // viewDir aligns with -sunDir when looking at sun
                float cosRadius = cos(radians(_SunDiskAngle));
                // if not facing sun, skip quickly
                if (cosTheta < cosRadius) return float3(0,0,0);
    
    
                float disToPlanet = RayIntersectSphere(eyePos, viewDir, float3(0, 0, 0), _PlanetRadius);
                if (disToPlanet >= 0)
                    return float3(0, 0, 0);
    
                float disToAtmosphere = RayIntersectSphere(eyePos, viewDir, float3(0, 0, 0), _PlanetRadius + _AtmosphereHeight);
                if (disToAtmosphere < 0)
                    return float3(0, 0, 0);   
    
                float edgeSoftness = 0.02; // in degrees, adjust to taste
                float cosInner = cos(radians(max(0.0, _SunDiskAngle - edgeSoftness)));
                //float weight = smoothstep(cosRadius, cosInner, cosTheta);
                float3 trans = TransmittanceToAtmosphere(eyePos, viewDir, _transmittanceLut, samplerLinearClamp);
                float3 sunColor = 5.0 * trans ;
                   
                return sunColor;
                

            }



            float3 GetMoonDisk(float3 eyePos, float3 viewDir, float3 moonDir)
            {

               float cosine_theta = dot(viewDir, moonDir);
                float theta = acos(cosine_theta) * (180.0 /  UNITY_PI);
                float3 moonDirLuminace = _SunLuminance.rgb;
    
                float2 moonUV = 0.5.xx;

    
                float3 moonRight = normalize(cross(float3(0, 1, 0), moonDir));
                float3 moonUp = normalize(cross(moonDir, moonRight));

    
                float3 moonLocalDir = normalize(viewDir + moonDir);
                float offsetX = dot(moonLocalDir, moonRight) / sin(radians(_MoonDiskAngle));
                float offsetY = dot(moonLocalDir, moonUp) / sin(radians(_MoonDiskAngle));

   
                moonUV += float2(offsetX, offsetY) * 0.5;
                //moonUV = saturate(moonUV);
                //moonUV = moonUV*1.1;
    
                float3 moonColor = float3(0,0.8,1);
                moonColor = _MoonTex.SampleLevel(samplerLinearClamp, moonUV, 0).rgb;

    
   
                float disToPlanet = RayIntersectSphere(eyePos, viewDir, float3(0, 0, 0),  _PlanetRadius);
                if (disToPlanet >= 0)
                    return float3(0, 0, 0);
    
                float disToAtmosphere = RayIntersectSphere(eyePos, viewDir, float3(0, 0, 0),  _PlanetRadius + _AtmosphereHeight);
                if (disToAtmosphere < 0)
                    return float3(0, 0, 0);
    
                moonColor *= TransmittanceToAtmosphere(eyePos, viewDir, _transmittanceLut, samplerLinearClamp);

                 
                // if (theta < _MoonDiskAngle)
                // {
                //     if (theta >_MoonDiskAngle-0.0001) {
                //        return moonColor*lerp(0,1,(theta-_MoonDiskAngle+0.0001)/0.0001);
                //     }
                    
                // }
                   
                if (theta < _MoonDiskAngle+5) {
                    if(theta > _MoonDiskAngle)
                    return moonColor* lerp(0,1,(5-theta+_MoonDiskAngle)/5);
                    
                    return moonColor;}
                return float3(0, 0, 0);
            }

         
            float2 ViewDirToUV(float3 v)
            {
                float2 uv = float2(atan2(v.z, v.x), asin(v.y));
                uv /= float2(2.0 * UNITY_PI,UNITY_PI);
                uv += float2(0.5, 0.5);

                return uv;
            }




            v2f vert(appdata v)
            {
                v2f o;
                o.pos = UnityObjectToClipPos(v.vertex);
                // 计算方向向量
                o.worldDir = normalize(mul((float3x3)unity_ObjectToWorld, v.vertex.xyz));
                return o;
            }

            fixed4 frag(v2f i) : SV_Target
            {
                float3 dir = normalize(i.worldDir);
                // 将方向映射到 uv
                // float u = atan2(dir.x, dir.z) / (2.0 * UNITY_PI) + 0.5;
                // float v = asin(dir.y) / UNITY_PI + 0.5;
                float2 uvx = ViewDirToUV(dir);
                float4 col = tex2D(_SkyScatterTex, uvx);
                
                 float3 eyePos = _EyePos.xyz;

                // float3 dir1 = float3(dir.xy,-dir.z);

                // float angleRad = radians(90.0); 
                // float cosA = cos(angleRad);
                // float sinA = sin(angleRad);

                // float3 rotatedDir;
                // rotatedDir.x = cosA * dir1.x + sinA * dir1.z;
                // rotatedDir.y = dir1.y;
                // rotatedDir.z = -sinA * dir1.x + cosA * dir1.z;

                 float3 sunContrib =GetSunDisk(_EyePos,dir, -normalize(_LightDir.xyz));
                float3 moonContrib = GetMoonDisk(_EyePos,dir ,  -normalize(_LightDir.xyz));


                float3 finalLinear = col + sunContrib + moonContrib;

                // simple tonemapping (Reinhard)
                //finalLinear = finalLinear / (finalLinear + 1.0);

                // gamma correct to sRGB
               // finalLinear = pow(saturate(finalLinear), 1.0/2.2);

                return float4(finalLinear, 1.0);
               
            }
            ENDCG
        }
    }
    FallBack "Skybox/Procedural"
}
