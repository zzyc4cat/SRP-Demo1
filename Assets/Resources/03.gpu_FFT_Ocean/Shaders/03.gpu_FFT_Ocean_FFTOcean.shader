// =============================================================================
// ZZY/03.gpu_FFT_Ocean/FFTOcean — URP Forward 海面着色（gasgiant / Tessendorf 三频带 FFT）
// -----------------------------------------------------------------------------
// 输入：每级联 Displacement / Derivatives / Turbulence（由 Compute 管线填充）
// 效果分段：
//   [Vertex]     XYZ 位移 + LOD 级联权重 + 大浪偏置（供 SSS / 浪尖泡沫）
//   [Depth]      场景深度 → 深浅水色 / Beer 吸收 / 屏幕折射
//   [Lighting]   Fresnel + 环境反射 + Blinn 高光 + SSS
//   [Whitecaps]  Tessendorf Jacobian 折叠白沫 + 波峰高度 + 四方连续噪声絮状
// =============================================================================
Shader "ZZY/03.gpu_FFT_Ocean/FFTOcean"
{
    Properties
    {
        // ----- [Albedo] 深浅水色 / SSS 色 -----
        [Header(Colors)]
        _OceanColorShallow ("Shallow", Color) = (0.40, 0.78, 0.72, 1)
        _OceanColorMid ("Mid", Color) = (0.04, 0.38, 0.52, 1)
        _OceanColorDeep ("Deep", Color) = (0.01, 0.10, 0.26, 1)
        _SSSColor ("SSS Color", Color) = (0.20, 0.75, 0.70, 1)

        // ----- [Depth] Beer 吸收与透明度 -----
        [Header(Depth)]
        _ShallowDistance ("Shallow Distance", Range(0.1, 20)) = 1.5
        _DeepDistance ("Deep Distance", Range(1, 80)) = 18
        _Absorption ("Absorption", Range(0.1, 8)) = 1.4
        _Opacity ("Base Opacity", Range(0, 1)) = 0.92

        // ----- [Lighting] 高光 / Fresnel / 天空 / SSS / LOD -----
        [Header(Lighting)]
        _SpecularIntensity ("Specular", Range(0, 8)) = 2.5
        _Gloss ("Gloss", Range(8, 512)) = 180
        _FresnelPower ("Fresnel Power", Range(1, 8)) = 5
        _FresnelBias ("Fresnel Bias", Range(0, 0.5)) = 0.04
        _EnvIntensity ("Sky Reflection", Range(0, 2)) = 0.75
        _SSSIntensity ("SSS Intensity", Range(0, 3)) = 1.1
        _SSSPower ("SSS Power", Range(1, 16)) = 4
        _LOD_scale ("Cascade LOD Scale", Range(0.5, 20)) = 8

        // ----- [Whitecaps] Jacobian 阈值 + 波峰 + 絮状噪声 -----
        [Header(Foam Whitecaps)]
        _FoamColor ("Foam Color", Color) = (0.97, 0.99, 1.0, 1)
        _FoamBias ("Jacobian Foam Bias", Range(0, 7)) = 2.85
        _FoamScale ("Foam Intensity", Range(0, 8)) = 1.35
        _CrestFoam ("Crest Peak Foam", Range(0, 4)) = 1.6
        _ContactFoam ("Contact Foam", Range(0, 3)) = 0.2
        _FoamNoise ("Foam Noise", 2D) = "white" {}
        _FoamNoiseScale ("Foam Noise Scale", Range(0.01, 2)) = 0.08

        // ----- [Refraction] 屏幕空间折射强度 -----
        [Header(Refraction)]
        _RefractionStrength ("Refraction", Range(0, 0.5)) = 0.12

        // ----- [Cascades] 由 FFTOceanSimulator 每帧绑定 -----
        [Header(Cascades Hidden)]
        [HideInInspector] _Displacement_c0 ("Disp0", 2D) = "black" {}
        [HideInInspector] _Derivatives_c0 ("Der0", 2D) = "black" {}
        [HideInInspector] _Turbulence_c0 ("Turb0", 2D) = "white" {}
        [HideInInspector] _Displacement_c1 ("Disp1", 2D) = "black" {}
        [HideInInspector] _Derivatives_c1 ("Der1", 2D) = "black" {}
        [HideInInspector] _Turbulence_c1 ("Turb1", 2D) = "white" {}
        [HideInInspector] _Displacement_c2 ("Disp2", 2D) = "black" {}
        [HideInInspector] _Derivatives_c2 ("Der2", 2D) = "black" {}
        [HideInInspector] _Turbulence_c2 ("Turb2", 2D) = "white" {}
        [HideInInspector] _LengthScale0 ("Len0", Float) = 250
        [HideInInspector] _LengthScale1 ("Len1", Float) = 17
        [HideInInspector] _LengthScale2 ("Len2", Float) = 5
    }

    SubShader
    {
        Tags
        {
            "RenderPipeline" = "UniversalPipeline"
            "Queue" = "Transparent"
            "RenderType" = "Transparent"
            "IgnoreProjector" = "True"
        }

        Pass
        {
            Name "FFTOceanForward"
            Tags { "LightMode" = "UniversalForward" }

            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite Off
            Cull Back

            HLSLPROGRAM
            #pragma target 3.5
            #pragma vertex Vert
            #pragma fragment Frag
            #pragma multi_compile_fog
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile_fragment _ _SHADOWS_SOFT

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareOpaqueTexture.hlsl"

            TEXTURE2D(_Displacement_c0); SAMPLER(sampler_Displacement_c0);
            TEXTURE2D(_Displacement_c1); SAMPLER(sampler_Displacement_c1);
            TEXTURE2D(_Displacement_c2); SAMPLER(sampler_Displacement_c2);
            TEXTURE2D(_Derivatives_c0); SAMPLER(sampler_Derivatives_c0);
            TEXTURE2D(_Derivatives_c1); SAMPLER(sampler_Derivatives_c1);
            TEXTURE2D(_Derivatives_c2); SAMPLER(sampler_Derivatives_c2);
            TEXTURE2D(_Turbulence_c0); SAMPLER(sampler_Turbulence_c0);
            TEXTURE2D(_Turbulence_c1); SAMPLER(sampler_Turbulence_c1);
            TEXTURE2D(_Turbulence_c2); SAMPLER(sampler_Turbulence_c2);
            TEXTURE2D(_FoamNoise); SAMPLER(sampler_FoamNoise);

            CBUFFER_START(UnityPerMaterial)
                float4 _OceanColorShallow;
                float4 _OceanColorMid;
                float4 _OceanColorDeep;
                float4 _FoamColor;
                float4 _SSSColor;
                float _ShallowDistance;
                float _DeepDistance;
                float _Absorption;
                float _Opacity;
                float _SpecularIntensity;
                float _Gloss;
                float _FresnelPower;
                float _FresnelBias;
                float _EnvIntensity;
                float _SSSIntensity;
                float _SSSPower;
                float _LOD_scale;
                float _FoamBias;
                float _FoamScale;
                float _CrestFoam;
                float _ContactFoam;
                float4 _FoamNoise_ST;
                float _FoamNoiseScale;
                float _RefractionStrength;
                float _LengthScale0;
                float _LengthScale1;
                float _LengthScale2;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                float4 screenPos : TEXCOORD1;
                float viewDist : TEXCOORD2;
                float fogFactor : TEXCOORD3;
                float largeWaveY : TEXCOORD4;
            };

            float SampleLod(float lengthScale, float viewDist)
            {
                // 距离越大越裁掉短波长级联，减轻远处高频闪烁
                return saturate(_LOD_scale * lengthScale / max(viewDist, 1.0));
            }

            // ----- [Vertex] 三频带位移采样 -----
            float3 SampleDisplacement(float2 worldXZ, float viewDist)
            {
                float lod0 = SampleLod(_LengthScale0, viewDist);
                float lod1 = SampleLod(_LengthScale1, viewDist);
                float lod2 = SampleLod(_LengthScale2, viewDist);
                float3 d = 0;
                d += SAMPLE_TEXTURE2D_LOD(_Displacement_c0, sampler_Displacement_c0, worldXZ / _LengthScale0, 0).xyz * lod0;
                d += SAMPLE_TEXTURE2D_LOD(_Displacement_c1, sampler_Displacement_c1, worldXZ / _LengthScale1, 0).xyz * lod1;
                d += SAMPLE_TEXTURE2D_LOD(_Displacement_c2, sampler_Displacement_c2, worldXZ / _LengthScale2, 0).xyz * lod2;
                return d;
            }

            Varyings Vert(Attributes input)
            {
                Varyings o;
                float3 posWS = TransformObjectToWorld(input.positionOS.xyz);
                float viewDist = length(_WorldSpaceCameraPos - posWS);
                float3 displacement = SampleDisplacement(posWS.xz, viewDist);
                // 大尺度级联高度：用于 SSS 与浪尖白沫（相对细浪的额外抬升）
                float largeY = SAMPLE_TEXTURE2D_LOD(_Displacement_c0, sampler_Displacement_c0, posWS.xz / _LengthScale0, 0).y
                    * SampleLod(_LengthScale0, viewDist);
                posWS += displacement;
                o.positionWS = posWS;
                o.positionCS = TransformWorldToHClip(posWS);
                o.screenPos = ComputeScreenPos(o.positionCS);
                o.viewDist = viewDist;
                o.fogFactor = ComputeFogFactor(o.positionCS.z);
                o.largeWaveY = max(displacement.y - largeY * 0.8, 0);
                return o;
            }

            // ----- [Normal] 由导数图重建坡度法线（gasgiant Ocean.shader） -----
            float3 SampleNormal(float2 worldXZ, float viewDist)
            {
                float lod1 = SampleLod(_LengthScale1, viewDist);
                float lod2 = SampleLod(_LengthScale2, viewDist);
                float4 der = SAMPLE_TEXTURE2D(_Derivatives_c0, sampler_Derivatives_c0, worldXZ / _LengthScale0);
                der += SAMPLE_TEXTURE2D(_Derivatives_c1, sampler_Derivatives_c1, worldXZ / _LengthScale1) * lod1;
                der += SAMPLE_TEXTURE2D(_Derivatives_c2, sampler_Derivatives_c2, worldXZ / _LengthScale2) * lod2;
                float2 slope = float2(der.x / (1.0 + der.z), der.y / (1.0 + der.w));
                return normalize(float3(-slope.x, 1.0, -slope.y));
            }

            // ----- [Whitecaps] Tessendorf：J 变低表示水平位移折叠 → 浪尖破碎 -----
            // Turbulence 存的是累积后的 J（平静≈高，折叠≈低）
            float SampleJacobianFoam(float2 worldXZ, float viewDist)
            {
                float lod1 = SampleLod(_LengthScale1, viewDist);
                float lod2 = SampleLod(_LengthScale2, viewDist);
                float j =
                    SAMPLE_TEXTURE2D(_Turbulence_c0, sampler_Turbulence_c0, worldXZ / _LengthScale0).x +
                    SAMPLE_TEXTURE2D(_Turbulence_c1, sampler_Turbulence_c1, worldXZ / _LengthScale1).x * lod1 +
                    SAMPLE_TEXTURE2D(_Turbulence_c2, sampler_Turbulence_c2, worldXZ / _LengthScale2).x * lod2;
                return saturate((-j + _FoamBias) * _FoamScale);
            }

            // 四方连续 fBm+Worley 噪声：双层错速采样，打破单贴图周期感
            float SampleLaceNoise(float2 worldXZ)
            {
                float2 nUV0 = worldXZ * _FoamNoiseScale + _Time.y * float2(0.018, 0.012);
                float2 nUV1 = worldXZ * (_FoamNoiseScale * 1.73) - _Time.y * float2(0.011, 0.017);
                float n0 = SAMPLE_TEXTURE2D(_FoamNoise, sampler_FoamNoise, nUV0).r;
                float n1 = SAMPLE_TEXTURE2D(_FoamNoise, sampler_FoamNoise, nUV1).g;
                float n2 = SAMPLE_TEXTURE2D(_FoamNoise, sampler_FoamNoise, nUV0 * 2.3 + 0.31).b;
                return saturate(n0 * 0.45 + n1 * 0.35 + n2 * 0.2);
            }

            half4 Frag(Varyings i) : SV_Target
            {
                float2 screenUV = i.screenPos.xy / max(i.screenPos.w, 1e-5);
                float2 worldXZ = i.positionWS.xz;
                float3 N = SampleNormal(worldXZ, i.viewDist);
                float3 V = normalize(_WorldSpaceCameraPos - i.positionWS);

                // ----- [Depth] 场景水深；无海底时用 DeepDistance 回退（开放洋面） -----
                float rawDepth = SampleSceneDepth(screenUV);
                float sceneZ = LinearEyeDepth(rawDepth, _ZBufferParams);
                float surfaceZ = LinearEyeDepth(i.positionCS.z / i.positionCS.w, _ZBufferParams);
                float waterDepth = max(sceneZ - surfaceZ, 0.0);
                bool hasSeabed = waterDepth > 1e-3 && waterDepth < 500.0;
                if (!hasSeabed)
                    waterDepth = _DeepDistance * 0.65;

                // ----- [Albedo] 浅→中→深水色 + Beer 吸收 + 法线折射 -----
                float shallowT = saturate(waterDepth / max(_ShallowDistance, 1e-3));
                float deepT = saturate(waterDepth / max(_DeepDistance, 1e-3));
                float3 waterCol = lerp(_OceanColorShallow.rgb, _OceanColorMid.rgb, shallowT);
                waterCol = lerp(waterCol, _OceanColorDeep.rgb, deepT);

                float2 refrUV = screenUV + N.xz * _RefractionStrength * saturate(1.0 - deepT);
                float3 sceneColor = SampleSceneColor(refrUV);
                float absorb = saturate(1.0 - exp(-waterDepth * _Absorption * 0.15));
                float3 baseCol = lerp(sceneColor, waterCol, absorb);

                // ----- [Lighting] 主光阴影 · Fresnel 天空 · Blinn · SSS -----
                float4 shadowCoord = TransformWorldToShadowCoord(i.positionWS);
                Light mainLight = GetMainLight(shadowCoord);
                float3 L = mainLight.direction;
                float3 H = normalize(L + V);
                float NdotL = saturate(dot(N, L));
                float NdotV = saturate(dot(N, V));
                float NdotH = saturate(dot(N, H));

                float fresnel = _FresnelBias + (1.0 - _FresnelBias) * pow(1.0 - NdotV, _FresnelPower);
                float3 R = reflect(-V, N);
                float3 sky = GlossyEnvironmentReflection(R, i.positionWS, 0.05, 1.0);
                float3 reflectCol = sky * _EnvIntensity;

                float spec = pow(NdotH, _Gloss) * _SpecularIntensity * mainLight.shadowAttenuation;
                float3 specular = mainLight.color * spec;

                float back = pow(saturate(dot(V, -L + N * 0.2)), _SSSPower);
                float3 sss = _SSSColor.rgb * back * _SSSIntensity * i.largeWaveY * mainLight.color;

                // ----- [Whitecaps] Jacobian 折叠 + 波峰高度 + 絮状噪声 -----
                float lace = SampleLaceNoise(worldXZ);
                float whitecap = SampleJacobianFoam(worldXZ, i.viewDist);
                float crest = saturate(i.largeWaveY * _CrestFoam);
                crest = crest * crest; // 只强调尖峰
                whitecap = saturate(whitecap + crest * 0.55);
                whitecap *= lerp(0.2, 1.0, lace); // 非实心白片
                whitecap = smoothstep(0.12, 0.85, whitecap);

                // 岸线接触泡沫：仅真实深度缓冲有海底时启用
                float contact = 0;
                if (hasSeabed)
                {
                    contact = saturate((_ContactFoam * 0.45) / max(waterDepth, 0.08));
                    contact *= lerp(0.35, 1.0, lace);
                }
                float foam = saturate(whitecap + contact);

                specular *= 1.0 - foam * 0.75; // 泡沫区压高光

                float3 col = lerp(baseCol, reflectCol, fresnel * 0.85);
                col += specular;
                col += sss;
                col *= mainLight.color * (0.35 + 0.65 * NdotL * mainLight.shadowAttenuation) + 0.45;

                col = lerp(col, _FoamColor.rgb, foam);
                col += _FoamColor.rgb * foam * lace * 0.15;

                float alpha = saturate(_Opacity + absorb * 0.25 + foam * 0.4);
                alpha = lerp(alpha * 0.55, alpha, saturate(waterDepth * 2.0));

                col = MixFog(col, i.fogFactor);
                return half4(col, alpha);
            }
            ENDHLSL
        }
    }
    FallBack Off
}
