// =============================================================================
// [流光 FlowTranslucent]
// 半透明角色材质：Fresnel 外轮廓 + 物体空间无缝流光带（Additive）。
// 场景：Assets/Scenes/06.effect_FlowTranslucent.unity
// 材质：Materials/FlowTranslucent.mat · 贴图 EffectFlow.png
// =============================================================================
Shader "ZZY/06.effect/FlowTranslucent"
{
    Properties
    {
        _BaseMap ("Mask (R)", 2D) = "white" {}
        _InnerColor ("Inner Color", Color) = (0.05, 0.15, 0.35, 0.15)
        _RimColor ("Rim Color", Color) = (0.3, 0.85, 1.0, 1)
        _RimMin ("Rim Min", Range(-1,1)) = 0.05
        _RimMax ("Rim Max", Range(0,2)) = 0.85
        _RimIntensity ("Rim Intensity", Float) = 2.2
        _FlowMap ("Flow Map", 2D) = "white" {}
        _FlowColor ("Flow Color", Color) = (0.4, 1.0, 1.0, 1)
        _FlowTiling ("Flow Tiling", Vector) = (0.55, 0.55, 0, 0)
        _FlowSpeed ("Flow Speed", Vector) = (0.0, 0.18, 0, 0)
        _FlowIntensity ("Flow Intensity", Float) = 1.15
        _FlowPower ("Flow Power", Range(0.1, 8)) = 1.6
        _InnerAlpha ("Inner Alpha", Range(0,1)) = 0.12
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
            Cull Back
            ZWrite Off
            Blend SrcAlpha One

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Library/EffectCommon.hlsl"

            TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);
            TEXTURE2D(_FlowMap); SAMPLER(sampler_FlowMap);

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                half4 _InnerColor;
                half4 _RimColor;
                half _RimMin;
                half _RimMax;
                half _RimIntensity;
                half4 _FlowColor;
                float4 _FlowTiling;
                float4 _FlowSpeed;
                half _FlowIntensity;
                half _FlowPower;
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
                float3 positionOS : TEXCOORD2;
                float3 normalWS : TEXCOORD3;
                float3 pivotWS : TEXCOORD4;
            };

            Varyings vert(Attributes v)
            {
                Varyings o;
                float3 posWS = TransformObjectToWorld(v.positionOS.xyz);
                o.positionCS = TransformWorldToHClip(posWS);
                o.positionWS = posWS;
                o.positionOS = v.positionOS.xyz;
                o.normalWS = TransformObjectToWorldNormal(v.normalOS);
                o.pivotWS = TransformObjectToWorld(float3(0, 0, 0));
                o.uv = TRANSFORM_TEX(v.uv, _BaseMap);
                return o;
            }

            half4 frag(Varyings i) : SV_Target
            {
                float3 n = normalize(i.normalWS);
                float3 viewWS = GetWorldSpaceNormalizeViewDir(i.positionWS);
                half ndv = saturate(dot(n, viewWS));
                half fresnel = 1.0 - ndv;
                fresnel = smoothstep(_RimMin, _RimMax, fresnel);

                // Soften fresnel with object-space sample (avoid mirrored mesh-UV center seam)
                float2 uvMask = EffectObjectFlowUV(i.positionOS, _FlowTiling.xy * 0.35, float2(0, 0), 0);
                half mask = SAMPLE_TEXTURE2D(_FlowMap, sampler_FlowMap, uvMask).r;
                half finalFresnel = saturate(fresnel + mask * 0.1);

                half3 rimCol = lerp(_InnerColor.rgb, _RimColor.rgb * _RimIntensity, finalFresnel);

                // Object-space XY + seamless horizontal-band map → continuous across the body front
                float2 uvFlow = EffectObjectFlowUV(i.positionOS, _FlowTiling.xy, _FlowSpeed.xy, _Time.y);
                half flowSample = SAMPLE_TEXTURE2D(_FlowMap, sampler_FlowMap, uvFlow).r;
                flowSample = pow(saturate(flowSample), _FlowPower);
                half3 flowCol = _FlowColor.rgb * flowSample * _FlowIntensity;

                half3 col = rimCol + flowCol;
                half alpha = saturate(finalFresnel + flowSample * 0.85 + _InnerAlpha);
                return half4(col, alpha);
            }
            ENDHLSL
        }
    }
    FallBack Off
}
