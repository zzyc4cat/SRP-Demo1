#ifndef WATER_LIGHTING_INCLUDED
#define WATER_LIGHTING_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

#define SHADOW_ITERATIONS 4

half CalculateFresnelTerm(half3 normalWS, half3 viewDirectionWS)
{
    return saturate(pow(1.0 - dot(normalWS, viewDirectionWS), 5));
}

// 顶点光和雾。返回值 x 是雾，yzw 是顶点光
half4 VertexLightingAndFog(half3 normalWS, half3 posWS, half3 clipPos)
{
    half3 vertexLight = VertexLighting(posWS, normalWS);
    half fogFactor = ComputeFogFactor(clipPos.z);
    return half4(fogFactor, vertexLight);
}

// 移动端近似的 GGX 高光，粗糙度来自水面材质
half3 Highlights(half3 positionWS, half roughness, half3 normalWS, half3 viewDirectionWS)
{
    Light mainLight = GetMainLight();

    half roughness2 = roughness * roughness;
    half3 halfDir = SafeNormalize(mainLight.direction + viewDirectionWS);
    half NoH = saturate(dot(normalize(normalWS), halfDir));
    half LoH = saturate(dot(mainLight.direction, halfDir));
    half d = NoH * NoH * (roughness2 - 1.h) + 1.0001h;
    half LoH2 = LoH * LoH;
    half specularTerm = roughness2 / ((d * d) * max(0.1h, LoH2) * (roughness + 0.5h) * 4);
#if defined (SHADER_API_MOBILE)
    specularTerm = specularTerm - HALF_MIN;
    specularTerm = clamp(specularTerm, 0.0, 5.0);
#endif
    return specularTerm * mainLight.color * mainLight.distanceAttenuation;
}

// 沿视线抖动多次采样阴影图，水深越大抖动越开
half SoftShadows(float3 screenUV, float3 positionWS, half3 viewDir, half depth)
{
#if _MAIN_LIGHT_SHADOWS
    half2 jitterUV = screenUV.xy * _ScreenParams.xy * _DitherPattern_TexelSize.xy;
	half shadowAttenuation = 0;

	float loopDiv = 1.0 / SHADOW_ITERATIONS;
	half depthFrac = depth * loopDiv;
	half3 lightOffset = -viewDir * depthFrac;
	for (uint i = 0u; i < SHADOW_ITERATIONS; ++i)
    {
#ifndef _STATIC_SHADER
        jitterUV += frac(half2(_Time.x, -_Time.z));
#endif
        float3 jitterTexture = SAMPLE_TEXTURE2D(_DitherPattern, sampler_DitherPattern, jitterUV + i * _ScreenParams.xy).xyz * 2 - 1;
	    half3 j = jitterTexture.xzy * depthFrac * i * 0.1;
	    float3 lightJitter = (positionWS + j) + (lightOffset * (i + jitterTexture.y));
	    shadowAttenuation += SAMPLE_TEXTURE2D_SHADOW(_MainLightShadowmapTexture, sampler_MainLightShadowmapTexture, TransformWorldToShadowCoord(lightJitter));
	}
    return BEYOND_SHADOW_FAR(TransformWorldToShadowCoord(positionWS * 1.1)) ? 1.0 : shadowAttenuation * loopDiv;
#else
    return 1;
#endif
}

// 三种反射：Cubemap、最近反射探针、平面反射贴图。平面反射会用法线偏移 UV
half3 SampleReflections(half3 normalWS, half3 viewDirectionWS, half2 screenUV, half roughness)
{
    half3 reflection = 0;
    half2 refOffset = 0;

#if _REFLECTION_CUBEMAP
    half3 reflectVector = reflect(-viewDirectionWS, normalWS);
    reflection = SAMPLE_TEXTURECUBE(_CubemapTexture, sampler_CubemapTexture, reflectVector).rgb;
#elif _REFLECTION_PROBES
    half3 reflectVector = reflect(-viewDirectionWS, normalWS);
    reflection = GlossyEnvironmentReflection(reflectVector, 0, 1);
#elif _REFLECTION_PLANARREFLECTION

    float2 p11_22 = float2(unity_CameraInvProjection._11, unity_CameraInvProjection._22) * 10;
    float3 viewDir = -(float3((screenUV * 2 - 1) / p11_22, -1));

    half3 viewNormal = mul(normalWS, (float3x3)GetWorldToViewMatrix()).xyz;
    half3 reflectVector = reflect(-viewDir, viewNormal);

    half2 reflectionUV = screenUV + normalWS.zx * half2(0.02, 0.15);
    reflection += SAMPLE_TEXTURE2D_LOD(_PlanarReflectionTexture, sampler_ScreenTextures_linear_clamp, reflectionUV, 6 * roughness).rgb;
#endif
    return reflection;
}

#endif // WATER_LIGHTING_INCLUDED