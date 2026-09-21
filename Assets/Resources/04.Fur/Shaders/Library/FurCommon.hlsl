#ifndef FUR_COMMON_INCLUDED
#define FUR_COMMON_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

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

float4 _WindVector;

TEXTURE2D(_BaseMap);    SAMPLER(sampler_BaseMap);
TEXTURE2D(_NoiseTex);   SAMPLER(sampler_NoiseTex);
TEXTURE2D(_LengthMap);  SAMPLER(sampler_LengthMap);

// 采样基础色
inline float3 FurSampleBaseAlbedo(float2 uvBase)
{
    float3 baseMap = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, uvBase).rgb;
    return baseMap;
}

UNITY_INSTANCING_BUFFER_START(FurProps)
    UNITY_DEFINE_INSTANCED_PROP(float, _LayerRatio)
UNITY_INSTANCING_BUFFER_END(FurProps)

// 避免负底数的幂
inline float FurSafePow(float v, float e)
{
    return pow(max(v, 1e-5), e);
}

// 采样长度遮罩
inline float FurSampleLengthMask(float2 uv)
{
    float2 lengthUV = TRANSFORM_TEX(uv, _LengthMap);
    return SAMPLE_TEXTURE2D_LOD(_LengthMap, sampler_LengthMap, lengthUV, 0).r;
}

// 按壳层挤出并弯曲毛发
inline void FurApplyShellDeform(
    inout float3 posWS,
    inout float3 normalWS,
    float2 uv,
    float ratio)
{
    // 用长度遮罩控制局部毛长
    float lengthMask = FurSampleLengthMask(uv);
    float actualFurLength = _FurLength * lengthMask;

    // 沿法线挤出壳层
    float extrusion = ratio * actualFurLength;
    posWS += normalWS * extrusion;

    // 重力与梳毛
    float bend = ratio * ratio;
    float3 gravityDrop = float3(0.0, -1.0, 0.0) * _Gravity;
    float3 combOffset = _CombDir.xyz + gravityDrop;
    float3 dirOffset = combOffset * actualFurLength * bend;

    // 发梢风力摆动
    float3 wind = _WindVector.xyz * bend * actualFurLength;
    wind += sin(_WindVector.w + posWS.x * 3.0 + posWS.z * 2.0) * wind * 0.35;

    // 凌乱扰动
    float3 messOffset = sin(posWS * 30.0) * (_Messiness * actualFurLength * 0.5) * bend;

    // 叠加弯曲、风力与凌乱
    posWS += dirOffset + wind + messOffset;

    // 近似更新法线
    normalWS = normalize(normalWS + dirOffset + messOffset + wind * 0.25);
}

// 计算发丝裁剪阈值
inline float FurComputeCutoff(float ratio)
{
    // 根密梢稀的锥度
    float shapeCurve = FurSafePow(saturate(ratio), _ThicknessCurve);
    float rootCutoff = 1.0 - _Density;
    float cutoff = lerp(rootCutoff, _TipCutoff, shapeCurve);

    // 限制全局最大密度
    float minCutoffLimit = 1.0 - _MaxDensity;
    return max(cutoff, minCutoffLimit);
}

// 采样带扰动的毛发噪声
inline float FurSampleNoise(float2 uv, float ratio)
{
    // 轻微扰动噪声坐标
    float2 uvOffset = sin(uv * 50.0) * (_Messiness * 0.02 * ratio);
    float2 noiseUV = (uv + uvOffset) * _NoiseTiling;
    return SAMPLE_TEXTURE2D(_NoiseTex, sampler_NoiseTex, noiseUV).r;
}

// 按噪声裁剪发丝
inline void FurClipStrand(float noiseVal, float cutoff, float ratio)
{
    // 最底层保留，上层裁剪
    if (ratio > 0.02)
    {
        clip(noiseVal - cutoff);
    }
}

#endif
