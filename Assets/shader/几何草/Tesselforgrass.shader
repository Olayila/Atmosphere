// MIT License

// Copyright (c) 2021 NedMakesGames

// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files(the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and / or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions :

// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.

// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

// This is a shader that demonstrates tessellation factors and partitioning modes

//以上为tessellation部分的版权声明，主要控制曲面细分的着色器
//在此基础上增加草地绘制的几何着色器

Shader "Tessellation/Grass" {
    Properties{

        _BaseMap("BaseMap", 2D) = "blue" {}
        
        _TessellationFactor ("Tessellation Factor", Vector) = (1, 1, 1, 0) // 细分因子
        //草地部分
        [MainColor] _MainColor ("Map Color", Color) = (1,1,1,1)         // [MainColor] 标记为主颜色属性，影响非草叶区域的颜色，RGBA 格式
        _TopColor("Top Color", Color) = (1,1,1,1)                   // 草叶顶部的颜色，用于实现从底部到顶部的渐变效果
        _BottomColor("Bottom Color", Color) = (1,1,1,1)                 // 草叶底部的颜色，配合 TopColor 实现垂直渐变
        _BendRotationRandom("Bend Rdm Factor", Range(0, 2)) = 0.2      // 控制草叶弯曲角度的随机范围（弧度），通过随机旋转矩阵应用，增加自然感
        _grassHeight("Grass Height", Range(0.1, 5)) = 1                   // 草叶总高度（单位：Unity 世界单位），影响几何体生成长度
        _grassHeightRandom("Height Rdm Factor", Range(0.001, 1)) = 0.1  // 草高度的随机扰动幅度，基于伪随机函数，增强多样性
        _grassWidth("Grass Width", Range(0.05, 2)) = 0.1                 // 草叶宽度（单位：Unity 世界单位），定义几何体的横向跨度
        _grassWidthRandom("Width Rdm Factor", Range(0.001, 1)) = 0.1   // 草宽度的随机扰动幅度，增加视觉上的不规则性
        //_TessPhongStrength("Phong细分强度", Range(0, 1)) = 0.5      // Phong 细分中的插值权重，0 表示无插值，1 表示完全沿法线平滑，优化曲面细节
        _WindDistortionMap("Wind Distortion Noise", 2D) = "white" {}             // 2D 纹理控制风向和强度，白色表示无风，UV 映射到世界空间
        _WindFrequency("Wind Frequency", Vector) = (0.05, 0.05, 0, 0)     // 风力变化频率向量，x/y 控制空间频率，z/w 保留，影响风的周期性
        _WindStrength("Wind Strength", float) = 0.1                      // 风力对草叶变形的影响系数，放大风力贴图采样值
        _BladeForward("Bend forward", float) = 0.4                      // 草叶向前弯曲的偏移量，影响风力变形方向
        _BladeCurve("Bend Curve", Range(1, 4)) = 2                    // 弯曲的非线性指数，控制草叶从底部到顶部的弯曲形状，2 表示二次曲线
    
        //_Smooth ("Smooth", Range(0,1)) = 0.0
        //_DepthBias("Depth Bias", Float) = 0.5

        //_HeightMap("HeightMap", 2D) = "white" {}        
        //_Metallic("Metallic", Float) = 0.5
        //_DepthScale ("Depth Scale", Float) = 0.5       
        //_HeightMapAltitude("HeightMapAltitude", Range(0,1)) = 0.0
       
       //_objPos ("Object Position", Vector) = (1, 1, 1) // 缩放因子        
        //_TessellationBias ("Tessellation Bias", Float) = 0.0  // 偏移量
        // This keyword enum allows us to choose between partitioning modes. It's best to try them out for yourself
        [KeywordEnum(INTEGER, FRAC_EVEN, FRAC_ODD, POW2)] _PARTITIONING("Partition algoritm", Float) = 0}






    
    SubShader{
        Tags{"RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" 
        //"IgnoreProjector" = "True"//设置 "IgnoreProjector" = "True" 后，即使物体在 Projector 的影响范围内，也不会被投影材质覆盖。
        //"Queue" = "Transparent"//透明物体可开启
    }

        Pass {
            Name "ForwardLit"
            Tags{"LightMode" = "UniversalForward"}
             // 渲染状态设置
            ZWrite On                             // 开启深度写入，确保对象按距离正确遮挡
            Cull Off     //双面
            HLSLPROGRAM
            #pragma target 5.0 // 5.0 required for tessellation

            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            #pragma multi_compile_fog
            #pragma multi_compile_instancing

            // Material keywords
            #pragma shader_feature_local _PARTITIONING_INTEGER _PARTITIONING_FRAC_EVEN _PARTITIONING_FRAC_ODD _PARTITIONING_POW2

            #pragma vertex Vertex
            #pragma hull Hull
            #pragma domain Domain
            #pragma fragment Fragment

            #pragma geometry geo
            #pragma require tessellation tessHW
            #pragma require geometry
            #pragma multi_compile_instancing 


            #define BLADE_SEGMENTS 16

            //#include "TessellationFactors.hlsl"


            // MIT License



#ifndef TESSELLATION_FACTORS_INCLUDED
#define TESSELLATION_FACTORS_INCLUDED
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
//1. vertex shader结构体
struct Attributes
{
    float3 positionOS : POSITION;
    float3 normalOS : NORMAL;
    float4 tangentOS : TANGENT;
    float2 uv : TEXCOORD0;
    uint vertexID : TEXCOORD1;
    
    UNITY_VERTEX_INPUT_INSTANCE_ID
};
//2.hull function----patch constant funtion
struct TessellationFactors
{
    float edge[3] : SV_TessFactor;
    float inside : SV_InsideTessFactor;   
    //float3 bezierPoints[NUM_BEZIER_CONTROL_POINTS] : BEZIERPOS;
};
//2.hull function
struct TessellationControlPoint
{
    float4 positionCS : SV_POSITION;
    float3 positionWS : INTERNALTESSPOS;
    float3 normalWS : NORMAL;
    float4 tangentWS : TANGENT;
    float2 uv : TEXCOORD0;
    
    float2 uv2 : TEXCOORD1;
    UNITY_VERTEX_INPUT_INSTANCE_ID
};
 //3. domain function input
struct Interpolators
{
    float3 normalWS : TEXCOORD3;
    float3 positionWS : TEXCOORD1;
    float4 positionCS : SV_POSITION;
    float4 tangentWS : TEXCOORD2;
    float2 uv : TEXCOORD0;
    //float2 uv2 : TEXCOORD4;
    //float4 screenPos : TEXCOORD5;
    
    float3 viewDirWS : TEXCOORD4; // 视角方向向量
    float3 normal : NORMAL;
    float3 tangent : TANGENT;
    float2 windSample : TEXCOORD5;

    UNITY_VERTEX_INPUT_INSTANCE_ID
    UNITY_VERTEX_OUTPUT_STEREO

};
    
struct GeometryOutput
{
    float4 positionCS : SV_POSITION; // 裁剪空间位置
    float2 uv : TEXCOORD0; // UV 坐标
    float isNewTri : TEXCOORD1; // 标志位，区分地面和草叶
};  
/*struct Varyings
{
    float4 positionCS : SV_POSITION; // 顶点在裁剪空间的坐标，供光栅化使用
    float2 uv : TEXCOORD0; // UV 坐标，传递到片段着色器
    float3 positionWS : TEXCOORD1; // 世界空间位置，用于光照和风力计算
    float3 normalWS : TEXCOORD2; // 世界空间法线
    float3 viewDirWS : TEXCOORD3; // 视角方向向量
    float3 normal : NORMAL; // 法线，供后续扩展使用
    float3 tangent : TANGENT; // 切线，简单初始化
    float2 windSample : TEXCOORD4; // 风力采样值，从贴图获取
    UNITY_VERTEX_INPUT_INSTANCE_ID     // 实例化支持
};
    */

    
    

CBUFFER_START(UnityPerMaterial)
    
    float3 _TessellationFactor;        
        
    float _Smooth;
    float _metallic;
    float _HeightMapAltitude;
    
    float _DepthScale;
    float _DepthBias;
    
    
    float4 _BaseMap_TexelSize;
    float4 _HeightMap_TexelSize;
    
    TEXTURE2D_X(_CameraOpaqueTexture); // URP 自带
    SAMPLER(sampler_CameraOpaqueTexture);
    
    texture2D _BaseMap;
    SAMPLER(sampler_BaseMap);

    float3 _objPos; 
    texture2D _HeightMap;
    SAMPLER(sampler_HeightMap);        
    float4 _HeightMap_ST;
    float4 _BaseMap_ST;

    TEXTURE2D(_CameraDepthTexture);
    SAMPLER(sampler_CameraDepthTexture);



    //grass part 
    half4 _MainColor; // 主颜色，使用 half4 节省内存
    half4 _TopColor; // 顶部颜色
    half4 _BottomColor; // 底部颜色
    float _BendRotationRandom; // 草弯曲随机性
    float _grassHeight; // 草高度
    float _grassHeightRandom; // 草高度随机系数
    float _grassWidth; // 草宽度
    float _grassWidthRandom; // 草宽度随机系数
   // float _TessPhongStrength; // Phong 细分强度
    
    float2 _WindFrequency; // 风力频率
    float4 _WindDistortionMap_ST; // 风力贴图的 Tiling (xy) 和 Offset (zw)
    float _WindStrength; // 风力强度
    float _BladeForward; // 弯曲延伸
    float _BladeCurve; // 弯曲曲线
    UNITY_INSTANCING_BUFFER_START(Props)//properties name Props
        UNITY_DEFINE_INSTANCED_PROP(float, _InstanceGrassHeight) // 每实例草高度，动态设置
        UNITY_DEFINE_INSTANCED_PROP(float, _InstanceGrassWidth)  // 每实例草宽度
    UNITY_INSTANCING_BUFFER_END(Props)

    TEXTURE2D(_WindDistortionMap);         // 风力贴图纹理，存储风向和强度
    SAMPLER(sampler_WindDistortionMap);    // 采样器，定义纹理过滤和寻址模式
       
CBUFFER_END

    float3 GetViewDirectionFromPosition(float3 positionWS)
    {
        return normalize(GetCameraPositionWS() - positionWS);
    }

    float4 GetShadowCoord(float3 positionWS, float4 positionCS)
    {
    // Calculate the shadow coordinate depending on the type of shadows currently in use
        #if SHADOWS_SCREEN
            return ComputeScreenPos(positionCS);
        #else
                return TransformWorldToShadowCoord(positionWS);
        #endif
    }
    
    
    //1. vertex shader
    TessellationControlPoint Vertex(Attributes input)
    {
        TessellationControlPoint output;

        UNITY_SETUP_INSTANCE_ID(input);
        UNITY_TRANSFER_INSTANCE_ID(input, output);

        VertexPositionInputs posnInputs = GetVertexPositionInputs(input.positionOS);
        VertexNormalInputs normalInputs = GetVertexNormalInputs(input.normalOS);
        
        output.positionCS = posnInputs.positionCS;
        output.positionWS = posnInputs.positionWS;
        output.normalWS = normalInputs.normalWS;
        output.tangentWS = float4(TransformObjectToWorldDir(input.tangentOS.xyz), input.tangentOS.w); 
        output.uv = input.uv*_BaseMap_ST.xy + _BaseMap_ST.zw;
    
        float2 uv_heightTex = input.uv * _HeightMap_ST.xy + _HeightMap_ST.zw;
        output.uv2.x = _HeightMap.SampleLevel(sampler_HeightMap, uv_heightTex, 0).r;
        return output;
    }
    
    // Returns true if the point is outside the bounds set by lower and higher
    bool IsOutOfBounds(float3 p, float3 lower, float3 higher)
    {
        return p.x < lower.x || p.x > higher.x || p.y < lower.y || p.y > higher.y || p.z < lower.z || p.z > higher.z;
    }

// Returns true if the given vertex is outside the camera fustum and should be culled
    bool IsPointOutOfFrustum(float4 positionCS, float tolerance)
    {
        float3 culling = positionCS.xyz;
        float w = positionCS.w;
    // UNITY_RAW_FAR_CLIP_VALUE is either 0 or 1, depending on graphics API
    // Most use 0, however OpenGL uses 1
        float3 lowerBounds = float3(-w - tolerance, -w - tolerance, -w * UNITY_RAW_FAR_CLIP_VALUE - tolerance);
        float3 higherBounds = float3(w + tolerance, w + tolerance, w + tolerance);
        return IsOutOfBounds(culling, lowerBounds, higherBounds);
    }
    
    
    
    // Returns true if the points in this triangle are wound counter-clockwise
    bool ShouldBackFaceCull(float4 p0PositionCS, float4 p1PositionCS, float4 p2PositionCS, float tolerance)
    {
        float3 point0 = p0PositionCS.xyz / p0PositionCS.w;
        float3 point1 = p1PositionCS.xyz / p1PositionCS.w;
        float3 point2 = p2PositionCS.xyz / p2PositionCS.w;
        float3 normal = cross(point1 - point0, point2 - point0);
        #if UNITY_REVERSED_Z
            return cross(point1 - point0, point2 - point0).z < -tolerance;
        #else // In OpenGL, the test is reversed
        return cross(point1 - point0, point2 - point0).z > -tolerance;
        #endif
       //
        //return false;
    }
    
    bool ShouldClipPatch(float4 p0PositionCS, float4 p1PositionCS, float4 p2PositionCS)
    {
        bool allOutside = IsPointOutOfFrustum(p0PositionCS, _TessellationFactor.z) &&
        IsPointOutOfFrustum(p1PositionCS, _TessellationFactor.z) &&
        IsPointOutOfFrustum(p2PositionCS, _TessellationFactor.z);
        return allOutside || ShouldBackFaceCull(p0PositionCS, p1PositionCS, p2PositionCS, _TessellationFactor.z);
        return false;
    }
    //提前深度剔除
    bool ShouldClipFromDepth(float4 p0PositionCS, float4 p1PositionCS, float4 p2PositionCS){

        float4 clip0 = p0PositionCS;
        float4 clip1 = p1PositionCS;
        float4 clip2 = p2PositionCS;
    
        // 2. 转为 NDC 0~1 深度（和 _CameraDepthTexture 一致！）
        float depth0 = (clip0.z / clip0.w) * 0.5 + 0.5;
        float depth1 = (clip1.z / clip1.w) * 0.5 + 0.5;
        float depth2 = (clip2.z / clip2.w) * 0.5 + 0.5;
    
        // 3. 计算三角形中心屏幕 UV
        float3 centerClip = (clip0.xyz + clip1.xyz + clip2.xyz) / 3.0;
        float2 centerUV = centerClip.xy / centerClip.z * 0.5 + 0.5;
    
        // 4. 采样场景深度
        float sceneDepth01 = SAMPLE_TEXTURE2D_LOD(_CameraDepthTexture, sampler_CameraDepthTexture, centerUV, 0).r;
    
        // 5. 三个顶点都在场景深度之外？
        float threshold = 0.001;  // 防 Z-fighting
        bool isallBehind = (depth0 > sceneDepth01 + threshold) &&
                         (depth1 > sceneDepth01 + threshold) &&
                         (depth2 > sceneDepth01 + threshold);
        return isallBehind;

        }
    
    
    //
   // Calculate the tessellation factor for an edge
// This function needs the world and clip space positions of the connected vertices
// Calculate the tessellation factor for an edge
// This function needs the world and clip space positions of the connected vertices
    
        // Sample the height map, using mipmaps
    // float SampleHeight(float2 uv)
    // {
    //     return SAMPLE_TEXTURE2D(_HeightMap, sampler_HeightMap, uv).r;
    // }

float EdgeTessellationFactor(float scale, float bias, float3 p0PositionWS, float4 p0PositionCS, float3 p1PositionWS, float4 p1PositionCS)
{
        
    float length = distance(p0PositionWS, p1PositionWS);
    float distanceToCamera = distance(_objPos, (p0PositionWS + p1PositionWS) * 0.5);
    float factor = length / (scale * distanceToCamera * distanceToCamera);
    
    
    return max(1, factor + bias);        
}
  
[domain("tri")]

    //2.hull function----patch constant funtion
    // The patch constant function runs once per triangle, or "patch"
    // It runs in parallel to the hull function
    TessellationFactors PatchConstantFunction(
    InputPatch<TessellationControlPoint, 3> patch)
    {
        UNITY_SETUP_INSTANCE_ID(patch[0]); // Set up instancing
    // Calculate tessellation factors
        TessellationFactors f = (TessellationFactors) 0;
    
    
        // Check if this patch should be culled (it is out of view)
        if (ShouldClipPatch(patch[0].positionCS, patch[1].positionCS, patch[2].positionCS))
        {
            f.edge[0] = f.edge[1] = f.edge[2] = f.inside = 0; // Cull the patch
        }
        else
        {
            // if (ShouldClipFromDepth(patch[0].positionCS, patch[1].positionCS, patch[2].positionCS))
            // {
            //      f.edge[0] = f.edge[1] = f.edge[2] = f.inside = 0;
            // }
            // else{
                float h0 = abs(patch[0].uv2.x);
                float h1 = abs(patch[1].uv2.x);
                float h2 = abs(patch[2].uv2.x);         
                float diff = max(1.0, max(h0, max(h1,h2)) * 100.0f);
                
                f.edge[0] = EdgeTessellationFactor(_TessellationFactor.z, _TessellationFactor.y,
                patch[1].positionWS, patch[1].positionCS, patch[2].positionWS, patch[2].positionCS);
                f.edge[1] = EdgeTessellationFactor(_TessellationFactor.z, _TessellationFactor.y,
                patch[2].positionWS, patch[2].positionCS, patch[0].positionWS, patch[0].positionCS);
                f.edge[2] = EdgeTessellationFactor(_TessellationFactor.z, _TessellationFactor.y,
                patch[0].positionWS, patch[0].positionCS, patch[1].positionWS, patch[1].positionCS);
                f.inside = (f.edge[0] + f.edge[1] + f.edge[2]) / 3.0;
            // }
        
        
        
        //f.edge[0] = max(f.edge[0], diff);
        //f.edge[1] = max(f.edge[1], diff);
        //f.edge[2] = max(f.edge[2], diff);
        //f.inside = max(f.inside, diff);
    }
        return f;
        }

    
    
    // Calculate the tessellation factor for an edge
    
// The hull function runs once per vertex. You can use it to modify vertex
// data based on values in the entire triangle
    [domain("tri")] // Signal we're inputting triangles
    [outputcontrolpoints(3)] // Triangles have three points
    [outputtopology("triangle_cw")] // Signal we're outputting triangles
    [patchconstantfunc("PatchConstantFunction")] // Register the patch constant function
    // Select a partitioning mode based on keywords
    #if defined(_PARTITIONING_INTEGER)
    [partitioning("integer")]
    #elif defined(_PARTITIONING_FRAC_EVEN)
    [partitioning("fractional_even")]
    #elif defined(_PARTITIONING_FRAC_ODD)
    [partitioning("fractional_odd")]
    #elif defined(_PARTITIONING_POW2)
    [partitioning("pow2")]
    #else 
        [partitioning("fractional_odd")]
    #endif
    
    //2.hull function
    TessellationControlPoint Hull(
        InputPatch<TessellationControlPoint, 3> patch, // Input triangle
        uint id : SV_OutputControlPointID)
        { // Vertex index on the triangle

            return patch[id];
        }

    // Call this macro to interpolate between a triangle patch, passing the field name
    #define BARYCENTRIC_INTERPOLATE(fieldName) \
		patch[0].fieldName * barycentricCoordinates.x + \
		patch[1].fieldName * barycentricCoordinates.y + \
		patch[2].fieldName * barycentricCoordinates.z

    // Calculate Phong projection offset
    float3 PhongProjectedPosition(float3 flatPositionWS, float3 cornerPositionWS, float3 normalWS)
    {
        return flatPositionWS - dot(flatPositionWS - cornerPositionWS, normalWS) * normalWS;
    }
    
    // Apply Phong smoothing
float3 CalculatePhongPosition(float3 bary, float smoothing, float3 p0PositionWS, float3 p0NormalWS,
    float3 p1PositionWS, float3 p1NormalWS, float3 p2PositionWS, float3 p2NormalWS)
    {
        float3 flatPositionWS = bary.x * p0PositionWS + bary.y * p1PositionWS + bary.z * p2PositionWS;
        float3 smoothedPositionWS =
        bary.x * PhongProjectedPosition(flatPositionWS, p0PositionWS, p0NormalWS) +
        bary.y * PhongProjectedPosition(flatPositionWS, p1PositionWS, p1NormalWS) +
        bary.z * PhongProjectedPosition(flatPositionWS, p2PositionWS, p2NormalWS);
        return lerp(flatPositionWS, smoothedPositionWS, smoothing);
}
    
    
    
    
    
    //3.domain function
    // The domain function runs once per vertex in the final, tessellated mesh
    // Use it to reposition vertices and prepare for the fragment stage
    [domain("tri")] // Signal we're inputting triangles
    [partitioning("integer")]
    Interpolators Domain(
        TessellationFactors factors, // The output of the patch constant function
        OutputPatch<TessellationControlPoint, 3> patch, // The Input triangle
        float3 barycentricCoordinates : SV_DomainLocation)
        { // The barycentric coordinates of the vertex on the triangle

            Interpolators output;

        // Setup instancing and stereo support (for VR)
            UNITY_SETUP_INSTANCE_ID(patch[0]);
            UNITY_TRANSFER_INSTANCE_ID(patch[0], output);
            UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

            //float3 positionWS = BARYCENTRIC_INTERPOLATE(positionWS);
            float3 normalWS = normalize(BARYCENTRIC_INTERPOLATE(normalWS));
            float3 positionWS = CalculatePhongPosition(barycentricCoordinates,_Smooth,
            patch[0].positionWS, patch[0].normalWS,
            patch[1].positionWS, patch[1].normalWS,
            patch[2].positionWS, patch[2].normalWS);
        
            
            float3 tangentWS = normalize(BARYCENTRIC_INTERPOLATE(tangentWS.xyz));
            float tangentSign = BARYCENTRIC_INTERPOLATE(tangentWS.w);
            output.tangentWS = float4(tangentWS, tangentSign);
            output.uv = BARYCENTRIC_INTERPOLATE(uv) * _BaseMap_ST.xy + _BaseMap_ST.zw;

            //根据texture 确定风力部分            
             float2 noiseInput = positionWS.xz * 0.01;

            // 模拟风速起伏，增加自然感
            // windSpeedMultiplier 使用线性时间变化，范围 0.1 到 1.1
            float windSpeedMultiplier = (_Time.y * 0.5) * 0.5 + 0.6;

            // 计算风力 UV，结合贴图变换和噪声            
            float2 windUV = positionWS.xz * _WindDistortionMap_ST.xy + _WindDistortionMap_ST.zw + _WindFrequency * windSpeedMultiplier + noiseInput;
            output.windSample = (SAMPLE_TEXTURE2D_LOD(_WindDistortionMap, sampler_WindDistortionMap, windUV, 0).xy * 2
                                        - 1) * _WindStrength; // 采样风力贴图，归一化到 [-1, 1]
        
        
            output.positionCS = TransformWorldToHClip(positionWS);
            //output.screenPos = ComputeScreenPos(output.positionCS);
            output.viewDirWS = GetCameraPositionWS() - positionWS;
            output.normalWS = normalWS;
            output.positionWS = positionWS;
            output.tangentWS = float4(tangentWS, patch[0].tangentWS.w);
        
            return output;
        }

GeometryOutput VertexOutput(float3 pos, float2 uv, float isNewTri)
{
    GeometryOutput o;
    o.positionCS = TransformWorldToHClip(float4(pos, 1).xyz); // 应用投影矩阵
    o.uv = uv; // 传递 UV
    o.isNewTri = isNewTri; // 标记新三角形
    return o;
}
float rand(float3 co)
{
    return frac(sin(dot(co.xyz, float3(12.9898, 78.233, 53.539))) * 43758.5453);
                // dot(co, float3) 产生标量，sin 引入非线性，43758.5453 为放大因子
                // frac 取小数部分，范围 [0, 1]
}
// 角度轴旋转矩阵函数
            // AngleAxis3x3 根据欧拉角度和轴生成 3x3 旋转矩阵
float3x3 AngleAxis3x3(float angle, float3 axis)
{
    float c, s; // 余弦和正弦值
    sincos(angle, s, c); // HLSL 内置函数，计算 sin 和 cos
    float t = 1 - c; // 1 - cos，用于罗德里格斯公式
    float x = axis.x, y = axis.y, z = axis.z; // 轴向量分量
    return float3x3( // 构造旋转矩阵
                    t * x * x + c, t * x * y - s * z, t * x * z + s * y, // 第一行
                    t * x * y + s * z, t * y * y + c, t * y * z - s * x, // 第二行
                    t * x * z - s * y, t * y * z + s * x, t * z * z + c // 第三行
                    // 公式基于罗德里格斯旋转公式：R = I + sin(θ)K + (1 - cos(θ))K^2
                );
}

// Geometry Shader：生成草叶几何体
            // geo 使用三角形流生成草叶，BLADE_SEGMENTS 控制段数
[maxvertexcount(BLADE_SEGMENTS * 2 + 1)]
void geo(triangle Interpolators IN[3], inout TriangleStream<GeometryOutput> triStream)
{
    UNITY_SETUP_INSTANCE_ID(IN[0]); // 初始化实例 ID
                // 输出原始三角形，作为地面基面
    for (int i = 0; i < 3; ++i)
        triStream.Append(VertexOutput(IN[i].positionWS, IN[i].uv, 0));
    triStream.RestartStrip();

                // 获取基点位置和风力采样
    float3 basePos = IN[0].positionWS; // 草叶基点，地面位置
    float2 windSample = IN[0].windSample; // 从风力贴图采样值

                // 创建风力旋转矩阵，限制 y 轴影响
                // 仅沿 x 轴旋转，减少风力向下拉伸
    float3x3 windRotation = AngleAxis3x3(PI * windSample.x, float3(1, 0, 0));

                // 计算法线、切线和副切线
                // vNormal 确定草叶生长方向，基于世界空间法线
    float3 vNormal = IN[0].normalWS.y > 0 ? IN[0].normalWS : -IN[0].normalWS;
    float3 vTangent =  IN[0].tangentWS; // 简单切线，沿 x 轴
    float3 vBinormal = normalize(cross(vNormal, vTangent)); // 叉积生成副切线
    float3x3 tangentToWorld = float3x3(vTangent, vBinormal, vNormal); // 局部到世界变换

                // 生成面朝和弯曲旋转矩阵
                // facingRotationMatrix 基于随机角度旋转草叶方向
    float3x3 facingRotationMatrix = AngleAxis3x3(rand(basePos) * PI, float3(0, 0, 1));
                // bendRotationMatrix 基于随机性和 BendRotationRandom 控制弯曲
    float3x3 bendRotationMatrix = AngleAxis3x3(rand(basePos.zzx) * _BendRotationRandom * PI * 0.5,
                                                        float3(-1, 0, 0));
                // 组合变换矩阵
    float3x3 transformationMatrix = mul(mul(tangentToWorld, facingRotationMatrix),
                                                  mul(bendRotationMatrix, windRotation));

                // 获取实例化草高度和宽度
    float grassHeight = UNITY_ACCESS_INSTANCED_PROP(Props, _InstanceGrassHeight);
    float grassWidth = UNITY_ACCESS_INSTANCED_PROP(Props, _InstanceGrassWidth);
                // 应用随机高度，基于 rand 函数
    grassHeight = (grassHeight > 0
                             ? grassHeight
                             : (rand(basePos.xyz) * 2 - 1) * _grassHeightRandom + _grassHeight);
                // 应用随机宽度
    grassWidth = (grassWidth > 0
                            ? grassWidth
                            : (rand(basePos.xzy) * 2 - 1) * _grassWidthRandom + _grassWidth);

                // 计算弯曲延伸
    float forward = rand(basePos.yyz) * _BladeForward;

    // 草叶
    for (int j = 0; j < BLADE_SEGMENTS; j++)
    {
        float t = j / (float) BLADE_SEGMENTS; 
        float segmentHeight = grassHeight * t; 
        float segmentWidth = grassWidth * (1 - t); 

        // 计算弯曲偏移，限制向下
        float segmentForward = pow(t, _BladeCurve) * forward; // 幂函数控制弯曲形状
        segmentForward = max(0, segmentForward); // 限制为非负，防止向下穿透

        // 计算局部位置
        float3 localPos = float3(-segmentWidth, segmentHeight, segmentForward);
        float3 worldPos = basePos + mul(transformationMatrix, localPos); // 应用变换
        worldPos.y = max(basePos.y, worldPos.y); // 限制 y 坐标不低于地面

         // 输出左顶点
        triStream.Append(VertexOutput(worldPos, float2(0, t), 1));
        // 计算右顶点
        worldPos = basePos + mul(transformationMatrix, float3(segmentWidth, segmentHeight, segmentForward));
        worldPos.y = max(basePos.y, worldPos.y);
        triStream.Append(VertexOutput(worldPos, float2(1, t), 1));
    }

    triStream.RestartStrip(); // 结束当前条带，开始新几何体
}



    
    half4 Fragment(GeometryOutput input) : SV_Target
    {
    if (input.isNewTri > 0.5)                         // 判断是否为草叶三角形
        return lerp(_BottomColor, _TopColor, input.uv.y)* (1.0+SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv).y); // 沿 y 轴渐变，IN.uv.y 从 0 到 1
    else
        return SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv); // 返回主颜色，绘制地面

       
    } 
    
    

    #endif
           
            ENDHLSL
            // Blend SrcAlpha OneMinusSrcAlpha
            // ZWrite Off
        }
    }
}