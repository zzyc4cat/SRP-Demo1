Shader "ZZY/06.effect/FireRealistic"
{
    Properties
    {
        // 焰心颜色
        [HDR] _CoreColor ("Core Color", Color) = (2.4, 2.1, 1.35, 1)
        // 焰身颜色
        [HDR] _MidColor ("Mid Color", Color) = (1.8, 0.55, 0.08, 1)
        // 焰尖颜色
        [HDR] _TipColor ("Tip Color", Color) = (0.55, 0.08, 0.01, 1)
        // 火焰序列帧
        _MainTex ("Flame Flipbook", 2D) = "black" {}
        // 扭曲和碎边用的噪声
        _NoiseMap ("Noise Map", 2D) = "gray" {}
        // 序列帧列数
        _Columns ("Columns", Float) = 12
        // 序列帧行数
        _Rows ("Rows", Float) = 6
        // 序列帧播放速度
        _FPS ("FPS", Float) = 26
        // 时间偏移，用来错开多个火焰
        _TimeOffset ("Time Offset", Float) = 0
        // 两层噪声的缩放，xy 一层，zw 二层
        _NoiseScale ("Noise Scale", Vector) = (1.8, 1.1, 2.6, 1.6)
        // 两层噪声的滚动速度
        _NoiseSpeed ("Noise Speed", Vector) = (0.08, 0.55, -0.12, 0.85)
        // UV 扭曲强度，越往焰尖越强
        _Distort ("Distort", Range(0, 0.5)) = 0.085
        // 焰尖被噪声撕开的程度
        _WispStrength ("Wisp Strength", Range(0, 1)) = 0.45
        // 外形遮罩的软边
        _SoftEdge ("Soft Edge", Range(0.01, 0.5)) = 0.12
        // 整体亮度
        _Intensity ("Intensity", Range(0, 12)) = 3.2
        // 透明度放大
        _AlphaBoost ("Alpha Boost", Range(0, 4)) = 1.35
        // 焰心开始替换颜色的亮度
        _CoreThreshold ("Core Threshold", Range(0, 1)) = 0.62
        // 焰身开始替换颜色的亮度
        _MidThreshold ("Mid Threshold", Range(0, 1)) = 0.28
        // 沿高度压缩火焰
        _VerticalScale ("Vertical Scale", Range(0.5, 1.5)) = 0.92
        // 两侧收窄，并受噪声影响
        _SidePinch ("Side Pinch", Range(0, 2)) = 0.55
        [Header(Depth)]
        // 是否写入深度。默认关闭
        [Enum(Off, 0, On, 1)] _ZWrite ("ZWrite", Float) = 0
        // 深度比较。默认 LEqual
        [Enum(UnityEngine.Rendering.CompareFunction)] _ZTest ("ZTest", Float) = 4
    }

    SubShader
    {
        Tags
        {
            "RenderPipeline"="UniversalPipeline"
            "RenderType"="Transparent"
            "Queue"="Transparent"
        }

        Pass
        {
            Name "Forward"
            Tags { "LightMode"="UniversalForward" }
            Cull Off
            ZWrite [_ZWrite]
            ZTest [_ZTest]
            Blend One OneMinusSrcAlpha

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Library/EffectCommon.hlsl"

            TEXTURE2D(_MainTex); SAMPLER(sampler_MainTex);
            TEXTURE2D(_NoiseMap); SAMPLER(sampler_NoiseMap);

            CBUFFER_START(UnityPerMaterial)
                half4 _CoreColor;
                half4 _MidColor;
                half4 _TipColor;
                float4 _MainTex_ST;
                float4 _NoiseScale;
                float4 _NoiseSpeed;
                half _Columns;
                half _Rows;
                half _FPS;
                half _TimeOffset;
                half _Distort;
                half _WispStrength;
                half _SoftEdge;
                half _Intensity;
                half _AlphaBoost;
                half _CoreThreshold;
                half _MidThreshold;
                half _VerticalScale;
                half _SidePinch;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            // 计算某一帧在序列图里的 UV，并略微内缩避免采到相邻帧
            float2 FireCellUV(float2 localUV, float2 cells, float frame)
            {
                float2 cellCount = max(cells, float2(1, 1));
                float total = cellCount.x * cellCount.y;
                float f = floor(fmod(max(frame, 0.0), total));
                float col = fmod(f, cellCount.x);
                float row = floor(f / cellCount.x);
                float2 cellSize = 1.0 / cellCount;
                float2 offset = float2(col, (cellCount.y - 1.0 - row)) * cellSize;
                float2 inset = cellSize * 0.01;
                float2 uv = offset + inset + localUV * (cellSize - inset * 2.0);
                return uv;
            }

            // 采样当前帧和下一帧，按帧内小数混合，返回亮度
            half SampleFlame(float2 localUV, float frame, float2 cells)
            {
                float2 uvA = FireCellUV(localUV, cells, frame);
                float2 uvB = FireCellUV(localUV, cells, frame + 1.0);
                half3 a = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uvA).rgb;
                half3 b = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uvB).rgb;
                half t = frac(frame);
                half3 rgb = lerp(a, b, t);
                return max(rgb.r, max(rgb.g, rgb.b));
            }

            // 顶点：上部顶点做轻微热浪偏移
            Varyings vert(Attributes v)
            {
                Varyings o;
                float3 pos = v.positionOS.xyz;
                float flicker = EffectNoise2D(float2(pos.x * 4.0 + _Time.y * 3.1, pos.y * 2.0));
                pos.x += (flicker - 0.5) * 0.035 * saturate(v.uv.y);
                pos.y += (flicker - 0.5) * 0.02 * saturate(v.uv.y);
                o.positionCS = TransformObjectToHClip(pos);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                return o;
            }

            // 片元：噪声扭曲序列帧，再按亮度分成焰尖、焰身和焰心
            half4 frag(Varyings i) : SV_Target
            {
                float2 uv = i.uv;
                uv.y = saturate(uv.y * _VerticalScale);

                // 双层噪声扭曲，越靠近焰尖越强
                float2 nUV1 = uv * _NoiseScale.xy + _NoiseSpeed.xy * (_Time.y + _TimeOffset);
                float2 nUV2 = uv * _NoiseScale.zw + _NoiseSpeed.zw * (_Time.y + _TimeOffset);
                half n1 = SAMPLE_TEXTURE2D(_NoiseMap, sampler_NoiseMap, nUV1).r;
                half n2 = SAMPLE_TEXTURE2D(_NoiseMap, sampler_NoiseMap, nUV2).g;
                float tip = saturate(uv.y);
                float2 warp = float2(n1 - 0.5, n2 - 0.5) * _Distort * (0.25 + tip * 1.35);

                // 程序碎边，把两侧和顶部撕开
                float wispNoise = EffectFBM(float2(uv.x * 3.2 + _Time.y * 0.35, uv.y * 2.4 - _Time.y * 1.1) + warp * 4.0);
                float side = 1.0 - abs(uv.x - 0.5) * 2.0;
                side = saturate(side + (wispNoise - 0.5) * _SidePinch * tip);
                float heightMask = smoothstep(1.05, 0.15, uv.y + (wispNoise - 0.45) * 0.25);
                float shapeMask = saturate(side * heightMask);
                shapeMask = smoothstep(0.0, _SoftEdge, shapeMask);

                float2 localUV = saturate(uv + warp);
                float frame = (_Time.y + _TimeOffset) * _FPS;
                float2 cells = float2(_Columns, _Rows);
                half flame = SampleFlame(localUV, frame, cells);

                // 用噪声打散序列帧的硬轮廓
                half breakup = lerp(1.0, wispNoise, _WispStrength * tip);
                flame *= breakup;
                flame *= shapeMask;
                flame = saturate(flame);

                // 颜色：暗红外焰，中间橙，高亮处白热，底部更亮
                half3 col = _TipColor.rgb;
                col = lerp(col, _MidColor.rgb, smoothstep(_MidThreshold, _MidThreshold + 0.35, flame));
                col = lerp(col, _CoreColor.rgb, smoothstep(_CoreThreshold, 1.0, flame));
                // 越靠近底部越亮
                half baseHeat = saturate(1.0 - uv.y * 0.85);
                col = lerp(col * 0.75, col * 1.15, baseHeat);
                col *= flame * _Intensity;

                // 预乘，配合 Blend One OneMinusSrcAlpha
                half alpha = saturate(flame * _AlphaBoost);
                return half4(col * alpha, alpha);
            }
            ENDHLSL
        }
    }
    FallBack Off
}
