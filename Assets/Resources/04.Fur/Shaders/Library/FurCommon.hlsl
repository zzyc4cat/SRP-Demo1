#ifndef FUR_COMMON_INCLUDED
#define FUR_COMMON_INCLUDED

// ============================================================
// FurCommon.hlsl
// Shell Texturing 公共函数库（优化版）
// 供 Forward / DepthOnly Pass 复用，避免重复逻辑与变体膨胀
// ============================================================

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

// ---------- 材质常量缓冲（SRP Batcher 友好） ----------
CBUFFER_START(UnityPerMaterial)
    float4 _BaseColor;
    float4 _FurColor;
    float4 _BaseMap_ST;
    float4 _NoiseTex_ST;
    float4 _LengthMap_ST;
    float _NoiseTiling;
    float _MaxDensity;
    float _Density;
    float _TipCutoff;
    float _ThicknessCurve;
    float _FurLength;
    float _Gravity;
    float _Messiness;
    float4 _CombDir;
    float _AmbientStrength;
    float _SpecularStrength;
    float _SpecularPower;
CBUFFER_END

// 风力由 MaterialPropertyBlock / 全局属性注入，不进 PerMaterial CBUFFER
float4 _WindVector; // xyz = wind, w = phase

TEXTURE2D(_BaseMap);    SAMPLER(sampler_BaseMap);
TEXTURE2D(_NoiseTex);   SAMPLER(sampler_NoiseTex);
TEXTURE2D(_LengthMap);  SAMPLER(sampler_LengthMap);

/// 基础色贴图 × 颜色 tint（默认白贴图时退化为纯色）
inline float3 FurSampleBaseAlbedo(float2 uvBase)
{
    float3 baseMap = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, uvBase).rgb;
    return baseMap;
}

// ---------- Instancing：每层一个 _LayerRatio ----------
UNITY_INSTANCING_BUFFER_START(FurProps)
    UNITY_DEFINE_INSTANCED_PROP(float, _LayerRatio)
UNITY_INSTANCING_BUFFER_END(FurProps)

/// 安全 pow：避免负底数告警与平台未定义行为
inline float FurSafePow(float v, float e)
{
    return pow(max(v, 1e-5), e);
}

/// 采样长度遮罩（顶点阶段用 LOD0）
inline float FurSampleLengthMask(float2 uv)
{
    float2 lengthUV = TRANSFORM_TEX(uv, _LengthMap);
    return SAMPLE_TEXTURE2D_LOD(_LengthMap, sampler_LengthMap, lengthUV, 0).r;
}

/// 构造世界空间毛发位移：法线挤出 + 重力梳毛 + 凌乱 + 风力
inline void FurApplyShellDeform(
    inout float3 posWS,
    inout float3 normalWS,
    float2 uv,
    float ratio)
{
    // [长度遮罩] 用 R 通道控制局部毛长，发根区域可压短
    float lengthMask = FurSampleLengthMask(uv);
    float actualFurLength = _FurLength * lengthMask;

    // [法线外扩] Shell 核心：沿法线按层级比例挤出
    // extrusion = ratio * L，ratio=0 贴合皮肤，ratio=1 到发梢
    float extrusion = ratio * actualFurLength;
    posWS += normalWS * extrusion;

    // [非线性刚度] ratio^2：发根几乎不弯，发梢弯曲最大
    float bend = ratio * ratio;
    float3 gravityDrop = float3(0.0, -1.0, 0.0) * _Gravity;
    float3 combOffset = _CombDir.xyz + gravityDrop;
    float3 dirOffset = combOffset * actualFurLength * bend;

    // [风力] 发梢受风更强（同样乘 bend），并叠加相位晃动
    float3 wind = _WindVector.xyz * bend * actualFurLength;
    wind += sin(_WindVector.w + posWS.x * 3.0 + posWS.z * 2.0) * wind * 0.35;

    // [凌乱扰动] 基于世界坐标的相位差，打破完美平行
    float3 messOffset = sin(posWS * 30.0) * (_Messiness * actualFurLength * 0.5) * bend;

    posWS += dirOffset + wind + messOffset;

    // 近似更新法线，供漫反射/高光使用
    normalWS = normalize(normalWS + dirOffset + messOffset + wind * 0.25);
}

/// Alpha Test 阈值：根密梢稀 + 全局密度钳制
inline float FurComputeCutoff(float ratio)
{
    // [锥度曲线] 控制发丝由粗到细的速度
    float shapeCurve = FurSafePow(saturate(ratio), _ThicknessCurve);
    float rootCutoff = 1.0 - _Density;
    float cutoff = lerp(rootCutoff, _TipCutoff, shapeCurve);

    // [防夹断] 保证全局密度上限不被 tip 切得过狠
    float minCutoffLimit = 1.0 - _MaxDensity;
    return max(cutoff, minCutoffLimit);
}

/// 噪声采样 + 轻微 UV 扰动，增强乱发感
inline float FurSampleNoise(float2 uv, float ratio)
{
    float2 uvOffset = sin(uv * 50.0) * (_Messiness * 0.02 * ratio);
    float2 noiseUV = (uv + uvOffset) * _NoiseTiling;
    return SAMPLE_TEXTURE2D(_NoiseTex, sampler_NoiseTex, noiseUV).r;
}

/// 片元裁剪：最底层强制保留，防止走光
inline void FurClipStrand(float noiseVal, float cutoff, float ratio)
{
    if (ratio > 0.02)
    {
        clip(noiseVal - cutoff);
    }
}

#endif
