// =============================================================================
// ZZY/07.PBR_object/glTFPBR
// glTF 2.0 Metallic-Roughness PBR（不透明）
//
// 场景测试覆盖：
//   - MetalRoughnessGrid_5x5 ：金属度/粗糙度梯度 → 漫反射衰减、高光形状、反射强度
//   - SpecularTest           ：DebugMode 隔离 Specular / D / Fresnel
//   - NormalTangentMirrorTest：切线空间法线 + bumpScale
// 透射玻璃/液体请用 ZZY/07.PBR_object/glTFPBRTransmission
// =============================================================================
Shader "ZZY/07.PBR_object/glTFPBR"
{
    Properties
    {
        // ---------------------------------------------------------------------
        // [属性组] BaseColor — 表面固有色（电介质漫反射色 / 金属 F0 色）
        // ---------------------------------------------------------------------
        [Header(glTF Base Color)]
        _BaseMap ("BaseColor Map", 2D) = "white" {}
        [HDR] _BaseColorFactor ("BaseColor Factor", Color) = (1, 1, 1, 1)

        // ---------------------------------------------------------------------
        // [属性组] Metallic-Roughness — 金属度(B)×因子、粗糙度(G)×因子
        // 效果：驱动 Metal-Rough 阵列全部视觉差异
        // ---------------------------------------------------------------------
        [Header(glTF Metallic Roughness)]
        [NoScaleOffset] _MetallicRoughnessMap ("MetallicRoughness (G=Rough B=Metal)", 2D) = "white" {}
        _MetallicFactor ("Metallic Factor", Range(0, 1)) = 1
        _RoughnessFactor ("Roughness Factor", Range(0, 1)) = 1

        // ---------------------------------------------------------------------
        // [属性组] Normal — 切线空间法线（Normal-Tangent 测试）
        // ---------------------------------------------------------------------
        [Header(glTF Normal)]
        [NoScaleOffset] _BumpMap ("Normal Map", 2D) = "bump" {}
        _BumpScale ("Normal Scale", Range(0, 4)) = 1

        // ---------------------------------------------------------------------
        // [属性组] Occlusion — R 通道 AO，压暗接缝/环境光
        // ---------------------------------------------------------------------
        [Header(glTF Occlusion)]
        [NoScaleOffset] _OcclusionMap ("Occlusion Map (R)", 2D) = "white" {}
        _OcclusionStrength ("Occlusion Strength", Range(0, 1)) = 1

        // ---------------------------------------------------------------------
        // [属性组] Emission — 自发光（本 Demo 默认关闭）
        // ---------------------------------------------------------------------
        [Header(glTF Emission)]
        [NoScaleOffset] _EmissionMap ("Emission Map", 2D) = "white" {}
        [HDR] _EmissionColor ("Emission Factor", Color) = (0, 0, 0, 1)

        // ---------------------------------------------------------------------
        // [属性组] 光照缩放 — 教学对比时可单独开关漫反射/高光/环境
        // ---------------------------------------------------------------------
        [Header(Lighting Scales)]
        _SpecularIntensity ("Specular Intensity", Range(0, 4)) = 1
        _DirectDiffuseIntensity ("Direct Diffuse", Range(0, 4)) = 1
        _DirectSpecularIntensity ("Direct Specular", Range(0, 4)) = 1
        _EnvironmentIntensity ("Environment Intensity", Range(0, 4)) = 1

        // ---------------------------------------------------------------------
        // [属性组] Transmission 共享参数（不透明 Shader 中默认 Factor=0）
        // 真正启用透射请换 Transmission 变体 Shader
        // ---------------------------------------------------------------------
        [Header(Transmission KHR Shared Props)]
        _TransmissionFactor ("Transmission Factor", Range(0, 1)) = 0
        _ThicknessFactor ("Thickness", Range(0, 5)) = 1
        _AttenuationColor ("Attenuation Color", Color) = (1, 1, 1, 1)
        _AttenuationDistance ("Attenuation Distance", Float) = 1
        _IOR ("IOR", Range(1, 2.5)) = 1.5
        _RefractionStrength ("Screen Refraction Strength", Range(0, 0.2)) = 0.04
        _TransmissionRoughnessBoost ("Transmission Roughness Boost", Range(0, 1)) = 0

        // ---------------------------------------------------------------------
        // [属性组] SpecularTest Debug
        // 0 Full / 1 Spec / 2 Diff / 3 D / 4 Fresnel / 5 Metal / 6 Rough /
        // 7 WorldNormal / 8 AO / 9 Base / 10 F0
        // ---------------------------------------------------------------------
        [Header(Debug SpecularTest)]
        _DebugMode ("Debug Mode", Float) = 0

        [Enum(UnityEngine.Rendering.CullMode)] _Cull ("Cull", Float) = 2
    }

    SubShader
    {
        Tags
        {
            "RenderPipeline" = "UniversalPipeline"
            "RenderType" = "Opaque"
            "Queue" = "Geometry"
        }

        // =====================================================================
        // Pass 0: ForwardLit — 正式着色
        // 效果总成：采样全通道 PBR → Cook-Torrance 直接光 → IBL →（可选）Debug
        // 覆盖：Metal-Rough 梯度、SpecularTest、Normal-Tangent
        // =====================================================================
        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }
            Cull [_Cull]
            ZWrite On
            ZTest LEqual

            HLSLPROGRAM
            #pragma target 3.5
            #pragma vertex Vert
            #pragma fragment Frag
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            #pragma multi_compile_fog
            #include "Library/glTFPBRCommon.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float4 tangentOS  : TANGENT; // 法线贴图必需：提供切线 + 副切线符号
                float2 uv         : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv         : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
                float3 normalWS   : TEXCOORD2;
                float4 tangentWS  : TEXCOORD3; // xyz 切线，w 符号 → TBN
                float4 screenPos  : TEXCOORD4; // 透射屏幕折射预留
                float  fogFactor  : TEXCOORD5;
            };

            // -----------------------------------------------------------------
            // [顶点] 变换位置/法线/切线到世界空间，准备片元 BRDF 与法线贴图
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

                // 切线.w * 奇数负缩放：保证镜像缩放下面副切线方向正确
                real sign = input.tangentOS.w * GetOddNegativeScale();
                o.tangentWS = float4(nrmInputs.tangentWS, sign);

                o.screenPos = ComputeScreenPos(o.positionCS);
                o.fogFactor = ComputeFogFactor(o.positionCS.z);
                return o;
            }

            // -----------------------------------------------------------------
            // [片元] 调用库内 GltfEvaluateLighting
            // 内部依次：表面采样 → 法线 → 直接光 → IBL → 透射(0) → Debug → Fog
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
                col.rgb = MixFog(col.rgb, i.fogFactor);
                return half4(col.rgb, 1); // 不透明：强制 alpha=1
            }
            ENDHLSL
        }

        // =====================================================================
        // Pass 1: ShadowCaster — 写入阴影贴图
        // 效果：沿光线方向施加深度/法线 Bias，减少阴影痤疮；不输出颜色。
        // 说明：不 include Shadows.hlsl，避免 LerpWhiteTo 未声明的编译错误。
        // =====================================================================
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }
            ZWrite On
            ZTest LEqual
            ColorMask 0
            Cull [_Cull]

            HLSLPROGRAM
            #pragma target 3.5
            #pragma vertex ShadowVert
            #pragma fragment ShadowFrag
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            // URP ShadowUtils 注入：方向光用 _LightDirection，点/聚光用 _LightPosition
            float3 _LightDirection;
            float3 _LightPosition;
            float4 _ShadowBias; // x=深度偏置，y=法线偏置

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
            };

            // -----------------------------------------------------------------
            // [效果] 阴影 Bias：沿光线推开顶点 + 按 N·L 做法线内缩，抑制 acne
            // -----------------------------------------------------------------
            float3 ApplyShadowBiasLocal(float3 positionWS, float3 normalWS, float3 lightDirection)
            {
                float invNdotL = 1.0 - saturate(dot(lightDirection, normalWS));
                float scale = invNdotL * _ShadowBias.y;
                positionWS = lightDirection * _ShadowBias.xxx + positionWS;
                positionWS = normalWS * scale.xxx + positionWS;
                return positionWS;
            }

            float4 ShadowVert(Attributes input) : SV_POSITION
            {
                float3 posWS = TransformObjectToWorld(input.positionOS.xyz);
                float3 nWS = TransformObjectToWorldNormal(input.normalOS);

                // 方向光：常量光方向；点/聚光：顶点指向光源
                #if defined(_CASTING_PUNCTUAL_LIGHT_SHADOW)
                float3 lightDirectionWS = normalize(_LightPosition - posWS);
                #else
                float3 lightDirectionWS = _LightDirection;
                #endif

                float4 clip = TransformWorldToHClip(ApplyShadowBiasLocal(posWS, nWS, lightDirectionWS));
                #if UNITY_REVERSED_Z
                clip.z = min(clip.z, UNITY_NEAR_CLIP_VALUE);
                #else
                clip.z = max(clip.z, UNITY_NEAR_CLIP_VALUE);
                #endif
                return clip;
            }

            half4 ShadowFrag() : SV_Target { return 0; }
            ENDHLSL
        }

        // =====================================================================
        // Pass 2: DepthOnly — 仅写深度
        // 效果：供 URP Depth Prepass / 软粒子 / 后处理等使用深度缓冲。
        // =====================================================================
        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode" = "DepthOnly" }
            ZWrite On
            ColorMask 0
            Cull [_Cull]
            HLSLPROGRAM
            #pragma target 3.5
            #pragma vertex DepthVert
            #pragma fragment DepthFrag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            float4 DepthVert(float4 positionOS : POSITION) : SV_POSITION
            {
                return TransformObjectToHClip(positionOS.xyz);
            }

            half4 DepthFrag() : SV_Target { return 0; }
            ENDHLSL
        }
    }
    FallBack Off
}
