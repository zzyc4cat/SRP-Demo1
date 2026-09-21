Shader "ZZY/06.effect/FlowTranslucent"
{
    Properties
    {
        // 遮罩，R 通道参与轮廓和流光的可见范围
        _BaseMap ("Mask (R)", 2D) = "white" {}
        // 面朝摄像机时的内部颜色
        _InnerColor ("Inner Color", Color) = (0.05, 0.15, 0.35, 0.15)
        // 边缘轮廓颜色
        _RimColor ("Rim Color", Color) = (0.3, 0.85, 1.0, 1)
        // Fresnel 起始，低于此值不算边缘
        _RimMin ("Rim Min", Range(-1,1)) = 0.05
        // Fresnel 结束，高于此值轮廓饱和
        _RimMax ("Rim Max", Range(0,2)) = 0.85
        // 轮廓亮度
        _RimIntensity ("Rim Intensity", Float) = 2.2
        // 流光贴图
        _FlowMap ("Flow Map", 2D) = "white" {}
        // 流光颜色
        _FlowColor ("Flow Color", Color) = (0.4, 1.0, 1.0, 1)
        // 物体空间流光平铺
        _FlowTiling ("Flow Tiling", Vector) = (0.55, 0.55, 0, 0)
        // 物体空间流光速度
        _FlowSpeed ("Flow Speed", Vector) = (0.0, 0.18, 0, 0)
        // 流光亮度
        _FlowIntensity ("Flow Intensity", Float) = 1.15
        // 流光对比。越大亮带越窄
        _FlowPower ("Flow Power", Range(0.1, 8)) = 1.6
        // 内部基础透明度，避免中间完全镂空
        _InnerAlpha ("Inner Alpha", Range(0,1)) = 0.12
        [Header(Depth)]
        // 是否写入深度。默认关闭，让身体后面的物体仍可见
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
            Cull Back
            ZWrite [_ZWrite]
            ZTest [_ZTest]
            Blend SrcAlpha One

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Library/EffectCommon.hlsl"

            TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);
            TEXTURE2D(_FlowMap); SAMPLER(sampler_FlowMap);

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                half4 _InnerColor;
                half4 _RimColor;
                half _RimMin;
                half _RimMax;
                half _RimIntensity;
                half4 _FlowColor;
                float4 _FlowTiling;
                float4 _FlowSpeed;
                half _FlowIntensity;
                half _FlowPower;
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
                float3 positionOS : TEXCOORD2;
                float3 normalWS : TEXCOORD3;
                float3 pivotWS : TEXCOORD4;
            };

            // 顶点：输出物体空间坐标，供流光贴在身体上而不是贴在 UV 接缝上
            Varyings vert(Attributes v)
            {
                Varyings o;
                float3 posWS = TransformObjectToWorld(v.positionOS.xyz);
                o.positionCS = TransformWorldToHClip(posWS);
                o.positionWS = posWS;
                o.positionOS = v.positionOS.xyz;
                o.normalWS = TransformObjectToWorldNormal(v.normalOS);
                o.pivotWS = TransformObjectToWorld(float3(0, 0, 0));
                o.uv = TRANSFORM_TEX(v.uv, _BaseMap);
                return o;
            }

            // 片元：软 Fresnel 轮廓加物体空间流光
            half4 frag(Varyings i) : SV_Target
            {
                float3 n = normalize(i.normalWS);
                float3 viewWS = GetWorldSpaceNormalizeViewDir(i.positionWS);
                half ndv = saturate(dot(n, viewWS));
                half fresnel = 1.0 - ndv;
                fresnel = smoothstep(_RimMin, _RimMax, fresnel);

                // 轮廓：用物体空间采样稍微打散硬边
                float2 uvMask = EffectObjectFlowUV(i.positionOS, _FlowTiling.xy * 0.35, float2(0, 0), 0);
                half mask = SAMPLE_TEXTURE2D(_FlowMap, sampler_FlowMap, uvMask).r;
                half finalFresnel = saturate(fresnel + mask * 0.1);

                half3 rimCol = lerp(_InnerColor.rgb, _RimColor.rgb * _RimIntensity, finalFresnel);

                // 流光带
                float2 uvFlow = EffectObjectFlowUV(i.positionOS, _FlowTiling.xy, _FlowSpeed.xy, _Time.y);
                half flowSample = SAMPLE_TEXTURE2D(_FlowMap, sampler_FlowMap, uvFlow).r;
                flowSample = pow(saturate(flowSample), _FlowPower);
                half3 flowCol = _FlowColor.rgb * flowSample * _FlowIntensity;

                half3 col = rimCol + flowCol;
                half alpha = saturate(finalFresnel + flowSample * 0.85 + _InnerAlpha);
                return half4(col, alpha);
            }
            ENDHLSL
        }
    }
    FallBack Off
}
