Shader "ZZY/03.gpu_FFT_Ocean/FFTOcean"
{
    Properties
    {
        [Header(Colors)]
        // 浅水颜色
        _OceanColorShallow ("Shallow", Color) = (0.40, 0.78, 0.72, 1)
        // 中等水深颜色
        _OceanColorMid ("Mid", Color) = (0.04, 0.38, 0.52, 1)
        // 深水颜色
        _OceanColorDeep ("Deep", Color) = (0.01, 0.10, 0.26, 1)
        // 次表面颜色
        _SSSColor ("SSS Color", Color) = (0.20, 0.75, 0.70, 1)

        [Header(Depth)]
        // 浅水过渡距离
        _ShallowDistance ("Shallow Distance", Range(0.1, 20)) = 1.5
        // 深水过渡距离
        _DeepDistance ("Deep Distance", Range(1, 80)) = 18
        // 水体吸收强度
        _Absorption ("Absorption", Range(0.1, 8)) = 1.4
        // 基础不透明度
        _Opacity ("Base Opacity", Range(0, 1)) = 0.92

        [Header(Lighting)]
        // 高光强度
        _SpecularIntensity ("Specular", Range(0, 8)) = 2.5
        // 高光锐度
        _Gloss ("Gloss", Range(8, 512)) = 180
        // 菲涅尔幂
        _FresnelPower ("Fresnel Power", Range(1, 8)) = 5
        // 菲涅尔偏移
        _FresnelBias ("Fresnel Bias", Range(0, 0.5)) = 0.04
        // 天空反射强度
        _EnvIntensity ("Sky Reflection", Range(0, 2)) = 0.75
        // 次表面强度
        _SSSIntensity ("SSS Intensity", Range(0, 3)) = 1.1
        // 次表面收束
        _SSSPower ("SSS Power", Range(1, 16)) = 4
        // 级联随距离衰减的缩放
        _LOD_scale ("Cascade LOD Scale", Range(0.5, 20)) = 8

        [Header(Foam Whitecaps)]
        // 泡沫颜色
        _FoamColor ("Foam Color", Color) = (0.97, 0.99, 1.0, 1)
        // 雅可比泡沫阈值
        _FoamBias ("Jacobian Foam Bias", Range(0, 7)) = 2.85
        // 泡沫强度
        _FoamScale ("Foam Intensity", Range(0, 8)) = 1.35
        // 波峰泡沫
        _CrestFoam ("Crest Peak Foam", Range(0, 4)) = 1.6
        // 岸线接触泡沫
        _ContactFoam ("Contact Foam", Range(0, 3)) = 0.2
        // 泡沫噪声贴图
        _FoamNoise ("Foam Noise", 2D) = "white" {}
        // 泡沫噪声缩放
        _FoamNoiseScale ("Foam Noise Scale", Range(0.01, 2)) = 0.08

        [Header(Refraction)]
        // 屏幕折射强度
        _RefractionStrength ("Refraction", Range(0, 0.5)) = 0.12

        [Header(Cascades Hidden)]
        // 第一级联位移
        [HideInInspector] _Displacement_c0 ("Disp0", 2D) = "black" {}
        // 第一级联导数
        [HideInInspector] _Derivatives_c0 ("Der0", 2D) = "black" {}
        // 第一级联湍流
        [HideInInspector] _Turbulence_c0 ("Turb0", 2D) = "white" {}
        // 第二级联位移
        [HideInInspector] _Displacement_c1 ("Disp1", 2D) = "black" {}
        // 第二级联导数
        [HideInInspector] _Derivatives_c1 ("Der1", 2D) = "black" {}
        // 第二级联湍流
        [HideInInspector] _Turbulence_c1 ("Turb1", 2D) = "white" {}
        // 第三级联位移
        [HideInInspector] _Displacement_c2 ("Disp2", 2D) = "black" {}
        // 第三级联导数
        [HideInInspector] _Derivatives_c2 ("Der2", 2D) = "black" {}
        // 第三级联湍流
        [HideInInspector] _Turbulence_c2 ("Turb2", 2D) = "white" {}
        // 第一级联波长
        [HideInInspector] _LengthScale0 ("Len0", Float) = 250
        // 第二级联波长
        [HideInInspector] _LengthScale1 ("Len1", Float) = 17
        // 第三级联波长
        [HideInInspector] _LengthScale2 ("Len2", Float) = 5
        [Header(Depth)]
        // 深度写入，默认关闭
        [Enum(Off, 0, On, 1)] _ZWrite ("ZWrite", Float) = 0
        // 深度测试，默认小于等于
        [Enum(UnityEngine.Rendering.CompareFunction)] _ZTest ("ZTest", Float) = 4
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
            ZWrite [_ZWrite]
            ZTest [_ZTest]
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

            // 距离越远，短波级联权重越低
            float SampleLod(float lengthScale, float viewDist)
            {
                return saturate(_LOD_scale * lengthScale / max(viewDist, 1.0));
            }

            // 按距离权重采样三级联位移
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

            // 顶点：三级联位移、大浪高度和雾
            Varyings Vert(Attributes input)
            {
                Varyings o;
                float3 posWS = TransformObjectToWorld(input.positionOS.xyz);
                float viewDist = length(_WorldSpaceCameraPos - posWS);
                float3 displacement = SampleDisplacement(posWS.xz, viewDist);
                // 大浪高度，留给次表面和浪尖泡沫
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

            // 用导数图重建坡度法线
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

            // 雅可比变低时产生破碎白沫
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

            // 两层错速噪声，打破泡沫的重复感
            float SampleLaceNoise(float2 worldXZ)
            {
                float2 nUV0 = worldXZ * _FoamNoiseScale + _Time.y * float2(0.018, 0.012);
                float2 nUV1 = worldXZ * (_FoamNoiseScale * 1.73) - _Time.y * float2(0.011, 0.017);
                float n0 = SAMPLE_TEXTURE2D(_FoamNoise, sampler_FoamNoise, nUV0).r;
                float n1 = SAMPLE_TEXTURE2D(_FoamNoise, sampler_FoamNoise, nUV1).g;
                float n2 = SAMPLE_TEXTURE2D(_FoamNoise, sampler_FoamNoise, nUV0 * 2.3 + 0.31).b;
                return saturate(n0 * 0.45 + n1 * 0.35 + n2 * 0.2);
            }

            // 片元：水色、折射、光照、白沫和雾
            half4 Frag(Varyings i) : SV_Target
            {
                float2 screenUV = i.screenPos.xy / max(i.screenPos.w, 1e-5);
                float2 worldXZ = i.positionWS.xz;
                float3 N = SampleNormal(worldXZ, i.viewDist);
                float3 V = normalize(_WorldSpaceCameraPos - i.positionWS);

                // 场景水深，没有海底时回退到深水距离
                float rawDepth = SampleSceneDepth(screenUV);
                float sceneZ = LinearEyeDepth(rawDepth, _ZBufferParams);
                float surfaceZ = LinearEyeDepth(i.positionCS.z / i.positionCS.w, _ZBufferParams);
                float waterDepth = max(sceneZ - surfaceZ, 0.0);
                bool hasSeabed = waterDepth > 1e-3 && waterDepth < 500.0;
                if (!hasSeabed)
                    waterDepth = _DeepDistance * 0.65;

                // 深浅水色、比尔吸收和法线折射
                float shallowT = saturate(waterDepth / max(_ShallowDistance, 1e-3));
                float deepT = saturate(waterDepth / max(_DeepDistance, 1e-3));
                float3 waterCol = lerp(_OceanColorShallow.rgb, _OceanColorMid.rgb, shallowT);
                waterCol = lerp(waterCol, _OceanColorDeep.rgb, deepT);

                float2 refrUV = screenUV + N.xz * _RefractionStrength * saturate(1.0 - deepT);
                float3 sceneColor = SampleSceneColor(refrUV);
                float absorb = saturate(1.0 - exp(-waterDepth * _Absorption * 0.15));
                float3 baseCol = lerp(sceneColor, waterCol, absorb);

                // 菲涅尔天空反射、高光和次表面
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

                // 折叠白沫、波峰高度和絮状噪声
                float lace = SampleLaceNoise(worldXZ);
                float whitecap = SampleJacobianFoam(worldXZ, i.viewDist);
                float crest = saturate(i.largeWaveY * _CrestFoam);
                crest = crest * crest;
                whitecap = saturate(whitecap + crest * 0.55);
                whitecap *= lerp(0.2, 1.0, lace);
                whitecap = smoothstep(0.12, 0.85, whitecap);

                // 只有真实海底深度时才加岸边泡沫
                float contact = 0;
                if (hasSeabed)
                {
                    contact = saturate((_ContactFoam * 0.45) / max(waterDepth, 0.08));
                    contact *= lerp(0.35, 1.0, lace);
                }
                float foam = saturate(whitecap + contact);

                // 泡沫压暗高光，再混合反射、散射和雾
                specular *= 1.0 - foam * 0.75;

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
