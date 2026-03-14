Shader "holographic/StencilMask"
{
    Properties
    {
        [IntRange]_StencilReference ("Stencil Ref", Range(0,255)) = 1//[IntRange]属性修饰符
    }
    SubShader
    {
        Tags { 
            "RenderType"="Opaque"
            "Queue" = "Geometry"
            "RenderPipeline" = "universalPipeline"
        
        
        
        }
        LOD 100

        Pass
        {
            Stencil{
                Ref[_StencilReference]
                Comp Always
                //stencil buffer 默认是0
               
                Pass Replace//模板检测通过后进行何种操作
                Fail Keep//失败则保留模板缓冲区的值
                }
            Zwrite Off//渲染mask后的obj
            ColorMask 0
            tags{
                "LightMode" = "UniversalForward"
                }
        }

    }
    Fallback off
}
