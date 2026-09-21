Shader "ZZY/05.renderfeature/DepthOfField"
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
            Name "DepthOfField"
            HLSLPROGRAM
            #pragma vertex PPVert
            #pragma fragment Frag
            #include "Library/CustomPPCommon.hlsl"

            float4 _PPParams0;

            // 基于弥散圆的景深
            float4 Frag(PPVaryings i) : SV_Target
            {
                // 清晰色与对焦距离
                float3 sharp = SampleSource(i.uv);
                float eyeDepth = LinearEyeDepth01(SampleDepth01(i.uv));

                float focus = _PPParams0.x;
                float blurRadius = _PPParams0.y;
                float nearT = _PPParams0.z;
                float farT = _PPParams0.w;

                // 离焦距离归一化
                float coc = eyeDepth < focus
                    ? saturate((focus - eyeDepth) / max(nearT, 1e-3))
                    : saturate((eyeDepth - focus) / max(farT, 1e-3));

                // 按弥散圆做加权模糊
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

                // 混合清晰图与模糊图
                return float4(lerp(sharp, blur / wsum, coc), 1);
            }
            ENDHLSL
        }
    }
    FallBack Off
}
