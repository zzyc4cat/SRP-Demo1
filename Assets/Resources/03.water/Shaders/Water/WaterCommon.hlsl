#ifndef WATER_COMMON_INCLUDED
#define WATER_COMMON_INCLUDED

#define SHADOWS_SCREEN 0

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "WaterInput.hlsl"
#include "CommonUtilities.hlsl"
#include "GerstnerWaves.hlsl"
#include "WaterLighting.hlsl"

// 顶点输入输出。波浪位移后的世界坐标和波浪前的屏幕坐标分开保存，折射和 WaterFX 要用后者。

struct WaterVertexInput
{
	float4	vertex 					: POSITION;
	float2	texcoord 				: TEXCOORD0;
	UNITY_VERTEX_INPUT_INSTANCE_ID
};

struct WaterVertexOutput
{
	float4	uv 						: TEXCOORD0;	// xy 几何 UV，zw 世界水平 UV
	float3	posWS					: TEXCOORD1;
	half3 	normal 					: NORMAL;
	float3 	viewDir 				: TEXCOORD2;
	float3	preWaveSP 				: TEXCOORD3;	// 波浪位移前的屏幕坐标
	half2 	fogFactorNoise          : TEXCOORD4;	// x 雾，y 噪声
	float4	additionalData			: TEXCOORD5;	// x 视线拉伸，y 到相机距离，z 归一化波高，w 水平位移
	half4	shadowCoord				: TEXCOORD6;

	float4	clipPos					: SV_POSITION;
	UNITY_VERTEX_INPUT_INSTANCE_ID
	UNITY_VERTEX_OUTPUT_STEREO
};

// 把 WaterFX 的法线、泡沫、位移分三块画出来，只给调试用
half3 DebugWaterFX(half3 input, half4 waterFX, half screenUV)
{
    input = lerp(input, half3(waterFX.y, 1, waterFX.z), saturate(floor(screenUV + 0.7)));
    input = lerp(input, waterFX.xxx, saturate(floor(screenUV + 0.5)));
    half3 disp = lerp(0, half3(1, 0, 0), saturate((waterFX.www - 0.5) * 4));
    disp += lerp(0, half3(0, 0, 1), saturate(((1-waterFX.www) - 0.5) * 4));
    input = lerp(input, disp, saturate(floor(screenUV + 0.3)));
    return input;
}

// 水色、水深、折射。吸收和散射都从同一张 ramp 的不同行取出。

half3 Scattering(half depth)
{
	return SAMPLE_TEXTURE2D(_AbsorptionScatteringRamp, sampler_AbsorptionScatteringRamp, half2(depth, 0.375h)).rgb;
}

half3 Absorption(half depth)
{
	return SAMPLE_TEXTURE2D(_AbsorptionScatteringRamp, sampler_AbsorptionScatteringRamp, half2(depth, 0.0h)).rgb;
}

float2 AdjustedDepth(half2 uvs, half4 additionalData)
{
	float rawD = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, sampler_ScreenTextures_linear_clamp, uvs);
	float d = LinearEyeDepth(rawD, _ZBufferParams);

#if UNITY_REVERSED_Z
	float offset = 0;
#else
	float offset = 1;
#endif
	
 	return float2(d * additionalData.x - additionalData.y, (rawD * -_ProjectionParams.x) + offset);
}

float WaterTextureDepth(float3 posWS)
{
    return (1 - SAMPLE_TEXTURE2D_LOD(_WaterDepthMap, sampler_WaterDepthMap_linear_clamp, posWS.xz * 0.002 + 0.5, 1).r) * (_MaxDepth + _VeraslWater_DepthCamParams.x) - _VeraslWater_DepthCamParams.x;
}

// 正交水深图还原的水深。x 是视线深度，y 是岸边水深
float3 WaterDepth(float3 posWS, half4 additionalData, half2 screenUVs)
{
	float3 outDepth = 0;
	outDepth.xz = AdjustedDepth(screenUVs, additionalData);
	float wd = WaterTextureDepth(posWS);
	outDepth.y = wd + posWS.y;
	return outDepth;
}

half3 Refraction(half2 distortion, half depth, real depthMulti)
{
	half3 output = SAMPLE_TEXTURE2D_LOD(_CameraOpaqueTexture, sampler_CameraOpaqueTexture_linear_clamp, distortion, depth * 0.25).rgb;
	output *= Absorption((depth) * depthMulti);
	return output;
}

half2 DistortionUVs(half depth, float3 normalWS)
{
    half3 viewNormal = mul((float3x3)GetWorldToHClipMatrix(), -normalWS).xyz;

    return viewNormal.xz * saturate((depth) * 0.005);
}

half4 AdditionalData(float3 postionWS, WaveStruct wave)
{
    half4 data = half4(0.0, 0.0, 0.0, 0.0);
    float3 viewPos = TransformWorldToView(postionWS);
	data.x = length(viewPos / viewPos.z);
    data.y = length(GetCameraPositionWS().xyz - postionWS);
	data.z = wave.position.y / _MaxWaveHeight * 0.5 + 0.5;
	data.w = wave.position.x + wave.position.z;
	return data;
}

WaterVertexOutput WaveVertexOperations(WaterVertexOutput input)
{
#ifdef _STATIC_SHADER
	float time = 0;
#else
	float time = _Time.y;
#endif

    input.normal = float3(0, 1, 0);
	input.fogFactorNoise.y = ((noise((input.posWS.xz * 0.5) + time) + noise((input.posWS.xz * 1) + time)) * 0.25 - 0.5) + 1;

	// 两套滚动 UV，后面叠细法线
    input.uv.zw = input.posWS.xz * 0.1h + time * 0.05h + (input.fogFactorNoise.y * 0.1);
    input.uv.xy = input.posWS.xz * 0.4h - time.xx * 0.1h + (input.fogFactorNoise.y * 0.2);

	half4 screenUV = ComputeScreenPos(TransformWorldToHClip(input.posWS));
	screenUV.xyz /= screenUV.w;

    // 浅水把顶点抬高，避免网格穿进岸边
    half waterDepth = WaterTextureDepth(input.posWS);
    input.posWS.y += pow(saturate((-waterDepth + 1.5) * 0.4), 2);

	// Gerstner 位移和法线。水深越浅，水平位移越小
	WaveStruct wave;
	SampleWaves(input.posWS, saturate((waterDepth * 0.1 + 0.05)), wave);
	input.normal = wave.normal;
    input.posWS += wave.position;

#ifdef SHADER_API_PS4
	input.posWS.y -= 0.5;
#endif

    // WaterFX 的 A 通道是局部上下位移，0.5 表示不动
	half4 waterFX = SAMPLE_TEXTURE2D_LOD(_WaterFXMap, sampler_ScreenTextures_linear_clamp, screenUV.xy, 0);
	input.posWS.y += waterFX.w * 2 - 1;

	input.clipPos = TransformWorldToHClip(input.posWS);
	input.shadowCoord = ComputeScreenPos(input.clipPos);
    input.viewDir = SafeNormalize(_WorldSpaceCameraPos - input.posWS);

	input.fogFactorNoise.x = ComputeFogFactor(input.clipPos.z);
	input.preWaveSP = screenUV.xyz;

	input.additionalData = AdditionalData(input.posWS, wave);

	// 远处法线拉平，避免远景闪烁
	half distanceBlend = saturate(abs(length((_WorldSpaceCameraPos.xz - input.posWS.xz) * 0.005)) - 0.25);
	input.normal = lerp(input.normal, half3(0, 1, 0), distanceBlend);

	return input;
}

// 顶点只做对象到世界，波浪在 WaveVertexOperations 里完成
WaterVertexOutput WaterVertex(WaterVertexInput v)
{
    WaterVertexOutput o;
	UNITY_SETUP_INSTANCE_ID(v);
    UNITY_TRANSFER_INSTANCE_ID(v, o);
	UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);

    o.uv.xy = v.texcoord;
    o.posWS = TransformObjectToWorld(v.vertex.xyz);

	o = WaveVertexOperations(o);
    return o;
}

// 片元：细法线、折射、菲涅尔、次表面、泡沫、高光，最后和反射合成
half4 WaterFragment(WaterVertexOutput IN) : SV_Target
{
	UNITY_SETUP_INSTANCE_ID(IN);
	half3 screenUV = IN.shadowCoord.xyz / IN.shadowCoord.w;

	half4 waterFX = SAMPLE_TEXTURE2D(_WaterFXMap, sampler_ScreenTextures_linear_clamp, IN.preWaveSP.xy);

	// 视线深度和岸边水深，用来压折射、泡沫和水色
	float3 depth = WaterDepth(IN.posWS, IN.additionalData, screenUV.xy);
	half depthMulti = 1 / _MaxDepth;

    // 两层滚动法线叠到 Gerstner 法线上，浅水减弱，再加 WaterFX 法线
	half2 detailBump1 = SAMPLE_TEXTURE2D(_SurfaceMap, sampler_SurfaceMap, IN.uv.zw).xy * 2 - 1;
	half2 detailBump2 = SAMPLE_TEXTURE2D(_SurfaceMap, sampler_SurfaceMap, IN.uv.xy).xy * 2 - 1;
	half2 detailBump = (detailBump1 + detailBump2 * 0.5) * saturate(depth.x * 0.25 + 0.25);

	IN.normal += half3(detailBump.x, 0, detailBump.y) * _BumpScale;
	IN.normal += half3(1-waterFX.y, 0.5h, 1-waterFX.z) - 0.5;
	IN.normal = normalize(IN.normal);

    // 用法线偏移不透明贴图 UV。若偏到水面上，退回原 UV
	half2 distortion = DistortionUVs(depth.x, IN.normal);
	distortion = screenUV.xy + distortion;
	float d = depth.x;
	depth.xz = AdjustedDepth(distortion, IN.additionalData);
	distortion = depth.x < 0 ? screenUV.xy : distortion;
	depth.x = depth.x < 0 ? d : depth.x;

	half fresnelTerm = CalculateFresnelTerm(IN.normal, IN.viewDir.xyz);

	Light mainLight = GetMainLight(TransformWorldToShadowCoord(IN.posWS));
    half shadow = SoftShadows(screenUV, IN.posWS, IN.viewDir.xyz, depth.x);
    half3 GI = SampleSH(IN.normal);

    // 次表面：天顶光加上逆光方向的浪尖透光
    half3 directLighting = dot(mainLight.direction, half3(0, 1, 0)) * mainLight.color;
    directLighting += saturate(pow(dot(IN.viewDir, -mainLight.direction) * IN.additionalData.z, 3)) * 5 * mainLight.color;
    half3 sss = directLighting * shadow + GI;

	// 泡沫来自三处：浪尖、岸线、WaterFX 的 R。贴图 RGB 是厚、中、薄
	half3 foamMap = SAMPLE_TEXTURE2D(_FoamMap, sampler_FoamMap,  IN.uv.zw).rgb;
	half depthEdge = saturate(depth.x * 20);
	half waveFoam = saturate(IN.additionalData.z - 0.75 * 0.5);
	half depthAdd = saturate(1 - depth.x * 4) * 0.5;
	half edgeFoam = saturate((1 - min(depth.x, depth.y) * 0.5 - 0.25) + depthAdd) * depthEdge;
	half foamBlendMask = max(max(waveFoam, edgeFoam), waterFX.r * 2);
	half3 foamBlend = SAMPLE_TEXTURE2D(_AbsorptionScatteringRamp, sampler_AbsorptionScatteringRamp, half2(foamBlendMask, 0.66)).rgb;
	half foamMask = saturate(length(foamMap * foamBlend) * 1.5 - 0.1);
	half3 foam = foamMask.xxx * (mainLight.shadowAttenuation * mainLight.color + GI);

    BRDFData brdfData;
    half alpha = 1;
    InitializeBRDFData(half3(0, 0, 0), 0, half3(1, 1, 1), 0.95, alpha, brdfData);
	half3 spec = DirectBDRF(brdfData, IN.normal, mainLight.direction, IN.viewDir) * shadow * mainLight.color;
#ifdef _ADDITIONAL_LIGHTS
    uint pixelLightCount = GetAdditionalLightsCount();
    for (uint lightIndex = 0u; lightIndex < pixelLightCount; ++lightIndex)
    {
        Light light = GetAdditionalLight(lightIndex, IN.posWS);
        spec += LightingPhysicallyBased(brdfData, light, IN.normal, IN.viewDir);
        sss += light.distanceAttenuation * light.color;
    }
#endif

    sss *= Scattering(depth.x * depthMulti);

	half3 reflection = SampleReflections(IN.normal, IN.viewDir.xyz, screenUV.xy, 0.0);

	// 折射按水深乘吸收色，再按菲涅尔和反射混合，泡沫盖在最上面
	half3 refraction = Refraction(distortion, depth.x, depthMulti);

	half3 comp = lerp(lerp(refraction, reflection, fresnelTerm) + sss + spec, foam, foamMask);

    float fogFactor = IN.fogFactorNoise.x;
    comp = MixFog(comp, fogFactor);
#if defined(_DEBUG_FOAM)
    return half4(foamMask.xxx, 1);
#elif defined(_DEBUG_SSS)
    return half4(sss, 1);
#elif defined(_DEBUG_REFRACTION)
    return half4(refraction, 1);
#elif defined(_DEBUG_REFLECTION)
    return half4(reflection, 1);
#elif defined(_DEBUG_NORMAL)
    return half4(IN.normal.x * 0.5 + 0.5, 0, IN.normal.z * 0.5 + 0.5, 1);
#elif defined(_DEBUG_FRESNEL)
    return half4(fresnelTerm.xxx, 1);
#elif defined(_DEBUG_WATEREFFECTS)
    return half4(waterFX);
#elif defined(_DEBUG_WATERDEPTH)
    return half4(frac(depth), 1);
#else
    return half4(comp, 1);
#endif
}

#endif // WATER_COMMON_INCLUDED