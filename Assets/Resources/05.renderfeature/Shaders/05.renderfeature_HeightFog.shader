Shader "ZZY/05.renderfeature/HeightFog"
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
            Name "HeightFog"
            HLSLPROGRAM
            #pragma vertex PPVert
            #pragma fragment Frag
            #include "Library/CustomPPCommon.hlsl"

            float4 _PPParams0;
            float4 _PPParams1;
            float4 _PPColor;

            // 沿世界高度的雾
            float4 Frag(PPVaryings i) : SV_Target
            {
                // 重建世界坐标
                float3 col = SampleSource(i.uv);
                float rawDepth = SampleDepth01(i.uv);
                float isSky = IsSkyPixel(rawDepth);
                float3 worldPos = ReconstructWorldPos(i.uv, rawDepth);

                float strength = _PPParams0.x;
                float baseHeight = _PPParams0.y;
                float heightFalloff = _PPParams0.z;
                float noiseStrength = _PPParams0.w;
                float skyInfluence = _PPParams1.x;

                // 贴地浓、向上变稀
                float h = max(0.0, worldPos.y - baseHeight);
                float heightFactor = exp(-heightFalloff * h);

                // 噪声扰动雾边界
                float n = frac(sin(dot(i.uv, float2(12.9898, 78.233))) * 43758.5453);
                heightFactor *= lerp(1.0, 0.75 + n * 0.5, noiseStrength);

                // 天空影响并混合雾色
                float fogAmount = saturate(strength * heightFactor);
                fogAmount = lerp(fogAmount, skyInfluence, isSky * skyInfluence);

                return float4(lerp(col, _PPColor.rgb, fogAmount), 1);
            }
            ENDHLSL
        }
    }
    FallBack Off
}
