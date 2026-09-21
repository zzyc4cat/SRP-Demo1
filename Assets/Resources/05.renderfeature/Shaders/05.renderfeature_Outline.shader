// ============================================================
// CustomPP_Outline.shader
// 效果：基于深度差 + 亮度差的屏幕空间描边（Sobel 风格）
// 参数：
//   _PPParams0 = (thickness, depthSensitivity, colorSensitivity, strength)
//   _PPColor   = outline color
// ============================================================
Shader "ZZY/05.renderfeature/Outline"
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
            Name "Outline"
            HLSLPROGRAM
            #pragma vertex PPVert
            #pragma fragment Frag
            #include "Library/CustomPPCommon.hlsl"

            float4 _PPParams0;
            float4 _PPColor;

            float4 Frag(PPVaryings i) : SV_Target
            {
                float3 col = SampleSource(i.uv);
                float2 texel = _MainTex_TexelSize.xy * _PPParams0.x;

                // 深度边缘：左右/上下线性深度差分
                float depthEdge =
                    abs(LinearEyeDepth01(SampleDepth01(i.uv + float2(texel.x, 0))) -
                        LinearEyeDepth01(SampleDepth01(i.uv - float2(texel.x, 0)))) +
                    abs(LinearEyeDepth01(SampleDepth01(i.uv + float2(0, texel.y))) -
                        LinearEyeDepth01(SampleDepth01(i.uv - float2(0, texel.y))));
                depthEdge = saturate(depthEdge * _PPParams0.y);

                // 颜色边缘：亮度差分，补深度平滑处的轮廓
                float colorEdge =
                    abs(LuminancePP(SampleSource(i.uv + float2(texel.x, 0))) -
                        LuminancePP(SampleSource(i.uv - float2(texel.x, 0)))) +
                    abs(LuminancePP(SampleSource(i.uv + float2(0, texel.y))) -
                        LuminancePP(SampleSource(i.uv - float2(0, texel.y))));
                colorEdge = saturate(colorEdge * _PPParams0.z);

                float edge = saturate(max(depthEdge, colorEdge));
                return float4(lerp(col, _PPColor.rgb, edge * _PPParams0.w), 1);
            }
            ENDHLSL
        }
    }
    FallBack Off
}
