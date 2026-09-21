// ============================================================
// CustomPP_DepthOfField.shader
// 效果：基于 CoC（弥散圆）的简易景深
// 参数：
//   _PPParams0 = (focusDistance, blurRadius, nearTransition, farTransition)
// ============================================================
Shader "ZZY/05.renderfeature/DepthOfField"
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
            Name "DepthOfField"
            HLSLPROGRAM
            #pragma vertex PPVert
            #pragma fragment Frag
            #include "Library/CustomPPCommon.hlsl"

            float4 _PPParams0;

            float4 Frag(PPVaryings i) : SV_Target
            {
                float3 sharp = SampleSource(i.uv);
                float eyeDepth = LinearEyeDepth01(SampleDepth01(i.uv));

                float focus = _PPParams0.x;
                float blurRadius = _PPParams0.y;
                float nearT = _PPParams0.z;
                float farT = _PPParams0.w;

                // CoC：离焦距离归一化到 [0,1]
                float coc = eyeDepth < focus
                    ? saturate((focus - eyeDepth) / max(nearT, 1e-3))
                    : saturate((eyeDepth - focus) / max(farT, 1e-3));

                // 9-tap 加权模糊，半径随 CoC 放大
                float2 texel = _MainTex_TexelSize.xy * blurRadius * coc;
                float3 blur = 0;
                float wsum = 0;
                const float2 offs[9] = {
                    float2(0,0), float2(1,0), float2(-1,0), float2(0,1), float2(0,-1),
                    float2(1,1), float2(-1,1), float2(1,-1), float2(-1,-1)
                };
                const float ws[9] = { 1.0, 0.7, 0.7, 0.7, 0.7, 0.45, 0.45, 0.45, 0.45 };

                [unroll]
                for (int k = 0; k < 9; k++)
                {
                    blur += SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv + offs[k] * texel).rgb * ws[k];
                    wsum += ws[k];
                }

                // 清晰图与模糊图按 CoC 混合
                return float4(lerp(sharp, blur / wsum, coc), 1);
            }
            ENDHLSL
        }
    }
    FallBack Off
}
