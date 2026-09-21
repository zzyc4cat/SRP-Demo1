Shader "ZZY/05.renderfeature/BloomMaskMultiply"
{
    Properties
    {
        // 源颜色贴图
        _MainTex ("Source", 2D) = "white" {}
        // 辉光遮罩
        _MaskTex ("Mask", 2D) = "black" {}

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
            Name "BloomMaskMultiply"
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);
            TEXTURE2D(_MaskTex);
            SAMPLER(sampler_MaskTex);

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            // 全屏网格顶点
            Varyings Vert(Attributes input)
            {
                Varyings output;
                // 使用裁剪空间四边形
                output.positionCS = float4(input.positionOS.xy, 0.0, 1.0);
                output.uv = input.uv;
                #if UNITY_UV_STARTS_AT_TOP
                #endif
                return output;
            }

            // 场景色乘遮罩
            float4 Frag(Varyings i) : SV_Target
            {
                // 用遮罩提取辉光区域
                float3 c = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv).rgb;
                float m = SAMPLE_TEXTURE2D(_MaskTex, sampler_MaskTex, i.uv).r;
                return float4(c * m, 1);
            }
            ENDHLSL
        }
    }
    FallBack Off
}
