#ifndef CUSTOM_PP_COMMON_INCLUDED
#define CUSTOM_PP_COMMON_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

TEXTURE2D(_MainTex);
SAMPLER(sampler_MainTex);
float4 _MainTex_TexelSize;

TEXTURE2D(_SourceTex2);
SAMPLER(sampler_SourceTex2);

struct PPAttributes
{
    float4 positionOS : POSITION;
    float2 uv : TEXCOORD0;
};

struct PPVaryings
{
    float4 positionCS : SV_POSITION;
    float2 uv : TEXCOORD0;
};

// 全屏三角形顶点变换
PPVaryings PPVert(PPAttributes input)
{
    // 变换到裁剪空间并传递紫外
    PPVaryings output;
    output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
    output.uv = input.uv;
    return output;
}

// 采样后处理源图
float3 SampleSource(float2 uv)
{
    return SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv).rgb;
}

// 采样场景深度
float SampleDepth01(float2 uv)
{
    return SampleSceneDepth(uv);
}

// 非线性深度转视空间距离
float LinearEyeDepth01(float rawDepth)
{
    return LinearEyeDepth(rawDepth, _ZBufferParams);
}

// 由屏幕坐标重建世界位置
float3 ReconstructWorldPos(float2 uv, float rawDepth)
{
    return ComputeWorldSpacePosition(uv, rawDepth, UNITY_MATRIX_I_VP);
}

// 计算亮度
float LuminancePP(float3 c)
{
    return dot(c, float3(0.2126, 0.7152, 0.0722));
}

// 判断天空或远裁面
float IsSkyPixel(float rawDepth)
{
    // 反向深度下远平面接近零
#if UNITY_REVERSED_Z
    return rawDepth < 1.0e-5 ? 1.0 : 0.0;
#else
    return rawDepth > 0.99999 ? 1.0 : 0.0;
#endif
}

#endif
