Shader "ZZY/05.renderfeature/DepthFog"
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
            Name "DepthFog"
            HLSLPROGRAM
            #pragma vertex PPVert
            #pragma fragment Frag
            #include "Library/CustomPPCommon.hlsl"

            float4 _PPParams0;
            float4 _PPParams1;
            float4 _PPColor;

            // 沿视线距离的雾
            float4 Frag(PPVaryings i) : SV_Target
            {
                // 采样颜色与视空间深度
                float3 col = SampleSource(i.uv);
                float rawDepth = SampleDepth01(i.uv);
                float eyeDepth = LinearEyeDepth01(rawDepth);
                float isSky = IsSkyPixel(rawDepth);

                float density = _PPParams0.x;
                float startDistance = _PPParams0.y;
                float endDistance = _PPParams0.z;
                float skyInfluence = _PPParams1.x;
                float noiseStrength = _PPParams1.y;

                float dist = max(0.0, eyeDepth - startDistance);
                float fogAmount;

                // 线性雾或指数雾
                if (endDistance > startDistance)
                {
                    fogAmount = saturate(dist / max(endDistance - startDistance, 1e-3));
                    fogAmount *= density;
                }
                else
                {
                    fogAmount = saturate(1.0 - exp(-density * dist));
                }

                // 噪声扰动并处理天空
                float n = frac(sin(dot(i.uv * 1.7, float2(39.1, 11.7))) * 21041.0);
                fogAmount *= lerp(1.0, 0.85 + n * 0.3, noiseStrength);
                fogAmount = saturate(fogAmount);
                fogAmount = lerp(fogAmount, skyInfluence, isSky * skyInfluence);

                // 混合雾色
                return float4(lerp(col, _PPColor.rgb, fogAmount), 1);
            }
            ENDHLSL
        }
    }
    FallBack Off
}
