Shader "ZZY/07.PBR_object/glTFPBR"
{
    Properties
    {
        [Header(glTF Base Color)]
        // 基础色贴图
        _BaseMap ("BaseColor Map", 2D) = "white" {}
        // 基础色系数
        [HDR] _BaseColorFactor ("BaseColor Factor", Color) = (1, 1, 1, 1)

        [Header(glTF Metallic Roughness)]
        // 金属粗糙度贴图
        [NoScaleOffset] _MetallicRoughnessMap ("MetallicRoughness (G=Rough B=Metal)", 2D) = "white" {}
        // 金属度
        _MetallicFactor ("Metallic Factor", Range(0, 1)) = 1
        // 粗糙度
        _RoughnessFactor ("Roughness Factor", Range(0, 1)) = 1

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

        [Header(Transmission KHR Shared Props)]
        // 透射强度
        _TransmissionFactor ("Transmission Factor", Range(0, 1)) = 0
        // 体积厚度
        _ThicknessFactor ("Thickness", Range(0, 5)) = 1
        // 体积衰减颜色
        _AttenuationColor ("Attenuation Color", Color) = (1, 1, 1, 1)
        // 衰减距离
        _AttenuationDistance ("Attenuation Distance", Float) = 1
        // 折射率
        _IOR ("IOR", Range(1, 2.5)) = 1.5
        // 屏幕折射强度
        _RefractionStrength ("Screen Refraction Strength", Range(0, 0.2)) = 0.04
        // 透射粗糙加强
        _TransmissionRoughnessBoost ("Transmission Roughness Boost", Range(0, 1)) = 0

        [Header(Debug SpecularTest)]
        // 调试模式
        _DebugMode ("Debug Mode", Float) = 0

        // 剔除模式
        [Enum(UnityEngine.Rendering.CullMode)] _Cull ("Cull", Float) = 2

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
            "RenderPipeline" = "UniversalPipeline"
            "RenderType" = "Opaque"
            "Queue" = "Geometry"
        }

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }
            Cull [_Cull]
            ZWrite [_ZWrite]
            ZTest [_ZTest]

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

            // 不透明前向顶点
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

                // 保证镜像缩放时副切线方向正确
                real sign = input.tangentOS.w * GetOddNegativeScale();
                o.tangentWS = float4(nrmInputs.tangentWS, sign);

                // 传递屏幕坐标与雾
                o.screenPos = ComputeScreenPos(o.positionCS);
                o.fogFactor = ComputeFogFactor(o.positionCS.z);
                return o;
            }

            // 不透明前向片元
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

                // 计算光照并混合雾
                half4 col = GltfEvaluateLighting(input);
                col.rgb = MixFog(col.rgb, i.fogFactor);
                return half4(col.rgb, 1);
            }
            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }
            ZWrite [_ZWrite]
            ZTest [_ZTest]
            ColorMask [_DepthColorMask]
            Cull [_Cull]

            HLSLPROGRAM
            #pragma target 3.5
            #pragma vertex ShadowVert
            #pragma fragment ShadowFrag
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            float3 _LightDirection;
            float3 _LightPosition;
            float4 _ShadowBias;

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
            };

            // 沿光线施加阴影偏移
            float3 ApplyShadowBiasLocal(float3 positionWS, float3 normalWS, float3 lightDirection)
            {
                // 按法线夹角内缩并沿光推开
                float invNdotL = 1.0 - saturate(dot(lightDirection, normalWS));
                float scale = invNdotL * _ShadowBias.y;
                positionWS = lightDirection * _ShadowBias.xxx + positionWS;
                positionWS = normalWS * scale.xxx + positionWS;
                return positionWS;
            }

            // 阴影顶点
            float4 ShadowVert(Attributes input) : SV_POSITION
            {
                // 世界空间位置与法线
                float3 posWS = TransformObjectToWorld(input.positionOS.xyz);
                float3 nWS = TransformObjectToWorldNormal(input.normalOS);

                // 方向光或点光源方向
                #if defined(_CASTING_PUNCTUAL_LIGHT_SHADOW)
                float3 lightDirectionWS = normalize(_LightPosition - posWS);
                #else
                float3 lightDirectionWS = _LightDirection;
                #endif

                // 偏移后钳制近裁剪面
                float4 clip = TransformWorldToHClip(ApplyShadowBiasLocal(posWS, nWS, lightDirectionWS));
                #if UNITY_REVERSED_Z
                clip.z = min(clip.z, UNITY_NEAR_CLIP_VALUE);
                #else
                clip.z = max(clip.z, UNITY_NEAR_CLIP_VALUE);
                #endif
                return clip;
            }

            // 阴影片元不输出颜色
            half4 ShadowFrag() : SV_Target { return 0; }
            ENDHLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode" = "DepthOnly" }
            ZWrite [_ZWrite]
            ZTest [_ZTest]
            ColorMask [_DepthColorMask]
            Cull [_Cull]
            HLSLPROGRAM
            #pragma target 3.5
            #pragma vertex DepthVert
            #pragma fragment DepthFrag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            // 深度顶点变换
            float4 DepthVert(float4 positionOS : POSITION) : SV_POSITION
            {
                return TransformObjectToHClip(positionOS.xyz);
            }

            // 深度片元不输出颜色
            half4 DepthFrag() : SV_Target { return 0; }
            ENDHLSL
        }
    }
    FallBack Off
}
