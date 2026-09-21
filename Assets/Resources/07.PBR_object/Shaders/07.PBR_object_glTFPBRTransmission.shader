// =============================================================================
// ZZY/07.PBR_object/glTFPBRTransmission
// KHR_materials_transmission 风格透射 BRDF（玻璃 / 液体）
//
// 与不透明版共用 Library/glTFPBRCommon.hlsl。
// 场景测试：TransmissionRoughnessTest
//   - 透射度 × 粗糙度矩阵：清晰折射 ↔ 磨砂透射
//   - 体积衰减：液体染色（Beer-Lambert）
//   - 屏幕空间折射：透过球体看到背后棋盘墙
// =============================================================================
Shader "ZZY/07.PBR_object/glTFPBRTransmission"
{
    Properties
    {
        // ---------------------------------------------------------------------
        // [属性组] BaseColor — 透射时同时作为体积染色的底色
        // ---------------------------------------------------------------------
        [Header(glTF Base Color)]
        _BaseMap ("BaseColor Map", 2D) = "white" {}
        [HDR] _BaseColorFactor ("BaseColor Factor", Color) = (1, 1, 1, 0.05)

        // ---------------------------------------------------------------------
        // [属性组] Metallic-Roughness
        // 透射体通常 metallic=0；roughness 控制透射模糊（磨砂玻璃）
        // ---------------------------------------------------------------------
        [Header(glTF Metallic Roughness)]
        [NoScaleOffset] _MetallicRoughnessMap ("MetallicRoughness (G=Rough B=Metal)", 2D) = "white" {}
        _MetallicFactor ("Metallic Factor", Range(0, 1)) = 0
        _RoughnessFactor ("Roughness Factor", Range(0, 1)) = 0.05

        // ---------------------------------------------------------------------
        // [属性组] Normal — 折射方向随法线扰动（水面波纹感）
        // ---------------------------------------------------------------------
        [Header(glTF Normal)]
        [NoScaleOffset] _BumpMap ("Normal Map", 2D) = "bump" {}
        _BumpScale ("Normal Scale", Range(0, 4)) = 1

        [Header(glTF Occlusion)]
        [NoScaleOffset] _OcclusionMap ("Occlusion Map (R)", 2D) = "white" {}
        _OcclusionStrength ("Occlusion Strength", Range(0, 1)) = 1

        [Header(glTF Emission)]
        [NoScaleOffset] _EmissionMap ("Emission Map", 2D) = "white" {}
        [HDR] _EmissionColor ("Emission Factor", Color) = (0, 0, 0, 1)

        [Header(Lighting Scales)]
        _SpecularIntensity ("Specular Intensity", Range(0, 4)) = 1
        _DirectDiffuseIntensity ("Direct Diffuse", Range(0, 4)) = 1
        _DirectSpecularIntensity ("Direct Specular", Range(0, 4)) = 1
        _EnvironmentIntensity ("Environment Intensity", Range(0, 4)) = 1

        // ---------------------------------------------------------------------
        // [属性组] Transmission KHR — 本 Shader 的核心效果旋钮
        // TransmissionFactor : 透多少
        // Thickness/Attenuation : 染多深（液体）
        // IOR                 : 折射弯折程度
        // RefractionStrength  : 屏幕折射偏移
        // RoughnessBoost      : 额外磨砂
        // ---------------------------------------------------------------------
        [Header(Transmission KHR)]
        _TransmissionFactor ("Transmission Factor", Range(0, 1)) = 1
        _ThicknessFactor ("Thickness", Range(0, 5)) = 1.2
        _AttenuationColor ("Attenuation Color", Color) = (0.8, 0.95, 0.9, 1)
        _AttenuationDistance ("Attenuation Distance", Float) = 1.5
        _IOR ("IOR", Range(1, 2.5)) = 1.5
        _RefractionStrength ("Screen Refraction Strength", Range(0, 0.2)) = 0.05
        _TransmissionRoughnessBoost ("Transmission Roughness Boost", Range(0, 1)) = 0

        [Header(Debug)]
        _DebugMode ("Debug Mode", Float) = 0

        [Enum(UnityEngine.Rendering.CullMode)] _Cull ("Cull", Float) = 2
    }

    SubShader
    {
        // Transparent 队列：先画不透明（棋盘墙），再画玻璃，才能折射到背后
        Tags
        {
            "RenderPipeline" = "UniversalPipeline"
            "RenderType" = "Transparent"
            "Queue" = "Transparent"
            "IgnoreProjector" = "True"
        }

        // =====================================================================
        // Pass: ForwardTransmission
        // 效果：
        //   - ZWrite Off + One OneMinusSrcAlpha：正确叠在场景之上
        //   - 库内计算：表面高光仍在 + 透射折射 + 体积衰减
        //   - GLTF_USE_OPAQUE_TEXTURE：启用屏幕空间折射采样
        // =====================================================================
        Pass
        {
            Name "ForwardTransmission"
            Tags { "LightMode" = "UniversalForward" }
            Cull [_Cull]
            ZWrite Off
            ZTest LEqual
            Blend One OneMinusSrcAlpha // 预乘 alpha 友好

            HLSLPROGRAM
            #pragma target 3.5
            #pragma vertex Vert
            #pragma fragment Frag
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            #pragma multi_compile_fog

            // 开启库内屏幕折射分支（需 URP Opaque Texture）
            #define GLTF_USE_OPAQUE_TEXTURE 1
            #include "Library/glTFPBRCommon.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float4 tangentOS  : TANGENT;
                float2 uv         : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv         : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
                float3 normalWS   : TEXCOORD2;
                float4 tangentWS  : TEXCOORD3;
                float4 screenPos  : TEXCOORD4; // 屏幕折射 UV
                float  fogFactor  : TEXCOORD5;
            };

            // -----------------------------------------------------------------
            // [顶点] 与不透明版相同，额外输出 screenPos 供折射采样
            // -----------------------------------------------------------------
            Varyings Vert(Attributes input)
            {
                Varyings o;
                VertexPositionInputs posInputs = GetVertexPositionInputs(input.positionOS.xyz);
                VertexNormalInputs nrmInputs = GetVertexNormalInputs(input.normalOS, input.tangentOS);

                o.positionCS = posInputs.positionCS;
                o.positionWS = posInputs.positionWS;
                o.uv = input.uv;
                o.normalWS = nrmInputs.normalWS;
                real sign = input.tangentOS.w * GetOddNegativeScale();
                o.tangentWS = float4(nrmInputs.tangentWS, sign);
                o.screenPos = ComputeScreenPos(o.positionCS);
                o.fogFactor = ComputeFogFactor(o.positionCS.z);
                return o;
            }

            // -----------------------------------------------------------------
            // [片元]
            // 1) GltfEvaluateLighting：直接光高光 + IBL + 透射折射/体积衰减
            // 2) rgb *= a ：预乘，配合 Blend One OneMinusSrcAlpha
            // 3) 雾效
            // -----------------------------------------------------------------
            half4 Frag(Varyings i) : SV_Target
            {
                GltfInputData input;
                input.uv = i.uv;
                input.positionWS = i.positionWS;
                input.normalWS = normalize(i.normalWS);
                input.viewDirWS = GetWorldSpaceNormalizeViewDir(i.positionWS);
                input.tangentWS = i.tangentWS;
                input.screenPos = i.screenPos;

                half4 col = GltfEvaluateLighting(input);

                // 预乘 alpha：透明边缘与背景正确插值
                col.rgb *= col.a;
                col.rgb = MixFog(col.rgb, i.fogFactor);
                return col;
            }
            ENDHLSL
        }
    }
    FallBack Off
}
