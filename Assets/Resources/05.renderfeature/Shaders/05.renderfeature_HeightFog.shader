// ============================================================
// CustomPP_HeightFog.shader
// 效果：纯高度雾（沿世界 Y 轴，贴地浓、越高越稀）
// 参数：
//   _PPParams0 = (strength, baseHeight, heightFalloff, noiseStrength)
//   _PPParams1 = (skyboxInfluence, 0, 0, 0)
//   _PPColor   = fogColor
// ============================================================
Shader "ZZY/05.renderfeature/HeightFog"
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
            Name "HeightFog"
            HLSLPROGRAM
            #pragma vertex PPVert
            #pragma fragment Frag
            #include "Library/CustomPPCommon.hlsl"

            float4 _PPParams0;
            float4 _PPParams1;
            float4 _PPColor;

            float4 Frag(PPVaryings i) : SV_Target
            {
                float3 col = SampleSource(i.uv);
                float rawDepth = SampleDepth01(i.uv);
                float isSky = IsSkyPixel(rawDepth);
                float3 worldPos = ReconstructWorldPos(i.uv, rawDepth);

                float strength = _PPParams0.x;
                float baseHeight = _PPParams0.y;
                float heightFalloff = _PPParams0.z;
                float noiseStrength = _PPParams0.w;
                float skyInfluence = _PPParams1.x;

                // 相对基准高度：地面最浓，向上指数衰减
                float h = max(0.0, worldPos.y - baseHeight);
                float heightFactor = exp(-heightFalloff * h);

                // 噪声扰动高度雾边界
                float n = frac(sin(dot(i.uv, float2(12.9898, 78.233))) * 43758.5453);
                heightFactor *= lerp(1.0, 0.75 + n * 0.5, noiseStrength);

                // heightFactor∈(0,1]，雾量 = 强度 * 因子
                float fogAmount = saturate(strength * heightFactor);
                fogAmount = lerp(fogAmount, skyInfluence, isSky * skyInfluence);

                return float4(lerp(col, _PPColor.rgb, fogAmount), 1);
            }
            ENDHLSL
        }
    }
    FallBack Off
}
