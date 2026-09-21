// ============================================================
// CustomPP_ChromaticAberration.shader
// 效果：径向色差（R/B 通道沿径向反向偏移）
// 参数：
//   _PPParams0 = (intensity, start, 0, 0)
// ============================================================
Shader "ZZY/05.renderfeature/ChromaticAberration"
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
            Name "ChromaticAberration"
            HLSLPROGRAM
            #pragma vertex PPVert
            #pragma fragment Frag
            #include "Library/CustomPPCommon.hlsl"

            float4 _PPParams0;

            float4 Frag(PPVaryings i) : SV_Target
            {
                float2 center = i.uv - 0.5;
                float dist = length(center) * 2.0;

                // start：中心无色散区域，向外渐强
                float start = _PPParams0.y;
                float t = saturate((dist - start) / max(1.0 - start, 1e-3));
                float2 dir = length(center) > 1e-5 ? normalize(center) : float2(0, 0);

                // 偏移量随 intensity * t 增大
                float2 offset = dir * (_PPParams0.x * t) * _MainTex_TexelSize.xy * 40.0;

                float r = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv + offset).r;
                float g = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv).g;
                float b = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv - offset).b;
                return float4(r, g, b, 1);
            }
            ENDHLSL
        }
    }
    FallBack Off
}
