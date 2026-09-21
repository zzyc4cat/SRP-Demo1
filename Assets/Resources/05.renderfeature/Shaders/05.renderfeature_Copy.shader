Shader "ZZY/05.renderfeature/Copy"
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
            Name "Copy"
            HLSLPROGRAM
            #pragma vertex PPVert
            #pragma fragment Frag
            #include "Library/CustomPPCommon.hlsl"

            // 全屏拷贝
            float4 Frag(PPVaryings i) : SV_Target
            {
                return float4(SampleSource(i.uv), 1);
            }
            ENDHLSL
        }
    }
    FallBack Off
}
