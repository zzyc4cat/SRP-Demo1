Shader "ZZY/05.renderfeature/BloomLayerMask"
{
    Properties
    {
        [Header(Depth)]
        // 深度写入
        [Enum(Off, 0, On, 1)] _ZWrite ("ZWrite", Float) = 0
        // 深度测试
        [Enum(UnityEngine.Rendering.CompareFunction)] _ZTest ("ZTest", Float) = 8
        // 颜色通道遮罩
        [Enum(None, 0, RGB, 7, RGBA, 15)] _ColorMask ("ColorMask", Float) = 7
    }

    SubShader
    {
        Tags
        {
            "RenderPipeline" = "UniversalPipeline"
        }

        Pass
        {
            Name "BloomLayerMask"
            Tags { "LightMode" = "UniversalForward" }
            ZWrite [_ZWrite]
            ZTest [_ZTest]
            Cull Off
            ColorMask [_ColorMask]

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
            };

            // 遮罩顶点变换
            Varyings Vert(Attributes input)
            {
                Varyings output;
                output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                return output;
            }

            // 输出白色遮罩
            float4 Frag(Varyings input) : SV_Target
            {
                return float4(1, 1, 1, 1);
            }
            ENDHLSL
        }
    }
    FallBack Off
}
