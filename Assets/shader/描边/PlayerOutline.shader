// Upgrade NOTE: replaced 'mul(UNITY_MATRIX_MVP,*)' with 'UnityObjectToClipPos(*)'

Shader "Hidden/CopyStencilToRT"
{
     Properties
	{
		_MainTex ("Texture", 2D) = "white" {}
		_Stencil2Color("Stencil2 Color",COLOR)=(1,1,1,1)
	}
	SubShader
	{
		Pass
		{
		    Stencil
		    {
			  Ref 2
			  Comp Equal
		    }
			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			
			#include "UnityCG.cginc"
			
			struct appdata
			{
				float4 vertex : POSITION;
			};

			struct v2f
			{
				float4 vertex : SV_POSITION;
			};

			v2f vert (appdata v)
			{
				v2f o;
				o.vertex = UnityObjectToClipPos(v.vertex);
				return o;
			}
			
			sampler2D _MainTex;
			fixed4 _Stencil2Color;
			fixed4 frag (v2f i) : SV_Target
			{
				return _Stencil2Color;
			}
			ENDCG
		}
	}
}