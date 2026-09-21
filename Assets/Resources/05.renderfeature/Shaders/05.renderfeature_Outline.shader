Shader "ZZY/05.renderfeature/Outline"
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
            Name "Outline"
            HLSLPROGRAM
            #pragma vertex PPVert
            #pragma fragment Frag
            #include "Library/CustomPPCommon.hlsl"

            float4 _PPParams0;
            float4 _PPColor;

            // 屏幕空间描边
            float4 Frag(PPVaryings i) : SV_Target
            {
                // 采样源颜色
                float3 col = SampleSource(i.uv);
                float2 texel = _MainTex_TexelSize.xy * _PPParams0.x;

                // 深度差分边缘
                float depthEdge =
                    abs(LinearEyeDepth01(SampleDepth01(i.uv + float2(texel.x, 0))) -
                        LinearEyeDepth01(SampleDepth01(i.uv - float2(texel.x, 0)))) +
                    abs(LinearEyeDepth01(SampleDepth01(i.uv + float2(0, texel.y))) -
                        LinearEyeDepth01(SampleDepth01(i.uv - float2(0, texel.y))));
                depthEdge = saturate(depthEdge * _PPParams0.y);

                // 亮度差分边缘
                float colorEdge =
                    abs(LuminancePP(SampleSource(i.uv + float2(texel.x, 0))) -
                        LuminancePP(SampleSource(i.uv - float2(texel.x, 0)))) +
                    abs(LuminancePP(SampleSource(i.uv + float2(0, texel.y))) -
                        LuminancePP(SampleSource(i.uv - float2(0, texel.y))));
                colorEdge = saturate(colorEdge * _PPParams0.z);

                // 混合描边颜色
                float edge = saturate(max(depthEdge, colorEdge));
                return float4(lerp(col, _PPColor.rgb, edge * _PPParams0.w), 1);
            }
            ENDHLSL
        }
    }
    FallBack Off
}
