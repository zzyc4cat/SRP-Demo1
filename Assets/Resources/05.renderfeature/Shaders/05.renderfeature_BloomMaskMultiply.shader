// ============================================================
// CustomPP_BloomMaskMultiply.shader
// extract = scene(_MainTex) * mask(_MaskTex)
// 顶点：兼容 RenderingUtils.fullscreenMesh（裁剪空间四边形）
// ============================================================
Shader "ZZY/05.renderfeature/BloomMaskMultiply"
{
    Properties
    {
        _MainTex ("Source", 2D) = "white" {}
        _MaskTex ("Mask", 2D) = "black" {}
    }

    SubShader
    {
        Tags { "RenderPipeline" = "UniversalPipeline" }
        ZWrite Off ZTest Always Cull Off

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

            Varyings Vert(Attributes input)
            {
                Varyings output;
                // RenderingUtils.fullscreenMesh 顶点已在裁剪空间
                output.positionCS = float4(input.positionOS.xy, 0.0, 1.0);
                output.uv = input.uv;
                // 某些平台需要翻转 UV
                #if UNITY_UV_STARTS_AT_TOP
                // fullscreenMesh UV 通常已正确；保留直通
                #endif
                return output;
            }

            float4 Frag(Varyings i) : SV_Target
            {
                float3 c = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv).rgb;
                float m = SAMPLE_TEXTURE2D(_MaskTex, sampler_MaskTex, i.uv).r;
                return float4(c * m, 1);
            }
            ENDHLSL
        }
    }
    FallBack Off
}
