Shader "Unlit/GlowUnlitShader"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        
        // 发光参数
        [Header(Glow Settings)]
        _GlowColor ("Glow Color", Color) = (1,1,1,1)           // 发光颜色（通常白色或偏色）
        _GlowIntensity ("Glow Intensity", Range(0, 5)) = 1.5   // 发光强度
        _GlowThresholdR ("R Threshold", Range(0,1)) = 0.5      // R > 此值触发
        _GlowThresholdBG ("B+G Threshold", Range(0,1)) = 0.2   // B+G < 此值触发
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }
        LOD 100

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_fog

            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                UNITY_FOG_COORDS(1)
                float4 vertex : SV_POSITION;
            };

            sampler2D _MainTex;
            float4 _MainTex_ST;

            // 发光参数
            fixed4 _GlowColor;
            float _GlowIntensity;
            float _GlowThresholdR;
            float _GlowThresholdBG;

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                UNITY_TRANSFER_FOG(o,o.vertex);
                return o;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                // 采样纹理
                fixed4 col = tex2D(_MainTex, i.uv);

                // 判断是否触发发光条件
                float r = col.r;
                float bgSum = col.b + col.g;

                // 核心发光逻辑
                float glowMask = 0;
                if (r > _GlowThresholdR && bgSum < _GlowThresholdBG)
                {
                    // 发光强度基于 R 通道的超出量（可选更平滑）
                    float intensity = saturate((r - _GlowThresholdR) / (1.0 - _GlowThresholdR));
                    glowMask = intensity;
                }

                // 混合发光
                fixed4 glow = _GlowColor * glowMask * _GlowIntensity;
                col = col + glow;  // 简单叠加（可改成 lerp 或 max）

                // 应用雾效
                UNITY_APPLY_FOG(i.fogCoord, col);

                return col;
            }
            ENDCG
        }
    }
}