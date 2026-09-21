// ============================================================
// CustomPP_DepthFog.shader
// 效果：纯深度雾 / 距离雾（沿相机视线距离）
// 参数：
//   _PPParams0 = (density, startDistance, endDistance, 0)
//                endDistance<=0 时使用指数雾；>0 时使用线性雾
//   _PPParams1 = (skyboxInfluence, noiseStrength, 0, 0)
//   _PPColor   = fogColor
// ============================================================
Shader "ZZY/05.renderfeature/DepthFog"
{
    Properties
    {
        _MainTex ("Source", 2D) = "white" {}
    }

    SubShader
    {
        Tags { "RenderPipeline" = "UniversalPipeline" }
        ZWrite Off ZTest Always Cull Off

        Pass
        {
            Name "DepthFog"
            HLSLPROGRAM
            #pragma vertex PPVert
            #pragma fragment Frag
            #include "Library/CustomPPCommon.hlsl"

            float4 _PPParams0;
            float4 _PPParams1;
            float4 _PPColor;

            float4 Frag(PPVaryings i) : SV_Target
            {
                float3 col = SampleSource(i.uv);
                float rawDepth = SampleDepth01(i.uv);
                float eyeDepth = LinearEyeDepth01(rawDepth);
                float isSky = IsSkyPixel(rawDepth);

                float density = _PPParams0.x;
                float startDistance = _PPParams0.y;
                float endDistance = _PPParams0.z;
                float skyInfluence = _PPParams1.x;
                float noiseStrength = _PPParams1.y;

                float dist = max(0.0, eyeDepth - startDistance);
                float fogAmount;

                if (endDistance > startDistance)
                {
                    // 线性深度雾：start → end 从 0 过渡到 1
                    fogAmount = saturate(dist / max(endDistance - startDistance, 1e-3));
                    fogAmount *= density; // density 作强度缩放（建议 0~1）
                }
                else
                {
                    // 指数深度雾
                    fogAmount = saturate(1.0 - exp(-density * dist));
                }

                float n = frac(sin(dot(i.uv * 1.7, float2(39.1, 11.7))) * 21041.0);
                fogAmount *= lerp(1.0, 0.85 + n * 0.3, noiseStrength);
                fogAmount = saturate(fogAmount);
                fogAmount = lerp(fogAmount, skyInfluence, isSky * skyInfluence);

                return float4(lerp(col, _PPColor.rgb, fogAmount), 1);
            }
            ENDHLSL
        }
    }
    FallBack Off
}
