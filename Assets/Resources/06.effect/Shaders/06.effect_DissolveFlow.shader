Shader "ZZY/06.effect/DissolveFlow"
{
    Properties
    {
        // 溶解后仍保留区域的底色
        _BaseColor ("Base Color", Color) = (0.25, 0.45, 0.95, 1)
        // 溶解用的噪声，和阈值比较决定哪里先消失
        _NoiseMap ("Noise Map", 2D) = "gray" {}
        // 溶解前沿上的流光贴图
        _FlowMap ("Flow Map", 2D) = "white" {}
        // 溶解进度。0 完整，1 按噪声全部溶解
        _DissolveAmount ("Dissolve Amount", Range(0,1)) = 0.35
        // 溶解边界亮边的宽度
        _EdgeWidth ("Edge Width", Range(0.001, 0.5)) = 0.16
        // 溶解边界的额外柔化。越大前沿越虚
        _EdgeSoft ("Edge Softness", Range(0.001, 0.5)) = 0.14
        // 溶解边界的发光颜色
        _EdgeColor ("Edge Color", Color) = (0.35, 1.6, 2.4, 1)
        // 溶解边界的发光强度
        _EdgeIntensity ("Edge Intensity", Float) = 2.1
        // 前沿流光的颜色
        _FlowColor ("Flow Color", Color) = (0.4, 1.2, 2.0, 1)
        // 流光贴图的平铺
        _FlowTiling ("Flow Tiling", Vector) = (2, 2, 0, 0)
        // 流光沿 UV 的移动速度
        _FlowSpeed ("Flow Speed", Vector) = (0.2, 0.6, 0, 0)
        // 流光亮度
        _FlowIntensity ("Flow Intensity", Float) = 1.5
        // 外轮廓颜色
        _RimColor ("Rim Color", Color) = (0.5, 0.9, 1.5, 1)
        // 轮廓收边。越大越贴着边缘
        _RimPower ("Rim Power", Range(0.1, 8)) = 2.5
        // 轮廓亮度
        _RimIntensity ("Rim Intensity", Range(0, 5)) = 1.4
        // 大于 0.5 时忽略 Dissolve Amount，按时间自动往复
        _Animate ("Auto Animate", Float) = 1
        // 自动溶解的速度
        _AnimateSpeed ("Animate Speed", Float) = 0.25
        [Header(Depth)]
        // 是否写入深度。软溶解默认关闭，避免硬深度轮廓
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
            Blend SrcAlpha OneMinusSrcAlpha

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Library/EffectCommon.hlsl"

            TEXTURE2D(_NoiseMap); SAMPLER(sampler_NoiseMap);
            TEXTURE2D(_FlowMap); SAMPLER(sampler_FlowMap);

            CBUFFER_START(UnityPerMaterial)
                half4 _BaseColor;
                half _DissolveAmount;
                half _EdgeWidth;
                half _EdgeSoft;
                half4 _EdgeColor;
                half _EdgeIntensity;
                half4 _FlowColor;
                float4 _FlowTiling;
                float4 _FlowSpeed;
                half _FlowIntensity;
                half4 _RimColor;
                half _RimPower;
                half _RimIntensity;
                half _Animate;
                half _AnimateSpeed;
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

            // 顶点：变换到裁剪空间，并带上世界坐标、法线和 UV
            Varyings vert(Attributes v)
            {
                Varyings o;
                float3 posWS = TransformObjectToWorld(v.positionOS.xyz);
                o.positionCS = TransformWorldToHClip(posWS);
                o.positionWS = posWS;
                o.normalWS = TransformObjectToWorldNormal(v.normalOS);
                o.uv = v.uv;
                return o;
            }

            // 片元：软溶解、前沿流光、Fresnel 轮廓
            half4 frag(Varyings i) : SV_Target
            {
                float3 n = normalize(i.normalWS);
                float3 viewWS = GetWorldSpaceNormalizeViewDir(i.positionWS);

                // 溶解遮罩。可选按时间自动往复
                half noise = SAMPLE_TEXTURE2D(_NoiseMap, sampler_NoiseMap, i.uv).r;
                half amount = _DissolveAmount;
                if (_Animate > 0.5)
                    amount = saturate(0.5 + 0.5 * sin(_Time.y * _AnimateSpeed * 6.2831853));

                float d = (float)noise - (float)amount;
                float aa = max(fwidth((float)noise) * 2.0, 1e-4);
                float soft = max((float)_EdgeSoft, 0.02) + aa;
                float band = max((float)_EdgeWidth, 0.04) + aa;

                // 宽软透明度：从空洞一侧平滑淡到实体
                half keep = smoothstep(-soft, soft * 2.2, d);

                // 亮边：在阈值附近最亮，向内外两侧衰减
                half edgeIn = 1.0 - smoothstep(0.0, band, max(d, 0.0));
                half edgeOut = smoothstep(-soft * 0.85, soft * 0.35, d);
                half edge = saturate(edgeIn * edgeOut);
                edge = edge * edge * (3.0 - 2.0 * edge);

                // 只丢掉几乎看不见的像素
                clip(keep - 0.01);

                // 前沿流光
                float2 flowUV = EffectFlowUV(i.uv, _FlowTiling.xy, _FlowSpeed.xy, _Time.y);
                half flow = SAMPLE_TEXTURE2D(_FlowMap, sampler_FlowMap, flowUV).r;
                // 外轮廓
                half rim = EffectFresnel(n, viewWS, _RimPower, _RimIntensity);

                half3 col = _BaseColor.rgb;
                col += _FlowColor.rgb * flow * _FlowIntensity * keep;
                col += _RimColor.rgb * rim * keep;

                half3 edgeCol = _EdgeColor.rgb * _EdgeIntensity;
                // 亮边软混，并在半透明带上铺一层光晕
                half halo = saturate((1.0 - abs(d) / max(band + soft, 1e-4)));
                halo = halo * halo;
                col = lerp(col, edgeCol, edge * 0.8);
                col += edgeCol * halo * 0.65;

                half alpha = saturate(keep * (0.55 + edge * 0.45 + rim * 0.12));
                return half4(col, alpha);
            }
            ENDHLSL
        }
    }
    FallBack Off
}
