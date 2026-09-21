Shader "ZZY/06.effect/FlowPipe"
{
    Properties
    {
        // 液体基础颜色，Alpha 是基础透明度
        _BaseColor ("Liquid Color", Color) = (0.08, 0.42, 0.92, 0.38)
        // 正对摄像机的中心更深的颜色
        _DeepColor ("Deep Color", Color) = (0.02, 0.18, 0.55, 1)
        // 流动亮纹颜色
        _HighlightColor ("Highlight Color", Color) = (0.65, 0.95, 1.25, 1)
        // 流动噪声的平铺，x 绕管，y 沿管
        _FlowScale ("Flow Scale", Vector) = (2.5, 1.2, 0, 0)
        // 流动速度，主要用 y 沿管长方向
        _FlowSpeed ("Flow Speed", Vector) = (0.0, 0.35, 0, 0)
        // 亮纹对比。越大亮暗差越明显
        _FlowContrast ("Flow Contrast", Range(0.2, 3)) = 1.15
        // 亮纹混入颜色的强度
        _FlowIntensity ("Flow Intensity", Range(0, 3)) = 0.85
        // 噪声扭曲 UV 的幅度
        _WarpStrength ("Warp Strength", Range(0, 0.5)) = 0.12
        // 中心变深的收束
        _DensityPower ("Center Density Power", Range(0.3, 4)) = 1.35
        // 中心变深的强度
        _DensityIntensity ("Center Density", Range(0, 2)) = 0.7
        // 边缘颜色
        _RimColor ("Rim Color", Color) = (0.5, 0.95, 1.3, 1)
        // 边缘收束
        _RimPower ("Rim Power", Range(0.5, 8)) = 2.6
        // 边缘亮度
        _RimIntensity ("Rim Intensity", Range(0, 3)) = 0.55
        // 第一层顶点波浪幅度
        _WaveAmp ("Vertex Wave Amp", Range(0, 0.08)) = 0.012
        // 第一层顶点波浪频率
        _WaveFreq ("Vertex Wave Freq", Range(0.5, 20)) = 6.5
        // 顶点波浪速度
        _WaveSpeed ("Vertex Wave Speed", Range(0, 8)) = 2.2
        // 第二层顶点波浪幅度
        _WaveAmp2 ("Vertex Wave2 Amp", Range(0, 0.05)) = 0.006
        // 第二层顶点波浪频率
        _WaveFreq2 ("Vertex Wave2 Freq", Range(0.5, 30)) = 11.0
        // 额外的基础透明度
        _InnerAlpha ("Inner Alpha", Range(0, 1)) = 0.22
        [Header(Depth)]
        // 是否写入深度。默认开启，液体挡住管壁内侧
        [Enum(Off, 0, On, 1)] _ZWrite ("ZWrite", Float) = 1
        // 深度比较。原先未写，默认 LEqual
        [Enum(UnityEngine.Rendering.CompareFunction)] _ZTest ("ZTest", Float) = 4
    }

    SubShader
    {
        Tags
        {
            "RenderPipeline"="UniversalPipeline"
            "RenderType"="Transparent"
            "Queue"="Transparent+5"
        }

        Pass
        {
            Name "Forward"
            Tags { "LightMode"="UniversalForward" }
            Cull Back
            ZWrite [_ZWrite]
            ZTest [_ZTest]
            Blend SrcAlpha OneMinusSrcAlpha

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Library/EffectCommon.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            CBUFFER_START(UnityPerMaterial)
                half4 _BaseColor;
                half4 _DeepColor;
                half4 _HighlightColor;
                float4 _FlowScale;
                float4 _FlowSpeed;
                half _FlowContrast;
                half _FlowIntensity;
                half _WarpStrength;
                half _DensityPower;
                half _DensityIntensity;
                half4 _RimColor;
                half _RimPower;
                half _RimIntensity;
                half _WaveAmp;
                half _WaveFreq;
                half _WaveSpeed;
                half _WaveAmp2;
                half _WaveFreq2;
                half _InnerAlpha;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float2 uv : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
                float3 normalWS : TEXCOORD2;
            };

            // 顶点：沿管长做轻微径向起伏
            Varyings vert(Attributes v)
            {
                Varyings o;
                float3 posOS = v.positionOS.xyz;
                float3 nOS = normalize(v.normalOS);
                float along = v.uv.y;
                float around = v.uv.x;
                float t = _Time.y;

                // 三层正弦叠成软波浪
                float w1 = sin(along * _WaveFreq * 6.2831853 + t * _WaveSpeed);
                float w2 = sin(along * _WaveFreq2 * 6.2831853 - t * _WaveSpeed * 1.37 + around * 6.2831853);
                float w3 = sin((along * 3.1 + around * 2.0) * 6.2831853 + t * 1.1);
                float wave = w1 * _WaveAmp + w2 * _WaveAmp2 + w3 * (_WaveAmp * 0.35);
                posOS += nOS * wave;

                float3 posWS = TransformObjectToWorld(posOS);
                o.positionCS = TransformWorldToHClip(posWS);
                o.positionWS = posWS;
                o.normalWS = TransformObjectToWorldNormal(nOS);
                o.uv = v.uv;
                return o;
            }

            // 沿管长的软流动亮纹，用两层噪声互相扭曲
            half SoftFlow(float2 uv)
            {
                float t = _Time.y;
                float2 warpUv = float2(uv.x * 2.0, uv.y * 1.5 + t * 0.05);
                float2 warp = float2(
                    EffectFBM(warpUv),
                    EffectFBM(warpUv + float2(17.3, 3.1))
                );
                warp = (warp - 0.5) * _WarpStrength;

                // 主层沿管长拉长
                float2 p1 = float2(uv.x * _FlowScale.x, uv.y * _FlowScale.y) + float2(0.0, _FlowSpeed.y) * t + warp;
                float n1 = EffectFBM(p1);
                // 次层更慢，填补主层的空隙
                float2 p2 = float2(uv.x * (_FlowScale.x * 0.6), uv.y * (_FlowScale.y * 1.8))
                          + float2(0.02, _FlowSpeed.y * 1.45) * t - warp * 0.5;
                float n2 = EffectFBM(p2 + 9.1);

                // 宽过渡，避免硬阈值锯齿
                float flow = n1 * 0.55 + n2 * 0.45;
                flow = smoothstep(0.35, 0.72, flow);
                flow = lerp(0.5, flow, _FlowContrast);
                return saturate(flow);
            }

            // 片元：中心加深、边缘光、流动亮纹，再乘主光
            half4 frag(Varyings i) : SV_Target
            {
                float3 n = normalize(i.normalWS);
                float3 viewWS = GetWorldSpaceNormalizeViewDir(i.positionWS);
                Light light = GetMainLight();

                // 正对视线的地方更深，掠射处出边缘光
                half ndv = saturate(dot(n, viewWS));
                half density = pow(ndv, _DensityPower) * _DensityIntensity;
                half fresnel = 1.0 - ndv;
                fresnel = smoothstep(0.08, 0.95, fresnel);
                fresnel = pow(fresnel, _RimPower);

                half flow = SoftFlow(i.uv);

                half3 col = lerp(_BaseColor.rgb, _DeepColor.rgb, density);
                col = lerp(col, _HighlightColor.rgb, flow * _FlowIntensity);
                col += _RimColor.rgb * fresnel * _RimIntensity;

                half ndl = saturate(dot(n, light.direction)) * 0.25 + 0.75;
                col *= ndl;

                half alpha = saturate(_BaseColor.a + density * 0.45 + flow * 0.28 + fresnel * 0.18 + _InnerAlpha);
                return half4(col, alpha);
            }
            ENDHLSL
        }
    }
    FallBack Off
}
