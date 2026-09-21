// =============================================================================
// [溶解 DissolveFlow]
// 噪声阈值溶解 + 边缘 HDR 发光 + 溶解前沿流光 + Fresnel 外轮廓。
// 场景：Assets/Scenes/06.effect_DissolveFlow.unity
// 材质：Materials/DissolveFlow.mat
// 脚本：Scripts/DissolveFlowController.cs（可选驱动 _DissolveAmount）
// =============================================================================
Shader "ZZY/06.effect/DissolveFlow"
{
    Properties
    {
        _BaseColor ("Base Color", Color) = (0.25, 0.45, 0.95, 1)
        _NoiseMap ("Noise Map", 2D) = "gray" {}
        _FlowMap ("Flow Map", 2D) = "white" {}
        _DissolveAmount ("Dissolve Amount", Range(0,1)) = 0.35
        _EdgeWidth ("Edge Width", Range(0.001, 0.5)) = 0.08
        _EdgeColor ("Edge Color", Color) = (0.2, 1.5, 2.5, 1)
        _EdgeIntensity ("Edge Intensity", Float) = 3
        _FlowColor ("Flow Color", Color) = (0.4, 1.2, 2.0, 1)
        _FlowTiling ("Flow Tiling", Vector) = (2, 2, 0, 0)
        _FlowSpeed ("Flow Speed", Vector) = (0.2, 0.6, 0, 0)
        _FlowIntensity ("Flow Intensity", Float) = 1.5
        _RimColor ("Rim Color", Color) = (0.5, 0.9, 1.5, 1)
        _RimPower ("Rim Power", Range(0.1, 8)) = 2.5
        _RimIntensity ("Rim Intensity", Range(0, 5)) = 1.4
        _Animate ("Auto Animate", Float) = 1
        _AnimateSpeed ("Animate Speed", Float) = 0.25
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
            ZWrite On
            Blend SrcAlpha OneMinusSrcAlpha

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Library/EffectCommon.hlsl"

            TEXTURE2D(_NoiseMap); SAMPLER(sampler_NoiseMap);
            TEXTURE2D(_FlowMap); SAMPLER(sampler_FlowMap);

            CBUFFER_START(UnityPerMaterial)
                half4 _BaseColor;
                half _DissolveAmount;
                half _EdgeWidth;
                half4 _EdgeColor;
                half _EdgeIntensity;
                half4 _FlowColor;
                float4 _FlowTiling;
                float4 _FlowSpeed;
                half _FlowIntensity;
                half4 _RimColor;
                half _RimPower;
                half _RimIntensity;
                half _Animate;
                half _AnimateSpeed;
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
                float3 posWS = TransformObjectToWorld(v.positionOS.xyz);
                o.positionCS = TransformWorldToHClip(posWS);
                o.positionWS = posWS;
                o.normalWS = TransformObjectToWorldNormal(v.normalOS);
                o.uv = v.uv;
                return o;
            }

            half4 frag(Varyings i) : SV_Target
            {
                float3 n = normalize(i.normalWS);
                float3 viewWS = GetWorldSpaceNormalizeViewDir(i.positionWS);

                half noise = SAMPLE_TEXTURE2D(_NoiseMap, sampler_NoiseMap, i.uv).r;
                half amount = _DissolveAmount;
                if (_Animate > 0.5)
                    amount = saturate(0.5 + 0.5 * sin(_Time.y * _AnimateSpeed * 6.2831853));

                float keep, edge;
                EffectDissolve(noise, amount, _EdgeWidth, keep, edge);
                clip(keep);

                float2 flowUV = EffectFlowUV(i.uv, _FlowTiling.xy, _FlowSpeed.xy, _Time.y);
                half flow = SAMPLE_TEXTURE2D(_FlowMap, sampler_FlowMap, flowUV).r;
                half rim = EffectFresnel(n, viewWS, _RimPower, _RimIntensity);

                half3 col = _BaseColor.rgb;
                col += _FlowColor.rgb * flow * _FlowIntensity;
                col += _RimColor.rgb * rim;
                col = lerp(col, _EdgeColor.rgb * _EdgeIntensity, saturate(edge));

                half alpha = saturate(0.85 + rim * 0.2);
                return half4(col, alpha);
            }
            ENDHLSL
        }
    }
    FallBack Off
}
