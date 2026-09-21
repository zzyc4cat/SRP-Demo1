#ifndef GLTF_PBR_COMMON_INCLUDED
#define GLTF_PBR_COMMON_INCLUDED

// =============================================================================
// glTFPBRCommon.hlsl
// glTF 2.0 Metallic-Roughness PBR / Cook-Torrance BRDF 公共库
//
// 供 URP_glTF_PBR（不透明）与 URP_glTF_PBR_Transmission（透射）共用。
//
// 规范对齐（glTF 2.0）：
//   - baseColor / metallic / roughness / normal / occlusion 通道语义
//   - dielectric F0 = 0.04（IOR ≈ 1.5）
//   - metallicRoughnessTexture：G = roughness，B = metallic
//   - normalTexture：切线空间，OpenGL 朝向（+Y）
//   - occlusionTexture：R 通道 AO，strength 按 occlusionStrength 混合
//   - transmission：KHR_materials_transmission 风格近似
// =============================================================================

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

// -----------------------------------------------------------------------------
// [可选模块] 屏幕空间折射
// 效果：透射材质可采样相机不透明纹理，做出“透过玻璃看到背后场景”的折射偏移。
// 启用条件：着色器中 #define GLTF_USE_OPAQUE_TEXTURE 1，且 URP Asset 开启 Opaque Texture。
// -----------------------------------------------------------------------------
#if defined(GLTF_USE_OPAQUE_TEXTURE)
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareOpaqueTexture.hlsl"
#endif

#ifndef HALF_MIN
#define HALF_MIN 6.103515625e-5
#endif
#ifndef HALF_MIN_SQRT
#define HALF_MIN_SQRT 0.0078125
#endif

// -----------------------------------------------------------------------------
// [常量] 电介质法向入射反射率 F0
// 效果：非金属材质正对观察时约反射 4% 环境光（IOR≈1.5，玻璃/塑料）。
// 金属的 F0 则来自 baseColor（见下方 GltfSampleSurface）。
// -----------------------------------------------------------------------------
static const half3 kDielectricF0 = half3(0.04h, 0.04h, 0.04h);

// -----------------------------------------------------------------------------
// [材质常量缓冲] UnityPerMaterial — SRP Batcher 友好
// 分组对应：BaseColor / Metal-Rough / Normal / AO / Emission /
//           Transmission(KHR) / 光照缩放 / SpecularTest Debug
// -----------------------------------------------------------------------------
CBUFFER_START(UnityPerMaterial)
    // --- BaseColor（漫反射/金属自身色）---
    float4 _BaseColorFactor;
    float4 _BaseMap_ST;
    float4 _MetallicRoughnessMap_ST;
    float4 _BumpMap_ST;
    float4 _OcclusionMap_ST;
    float4 _EmissionMap_ST;

    // --- Metallic-Roughness 因子（与贴图相乘）---
    float _MetallicFactor;   // 0=电介质，1=纯金属 → 控制漫反射衰减与 F0 来源
    float _RoughnessFactor;  // 0=镜面高光极尖，1=高光展宽成漫射感
    float _BumpScale;        // 法线强度：Normal-Tangent 测试的核心旋钮
    float _OcclusionStrength;// AO 混合强度：0=关闭 AO，1=完全使用贴图
    float4 _EmissionColor;

    // --- Transmission（KHR_materials_transmission / volume 简化）---
    float _TransmissionFactor;          // 0=不透，1=全透（玻璃）
    float _ThicknessFactor;             // 体积厚度，影响 Beer-Lambert 染色
    float4 _AttenuationColor;           // 体积衰减颜色（液体染色）
    float _AttenuationDistance;         // 衰减距离：越小颜色吸得越快
    float _IOR;                         // 折射率：折射方向 + Fresnel 行为
    float _RefractionStrength;          // 屏幕折射偏移强度
    float _TransmissionRoughnessBoost;  // 额外模糊透射（磨砂玻璃）

    // --- 光照缩放（教学/对比用，默认均为 1）---
    float _SpecularIntensity;
    float _DirectDiffuseIntensity;
    float _DirectSpecularIntensity;
    float _EnvironmentIntensity;

    // --- SpecularTest Debug：隔离观察 BRDF 各项 ---
    // 0 Full  1 SpecOnly  2 DiffOnly  3 D_GGX  4 Fresnel
    // 5 Metallic  6 Roughness  7 WorldNormal  8 AO  9 BaseColor  10 F0
    float _DebugMode;
CBUFFER_END

// -----------------------------------------------------------------------------
// [贴图声明] 全通道标准 PBR（glTF）
// BaseColor RGB+A | MetallicRoughness G/B | Normal TS | Occlusion R | Emission RGB
// -----------------------------------------------------------------------------
TEXTURE2D(_BaseMap);                 SAMPLER(sampler_BaseMap);
TEXTURE2D(_MetallicRoughnessMap);    SAMPLER(sampler_MetallicRoughnessMap);
TEXTURE2D(_BumpMap);                 SAMPLER(sampler_BumpMap);
TEXTURE2D(_OcclusionMap);            SAMPLER(sampler_OcclusionMap);
TEXTURE2D(_EmissionMap);             SAMPLER(sampler_EmissionMap);

// -----------------------------------------------------------------------------
// [数据结构] 表面参数：采样贴图并换算成 BRDF 可直接使用的量
// -----------------------------------------------------------------------------
struct GltfSurfaceData
{
    half3  albedo;               // baseColor.rgb（线性）
    half   alpha;                // 不透明度
    half   metallic;             // [0,1] 金属度
    half   perceptualRoughness;  // [0,1] glTF 感知粗糙度（美术参数）
    half   roughness;            // α = r²，进入 GGX 的微观粗糙度
    half3  f0;                   // 法向入射反射率（电介质 0.04 或金属 baseColor）
    half3  diffuseColor;         // albedo * (1 - metallic)，金属时漫反射趋近 0
    half3  specularColor;        // 即 F0，用于高光染色
    half   ao;                   // 环境光遮蔽
    half3  emission;             // 自发光
    half   transmission;         // [0,1] 透射因子
    half   ior;                  // 折射率
};

// -----------------------------------------------------------------------------
// [数据结构] 片元输入：世界空间几何 + UV + 屏幕坐标（折射用）
// -----------------------------------------------------------------------------
struct GltfInputData
{
    float2 uv;
    float3 positionWS;
    float3 normalWS;
    float3 viewDirWS;
    float4 tangentWS; // xyz = 切线，w = 副切线符号（镜像 UV 翻转）
    float4 screenPos; // 屏幕空间折射采样用
};

// =============================================================================
// 一、基础数学工具
// =============================================================================

// -----------------------------------------------------------------------------
// [工具] Pow5：Schlick Fresnel 中 (1-x)^5 的快速近似
// 效果：决定“掠射角更亮”的边缘高光上升曲线是否符合物理观感。
// -----------------------------------------------------------------------------
inline half GltfPow5(half x)
{
    half x2 = x * x;
    return x2 * x2 * x;
}

inline half GltfSq(half x)
{
    return x * x;
}

// -----------------------------------------------------------------------------
// [效果] 感知粗糙度 → GGX α
// 公式：α = perceptualRoughness²（Disney / glTF / Filament 一致）
// 观感：同样把滑条从 0→1，高光展宽呈非线性，中间档更接近真实材质。
// -----------------------------------------------------------------------------
inline half GltfPerceptualRoughnessToAlpha(half perceptualRoughness)
{
    return max(GltfSq(perceptualRoughness), HALF_MIN);
}

// =============================================================================
// 二、Fresnel（菲涅尔）— SpecularTest 边缘衰减核心
// =============================================================================

// -----------------------------------------------------------------------------
// [效果] Schlick Fresnel（直接光，半角 V·H）
// 公式：F = F0 + (1-F0) * (1-VdotH)^5
// 观感：
//   - 正对表面 → 接近 F0（电介质很暗的反射，金属保持自身色）
//   - 掠射角   → 趋近白色/全反射，产生边缘高光
// SpecularTest：DebugMode=4 可单独观察此项。
// -----------------------------------------------------------------------------
inline half3 GltfFresnelSchlick(half3 f0, half VdotH)
{
    half fc = GltfPow5(saturate(1.0h - VdotH));
    return f0 + (1.0h - f0) * fc;
}

// -----------------------------------------------------------------------------
// [效果] 粗糙度修正 Fresnel（环境反射用）
// 公式：F = F0 + (max(1-roughness, F0) - F0) * (1-NdotV)^5
// 观感：粗糙表面掠射角不再“假亮成镜子”，环境反射更自然。
// -----------------------------------------------------------------------------
inline half3 GltfFresnelSchlickRoughness(half3 f0, half NdotV, half perceptualRoughness)
{
    half3 fr = max(1.0h - perceptualRoughness, f0) - f0;
    return f0 + fr * GltfPow5(saturate(1.0h - NdotV));
}

// =============================================================================
// 三、Cook-Torrance 高光 BRDF 三项：D / G / F
// =============================================================================

// -----------------------------------------------------------------------------
// [效果] D — GGX / Trowbridge-Reitz 法线分布
// 作用：描述微表面法线朝向半角 H 的概率 → 决定高光“形状”
// 观感：
//   - roughness→0：高光极尖、极亮（镜面光斑）
//   - roughness→1：高光展成宽而暗的光晕
// SpecularTest：DebugMode=3 单独显示 D（已缩放便于观察）。
// -----------------------------------------------------------------------------
inline half GltfD_GGX(half NdotH, half roughness)
{
    half a2 = GltfSq(roughness);
    half d = GltfSq(NdotH) * (a2 - 1.0h) + 1.0h;
    return a2 / max(PI * GltfSq(d), HALF_MIN);
}

// -----------------------------------------------------------------------------
// [效果] G — Smith-GGX 几何遮挡/阴影项
// 作用：微表面互相遮挡导致的能量损失；内含 1/(4·NdotL·NdotV) 的高度相关近似
// 观感：掠射角与粗糙表面时压暗高光，避免能量爆炸。
// -----------------------------------------------------------------------------
inline half GltfG_SmithGGX(half NdotV, half NdotL, half roughness)
{
    half a2 = GltfSq(roughness);
    half GV = NdotL * sqrt(NdotV * NdotV * (1.0h - a2) + a2);
    half GL = NdotV * sqrt(NdotL * NdotL * (1.0h - a2) + a2);
    return 0.5h / max(GV + GL, HALF_MIN);
}

// -----------------------------------------------------------------------------
// [效果] 完整高光 BRDF = D * G * F
// 对应测试：SpecularTest 高光形状、强度、边缘衰减是否物理。
// -----------------------------------------------------------------------------
inline half3 GltfSpecularBRDF(half3 f0, half NdotV, half NdotL, half NdotH, half VdotH, half roughness)
{
    half D = GltfD_GGX(NdotH, roughness);
    half G = GltfG_SmithGGX(NdotV, NdotL, roughness);
    half3 F = GltfFresnelSchlick(f0, VdotH);
    return D * G * F;
}

// -----------------------------------------------------------------------------
// [效果] Lambert 漫反射 BRDF = albedo / π
// 能量守恒：调用方需再乘 (1-F)，金属时 diffuseColor 已接近 0。
// 观感：金属度↑ → 漫反射变暗（Metal-Roughness 梯度阵列左→右可见）。
// -----------------------------------------------------------------------------
inline half3 GltfDiffuseBRDF(half3 diffuseColor)
{
    return diffuseColor * (1.0h / PI);
}

// =============================================================================
// 四、法线 / 切线空间 — Normal-Tangent Mirror Test
// =============================================================================

// -----------------------------------------------------------------------------
// [效果] 切线空间法线 → 世界空间法线（TBN）
// 步骤：用 tangent.w 符号重建 bitangent，构造 TBN，变换 normalTS。
// 观感：法线扰动改变反射/高光方向；对着镜面平面可验证切线空间是否正确。
// -----------------------------------------------------------------------------
inline half3 GltfGetNormalWS(GltfInputData input, half3 normalTS)
{
    float sgn = input.tangentWS.w;
    float3 bitangent = sgn * cross(input.normalWS.xyz, input.tangentWS.xyz);
    float3x3 tbn = float3x3(input.tangentWS.xyz, bitangent, input.normalWS.xyz);
    return normalize(mul(normalTS, tbn));
}

// -----------------------------------------------------------------------------
// [效果] 采样法线贴图 + bumpScale（glTF normalTexture.scale）
// 观感：BumpScale=0 平坦；增大后砖缝凹凸与高光扭曲增强（Normal 测试球列）。
// -----------------------------------------------------------------------------
inline half3 GltfSampleNormalTS(float2 uv)
{
    half4 packed = SAMPLE_TEXTURE2D(_BumpMap, sampler_BumpMap, uv);
    half3 normalTS = UnpackNormalScale(packed, _BumpScale);
    return normalTS;
}

// =============================================================================
// 五、表面参数采样 — 全通道 glTF PBR
// =============================================================================

// -----------------------------------------------------------------------------
// [效果] 组装表面：贴图 × Factor → BRDF 输入
// 通道：
//   BaseColor.rgb * factor → albedo
//   MR.G * roughnessFactor → perceptualRoughness
//   MR.B * metallicFactor  → metallic
//   Occlusion.R            → ao（按 strength 混回 1）
//   Emission               → 自发光
// 换算：
//   F0 = lerp(0.04, albedo, metallic)
//   diffuseColor = albedo * (1 - metallic)  ← 金属漫反射衰减
// -----------------------------------------------------------------------------
inline GltfSurfaceData GltfSampleSurface(float2 uv)
{
    GltfSurfaceData s = (GltfSurfaceData)0;

    float2 uvBase = TRANSFORM_TEX(uv, _BaseMap);
    float2 uvMR   = TRANSFORM_TEX(uv, _MetallicRoughnessMap);
    float2 uvOcc  = TRANSFORM_TEX(uv, _OcclusionMap);
    float2 uvEmi  = TRANSFORM_TEX(uv, _EmissionMap);

    // --- BaseColor ---
    half4 baseSample = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, uvBase);
    half3 baseColor = baseSample.rgb * _BaseColorFactor.rgb;
    half alpha = baseSample.a * _BaseColorFactor.a;

    // --- Metallic-Roughness（glTF：G=roughness，B=metallic）---
    half4 mr = SAMPLE_TEXTURE2D(_MetallicRoughnessMap, sampler_MetallicRoughnessMap, uvMR);
    half metallic = saturate(mr.b * _MetallicFactor);
    half perceptualRoughness = saturate(mr.g * _RoughnessFactor);

    // --- AO：lerp(1, tex, strength) ---
    half aoTex = SAMPLE_TEXTURE2D(_OcclusionMap, sampler_OcclusionMap, uvOcc).r;
    half ao = lerp(1.0h, aoTex, saturate(_OcclusionStrength));

    // --- Emission ---
    half3 emission = SAMPLE_TEXTURE2D(_EmissionMap, sampler_EmissionMap, uvEmi).rgb * _EmissionColor.rgb;

    // --- 金属工作流换算 ---
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

// =============================================================================
// 六、直接光照 — 主光 + 附加光
// =============================================================================

// -----------------------------------------------------------------------------
// [效果] 单盏直接光着色 = (漫反射*(1-F) + 高光BRDF) * Radiance * NdotL
// 流程：
//   1) 构造半角 H = normalize(V+L)
//   2) 漫反射：Lambert * (1-F) * (1-transmission)
//   3) 高光：Cook-Torrance D·G·F
//   4) 乘灯光颜色、距离衰减、阴影
// Metal-Rough 阵列：同一光照下对比金属度/粗糙度对漫反射与高光的影响。
// -----------------------------------------------------------------------------
inline half3 GltfShadeDirectLight(GltfSurfaceData s, half3 N, half3 V, Light light)
{
    half3 L = light.direction;
    half3 H = normalize(V + L);

    half NdotL = saturate(dot(N, L));
    half NdotV = saturate(dot(N, V));
    half NdotH = saturate(dot(N, H));
    half VdotH = saturate(dot(V, H));

    // Fresnel：同时削弱漫反射、增强高光（能量守恒拆分）
    half3 F = GltfFresnelSchlick(s.f0, VdotH);
    half3 diffuse = GltfDiffuseBRDF(s.diffuseColor) * (1.0h - F) * _DirectDiffuseIntensity;
    half3 specular = GltfSpecularBRDF(s.f0, NdotV, NdotL, NdotH, VdotH, s.roughness)
                   * _SpecularIntensity * _DirectSpecularIntensity;

    // 透射材料：漫反射能量让给透射项，表面高光仍保留（玻璃仍有反射）
    diffuse *= (1.0h - s.transmission);

    half3 radiance = light.color * (light.distanceAttenuation * light.shadowAttenuation);
    return (diffuse + specular) * radiance * NdotL;
}

// =============================================================================
// 七、环境光照（IBL）— SH 漫反射 + Cubemap 高光
// =============================================================================

// -----------------------------------------------------------------------------
// [效果] 环境光
//   漫反射：球谐 SampleSH(N) * diffuseColor * (1-F) * (1-transmission)
//   高光  ：反射向量采样 SpecCube，mip = f(roughness)
// 观感：
//   - 光滑金属：清晰环境倒影
//   - 粗糙表面：倒影变糊、变弱（Metal-Rough 阵列自上而下可见）
//   - 最后乘 AO，暗缝更沉
// -----------------------------------------------------------------------------
inline half3 GltfShadeEnvironment(GltfSurfaceData s, half3 N, half3 V, float3 positionWS)
{
    half NdotV = saturate(dot(N, V));
    half3 F = GltfFresnelSchlickRoughness(s.f0, NdotV, s.perceptualRoughness);

    // --- 环境漫反射（间接光）---
    half3 irradiance = SampleSH(N);
    half3 diffuse = irradiance * s.diffuseColor * (1.0h - F) * (1.0h - s.transmission);

    // --- 环境高光：按粗糙度选 Cubemap mip（预过滤 IBL）---
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

// =============================================================================
// 八、透射 BRDF — TransmissionRoughnessTest（玻璃 / 液体）
// =============================================================================

// -----------------------------------------------------------------------------
// [效果] Beer-Lambert 体积衰减（KHR_materials_volume 简化）
// 公式：exp(-opticalDepth * thickness)
// 观感：厚液体/染色玻璃越厚颜色越深；AttenuationColor 控制染色色相。
// -----------------------------------------------------------------------------
inline half3 GltfVolumeAttenuation(half3 attenuationColor, half attenuationDistance, half thickness)
{
    if (attenuationDistance <= 1e-4h)
        return half3(1, 1, 1);
    half3 opticalDepth = -log(max(attenuationColor, half3(1e-5, 1e-5, 1e-5))) / attenuationDistance;
    return exp(-opticalDepth * max(thickness, 0.0h));
}

// -----------------------------------------------------------------------------
// [效果] 透射着色
// 步骤：
//   1) refract(-V, N, 1/IOR) 得到折射方向；全反射时退化为 reflect
//   2) 用 (roughness + boost) 选 Cubemap mip → 磨砂透射模糊
//   3) 可选：屏幕空间折射偏移采样背后场景（Opaque Texture）
//   4) × 体积衰减 × albedo
//   5) × (1-F) * transmission —— 反射能量不进入透射
// 对应测试：TransmissionRoughnessTest 矩阵（透射度 × 粗糙度）。
// -----------------------------------------------------------------------------
inline half3 GltfShadeTransmission(GltfSurfaceData s, GltfInputData input, half3 N, half3 V)
{
    if (s.transmission < 1e-4h)
        return 0;

    // --- 折射方向 ---
    half eta = 1.0h / s.ior;
    half3 refrDir = refract(-V, N, eta);
    if (dot(refrDir, refrDir) < 1e-6h)
        refrDir = reflect(-V, N); // 全内反射退化

    // --- 模糊透射（粗糙度越大背后越糊）---
    half transmissionRoughness = saturate(s.perceptualRoughness + _TransmissionRoughnessBoost);
    half mip = PerceptualRoughnessToMipmapLevel(transmissionRoughness);

    half4 encoded = SAMPLE_TEXTURECUBE_LOD(unity_SpecCube0, samplerunity_SpecCube0, refrDir, mip);
#if !defined(UNITY_USE_NATIVE_HDR)
    half3 transmitted = DecodeHDREnvironment(encoded, unity_SpecCube0_HDR);
#else
    half3 transmitted = encoded.rgb;
#endif

#if defined(GLTF_USE_OPAQUE_TEXTURE)
    // --- 屏幕空间折射：法线 XY 偏移采样不透明场景色 ---
    float2 uvSS = input.screenPos.xy / max(input.screenPos.w, 1e-5);
    float2 offset = N.xy * (_RefractionStrength * (1.0h - transmissionRoughness));
    half3 sceneColor = SampleSceneColor(saturate(uvSS + offset));
    transmitted = lerp(transmitted, sceneColor, saturate(_RefractionStrength));
#endif

    // --- 体积染色 ---
    half thickness = max(_ThicknessFactor, 0.0h);
    half3 attenuation = GltfVolumeAttenuation(_AttenuationColor.rgb, _AttenuationDistance, thickness);
    transmitted *= attenuation * s.albedo;

    // --- 能量：透射只拿走非反射部分 ---
    half NdotV = saturate(dot(N, V));
    half3 F = GltfFresnelSchlickRoughness(s.f0, NdotV, s.perceptualRoughness);
    return transmitted * (1.0h - F) * s.transmission;
}

// =============================================================================
// 九、Debug 可视化 — SpecularTest / 通道检查
// =============================================================================

// -----------------------------------------------------------------------------
// [效果] DebugMode 分流
// 用途：精准验证高光 BRDF 形状/强度/边缘，以及贴图通道是否正确。
//   1 SpecularOnly — 只看高光瓣
//   2 DiffuseOnly  — 只看漫反射
//   3 D_GGX        — 高光形状（分布项）
//   4 Fresnel      — 边缘衰减
//   5~10           — Metallic / Rough / Normal / AO / Base / F0
// -----------------------------------------------------------------------------
inline half3 GltfApplyDebug(half3 litColor, GltfSurfaceData s, half3 N, half3 V, Light mainLight)
{
    int mode = (int)_DebugMode;
    if (mode <= 0)
        return litColor;

    half3 L = mainLight.direction;
    half3 H = normalize(V + L);
    half NdotL = saturate(dot(N, L));
    half NdotV = saturate(dot(N, V));
    half NdotH = saturate(dot(N, H));
    half VdotH = saturate(dot(V, H));

    switch (mode)
    {
        case 1: // 高光 only：形状 + 强度
        {
            half3 spec = GltfSpecularBRDF(s.f0, NdotV, NdotL, NdotH, VdotH, s.roughness)
                       * mainLight.color * NdotL * _SpecularIntensity;
            return spec;
        }
        case 2: // 漫反射 only：金属度↑应明显变暗
            return GltfDiffuseBRDF(s.diffuseColor) * mainLight.color * NdotL;
        case 3: // D 项：高光几何形状（缩放 0.1 避免过曝）
        {
            half D = GltfD_GGX(NdotH, s.roughness);
            return D.xxx * 0.1h;
        }
        case 4: // Fresnel：掠射应变亮
            return GltfFresnelSchlick(s.f0, VdotH);
        case 5: // Metallic 通道
            return s.metallic.xxx;
        case 6: // Roughness 通道
            return s.perceptualRoughness.xxx;
        case 7: // 世界法线（Normal-Tangent 正确性）
            return N * 0.5h + 0.5h;
        case 8: // AO
            return s.ao.xxx;
        case 9: // BaseColor
            return s.albedo;
        case 10: // F0 / SpecularColor
            return s.f0;
        default:
            return litColor;
    }
}

// =============================================================================
// 十、完整着色入口 — 串联所有效果段
// =============================================================================

// -----------------------------------------------------------------------------
// [效果总成] GltfEvaluateLighting
// 流水线：
//   ① 采样表面参数（Metal-Rough / Base / AO / Emission）
//   ② 法线贴图 → 世界法线（Normal-Tangent）
//   ③ 主光 + 附加光直接光照（Specular / Diffuse BRDF）
//   ④ 环境 IBL
//   ⑤ 透射（TransmissionRoughness）
//   ⑥ 自发光
//   ⑦ Debug 覆盖（SpecularTest）
//   ⑧ 透射材质输出 alpha，供 Transparent 混合
// -----------------------------------------------------------------------------
inline half4 GltfEvaluateLighting(GltfInputData input)
{
    // ① 表面参数
    GltfSurfaceData s = GltfSampleSurface(input.uv);

    // ② 切线空间法线
    half3 normalTS = GltfSampleNormalTS(TRANSFORM_TEX(input.uv, _BumpMap));
    half3 N = GltfGetNormalWS(input, normalTS);
    half3 V = normalize(input.viewDirWS);

    // ③ 直接光
    Light mainLight = GetMainLight();
    half3 color = GltfShadeDirectLight(s, N, V, mainLight);

    uint lightsCount = GetAdditionalLightsCount();
    for (uint i = 0u; i < lightsCount; ++i)
    {
        Light light = GetAdditionalLight(i, input.positionWS);
        color += GltfShadeDirectLight(s, N, V, light);
    }

    // ④ 环境光
    color += GltfShadeEnvironment(s, N, V, input.positionWS);

    // ⑤ 透射
    color += GltfShadeTransmission(s, input, N, V);

    // ⑥ 自发光
    color += s.emission;

    // ⑦ Debug
    color = GltfApplyDebug(color, s, N, V, mainLight);

    // ⑧ 透射 alpha：alpha ≈ 1 - transmission*(1-F)，掠射仍偏不透明（保留边缘反射）
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
