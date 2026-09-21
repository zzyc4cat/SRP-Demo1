Shader "ZZY/04.Fur/StaticInstancedFur"
{
    Properties
    {
        [Header(Color Settings)]
        // 基础色贴图
        _BaseMap ("Base Map (Albedo)", 2D) = "white" {}
        // 根部颜色
        _BaseColor ("Base Color Tint (Root)", Color) = (1, 1, 1, 1)
        // 发梢颜色
        _FurColor ("Fur Tip Color Tint", Color) = (1, 1, 1, 1)

        [Header(Shape and Density)]
        // 毛发噪声遮罩
        _NoiseTex ("Fur Noise Mask", 2D) = "white" {}
        // 噪声平铺倍数
        _NoiseTiling ("Noise Tiling (Global Multiplier)", Float) = 34.0
        // 全局最大密度
        _MaxDensity ("Global Max Density", Range(0.0, 1.0)) = 1.0
        // 根部密度
        _Density ("Root Density (Base)", Range(0.0, 1.0)) = 1.0
        // 发梢稀疏裁剪
        _TipCutoff ("Tip Thinning (Cutoff)", Range(0.0, 1.0)) = 0.82
        // 根到梢的锥度
        _ThicknessCurve ("Taper Curve (Root to Tip)", Range(0.1, 5.0)) = 1.35

        [Header(Fur Length)]
        // 最大毛发长度
        _FurLength ("Max Fur Length (Global)", Float) = 0.28
        // 长度遮罩
        _LengthMap ("Length Mask (R Channel)", 2D) = "white" {}

        [Header(Physics and Natural)]
        // 重力下垂
        _Gravity ("Gravity / Droop", Range(0.0, 1.0)) = 0.24
        // 凌乱卷曲
        _Messiness ("Messiness (Tangle/Curl)", Range(0.0, 1.0)) = 0.32
        // 梳毛方向
        _CombDir ("Comb Direction (X, Y, Z)", Vector) = (0.05, -0.55, 0.35, 0.0)

        [Header(Lighting)]
        // 环境光强度
        _AmbientStrength ("Ambient Strength", Range(0.0, 1.0)) = 0.28
        // 高光强度
        _SpecularStrength ("Specular Strength", Range(0.0, 2.0)) = 0.35
        // 高光指数
        _SpecularPower ("Specular Power", Range(4.0, 128.0)) = 32.0

        [Header(Depth)]
        // 深度写入
        [Enum(Off, 0, On, 1)] _ZWrite ("ZWrite", Float) = 1
        // 深度测试
        [Enum(UnityEngine.Rendering.CompareFunction)] _ZTest ("ZTest", Float) = 4
        // 深度通道颜色遮罩
        [Enum(None, 0, RGB, 7, RGBA, 15)] _DepthColorMask ("ColorMask", Float) = 0
    }

    SubShader
    {
        Tags
        {
            "RenderType" = "TransparentCutout"
            "RenderPipeline" = "UniversalPipeline"
            "Queue" = "AlphaTest"
            "IgnoreProjector" = "True"
        }
        Cull Off

        Pass
        {
            Name "UniversalForward"
            Tags { "LightMode" = "UniversalForward" }

            ZWrite [_ZWrite]
            ZTest [_ZTest]

            HLSLPROGRAM
            #pragma target 4.5
            #pragma vertex FurVert
            #pragma fragment FurFrag
            #pragma multi_compile_instancing

            #include "Library/FurCommon.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float2 uv : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float2 uvBase : TEXCOORD1;
                float3 normalWS : TEXCOORD2;
                float3 positionWS : TEXCOORD3;
                float layerRatio : TEXCOORD4;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            // 毛发前向顶点
            Varyings FurVert(Attributes input)
            {
                Varyings output = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_TRANSFER_INSTANCE_ID(input, output);

                // 读取当前壳层比例
                float ratio = UNITY_ACCESS_INSTANCED_PROP(FurProps, _LayerRatio);
                output.layerRatio = ratio;

                // 变换到世界空间
                float3 posWS = TransformObjectToWorld(input.positionOS.xyz);
                float3 normalWS = TransformObjectToWorldDir(input.normalOS);

                // 壳层挤出与弯曲
                FurApplyShellDeform(posWS, normalWS, input.uv, ratio);

                // 输出裁剪空间与贴图坐标
                output.positionCS = TransformWorldToHClip(posWS);
                output.positionWS = posWS;
                output.normalWS = normalWS;
                output.uv = TRANSFORM_TEX(input.uv, _NoiseTex);
                output.uvBase = TRANSFORM_TEX(input.uv, _BaseMap);
                return output;
            }

            // 毛发前向片元
            half4 FurFrag(Varyings input) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(input);
                float ratio = input.layerRatio;

                // 噪声造型并裁剪发丝
                float noiseVal = FurSampleNoise(input.uv, ratio);
                float cutoff = FurComputeCutoff(ratio);
                FurClipStrand(noiseVal, cutoff, ratio);

                // 根梢颜色渐变
                float3 baseMap = FurSampleBaseAlbedo(input.uvBase);
                float3 tint = lerp(_BaseColor.rgb, _FurColor.rgb, ratio);
                float3 albedo = baseMap * tint;

                // 主光漫反射
                float3 n = normalize(input.normalWS);
                Light mainLight = GetMainLight();
                float NdotL = saturate(dot(n, mainLight.direction));
                float3 diffuse = albedo * mainLight.color * NdotL;

                // 环境光填充
                float3 ambient = albedo * _AmbientStrength;

                // 发梢增强的高光
                float3 viewDir = GetWorldSpaceNormalizeViewDir(input.positionWS);
                float3 halfDir = normalize(mainLight.direction + viewDir);
                float spec = FurSafePow(saturate(dot(n, halfDir)), _SpecularPower);
                float tipBoost = lerp(0.35, 1.0, ratio);
                float3 specular = mainLight.color * (spec * _SpecularStrength * tipBoost);

                // 合成最终颜色
                float3 finalColor = diffuse + ambient + specular;
                return half4(finalColor, 1.0);
            }
            ENDHLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode" = "DepthOnly" }

            ZWrite [_ZWrite]
            ZTest [_ZTest]
            ColorMask [_DepthColorMask]

            HLSLPROGRAM
            #pragma target 4.5
            #pragma vertex DepthVert
            #pragma fragment DepthFrag
            #pragma multi_compile_instancing

            #include "Library/FurCommon.hlsl"

            struct DepthAttributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float2 uv : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct DepthVaryings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float layerRatio : TEXCOORD1;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            // 深度通道顶点
            DepthVaryings DepthVert(DepthAttributes input)
            {
                DepthVaryings output = (DepthVaryings)0;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_TRANSFER_INSTANCE_ID(input, output);

                // 读取壳层比例
                float ratio = UNITY_ACCESS_INSTANCED_PROP(FurProps, _LayerRatio);
                output.layerRatio = ratio;
                output.uv = TRANSFORM_TEX(input.uv, _NoiseTex);

                // 与颜色通道相同的形变
                float3 posWS = TransformObjectToWorld(input.positionOS.xyz);
                float3 normalWS = TransformObjectToWorldDir(input.normalOS);

                FurApplyShellDeform(posWS, normalWS, input.uv, ratio);

                output.positionCS = TransformWorldToHClip(posWS);
                return output;
            }

            // 深度通道片元
            half4 DepthFrag(DepthVaryings input) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(input);

                // 按噪声裁剪深度
                float noiseVal = FurSampleNoise(input.uv, input.layerRatio);
                float cutoff = FurComputeCutoff(input.layerRatio);
                FurClipStrand(noiseVal, cutoff, input.layerRatio);
                return 0;
            }
            ENDHLSL
        }
    }

    FallBack Off
}
