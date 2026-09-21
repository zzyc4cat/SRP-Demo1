// =============================================================================
// [管道流水 · 液体 FlowPipe]
// 透明管内液体：软 FBM 域扭曲流动 + 中心密度 + 轻微顶点波浪。
// 与 FlowPipeGlass 成对使用；模型 FlowPipe.fbx 的 PipeLiquid 子网格。
// 场景：Assets/Scenes/06.effect_FlowPipe.unity
// =============================================================================
Shader "ZZY/06.effect/FlowPipe"
{
    Properties
    {
        _BaseColor ("Liquid Color", Color) = (0.08, 0.42, 0.92, 0.38)
        _DeepColor ("Deep Color", Color) = (0.02, 0.18, 0.55, 1)
        _HighlightColor ("Highlight Color", Color) = (0.65, 0.95, 1.25, 1)
        _FlowScale ("Flow Scale", Vector) = (2.5, 1.2, 0, 0)
        _FlowSpeed ("Flow Speed", Vector) = (0.0, 0.35, 0, 0)
        _FlowContrast ("Flow Contrast", Range(0.2, 3)) = 1.15
        _FlowIntensity ("Flow Intensity", Range(0, 3)) = 0.85
        _WarpStrength ("Warp Strength", Range(0, 0.5)) = 0.12
        _DensityPower ("Center Density Power", Range(0.3, 4)) = 1.35
        _DensityIntensity ("Center Density", Range(0, 2)) = 0.7
        _RimColor ("Rim Color", Color) = (0.5, 0.95, 1.3, 1)
        _RimPower ("Rim Power", Range(0.5, 8)) = 2.6
        _RimIntensity ("Rim Intensity", Range(0, 3)) = 0.55
        _WaveAmp ("Vertex Wave Amp", Range(0, 0.08)) = 0.012
        _WaveFreq ("Vertex Wave Freq", Range(0.5, 20)) = 6.5
        _WaveSpeed ("Vertex Wave Speed", Range(0, 8)) = 2.2
        _WaveAmp2 ("Vertex Wave2 Amp", Range(0, 0.05)) = 0.006
        _WaveFreq2 ("Vertex Wave2 Freq", Range(0.5, 30)) = 11.0
        _InnerAlpha ("Inner Alpha", Range(0, 1)) = 0.22
    }

    SubShader
    {
        Tags
        {
            "RenderPipeline"="UniversalPipeline"
            "RenderType"="Transparent"
            "Queue"="Transparent+5"
        }

        Pass
        {
            Name "Forward"
            Tags { "LightMode"="UniversalForward" }
            Cull Back
            ZWrite On
            Blend SrcAlpha OneMinusSrcAlpha

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Library/EffectCommon.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            CBUFFER_START(UnityPerMaterial)
                half4 _BaseColor;
                half4 _DeepColor;
                half4 _HighlightColor;
                float4 _FlowScale;
                float4 _FlowSpeed;
                half _FlowContrast;
                half _FlowIntensity;
                half _WarpStrength;
                half _DensityPower;
                half _DensityIntensity;
                half4 _RimColor;
                half _RimPower;
                half _RimIntensity;
                half _WaveAmp;
                half _WaveFreq;
                half _WaveSpeed;
                half _WaveAmp2;
                half _WaveFreq2;
                half _InnerAlpha;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float2 uv : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
                float3 normalWS : TEXCOORD2;
            };

            Varyings vert(Attributes v)
            {
                Varyings o;
                float3 posOS = v.positionOS.xyz;
                float3 nOS = normalize(v.normalOS);
                // UV.y = along-pipe factor from Blender unwrap
                float along = v.uv.y;
                float around = v.uv.x;
                float t = _Time.y;

                // Small radial vertex waves — soft fluid motion (no sharp displacement)
                float w1 = sin(along * _WaveFreq * 6.2831853 + t * _WaveSpeed);
                float w2 = sin(along * _WaveFreq2 * 6.2831853 - t * _WaveSpeed * 1.37 + around * 6.2831853);
                float w3 = sin((along * 3.1 + around * 2.0) * 6.2831853 + t * 1.1);
                float wave = w1 * _WaveAmp + w2 * _WaveAmp2 + w3 * (_WaveAmp * 0.35);
                posOS += nOS * wave;

                float3 posWS = TransformObjectToWorld(posOS);
                o.positionCS = TransformWorldToHClip(posWS);
                o.positionWS = posWS;
                o.normalWS = TransformObjectToWorldNormal(nOS);
                o.uv = v.uv;
                return o;
            }

            half SoftFlow(float2 uv)
            {
                // Longitudinal soft streaks (along V) with gentle around-pipe variation
                float t = _Time.y;
                float2 warpUv = float2(uv.x * 2.0, uv.y * 1.5 + t * 0.05);
                float2 warp = float2(
                    EffectFBM(warpUv),
                    EffectFBM(warpUv + float2(17.3, 3.1))
                );
                warp = (warp - 0.5) * _WarpStrength;

                // Primary: elongated along pipe length
                float2 p1 = float2(uv.x * _FlowScale.x, uv.y * _FlowScale.y) + float2(0.0, _FlowSpeed.y) * t + warp;
                float n1 = EffectFBM(p1);
                // Secondary slower layer
                float2 p2 = float2(uv.x * (_FlowScale.x * 0.6), uv.y * (_FlowScale.y * 1.8))
                          + float2(0.02, _FlowSpeed.y * 1.45) * t - warp * 0.5;
                float n2 = EffectFBM(p2 + 9.1);

                // Wide smoothstep = soft anti-aliased transitions (no hard threshold jaggies)
                float flow = n1 * 0.55 + n2 * 0.45;
                flow = smoothstep(0.35, 0.72, flow);
                flow = lerp(0.5, flow, _FlowContrast);
                return saturate(flow);
            }

            half4 frag(Varyings i) : SV_Target
            {
                float3 n = normalize(i.normalWS);
                float3 viewWS = GetWorldSpaceNormalizeViewDir(i.positionWS);
                Light light = GetMainLight();

                half ndv = saturate(dot(n, viewWS));
                half density = pow(ndv, _DensityPower) * _DensityIntensity;
                half fresnel = 1.0 - ndv;
                fresnel = smoothstep(0.08, 0.95, fresnel);
                fresnel = pow(fresnel, _RimPower);

                half flow = SoftFlow(i.uv);

                half3 col = lerp(_BaseColor.rgb, _DeepColor.rgb, density);
                col = lerp(col, _HighlightColor.rgb, flow * _FlowIntensity);
                col += _RimColor.rgb * fresnel * _RimIntensity;

                half ndl = saturate(dot(n, light.direction)) * 0.25 + 0.75;
                col *= ndl;

                half alpha = saturate(_BaseColor.a + density * 0.45 + flow * 0.28 + fresnel * 0.18 + _InnerAlpha);
                return half4(col, alpha);
            }
            ENDHLSL
        }
    }
    FallBack Off
}
