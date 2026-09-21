Shader "ZZY/07.PBR_object/glTFPBRTransmission"
{
    Properties
    {
        [Header(glTF Base Color)]
        // 基础色贴图
        _BaseMap ("BaseColor Map", 2D) = "white" {}
        // 基础色系数
        [HDR] _BaseColorFactor ("BaseColor Factor", Color) = (1, 1, 1, 0.05)

        [Header(glTF Metallic Roughness)]
        // 金属粗糙度贴图
        [NoScaleOffset] _MetallicRoughnessMap ("MetallicRoughness (G=Rough B=Metal)", 2D) = "white" {}
        // 金属度
        _MetallicFactor ("Metallic Factor", Range(0, 1)) = 0
        // 粗糙度
        _RoughnessFactor ("Roughness Factor", Range(0, 1)) = 0.05

        [Header(glTF Normal)]
        // 法线贴图
        [NoScaleOffset] _BumpMap ("Normal Map", 2D) = "bump" {}
        // 法线强度
        _BumpScale ("Normal Scale", Range(0, 4)) = 1

        [Header(glTF Occlusion)]
        // 遮蔽贴图
        [NoScaleOffset] _OcclusionMap ("Occlusion Map (R)", 2D) = "white" {}
        // 遮蔽强度
        _OcclusionStrength ("Occlusion Strength", Range(0, 1)) = 1

        [Header(glTF Emission)]
        // 自发光贴图
        [NoScaleOffset] _EmissionMap ("Emission Map", 2D) = "white" {}
        // 自发光颜色
        [HDR] _EmissionColor ("Emission Factor", Color) = (0, 0, 0, 1)

        [Header(Lighting Scales)]
        // 高光强度
        _SpecularIntensity ("Specular Intensity", Range(0, 4)) = 1
        // 直接光漫反射
        _DirectDiffuseIntensity ("Direct Diffuse", Range(0, 4)) = 1
        // 直接光高光
        _DirectSpecularIntensity ("Direct Specular", Range(0, 4)) = 1
        // 环境光强度
        _EnvironmentIntensity ("Environment Intensity", Range(0, 4)) = 1

        [Header(Transmission KHR)]
        // 透射强度
        _TransmissionFactor ("Transmission Factor", Range(0, 1)) = 1
        // 体积厚度
        _ThicknessFactor ("Thickness", Range(0, 5)) = 1.2
        // 体积衰减颜色
        _AttenuationColor ("Attenuation Color", Color) = (0.8, 0.95, 0.9, 1)
        // 衰减距离
        _AttenuationDistance ("Attenuation Distance", Float) = 1.5
        // 折射率
        _IOR ("IOR", Range(1, 2.5)) = 1.5
        // 屏幕折射强度
        _RefractionStrength ("Screen Refraction Strength", Range(0, 0.2)) = 0.05
        // 透射粗糙加强
        _TransmissionRoughnessBoost ("Transmission Roughness Boost", Range(0, 1)) = 0

        [Header(Debug)]
        // 调试模式
        _DebugMode ("Debug Mode", Float) = 0

        // 剔除模式
        [Enum(UnityEngine.Rendering.CullMode)] _Cull ("Cull", Float) = 2

        [Header(Depth)]
        // 深度写入
        [Enum(Off, 0, On, 1)] _ZWrite ("ZWrite", Float) = 0
        // 深度测试
        [Enum(UnityEngine.Rendering.CompareFunction)] _ZTest ("ZTest", Float) = 4
    }

    SubShader
    {
        Tags
        {
            "RenderPipeline" = "UniversalPipeline"
            "RenderType" = "Transparent"
            "Queue" = "Transparent"
            "IgnoreProjector" = "True"
        }

        Pass
        {
            Name "ForwardTransmission"
            Tags { "LightMode" = "UniversalForward" }
            Cull [_Cull]
            ZWrite [_ZWrite]
            ZTest [_ZTest]
            Blend One OneMinusSrcAlpha

            HLSLPROGRAM
            #pragma target 3.5
            #pragma vertex Vert
            #pragma fragment Frag
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            #pragma multi_compile_fog

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
                float4 screenPos  : TEXCOORD4;
                float  fogFactor  : TEXCOORD5;
            };

            // 透射顶点变换
            Varyings Vert(Attributes input)
            {
                Varyings o;
                // 变换位置、法线与切线
                VertexPositionInputs posInputs = GetVertexPositionInputs(input.positionOS.xyz);
                VertexNormalInputs nrmInputs = GetVertexNormalInputs(input.normalOS, input.tangentOS);

                o.positionCS = posInputs.positionCS;
                o.positionWS = posInputs.positionWS;
                o.uv = input.uv;
                o.normalWS = nrmInputs.normalWS;
                real sign = input.tangentOS.w * GetOddNegativeScale();
                o.tangentWS = float4(nrmInputs.tangentWS, sign);

                // 传递屏幕坐标供折射采样
                o.screenPos = ComputeScreenPos(o.positionCS);
                o.fogFactor = ComputeFogFactor(o.positionCS.z);
                return o;
            }

            // 透射片元着色
            half4 Frag(Varyings i) : SV_Target
            {
                // 填充光照输入
                GltfInputData input;
                input.uv = i.uv;
                input.positionWS = i.positionWS;
                input.normalWS = normalize(i.normalWS);
                input.viewDirWS = GetWorldSpaceNormalizeViewDir(i.positionWS);
                input.tangentWS = i.tangentWS;
                input.screenPos = i.screenPos;

                half4 col = GltfEvaluateLighting(input);

                // 预乘透明度并混合雾
                col.rgb *= col.a;
                col.rgb = MixFog(col.rgb, i.fogFactor);
                return col;
            }
            ENDHLSL
        }
    }
    FallBack Off
}
