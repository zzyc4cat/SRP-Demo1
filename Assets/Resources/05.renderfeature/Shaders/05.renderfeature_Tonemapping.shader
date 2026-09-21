Shader "ZZY/05.renderfeature/Tonemapping"
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
            Name "Tonemapping"
            HLSLPROGRAM
            #pragma vertex PPVert
            #pragma fragment Frag
            #include "Library/CustomPPCommon.hlsl"

            float4 _PPParams0;

            // 莱因哈德色调映射
            float3 TonemapReinhard(float3 x)
            {
                return x / (1.0 + x);
            }

            // 电影感色调映射
            float3 TonemapACES(float3 x)
            {
                const float a = 2.51;
                const float b = 0.03;
                const float c = 2.43;
                const float d = 0.59;
                const float e = 0.14;
                return saturate((x * (a * x + b)) / (x * (c * x + d) + e));
            }

            // 中性色调映射
            float3 TonemapNeutral(float3 x)
            {
                float3 y = max(0, x - 0.004);
                return (y * (6.2 * y + 0.5)) / (y * (6.2 * y + 1.7) + 0.06);
            }

            // 曝光、曲线与颜色校正
            float4 Frag(PPVaryings i) : SV_Target
            {
                // 按曝光缩放
                float3 col = SampleSource(i.uv) * _PPParams0.x;
                int mode = (int)_PPParams0.w;

                // 按模式做色调映射
                if (mode == 1) col = TonemapReinhard(col);
                else if (mode == 2) col = TonemapACES(col);
                else if (mode == 3) col = TonemapNeutral(col);

                // 绕中灰调整对比度
                col = (col - 0.5) * _PPParams0.y + 0.5;

                // 按亮度调整饱和度
                float luma = LuminancePP(col);
                col = lerp(luma.xxx, col, _PPParams0.z);

                return float4(saturate(col), 1);
            }
            ENDHLSL
        }
    }
    FallBack Off
}
