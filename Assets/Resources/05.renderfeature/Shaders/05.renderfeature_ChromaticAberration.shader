Shader "ZZY/05.renderfeature/ChromaticAberration"
{
    Properties
    {
        // 源颜色贴图
        _MainTex ("Source", 2D) = "white" {}

        [Header(Depth)]
        // 深度写入
        [Enum(Off, 0, On, 1)] _ZWrite ("ZWrite", Float) = 0
        // 深度测试
        [Enum(UnityEngine.Rendering.CompareFunction)] _ZTest ("ZTest", Float) = 8
    }

    SubShader
    {
        Tags { "RenderPipeline" = "UniversalPipeline" }
        ZWrite [_ZWrite]
        ZTest [_ZTest]
        Cull Off

        Pass
        {
            Name "ChromaticAberration"
            HLSLPROGRAM
            #pragma vertex PPVert
            #pragma fragment Frag
            #include "Library/CustomPPCommon.hlsl"

            float4 _PPParams0;

            // 径向色差
            float4 Frag(PPVaryings i) : SV_Target
            {
                // 计算离画面中心的距离
                float2 center = i.uv - 0.5;
                float dist = length(center) * 2.0;

                // 中心无色散，向外增强
                float start = _PPParams0.y;
                float t = saturate((dist - start) / max(1.0 - start, 1e-3));
                float2 dir = length(center) > 1e-5 ? normalize(center) : float2(0, 0);

                // 沿径向偏移红蓝通道
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
