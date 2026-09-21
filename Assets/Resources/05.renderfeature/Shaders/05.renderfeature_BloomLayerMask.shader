// ============================================================
// CustomPP_BloomLayerMask.shader
// 将指定 Layer 物体画成白色遮罩（黑底），供 Layer Bloom 提取使用。
// ============================================================
Shader "ZZY/05.renderfeature/BloomLayerMask"
{
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
            ZWrite Off
            ZTest Always
            Cull Off
            ColorMask RGB

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

            Varyings Vert(Attributes input)
            {
                Varyings output;
                output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                return output;
            }

            float4 Frag(Varyings input) : SV_Target
            {
                return float4(1, 1, 1, 1);
            }
            ENDHLSL
        }
    }
    FallBack Off
}
