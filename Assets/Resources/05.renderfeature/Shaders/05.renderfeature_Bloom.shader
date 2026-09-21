Shader "ZZY/05.renderfeature/Bloom"
{
    Properties
    {
        // 源颜色贴图
        _MainTex ("Source", 2D) = "white" {}
        // 第二路输入
        _SourceTex2 ("Source2", 2D) = "white" {}

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

        HLSLINCLUDE
        #include "Library/CustomPPCommon.hlsl"
        float4 _PPParams0;
        float4 _PPColor;
        ENDHLSL

        Pass
        {
            Name "BloomPrefilter"
            HLSLPROGRAM
            #pragma vertex PPVert
            #pragma fragment FragPre
            // 亮度阈值提取
            float4 FragPre(PPVaryings i) : SV_Target
            {
                // 计算亮度与阈值
                float3 c = SampleSource(i.uv);
                float lum = LuminancePP(c);
                float threshold = _PPParams0.x;
                float knee = _PPParams0.y * threshold;

                // 软膝过渡
                float soft = clamp(lum - threshold + knee, 0, 2.0 * knee);
                soft = soft * soft / max(4.0 * knee, 1e-4);
                float contrib = max(soft, lum - threshold) / max(lum, 1e-4);
                return float4(c * contrib, 1);
            }
            ENDHLSL
        }

        Pass
        {
            Name "BloomDown"
            HLSLPROGRAM
            #pragma vertex PPVert
            #pragma fragment FragDown
            // 盒式降采样
            float4 FragDown(PPVaryings i) : SV_Target
            {
                // 四邻域加中心加权
                float2 t = _MainTex_TexelSize.xy;
                float3 c = SampleSource(i.uv + float2(-t.x, -t.y))
                         + SampleSource(i.uv + float2( t.x, -t.y))
                         + SampleSource(i.uv + float2(-t.x,  t.y))
                         + SampleSource(i.uv + float2( t.x,  t.y))
                         + SampleSource(i.uv) * 2.0;
                return float4(c / 6.0, 1);
            }
            ENDHLSL
        }

        Pass
        {
            Name "BloomUp"
            HLSLPROGRAM
            #pragma vertex PPVert
            #pragma fragment FragUp
            // 上采样模糊
            float4 FragUp(PPVaryings i) : SV_Target
            {
                // 按散射半径模糊
                float2 t = _MainTex_TexelSize.xy * _PPParams0.x;
                float3 blur = SampleSource(i.uv + float2(-t.x, 0))
                           + SampleSource(i.uv + float2( t.x, 0))
                           + SampleSource(i.uv + float2(0, -t.y))
                           + SampleSource(i.uv + float2(0,  t.y))
                           + SampleSource(i.uv) * 2.0;
                blur /= 6.0;
                return float4(blur, 1);
            }
            ENDHLSL
        }

        Pass
        {
            Name "BloomApply"
            HLSLPROGRAM
            #pragma vertex PPVert
            #pragma fragment FragApply
            // 辉光叠回场景
            float4 FragApply(PPVaryings i) : SV_Target
            {
                // 场景色加上着色辉光
                float3 scene = SampleSource(i.uv);
                float3 bloom = SAMPLE_TEXTURE2D(_SourceTex2, sampler_SourceTex2, i.uv).rgb;
                return float4(scene + bloom * _PPParams0.x * _PPColor.rgb, 1);
            }
            ENDHLSL
        }

        Pass
        {
            Name "BloomAdditive"
            Blend One One
            HLSLPROGRAM
            #pragma vertex PPVert
            #pragma fragment FragAdd
            // 加性合并
            float4 FragAdd(PPVaryings i) : SV_Target
            {
                return float4(SampleSource(i.uv), 1);
            }
            ENDHLSL
        }
    }
    FallBack Off
}
