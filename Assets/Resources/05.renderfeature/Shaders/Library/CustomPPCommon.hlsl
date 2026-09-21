#ifndef CUSTOM_PP_COMMON_INCLUDED
#define CUSTOM_PP_COMMON_INCLUDED

// ============================================================
// CustomPPCommon.hlsl
// 自定义后处理公共库：全屏顶点、源图采样、深度重建等
// 被各独立效果 Shader 共用，避免重复代码。
// ============================================================

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

// CommandBuffer.Blit 约定：源颜色绑定到 _MainTex
TEXTURE2D(_MainTex);
SAMPLER(sampler_MainTex);
float4 _MainTex_TexelSize;

// 第二输入（Bloom 上采样叠加 / 合成时使用）
TEXTURE2D(_SourceTex2);
SAMPLER(sampler_SourceTex2);

// ---------- 全屏三角形/四边形顶点输入输出 ----------
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

// 标准全屏顶点：对象空间 → 裁剪空间，透传 UV
PPVaryings PPVert(PPAttributes input)
{
    PPVaryings output;
    output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
    output.uv = input.uv;
    return output;
}

// 采样当前后处理源图（上一 Pass 输出）
float3 SampleSource(float2 uv)
{
    return SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv).rgb;
}

// 采样相机深度纹理（需 Feature ConfigureInput Depth）
float SampleDepth01(float2 uv)
{
    return SampleSceneDepth(uv);
}

// 非线性深度 → 眼睛空间线性深度（米）
float LinearEyeDepth01(float rawDepth)
{
    return LinearEyeDepth(rawDepth, _ZBufferParams);
}

// 由屏幕 UV + 深度重建世界坐标（高度雾等需要）
float3 ReconstructWorldPos(float2 uv, float rawDepth)
{
    return ComputeWorldSpacePosition(uv, rawDepth, UNITY_MATRIX_I_VP);
}

// Rec.709 亮度
float LuminancePP(float3 c)
{
    return dot(c, float3(0.2126, 0.7152, 0.0722));
}

// 判断是否为天空/远裁面像素（Reversed-Z 下远平面接近 0）
float IsSkyPixel(float rawDepth)
{
#if UNITY_REVERSED_Z
    return rawDepth < 1.0e-5 ? 1.0 : 0.0;
#else
    return rawDepth > 0.99999 ? 1.0 : 0.0;
#endif
}

#endif
