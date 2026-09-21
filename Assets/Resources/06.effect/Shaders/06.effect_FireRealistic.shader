// =============================================================================
// [真实火焰 FireRealistic]
// 12x6 火焰序列帧 + 双层噪声 UV 扭曲 + FBM 碎边 + HDR 白/橙/红渐变。
// 无烟雾、无 VFX Graph；交叉 billboard 增加体积感。
// 场景：Assets/Scenes/06.effect_FireRealistic.unity
// 材质：Materials/FireRealistic.mat / FireRealistic_B.mat
// 贴图：Textures/fire_src_1.png、EffectNoise.png
// =============================================================================
Shader "ZZY/06.effect/FireRealistic"
{
    Properties
    {
        [HDR] _CoreColor ("Core Color", Color) = (2.4, 2.1, 1.35, 1)
        [HDR] _MidColor ("Mid Color", Color) = (1.8, 0.55, 0.08, 1)
        [HDR] _TipColor ("Tip Color", Color) = (0.55, 0.08, 0.01, 1)
        _MainTex ("Flame Flipbook", 2D) = "black" {}
        _NoiseMap ("Noise Map", 2D) = "gray" {}
        _Columns ("Columns", Float) = 12
        _Rows ("Rows", Float) = 6
        _FPS ("FPS", Float) = 26
        _TimeOffset ("Time Offset", Float) = 0
        _NoiseScale ("Noise Scale", Vector) = (1.8, 1.1, 2.6, 1.6)
        _NoiseSpeed ("Noise Speed", Vector) = (0.08, 0.55, -0.12, 0.85)
        _Distort ("Distort", Range(0, 0.5)) = 0.085
        _WispStrength ("Wisp Strength", Range(0, 1)) = 0.45
        _SoftEdge ("Soft Edge", Range(0.01, 0.5)) = 0.12
        _Intensity ("Intensity", Range(0, 12)) = 3.2
        _AlphaBoost ("Alpha Boost", Range(0, 4)) = 1.35
        _CoreThreshold ("Core Threshold", Range(0, 1)) = 0.62
        _MidThreshold ("Mid Threshold", Range(0, 1)) = 0.28
        _VerticalScale ("Vertical Scale", Range(0.5, 1.5)) = 0.92
        _SidePinch ("Side Pinch", Range(0, 2)) = 0.55
    }

    SubShader
    {
        Tags
        {
            "RenderPipeline"="UniversalPipeline"
            "RenderType"="Transparent"
            "Queue"="Transparent"
        }

        Pass
        {
            Name "Forward"
            Tags { "LightMode"="UniversalForward" }
            Cull Off
            ZWrite Off
            Blend One OneMinusSrcAlpha

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Library/EffectCommon.hlsl"

            TEXTURE2D(_MainTex); SAMPLER(sampler_MainTex);
            TEXTURE2D(_NoiseMap); SAMPLER(sampler_NoiseMap);

            CBUFFER_START(UnityPerMaterial)
                half4 _CoreColor;
                half4 _MidColor;
                half4 _TipColor;
                float4 _MainTex_ST;
                float4 _NoiseScale;
                float4 _NoiseSpeed;
                half _Columns;
                half _Rows;
                half _FPS;
                half _TimeOffset;
                half _Distort;
                half _WispStrength;
                half _SoftEdge;
                half _Intensity;
                half _AlphaBoost;
                half _CoreThreshold;
                half _MidThreshold;
                half _VerticalScale;
                half _SidePinch;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            float2 FireCellUV(float2 localUV, float2 cells, float frame)
            {
                float2 cellCount = max(cells, float2(1, 1));
                float total = cellCount.x * cellCount.y;
                float f = floor(fmod(max(frame, 0.0), total));
                float col = fmod(f, cellCount.x);
                float row = floor(f / cellCount.x);
                float2 cellSize = 1.0 / cellCount;
                // Top-left origin flipbook
                float2 offset = float2(col, (cellCount.y - 1.0 - row)) * cellSize;
                // Inset slightly to avoid neighbor bleed from filtering
                float2 inset = cellSize * 0.01;
                float2 uv = offset + inset + localUV * (cellSize - inset * 2.0);
                return uv;
            }

            half SampleFlame(float2 localUV, float frame, float2 cells)
            {
                float2 uvA = FireCellUV(localUV, cells, frame);
                float2 uvB = FireCellUV(localUV, cells, frame + 1.0);
                half3 a = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uvA).rgb;
                half3 b = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uvB).rgb;
                half t = frac(frame);
                half3 rgb = lerp(a, b, t);
                return max(rgb.r, max(rgb.g, rgb.b));
            }

            Varyings vert(Attributes v)
            {
                Varyings o;
                // Subtle heat shimmer on upper verts
                float3 pos = v.positionOS.xyz;
                float flicker = EffectNoise2D(float2(pos.x * 4.0 + _Time.y * 3.1, pos.y * 2.0));
                pos.x += (flicker - 0.5) * 0.035 * saturate(v.uv.y);
                pos.y += (flicker - 0.5) * 0.02 * saturate(v.uv.y);
                o.positionCS = TransformObjectToHClip(pos);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                return o;
            }

            half4 frag(Varyings i) : SV_Target
            {
                float2 uv = i.uv;
                uv.y = saturate(uv.y * _VerticalScale);

                // Dual scrolling noise → UV warp (stronger toward tips)
                float2 nUV1 = uv * _NoiseScale.xy + _NoiseSpeed.xy * (_Time.y + _TimeOffset);
                float2 nUV2 = uv * _NoiseScale.zw + _NoiseSpeed.zw * (_Time.y + _TimeOffset);
                half n1 = SAMPLE_TEXTURE2D(_NoiseMap, sampler_NoiseMap, nUV1).r;
                half n2 = SAMPLE_TEXTURE2D(_NoiseMap, sampler_NoiseMap, nUV2).g;
                float tip = saturate(uv.y);
                float2 warp = float2(n1 - 0.5, n2 - 0.5) * _Distort * (0.25 + tip * 1.35);

                // Procedural wisps (extra tongues breaking off near the top)
                float wispNoise = EffectFBM(float2(uv.x * 3.2 + _Time.y * 0.35, uv.y * 2.4 - _Time.y * 1.1) + warp * 4.0);
                float side = 1.0 - abs(uv.x - 0.5) * 2.0;
                side = saturate(side + (wispNoise - 0.5) * _SidePinch * tip);
                float heightMask = smoothstep(1.05, 0.15, uv.y + (wispNoise - 0.45) * 0.25);
                float shapeMask = saturate(side * heightMask);
                shapeMask = smoothstep(0.0, _SoftEdge, shapeMask);

                float2 localUV = saturate(uv + warp);
                float frame = (_Time.y + _TimeOffset) * _FPS;
                float2 cells = float2(_Columns, _Rows);
                half flame = SampleFlame(localUV, frame, cells);

                // Soften hard flipbook silhouette with noise breakup
                half breakup = lerp(1.0, wispNoise, _WispStrength * tip);
                flame *= breakup;
                flame *= shapeMask;
                flame = saturate(flame);

                // HDR gradient: white-hot core → orange body → dark red tips
                half3 col = _TipColor.rgb;
                col = lerp(col, _MidColor.rgb, smoothstep(_MidThreshold, _MidThreshold + 0.35, flame));
                col = lerp(col, _CoreColor.rgb, smoothstep(_CoreThreshold, 1.0, flame));
                // Vertical heat: brighter near base
                half baseHeat = saturate(1.0 - uv.y * 0.85);
                col = lerp(col * 0.75, col * 1.15, baseHeat);
                col *= flame * _Intensity;

                half alpha = saturate(flame * _AlphaBoost);
                // Premultiply for soft additive-like glow without harsh edges
                return half4(col * alpha, alpha);
            }
            ENDHLSL
        }
    }
    FallBack Off
}
