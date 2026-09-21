// ============================================================
// CustomPP_Bloom.shader
// 效果：阈值提取 → 降采样金字塔 → 上采样散射 → 叠回场景
// Pass 0 Prefilter | 1 Down | 2 Up | 3 Apply
// ============================================================
Shader "ZZY/05.renderfeature/Bloom"
{
    Properties
    {
        _MainTex ("Source", 2D) = "white" {}
        _SourceTex2 ("Source2", 2D) = "white" {}
    }

    SubShader
    {
        Tags { "RenderPipeline" = "UniversalPipeline" }
        ZWrite Off ZTest Always Cull Off

        HLSLINCLUDE
        #include "Library/CustomPPCommon.hlsl"
        float4 _PPParams0;
        float4 _PPColor;
        ENDHLSL

        // ---------- Pass 0：亮度阈值提取（soft-knee） ----------
        // 输入应为「已乘过 Layer 遮罩」的颜色（非 Layer 区域为黑）
        Pass
        {
            Name "BloomPrefilter"
            HLSLPROGRAM
            #pragma vertex PPVert
            #pragma fragment FragPre
            float4 FragPre(PPVaryings i) : SV_Target
            {
                float3 c = SampleSource(i.uv);
                float lum = LuminancePP(c);
                float threshold = _PPParams0.x;
                float knee = _PPParams0.y * threshold;

                // Soft-knee：阈值附近平滑过渡，避免硬切高光
                float soft = clamp(lum - threshold + knee, 0, 2.0 * knee);
                soft = soft * soft / max(4.0 * knee, 1e-4);
                float contrib = max(soft, lum - threshold) / max(lum, 1e-4);
                return float4(c * contrib, 1);
            }
            ENDHLSL
        }

        // ---------- Pass 1：降采样（盒式滤波） ----------
        Pass
        {
            Name "BloomDown"
            HLSLPROGRAM
            #pragma vertex PPVert
            #pragma fragment FragDown
            float4 FragDown(PPVaryings i) : SV_Target
            {
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

        // ---------- Pass 2：上采样模糊（不在此叠加低层，由 CPU 侧加性合并） ----------
        Pass
        {
            Name "BloomUp"
            HLSLPROGRAM
            #pragma vertex PPVert
            #pragma fragment FragUp
            float4 FragUp(PPVaryings i) : SV_Target
            {
                // _PPParams0.x = scatter，控制上采样模糊半径
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

        // ---------- Pass 3：Bloom 叠回场景色 ----------
        Pass
        {
            Name "BloomApply"
            HLSLPROGRAM
            #pragma vertex PPVert
            #pragma fragment FragApply
            float4 FragApply(PPVaryings i) : SV_Target
            {
                float3 scene = SampleSource(i.uv);
                float3 bloom = SAMPLE_TEXTURE2D(_SourceTex2, sampler_SourceTex2, i.uv).rgb;
                // intensity * tint
                return float4(scene + bloom * _PPParams0.x * _PPColor.rgb, 1);
            }
            ENDHLSL
        }

        // ---------- Pass 4：加性合并（Blend One One，_MainTex 加到当前目标） ----------
        Pass
        {
            Name "BloomAdditive"
            Blend One One
            HLSLPROGRAM
            #pragma vertex PPVert
            #pragma fragment FragAdd
            float4 FragAdd(PPVaryings i) : SV_Target
            {
                return float4(SampleSource(i.uv), 1);
            }
            ENDHLSL
        }
    }
    FallBack Off
}
