// ============================================================
// URP_StaticInstancedFur_Optimized
// 优化点：
// 1. DepthOnly Pass（LightMode=DepthOnly）→ Early-Z，降低 Overdraw
// 2. 公共逻辑抽到 FurCommon.hlsl，Forward/Depth 共用形变与裁剪
// 3. FurSafePow 消除负底数 pow 警告
// 4. 风力向量 + 轻微 Specular，观感更好但成本仍可控
// 5. 配合 FurInstancedRendererOptimized 的距离 LOD 减层
// 注意：UniversalForward 必须放在 Pass 0，避免 Graphics.DrawMeshInstanced
//       在部分路径只跑第一个 Pass 时只写深度不写颜色。
// ============================================================
Shader "ZZY/04.Fur/StaticInstancedFur"
{
    Properties
    {
        [Header(Color Settings)]
        _BaseMap ("Base Map (Albedo)", 2D) = "white" {}
        _BaseColor ("Base Color Tint (Root)", Color) = (1, 1, 1, 1)
        _FurColor ("Fur Tip Color Tint", Color) = (1, 1, 1, 1)

        [Header(Shape and Density)]
        _NoiseTex ("Fur Noise Mask", 2D) = "white" {}
        _NoiseTiling ("Noise Tiling (Global Multiplier)", Float) = 34.0
        _MaxDensity ("Global Max Density", Range(0.0, 1.0)) = 1.0
        _Density ("Root Density (Base)", Range(0.0, 1.0)) = 1.0
        _TipCutoff ("Tip Thinning (Cutoff)", Range(0.0, 1.0)) = 0.82
        _ThicknessCurve ("Taper Curve (Root to Tip)", Range(0.1, 5.0)) = 1.35

        [Header(Fur Length)]
        _FurLength ("Max Fur Length (Global)", Float) = 0.28
        _LengthMap ("Length Mask (R Channel)", 2D) = "white" {}

        [Header(Physics and Natural)]
        _Gravity ("Gravity / Droop", Range(0.0, 1.0)) = 0.24
        _Messiness ("Messiness (Tangle/Curl)", Range(0.0, 1.0)) = 0.32
        _CombDir ("Comb Direction (X, Y, Z)", Vector) = (0.05, -0.55, 0.35, 0.0)

        [Header(Lighting)]
        _AmbientStrength ("Ambient Strength", Range(0.0, 1.0)) = 0.28
        _SpecularStrength ("Specular Strength", Range(0.0, 2.0)) = 0.35
        _SpecularPower ("Specular Power", Range(4.0, 128.0)) = 32.0
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

        // ========================================================
        // Pass 0: UniversalForward（必须最先）
        // 效果说明：正式着色。包含根梢染色、Lambert、环境光、轻量高光。
        // ========================================================
        Pass
        {
            Name "UniversalForward"
            Tags { "LightMode" = "UniversalForward" }

            ZWrite On
            ZTest LEqual

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

            Varyings FurVert(Attributes input)
            {
                Varyings output = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_TRANSFER_INSTANCE_ID(input, output);

                // ------------------------------------------------
                // [效果段 1] 读取当前 Shell 层级比率
                // ratio = 0 → 发根贴合表面；ratio = 1 → 最外层发梢
                // ------------------------------------------------
                float ratio = UNITY_ACCESS_INSTANCED_PROP(FurProps, _LayerRatio);
                output.layerRatio = ratio;

                float3 posWS = TransformObjectToWorld(input.positionOS.xyz);
                float3 normalWS = TransformObjectToWorldDir(input.normalOS);

                // ------------------------------------------------
                // [效果段 2] 顶点形变总成（详见 FurCommon.FurApplyShellDeform）
                // - 法线外扩：构建壳层体积
                // - 重力/梳毛：ratio^2 非线性刚度
                // - 凌乱扰动：打破 GPU 平行感
                // - 风力：发梢摇摆
                // ------------------------------------------------
                FurApplyShellDeform(posWS, normalWS, input.uv, ratio);

                output.positionCS = TransformWorldToHClip(posWS);
                output.positionWS = posWS;
                output.normalWS = normalWS;
                output.uv = TRANSFORM_TEX(input.uv, _NoiseTex);
                output.uvBase = TRANSFORM_TEX(input.uv, _BaseMap);
                return output;
            }

            half4 FurFrag(Varyings input) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(input);
                float ratio = input.layerRatio;

                // ------------------------------------------------
                // [效果段 3] 噪声发丝造型 + Alpha Test
                // 根层 cutoff 低 → 底绒致密；梢层 cutoff 高 → 只留高亮噪声点
                // 多层叠加后，人眼脑补成连续发丝
                // ------------------------------------------------
                float noiseVal = FurSampleNoise(input.uv, ratio);
                float cutoff = FurComputeCutoff(ratio);
                FurClipStrand(noiseVal, cutoff, ratio);

                // ------------------------------------------------
                // [效果段 4] 基础色贴图 × 根/梢 tint，再按层级做根梢渐变
                // albedo = BaseMap * lerp(RootTint, TipTint, ratio)
                // ------------------------------------------------
                float3 baseMap = FurSampleBaseAlbedo(input.uvBase);
                float3 tint = lerp(_BaseColor.rgb, _FurColor.rgb, ratio);
                float3 albedo = baseMap * tint;

                // ------------------------------------------------
                // [效果段 5] 主光 Lambert（廉价漫反射，适配高 Overdraw）
                // ------------------------------------------------
                float3 n = normalize(input.normalWS);
                Light mainLight = GetMainLight();
                float NdotL = saturate(dot(n, mainLight.direction));
                float3 diffuse = albedo * mainLight.color * NdotL;

                // ------------------------------------------------
                // [效果段 6] 环境光填充暗部，避免毛发“死黑”
                // ------------------------------------------------
                float3 ambient = albedo * _AmbientStrength;

                // ------------------------------------------------
                // [效果段 7] 轻量 Blinn-Phong 高光（发梢略增强）
                // 只在亮部加点油润感，成本远低于各向异性发丝高光
                // ------------------------------------------------
                float3 viewDir = GetWorldSpaceNormalizeViewDir(input.positionWS);
                float3 halfDir = normalize(mainLight.direction + viewDir);
                float spec = FurSafePow(saturate(dot(n, halfDir)), _SpecularPower);
                float tipBoost = lerp(0.35, 1.0, ratio);
                float3 specular = mainLight.color * (spec * _SpecularStrength * tipBoost);

                float3 finalColor = diffuse + ambient + specular;
                return half4(finalColor, 1.0);
            }
            ENDHLSL
        }

        // ========================================================
        // Pass 1: DepthOnly
        // 效果说明：仅写入深度，不输出颜色。
        // 作用：URP Depth Prepass / Early-Z 提前剔除被遮挡片元，
        //       降低后续 Forward 的毛发 Overdraw。
        // ========================================================
        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode" = "DepthOnly" }

            ZWrite On
            ColorMask 0

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

            DepthVaryings DepthVert(DepthAttributes input)
            {
                DepthVaryings output = (DepthVaryings)0;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_TRANSFER_INSTANCE_ID(input, output);

                // [层级比率] 由 C# MaterialPropertyBlock 按实例注入
                float ratio = UNITY_ACCESS_INSTANCED_PROP(FurProps, _LayerRatio);
                output.layerRatio = ratio;
                output.uv = TRANSFORM_TEX(input.uv, _NoiseTex);

                float3 posWS = TransformObjectToWorld(input.positionOS.xyz);
                float3 normalWS = TransformObjectToWorldDir(input.normalOS);

                // [形变复用] 深度 Pass 必须与颜色 Pass 使用同一套挤出/重力/风力
                FurApplyShellDeform(posWS, normalWS, input.uv, ratio);

                output.positionCS = TransformWorldToHClip(posWS);
                return output;
            }

            half4 DepthFrag(DepthVaryings input) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(input);

                // [发丝造型] 深度也要做 Alpha Test，否则深度缓冲会写成实心外壳
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
