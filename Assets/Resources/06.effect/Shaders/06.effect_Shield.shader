// =============================================================================
// [护盾 Shield]
// 等尺寸六边形球面：面心 UV 六边形描边/填充、Fresnel、深度交界光、点击涟漪。
// 网格：Models/ShieldHexSphere_Runtime.asset
// 场景：Assets/Scenes/06.effect_Shield.unity（需深度纹理）
// 脚本：Scripts/ShieldHitController.cs → 全局 _HitPos / _HitSize
// =============================================================================
Shader "ZZY/06.effect/Shield"
{
    Properties
    {
        _BaseColor ("Base Color", Color) = (0.02, 0.14, 0.42, 0.03)
        _RimColor ("Rim Color", Color) = (0.35, 0.9, 1.55, 1)
        _RimPower ("Rim Power", Range(0.1, 8)) = 2.4
        _RimIntensity ("Rim Intensity", Range(0, 5)) = 1.1
        _BaseIntensity ("Base Intensity", Range(0, 1)) = 0.07
        _HexLineColor ("Hex Line Color", Color) = (0.45, 1.25, 2.0, 1)
        _HexLineIntensity ("Hex Line Intensity", Range(0, 8)) = 2.2
        _HexLineWidth ("Hex Line Width", Range(0.005, 0.15)) = 0.028
        _HexLineSoft ("Hex Line Soft", Range(0.0005, 0.05)) = 0.002
        _HexFillColor ("Hex Fill Color", Color) = (0.12, 0.6, 1.15, 1)
        _HexFillIntensity ("Hex Fill Intensity", Range(0, 3)) = 0.35
        _HexInset ("Hex Fill Inset", Range(0.005, 0.15)) = 0.035
        _BlinkMap ("Blink Checker (UV2)", 2D) = "gray" {}
        _BlinkSpeed ("Blink Speed", Float) = 0.2
        _BlinkIntensity ("Blink Intensity", Range(0, 2)) = 0.7
        _NoiseMap ("Noise Map", 2D) = "gray" {}
        _EdgePower ("Intersection Power", Float) = 12
        _EdgeIntensity ("Intersection Intensity", Range(0, 5)) = 0.8
        _EdgeColor ("Intersection Color", Color) = (0.4, 1.25, 2.0, 1)
        _DissolvePos ("Dissolve Center (WS)", Vector) = (0, 0, 0, 0)
        _DissolveThreshold ("Dissolve Threshold", Float) = -1
        _DissolveEdge ("Dissolve Edge", Float) = 0.35
        _DissolveEdgeColor ("Dissolve Edge Color", Color) = (0.2, 1.5, 2.5, 1)
        _HitSpread ("Hit Spread", Float) = 0.8
        _HitFadeDistance ("Hit Fade Distance", Float) = 2.5
        _HitFadePower ("Hit Fade Power", Float) = 1.5
        _HitColor ("Hit Color", Color) = (1.0, 1.8, 2.4, 1)
        _HitIntensity ("Hit Intensity", Range(0, 8)) = 2.0
        [Toggle] _UseHexCenter ("Use Hex Face Center", Float) = 1
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
            Blend SrcAlpha OneMinusSrcAlpha

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Library/EffectCommon.hlsl"

            TEXTURE2D(_BlinkMap); SAMPLER(sampler_BlinkMap);
            TEXTURE2D(_NoiseMap); SAMPLER(sampler_NoiseMap);

            CBUFFER_START(UnityPerMaterial)
                half4 _BaseColor;
                half4 _RimColor;
                half _RimPower;
                half _RimIntensity;
                half _BaseIntensity;
                half4 _HexLineColor;
                half _HexLineIntensity;
                half _HexLineWidth;
                half _HexLineSoft;
                half4 _HexFillColor;
                half _HexFillIntensity;
                half _HexInset;
                half _BlinkSpeed;
                half _BlinkIntensity;
                half _EdgePower;
                half _EdgeIntensity;
                half4 _EdgeColor;
                float4 _DissolvePos;
                half _DissolveThreshold;
                half _DissolveEdge;
                half4 _DissolveEdgeColor;
                half _HitSpread;
                half _HitFadeDistance;
                half _HitFadePower;
                half4 _HitColor;
                half _HitIntensity;
                half _UseHexCenter;
            CBUFFER_END

            float4 _HitPos[20];
            float _HitSize[20];
            float _HitAmount;

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float2 uv : TEXCOORD0;
                float2 uv2 : TEXCOORD1;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float2 uv2 : TEXCOORD1;
                float3 positionWS : TEXCOORD2;
                float3 normalWS : TEXCOORD3;
                float3 pivotWS : TEXCOORD4;
                float4 screenPos : TEXCOORD5;
            };

            Varyings vert(Attributes v)
            {
                Varyings o;
                float3 posWS = TransformObjectToWorld(v.positionOS.xyz);
                o.positionCS = TransformWorldToHClip(posWS);
                o.positionWS = posWS;
                o.normalWS = TransformObjectToWorldNormal(v.normalOS);
                o.pivotWS = TransformObjectToWorld(float3(0, 0, 0));
                o.uv = v.uv;
                o.uv2 = v.uv2;
                o.screenPos = ComputeScreenPos(o.positionCS);
                return o;
            }

            half HitRipple(float3 worldPos, half noise)
            {
                half hitResult = 0;
                int count = (int)clamp(_HitAmount, 0, 20);
                for (int j = 0; j < 20; j++)
                {
                    if (j >= count) break;
                    half dist = distance(_HitPos[j].xyz, worldPos);
                    half hitRange = (dist - _HitSize[j] + noise) / max(_HitSpread, 1e-3);
                    hitRange = -clamp(hitRange, -0.99, 0.01);
                    half hitAtten = saturate((1.0 - dist / max(_HitFadeDistance, 1e-3)) * _HitFadePower);
                    half ring = saturate(1.0 - abs(hitRange) * 40.0);
                    hitResult += ring * hitAtten;
                }
                return saturate(hitResult);
            }

            half4 frag(Varyings i) : SV_Target
            {
                float3 n = normalize(i.normalWS);
                float3 sphereN = EffectSafeNormalize(i.positionWS - i.pivotWS);
                float3 viewWS = GetWorldSpaceNormalizeViewDir(i.positionWS);

                float3 effectPosWS = i.positionWS;
                if (_UseHexCenter > 0.5)
                    effectPosWS = EffectHexagonCenterWS(i.positionWS, n, i.pivotWS);

                // Sphere normals for rim so each flat cell doesn't get a soft center blob
                half rim = EffectFresnel(sphereN, viewWS, _RimPower, _RimIntensity);
                half3 col = _BaseColor.rgb * _BaseIntensity;
                col = lerp(col, _RimColor.rgb, saturate(rim) * 0.45);

                // Center-fan UV0: regular pointy-top hex per face → sharp straight edges
                float2 p = i.uv - 0.5;
                float d = EffectHexSDF(p);
                float outer = 0.45 * 0.86602540378;
                float w = max(_HexLineWidth, 1e-4);
                float s = max(_HexLineSoft, 1e-5);
                float bd = abs(d - outer);
                half hexLine = saturate(1.0 - bd / w);
                hexLine = hexLine * hexLine;
                hexLine *= 1.0 - saturate((bd - w) / s);

                // Hard hex fill (keeps sharp corners; avoids circular soft blobs)
                half hexFill = d < (outer - max(_HexInset, 1e-4)) ? 1.0 : 0.0;

                float2 blinkUV = i.uv2 + float2(_Time.y * _BlinkSpeed, _Time.y * _BlinkSpeed * 0.37);
                half blink = SAMPLE_TEXTURE2D(_BlinkMap, sampler_BlinkMap, blinkUV).r;
                blink = lerp(1.0 - _BlinkIntensity * 0.6, 1.0, blink);

                col += _HexLineColor.rgb * hexLine * _HexLineIntensity;
                col += _HexFillColor.rgb * hexFill * blink * _HexFillIntensity;

                float2 screenUV = i.screenPos.xy / max(i.screenPos.w, 1e-5);
                half intersect = EffectDepthIntersection(i.positionCS, screenUV, _EdgePower);
                // Keep intersection as a thin contact band; don't wash the hex grid
                intersect = saturate(intersect);
                intersect = intersect * intersect;
                col += _EdgeColor.rgb * intersect * _EdgeIntensity;

                half noise = SAMPLE_TEXTURE2D(_NoiseMap, sampler_NoiseMap, i.uv * 2.0).r;
                half dissolveDist = distance(_DissolvePos.xyz, effectPosWS);
                half dissolveKeep = dissolveDist - _DissolveThreshold - noise * 0.25;
                clip(dissolveKeep);
                half dissolveEdge = 1.0 - saturate(dissolveKeep / max(_DissolveEdge, 1e-3));
                col = lerp(col, _DissolveEdgeColor.rgb * 2.0, dissolveEdge);

                half hit = HitRipple(effectPosWS, noise * 0.2);
                col += _HitColor.rgb * hit * _HitIntensity * saturate(hexLine * 1.6 + hexFill * blink * 0.4);

                half alpha = saturate(
                    _BaseColor.a
                    + rim * 0.32
                    + hexLine * 0.9
                    + hexFill * blink * 0.28
                    + intersect * 0.5
                    + hit * 0.25
                    + dissolveEdge
                );

                return half4(col, alpha);
            }
            ENDHLSL
        }
    }
    FallBack Off
}
