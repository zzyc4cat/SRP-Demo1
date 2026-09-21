Shader "ZZY/03.water/Water"
{
	Properties
	{
		// 细波法线强度
		_BumpScale("Detail Wave Amount", Range(0, 2)) = 0.2
		// 阴影抖动图案
		_DitherPattern ("Dithering Pattern", 2D) = "bump" {}
		// 关闭时间，水面保持静止
		[Toggle(_STATIC_SHADER)] _Static ("Static", Float) = 0
		// 调试显示模式
		[KeywordEnum(Off, SSS, Refraction, Reflection, Normal, Fresnel, WaterEffects, Foam, WaterDepth)] _Debug ("Debug mode", Float) = 0
		[Header(Depth)]
		// 深度写入，默认开启
		[Enum(Off, 0, On, 1)] _ZWrite ("ZWrite", Float) = 1
		// 深度测试，默认小于等于
		[Enum(UnityEngine.Rendering.CompareFunction)] _ZTest ("ZTest", Float) = 4
	}
	SubShader
	{
		Tags { "RenderType"="Transparent" "Queue"="Transparent-100" "RenderPipeline" = "UniversalPipeline" }
		ZWrite [_ZWrite]
		ZTest [_ZTest]

		Pass
		{
			Name "WaterShading"
			Tags{"LightMode" = "UniversalForward"}

			HLSLPROGRAM
			#pragma prefer_hlslcc gles
			#pragma shader_feature _REFLECTION_CUBEMAP _REFLECTION_PROBES _REFLECTION_PLANARREFLECTION
			#pragma multi_compile _ USE_STRUCTURED_BUFFER
			#pragma multi_compile _ _STATIC_SHADER
			#pragma shader_feature _DEBUG_OFF _DEBUG_SSS _DEBUG_REFRACTION _DEBUG_REFLECTION _DEBUG_NORMAL _DEBUG_FRESNEL _DEBUG_WATEREFFECTS _DEBUG_FOAM _DEBUG_WATERDEPTH
						
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile _ _SHADOWS_SOFT

            #pragma multi_compile_instancing
            #pragma multi_compile_fog

			#include "WaterCommon.hlsl"

			#pragma vertex WaterVertex
			#pragma fragment WaterFragment

			ENDHLSL
		}
	}
	FallBack "Hidden/InternalErrorShader"
}
