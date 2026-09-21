// ============================================================
// CustomPP_Copy.shader
// 效果：全屏拷贝（中间缓冲 ping-pong 的起点）
// ============================================================
Shader "ZZY/05.renderfeature/Copy"
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
            Name "Copy"
            HLSLPROGRAM
            #pragma vertex PPVert
            #pragma fragment Frag
            #include "Library/CustomPPCommon.hlsl"

            // 原样输出源颜色
            float4 Frag(PPVaryings i) : SV_Target
            {
                return float4(SampleSource(i.uv), 1);
            }
            ENDHLSL
        }
    }
    FallBack Off
}
