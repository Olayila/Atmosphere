void MainLight_half(float3 WorldPos, out half3 Direction, out half3 Color, out half DistanceAtten, out half ShadowAtten)
{
#if SHADERGRAPH_PREVIEW
   Direction = half3(0.5, 0.5, 0);
   Color = 1;
   DistanceAtten = 1;
   ShadowAtten = 1;
#else
#if SHADOWS_SCREEN
   half4 clipPos = TransformWorldToHClip(WorldPos);
   half4 shadowCoord = ComputeScreenPos(clipPos);
#else
   half4 shadowCoord = TransformWorldToShadowCoord(WorldPos);
#endif
   Light mainLight = GetMainLight(shadowCoord);
   Direction = mainLight.direction;
   Color = mainLight.color;
   DistanceAtten = mainLight.distanceAttenuation;
   ShadowAtten = mainLight.shadowAttenuation;
#endif
}

#define PI 3.14159265358979323846

//法线分布项D
void DistributionGGX_float(float NdotH, float alpha, out float GGX)
{
    float a2 = alpha * alpha;
    float denom = (NdotH * NdotH) * (a2 - 1.0) + 1.0;
    GGX = a2 / (PI * denom * denom + 1e-6);
}
//几何遮蔽G
void GeometrySchlickGGX_float(float NdotV, float alpha, out float GeometrySchlick)
{
    float k = (alpha + 1) * (alpha + 1);
    GeometrySchlick = NdotV / (NdotV * (1.0 - k) + k + 1e-6);
}
/*
float GeometrySmith(float NdotV, float NdotL, float k)
{
    float ggx1 = GeometrySchlickGGX(NdotV, k);
    float ggx2 = GeometrySchlickGGX(NdotL, k);
    return ggx1 * ggx2;
}
*/
//菲涅尔项F
void FresnelSchlick_float(float VdotH, float3 F0, out float3 FresnelSchlick)
{
    FresnelSchlick = F0 + (1.0 - F0) * pow(1.0 - VdotH, 5.0);
}
/*
float3 GGX_Specular(float3 N, float3 V, float3 L, float roughness, float3 F0, float3 radiance)
{
    float3 H = normalize(V + L);
    float NdotH = saturate(dot(N, H));
    float NdotV = saturate(dot(N, V));
    float NdotL = saturate(dot(N, L));
    float VdotH = saturate(dot(V, H));

    // perceptual roughness -> alpha
    float alpha = max(0.001, roughness * roughness);

    float D = DistributionGGX(NdotH, alpha);

    // Schlick-GGX geometry factor (k)
    float k = (roughness + 1.0);
    k = (k * k) / 8.0; // UE/Disney style approximation

    float G = GeometrySmith(NdotV, NdotL, k);

    float3 F = FresnelSchlick(VdotH, F0);

    float3 numerator = D * G * F;
    float denom = max(4.0 * NdotV * NdotL, 1e-6);
    float3 spec = numerator / denom;

    // multiply by incoming light (radiance) and NdotL
    return spec * radiance * NdotL;
}
*/

//计算最终结果
void GGX_Specular_float(float3 WorldPos, float3 DFGresult, float NdotV, float NdotL, out
float3 result)
{
    
#if SHADERGRAPH_PREVIEW
        float3 lightColor = float3(1,1,1);  // 默认预览值
#else
    #if SHADOWS_SCREEN
                float4 clipPos = TransformWorldToHClip(WorldPos);
                float4 shadowCoord = ComputeScreenPos(clipPos);
    #else
        float4 shadowCoord = TransformWorldToShadowCoord(WorldPos);
    #endif
    Light mainLight = GetMainLight(shadowCoord);
    float3 lightColor = mainLight.color * mainLight.distanceAttenuation * mainLight.shadowAttenuation;
    #endif
    float denom = max(4.0 * NdotV * NdotL, 1e-6);
    float NdotLmax = saturate(NdotL);//防止背光面也计算反射
    result = NdotLmax * DFGresult / denom;

}


void CalculateAdditionalLightsDiffuse_float(
    float3 WorldPosition,
    float3 WorldNormal,    
    out float3 DiffuseOut)
{
    float3 N = normalize(WorldNormal);
    DiffuseOut = float3(0, 0, 0);

#if SHADERGRAPH_PREVIEW
    // Preview 模式使用虚拟光
    float3 L = normalize(float3(0.4, 0.6, 0.2));
    float NdotL = saturate(dot(N, L));
    DiffuseOut =  NdotL;
#else

    // 获取 Additional Light 数量
    uint lightCount = GetAdditionalLightsCount();

    for (uint i = 0; i < lightCount; i++)
    {
        // URP 自带距离衰减 + 阴影 + 色彩信息
        Light light = GetAdditionalLight(i, WorldPosition);

        // light.direction 已经是 normalized
        float NdotL = saturate(dot(N, light.direction));

        // 光照贡献 = 漫反射 * 光颜色 * 衰减 * 阴影
        float3 diffuse =  NdotL * light.color * light.distanceAttenuation * light.shadowAttenuation;

        DiffuseOut += diffuse;
    }

#endif
}




/*


void CalculateMultipleLights_float(
    float3 WorldPosition,
    float3 WorldNormal,
    float3 ViewDirection,
    float3 Albedo,
    float Metallic,
    float Roughness,
    out float3 FinalColor)
{
    FinalColor = float3(0, 0, 0);
    
    // 主方向光
 // ShaderGraph预览模式处理
    #if SHADERGRAPH_PREVIEW    
   
        float3 N = normalize(WorldNormal);
        float3 L = float3(0.5, 0.5, 0);
        float NdotL = max(dot(N, L), 0.0);        
   
        float3 diffuse = Albedo * NdotL;
        float3 specular = 0.04 * pow(max(dot(normalize(ViewDirection + L), N), 0.0), 32.0);
        
        FinalColor = diffuse + specular;
    
    
    #else
    
                // 主方向光
        float4 shadowCoord = TransformWorldToShadowCoord(WorldPosition);        
            Light mainLight = GetMainLight(shadowCoord);
        
    
        FinalColor += CalculatePBRContribution(mainLight, WorldPosition, WorldNormal, ViewDirection, Albedo, Metallic, Roughness);
    
        // 附加光源
        uint numAdditionalLights = GetAdditionalLightsCount();
    
    
        for (uint i = 0; i < numAdditionalLights; i++)
        {
        
                Light additionalLight = GetAdditionalLight(i, WorldPosition);
        
        
            FinalColor += CalculatePBRContribution(additionalLight, WorldPosition, WorldNormal, ViewDirection, Albedo, Metallic, Roughness);
        }
    #endif
}

// PBR光照计算函数
float3 CalculatePBRContribution(Light light, float3 WorldPosition, float3 WorldNormal, float3 ViewDirection, float3 Albedo, float Metallic, float Roughness)
{
    float3 L = light.direction;
    float3 N = normalize(WorldNormal);
    float3 V = normalize(ViewDirection);
    
    float NdotL = max(dot(N, L), 0.0);
    
    // 背光面直接返回0
    if (NdotL <= 0.0)
        return float3(0, 0, 0);
    
    // BRDF计算
    float3 brdf = CalculateBRDF(light, WorldPosition, N, V, Albedo, Metallic, Roughness);
    
    // 应用衰减和阴影
    float attenuation = light.distanceAttenuation * light.shadowAttenuation;
    
    return brdf * light.color * attenuation * NdotL;
}

// BRDF计算函数
float3 CalculateBRDF(Light light, float3 WorldPosition, float3 N, float3 V, float3 Albedo, float Metallic, float Roughness)
{
    float3 L = light.direction;
    float3 H = normalize(L + V);
    
    float NdotL = max(dot(N, L), 0.0);
    float NdotV = max(dot(N, V), 0.0);
    float NdotH = max(dot(N, H), 0.0);
    float LdotH = max(dot(L, H), 0.0);
    
    // 基础反射率
    float3 F0 = lerp(0.04, Albedo, Metallic);
    
    // 你的GGX Specular计算
    float3 specular = YourGGXSpecularFunction(NdotV, NdotL, NdotH, LdotH, Roughness, F0);
    
    // Disney漫反射
    float3 diffuse = Diffuse_Disney(Albedo, Roughness, NdotV, NdotL, LdotH) * (1.0 - Metallic);
    
    return diffuse + specular;
}

// Disney漫反射函数
float3 Diffuse_Disney(float3 albedo, float roughness, float NdotV, float NdotL, float LdotH)
{
    float energyBias = lerp(0.0, 0.5, roughness);
    float energyFactor = lerp(1.0, 1.0 / 1.51, roughness);
    float fd90 = energyBias + 2.0 * LdotH * LdotH * roughness;
    
    float lightScatter = 1.0 + (fd90 - 1.0) * pow(1.0 - NdotL, 5.0);
    float viewScatter = 1.0 + (fd90 - 1.0) * pow(1.0 - NdotV, 5.0);
    
    return albedo * (lightScatter * viewScatter * energyFactor / PI);
}
float3 GetAdditionalLightPosition(int index)
{
#if defined(_ADDITIONAL_LIGHTS)
    return _AdditionalLightsPosition[index].xyz;
#else
    return float3(0, 0, 0);
#endif
}
*/