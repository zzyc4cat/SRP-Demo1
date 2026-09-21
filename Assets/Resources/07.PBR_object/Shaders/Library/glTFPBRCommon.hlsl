#ifndef GLTF_PBR_COMMON_INCLUDED
#define GLTF_PBR_COMMON_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

#if defined(GLTF_USE_OPAQUE_TEXTURE)
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareOpaqueTexture.hlsl"
#endif

#ifndef HALF_MIN
#define HALF_MIN 6.103515625e-5
#endif
#ifndef HALF_MIN_SQRT
#define HALF_MIN_SQRT 0.0078125
#endif

static const half3 kDielectricF0 = half3(0.04h, 0.04h, 0.04h);

CBUFFER_START(UnityPerMaterial)
    float4 _BaseColorFactor;
    float4 _BaseMap_ST;
    float4 _MetallicRoughnessMap_ST;
    float4 _BumpMap_ST;
    float4 _OcclusionMap_ST;
    float4 _EmissionMap_ST;

    float _MetallicFactor;
    float _RoughnessFactor;
    float _BumpScale;
    float _OcclusionStrength;
    float4 _EmissionColor;

    float _TransmissionFactor;
    float _ThicknessFactor;
    float4 _AttenuationColor;
    float _AttenuationDistance;
    float _IOR;
    float _RefractionStrength;
    float _TransmissionRoughnessBoost;

    float _SpecularIntensity;
    float _DirectDiffuseIntensity;
    float _DirectSpecularIntensity;
    float _EnvironmentIntensity;

    float _DebugMode;
CBUFFER_END

TEXTURE2D(_BaseMap);                 SAMPLER(sampler_BaseMap);
TEXTURE2D(_MetallicRoughnessMap);    SAMPLER(sampler_MetallicRoughnessMap);
TEXTURE2D(_BumpMap);                 SAMPLER(sampler_BumpMap);
TEXTURE2D(_OcclusionMap);            SAMPLER(sampler_OcclusionMap);
TEXTURE2D(_EmissionMap);             SAMPLER(sampler_EmissionMap);

struct GltfSurfaceData
{
    half3  albedo;
    half   alpha;
    half   metallic;
    half   perceptualRoughness;
    half   roughness;
    half3  f0;
    half3  diffuseColor;
    half3  specularColor;
    half   ao;
    half3  emission;
    half   transmission;
    half   ior;
};

struct GltfInputData
{
    float2 uv;
    float3 positionWS;
    float3 normalWS;
    float3 viewDirWS;
    float4 tangentWS;
    float4 screenPos;
};

// 菲涅尔五次项
inline half GltfPow5(half x)
{
    half x2 = x * x;
    return x2 * x2 * x;
}

// 平方
inline half GltfSq(half x)
{
    return x * x;
}

// 感知粗糙度转微表面粗糙度
inline half GltfPerceptualRoughnessToAlpha(half perceptualRoughness)
{
    return max(GltfSq(perceptualRoughness), HALF_MIN);
}

// 直接光菲涅尔
inline half3 GltfFresnelSchlick(half3 f0, half VdotH)
{
    half fc = GltfPow5(saturate(1.0h - VdotH));
    return f0 + (1.0h - f0) * fc;
}

// 环境光粗糙度菲涅尔
inline half3 GltfFresnelSchlickRoughness(half3 f0, half NdotV, half perceptualRoughness)
{
    half3 fr = max(1.0h - perceptualRoughness, f0) - f0;
    return f0 + fr * GltfPow5(saturate(1.0h - NdotV));
}

// 法线分布项
inline half GltfD_GGX(half NdotH, half roughness)
{
    half a2 = GltfSq(roughness);
    half d = GltfSq(NdotH) * (a2 - 1.0h) + 1.0h;
    return a2 / max(PI * GltfSq(d), HALF_MIN);
}

// 几何遮挡项
inline half GltfG_SmithGGX(half NdotV, half NdotL, half roughness)
{
    half a2 = GltfSq(roughness);
    half GV = NdotL * sqrt(NdotV * NdotV * (1.0h - a2) + a2);
    half GL = NdotV * sqrt(NdotL * NdotL * (1.0h - a2) + a2);
    return 0.5h / max(GV + GL, HALF_MIN);
}

// 高光反射
inline half3 GltfSpecularBRDF(half3 f0, half NdotV, half NdotL, half NdotH, half VdotH, half roughness)
{
    // 组合分布、几何与菲涅尔
    half D = GltfD_GGX(NdotH, roughness);
    half G = GltfG_SmithGGX(NdotV, NdotL, roughness);
    half3 F = GltfFresnelSchlick(f0, VdotH);
    return D * G * F;
}

// 漫反射
inline half3 GltfDiffuseBRDF(half3 diffuseColor)
{
    return diffuseColor * (1.0h / PI);
}

// 切线法线转世界空间
inline half3 GltfGetNormalWS(GltfInputData input, half3 normalTS)
{
    // 重建切线空间并变换法线
    float sgn = input.tangentWS.w;
    float3 bitangent = sgn * cross(input.normalWS.xyz, input.tangentWS.xyz);
    float3x3 tbn = float3x3(input.tangentWS.xyz, bitangent, input.normalWS.xyz);
    return normalize(mul(normalTS, tbn));
}

// 采样法线贴图
inline half3 GltfSampleNormalTS(float2 uv)
{
    half4 packed = SAMPLE_TEXTURE2D(_BumpMap, sampler_BumpMap, uv);
    half3 normalTS = UnpackNormalScale(packed, _BumpScale);
    return normalTS;
}

// 采样并组装表面参数
inline GltfSurfaceData GltfSampleSurface(float2 uv)
{
    GltfSurfaceData s = (GltfSurfaceData)0;

    float2 uvBase = TRANSFORM_TEX(uv, _BaseMap);
    float2 uvMR   = TRANSFORM_TEX(uv, _MetallicRoughnessMap);
    float2 uvOcc  = TRANSFORM_TEX(uv, _OcclusionMap);
    float2 uvEmi  = TRANSFORM_TEX(uv, _EmissionMap);

    // 基础色
    half4 baseSample = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, uvBase);
    half3 baseColor = baseSample.rgb * _BaseColorFactor.rgb;
    half alpha = baseSample.a * _BaseColorFactor.a;

    // 金属度与粗糙度
    half4 mr = SAMPLE_TEXTURE2D(_MetallicRoughnessMap, sampler_MetallicRoughnessMap, uvMR);
    half metallic = saturate(mr.b * _MetallicFactor);
    half perceptualRoughness = saturate(mr.g * _RoughnessFactor);

    // 环境遮蔽
    half aoTex = SAMPLE_TEXTURE2D(_OcclusionMap, sampler_OcclusionMap, uvOcc).r;
    half ao = lerp(1.0h, aoTex, saturate(_OcclusionStrength));

    // 自发光
    half3 emission = SAMPLE_TEXTURE2D(_EmissionMap, sampler_EmissionMap, uvEmi).rgb * _EmissionColor.rgb;

    // 金属工作流换算
    half roughness = GltfPerceptualRoughnessToAlpha(perceptualRoughness);
    half3 f0 = lerp(kDielectricF0, baseColor, metallic);
    half3 diffuseColor = baseColor * (1.0h - metallic);

    s.albedo = baseColor;
    s.alpha = alpha;
    s.metallic = metallic;
    s.perceptualRoughness = perceptualRoughness;
    s.roughness = roughness;
    s.f0 = f0;
    s.diffuseColor = diffuseColor;
    s.specularColor = f0;
    s.ao = ao;
    s.emission = emission;
    s.transmission = saturate(_TransmissionFactor);
    s.ior = max(_IOR, 1.0h);
    return s;
}

// 单盏直接光着色
inline half3 GltfShadeDirectLight(GltfSurfaceData s, half3 N, half3 V, Light light)
{
    // 计算光照夹角
    half3 L = light.direction;
    half3 H = normalize(V + L);

    half NdotL = saturate(dot(N, L));
    half NdotV = saturate(dot(N, V));
    half NdotH = saturate(dot(N, H));
    half VdotH = saturate(dot(V, H));

    // 拆分漫反射与高光
    half3 F = GltfFresnelSchlick(s.f0, VdotH);
    half3 diffuse = GltfDiffuseBRDF(s.diffuseColor) * (1.0h - F) * _DirectDiffuseIntensity;
    half3 specular = GltfSpecularBRDF(s.f0, NdotV, NdotL, NdotH, VdotH, s.roughness)
                   * _SpecularIntensity * _DirectSpecularIntensity;

    // 透射让出漫反射
    diffuse *= (1.0h - s.transmission);

    // 乘灯光辐射与阴影
    half3 radiance = light.color * (light.distanceAttenuation * light.shadowAttenuation);
    return (diffuse + specular) * radiance * NdotL;
}

// 环境光照明
inline half3 GltfShadeEnvironment(GltfSurfaceData s, half3 N, half3 V, float3 positionWS)
{
    half NdotV = saturate(dot(N, V));
    half3 F = GltfFresnelSchlickRoughness(s.f0, NdotV, s.perceptualRoughness);

    // 环境漫反射
    half3 irradiance = SampleSH(N);
    half3 diffuse = irradiance * s.diffuseColor * (1.0h - F) * (1.0h - s.transmission);

    // 按粗糙度采样环境高光
    half3 R = reflect(-V, N);
    half mip = PerceptualRoughnessToMipmapLevel(s.perceptualRoughness);
    half4 encodedIrradiance = SAMPLE_TEXTURECUBE_LOD(unity_SpecCube0, samplerunity_SpecCube0, R, mip);
#if !defined(UNITY_USE_NATIVE_HDR)
    half3 specularEnv = DecodeHDREnvironment(encodedIrradiance, unity_SpecCube0_HDR);
#else
    half3 specularEnv = encodedIrradiance.rgb;
#endif
    half3 specular = specularEnv * F * _SpecularIntensity;

    return (diffuse + specular) * s.ao * _EnvironmentIntensity;
}

// 体积颜色衰减
inline half3 GltfVolumeAttenuation(half3 attenuationColor, half attenuationDistance, half thickness)
{
    // 按厚度指数吸收
    if (attenuationDistance <= 1e-4h)
        return half3(1, 1, 1);
    half3 opticalDepth = -log(max(attenuationColor, half3(1e-5, 1e-5, 1e-5))) / attenuationDistance;
    return exp(-opticalDepth * max(thickness, 0.0h));
}

// 透射折射着色
inline half3 GltfShadeTransmission(GltfSurfaceData s, GltfInputData input, half3 N, half3 V)
{
    if (s.transmission < 1e-4h)
        return 0;

    // 计算折射方向
    half eta = 1.0h / s.ior;
    half3 refrDir = refract(-V, N, eta);
    if (dot(refrDir, refrDir) < 1e-6h)
        refrDir = reflect(-V, N);

    // 按粗糙度模糊透射
    half transmissionRoughness = saturate(s.perceptualRoughness + _TransmissionRoughnessBoost);
    half mip = PerceptualRoughnessToMipmapLevel(transmissionRoughness);

    half4 encoded = SAMPLE_TEXTURECUBE_LOD(unity_SpecCube0, samplerunity_SpecCube0, refrDir, mip);
#if !defined(UNITY_USE_NATIVE_HDR)
    half3 transmitted = DecodeHDREnvironment(encoded, unity_SpecCube0_HDR);
#else
    half3 transmitted = encoded.rgb;
#endif

#if defined(GLTF_USE_OPAQUE_TEXTURE)
    // 屏幕空间折射
    float2 uvSS = input.screenPos.xy / max(input.screenPos.w, 1e-5);
    float2 offset = N.xy * (_RefractionStrength * (1.0h - transmissionRoughness));
    half3 sceneColor = SampleSceneColor(saturate(uvSS + offset));
    transmitted = lerp(transmitted, sceneColor, saturate(_RefractionStrength));
#endif

    // 体积染色
    half thickness = max(_ThicknessFactor, 0.0h);
    half3 attenuation = GltfVolumeAttenuation(_AttenuationColor.rgb, _AttenuationDistance, thickness);
    transmitted *= attenuation * s.albedo;

    // 扣除反射能量
    half NdotV = saturate(dot(N, V));
    half3 F = GltfFresnelSchlickRoughness(s.f0, NdotV, s.perceptualRoughness);
    return transmitted * (1.0h - F) * s.transmission;
}

// 调试模式输出
inline half3 GltfApplyDebug(half3 litColor, GltfSurfaceData s, half3 N, half3 V, Light mainLight)
{
    int mode = (int)_DebugMode;
    if (mode <= 0)
        return litColor;

    // 计算主光夹角
    half3 L = mainLight.direction;
    half3 H = normalize(V + L);
    half NdotL = saturate(dot(N, L));
    half NdotV = saturate(dot(N, V));
    half NdotH = saturate(dot(N, H));
    half VdotH = saturate(dot(V, H));

    // 按模式输出单项
    switch (mode)
    {
        case 1:
        {
            half3 spec = GltfSpecularBRDF(s.f0, NdotV, NdotL, NdotH, VdotH, s.roughness)
                       * mainLight.color * NdotL * _SpecularIntensity;
            return spec;
        }
        case 2:
            return GltfDiffuseBRDF(s.diffuseColor) * mainLight.color * NdotL;
        case 3:
        {
            half D = GltfD_GGX(NdotH, s.roughness);
            return D.xxx * 0.1h;
        }
        case 4:
            return GltfFresnelSchlick(s.f0, VdotH);
        case 5:
            return s.metallic.xxx;
        case 6:
            return s.perceptualRoughness.xxx;
        case 7:
            return N * 0.5h + 0.5h;
        case 8:
            return s.ao.xxx;
        case 9:
            return s.albedo;
        case 10:
            return s.f0;
        default:
            return litColor;
    }
}

// 完整光照入口
inline half4 GltfEvaluateLighting(GltfInputData input)
{
    // 采样表面参数
    GltfSurfaceData s = GltfSampleSurface(input.uv);

    // 法线贴图转世界法线
    half3 normalTS = GltfSampleNormalTS(TRANSFORM_TEX(input.uv, _BumpMap));
    half3 N = GltfGetNormalWS(input, normalTS);
    half3 V = normalize(input.viewDirWS);

    // 主光与附加光
    Light mainLight = GetMainLight();
    half3 color = GltfShadeDirectLight(s, N, V, mainLight);

    uint lightsCount = GetAdditionalLightsCount();
    for (uint i = 0u; i < lightsCount; ++i)
    {
        Light light = GetAdditionalLight(i, input.positionWS);
        color += GltfShadeDirectLight(s, N, V, light);
    }

    // 环境光
    color += GltfShadeEnvironment(s, N, V, input.positionWS);

    // 透射
    color += GltfShadeTransmission(s, input, N, V);

    // 自发光
    color += s.emission;

    // 调试覆盖
    color = GltfApplyDebug(color, s, N, V, mainLight);

    // 透射透明度
    half outAlpha = s.alpha;
    if (s.transmission > 1e-4h)
    {
        half NdotV = saturate(dot(N, V));
        half3 F = GltfFresnelSchlickRoughness(s.f0, NdotV, s.perceptualRoughness);
        half reflectAmount = Max3(F.r, F.g, F.b);
        outAlpha = saturate(1.0h - s.transmission * (1.0h - reflectAmount));
        outAlpha = max(outAlpha, s.alpha);
    }

    return half4(color, outAlpha);
}

#endif
