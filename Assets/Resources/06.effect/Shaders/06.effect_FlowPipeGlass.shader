// =============================================================================
// [管道流水 · 玻璃壳 FlowPipeGlass]
// 外层低透明度玻璃：软 Fresnel 边缘 + 高光；不写深度，叠在液体之上。
// 模型：FlowPipe.fbx → PipeGlass
// 场景：Assets/Scenes/06.effect_FlowPipe.unity
// =============================================================================
Shader "ZZY/06.effect/FlowPipeGlass"
{
    Properties
    {
        _BaseColor ("Glass Color", Color) = (0.65, 0.85, 0.98, 0.045)
        _RimColor ("Rim Color", Color) = (0.85, 0.97, 1.15, 1)
        _RimPower ("Rim Power", Range(0.5, 8)) = 3.5
        _RimIntensity ("Rim Intensity", Range(0, 3)) = 0.85
        _SpecColor ("Spec Color", Color) = (0.95, 0.99, 1, 1)
        _SpecPower ("Spec Power", Range(16, 256)) = 128
        _SpecIntensity ("Spec Intensity", Range(0, 2)) = 0.35
        _Thickness ("Edge Softness", Range(0.1, 2)) = 0.65
    }

    SubShader
    {
        Tags
        {
            "RenderPipeline"="UniversalPipeline"
            "RenderType"="Transparent"
            "Queue"="Transparent+20"
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
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            CBUFFER_START(UnityPerMaterial)
                half4 _BaseColor;
                half4 _RimColor;
                half _RimPower;
                half _RimIntensity;
                half4 _SpecColor;
                half _SpecPower;
                half _SpecIntensity;
                half _Thickness;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                float3 normalWS : TEXCOORD1;
            };

            Varyings vert(Attributes v)
            {
                Varyings o;
                float3 posWS = TransformObjectToWorld(v.positionOS.xyz);
                o.positionCS = TransformWorldToHClip(posWS);
                o.positionWS = posWS;
                o.normalWS = TransformObjectToWorldNormal(v.normalOS);
                return o;
            }

            half4 frag(Varyings i) : SV_Target
            {
                float3 n = normalize(i.normalWS);
                float3 vdir = GetWorldSpaceNormalizeViewDir(i.positionWS);
                Light light = GetMainLight();

                half ndv = saturate(dot(n, vdir));
                // Soft fresnel — smoothstep avoids harsh rim aliasing
                half fresnel = 1.0 - ndv;
                fresnel = smoothstep(0.05, _Thickness, fresnel);
                fresnel = pow(fresnel, _RimPower);

                float3 h = normalize(light.direction + vdir);
                half spec = pow(saturate(dot(n, h)), _SpecPower) * _SpecIntensity;
                spec = smoothstep(0.0, 1.0, spec);

                half3 col = _BaseColor.rgb + _RimColor.rgb * fresnel * _RimIntensity + _SpecColor.rgb * spec;
                half alpha = saturate(_BaseColor.a + fresnel * 0.4 + spec * 0.15);
                return half4(col, alpha);
            }
            ENDHLSL
        }
    }
    FallBack Off
}
