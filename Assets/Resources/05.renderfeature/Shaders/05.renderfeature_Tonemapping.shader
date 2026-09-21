// ============================================================
// CustomPP_Tonemapping.shader
// 效果：曝光 + 色调映射曲线 + 对比度/饱和度
// 参数：
//   _PPParams0 = (exposure, contrast, saturation, mode)
//   mode: 1=Reinhard, 2=ACES, 3=Neutral
// ============================================================
Shader "ZZY/05.renderfeature/Tonemapping"
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
            Name "Tonemapping"
            HLSLPROGRAM
            #pragma vertex PPVert
            #pragma fragment Frag
            #include "Library/CustomPPCommon.hlsl"

            float4 _PPParams0;

            // Reinhard：x/(1+x)，简单稳定
            float3 TonemapReinhard(float3 x)
            {
                return x / (1.0 + x);
            }

            // ACES 拟合曲线：电影感，高光更柔
            float3 TonemapACES(float3 x)
            {
                const float a = 2.51;
                const float b = 0.03;
                const float c = 2.43;
                const float d = 0.59;
                const float e = 0.14;
                return saturate((x * (a * x + b)) / (x * (c * x + d) + e));
            }

            // Neutral：偏亮部保留，适合写实
            float3 TonemapNeutral(float3 x)
            {
                float3 y = max(0, x - 0.004);
                return (y * (6.2 * y + 0.5)) / (y * (6.2 * y + 1.7) + 0.06);
            }

            float4 Frag(PPVaryings i) : SV_Target
            {
                float3 col = SampleSource(i.uv) * _PPParams0.x; // exposure
                int mode = (int)_PPParams0.w;

                if (mode == 1) col = TonemapReinhard(col);
                else if (mode == 2) col = TonemapACES(col);
                else if (mode == 3) col = TonemapNeutral(col);

                // 对比度：绕中灰 0.5 缩放
                col = (col - 0.5) * _PPParams0.y + 0.5;

                // 饱和度：亮度与彩色插值
                float luma = LuminancePP(col);
                col = lerp(luma.xxx, col, _PPParams0.z);

                return float4(saturate(col), 1);
            }
            ENDHLSL
        }
    }
    FallBack Off
}
