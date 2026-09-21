// ============================================================================
// ZZY/02.Grass/Grass — URP 草地（曲面细分 + 几何着色器）
// ----------------------------------------------------------------------------
// Pass：
//   1. UniversalForward — 草叶着色 / 透光 / 接收阴影
//   2. ShadowCaster    — 投影
// 库：
//   Library/CustomTessellation.hlsl — Hull / Domain
//   Library/Grass.hlsl              — Geometry / 风 / 压草
// 命名规范见 Library 文件头
// ============================================================================
Shader "ZZY/02.Grass/Grass"
{
    Properties
    {
        [Header(Shading)]
        _TopColor("草坪顶部颜色（Top Color）", Color) = (1, 1, 1, 1)
        _BottomColor("草坪底部颜色（Bottom Color）", Color) = (1, 1, 1, 1)
        _TranslucentGain("透光增益（Translucent Gain）", Range(0, 1)) = 0.5

        _BendRotationRandom("随机弯曲程度（Bend Rotation Random）", Range(0, 1)) = 0.2

        [Header(Blades)]
        _BladeWidth("草根宽度（Blade Width）", Float) = 0.05
        _BladeWidthRandom("草根宽度随机（Blade Width Random）", Float) = 0.02
        _BladeHeight("草高度（Blade Height）", Float) = 0.5
        _BladeHeightRandom("草高度随机（Blade Height Random）", Float) = 0.3

        _TessellationUniform("草坪密度（Tessellation Uniform）", Range(1, 64)) = 1

        [Header(Wind)]
        _WindDistortionMap("风力噪声图（Wind Distortion Map）", 2D) = "white" {}
        _WindFrequency("摆动频率（Wind Frequency）", Vector) = (0.05, 0.05, 0, 0)
        _WindStrength("风力强度（Wind Strength）", Float) = 1
    }

    SubShader
    {
        Tags
        {
            "RenderPipeline" = "UniversalPipeline"
            "RenderType" = "Opaque"
            "Queue" = "Geometry"
        }
        Cull Off

        // --------------------------------------------------------------------
        // Forward：细分 → 几何挤出草叶 → 片元光照
        // --------------------------------------------------------------------
        Pass
        {
            Name "GrassForward"
            Tags { "LightMode" = "UniversalForward" }

            HLSLPROGRAM
            #pragma target 4.6
            #pragma require geometry tessellation
            #pragma exclude_renderers gles gles3 glcore metal

            #pragma vertex Vert
            #pragma hull Hull
            #pragma domain Domain
            #pragma geometry GrassGeometry
            #pragma fragment Frag

            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile_fragment _ _SHADOWS_SOFT

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "./Library/Grass.hlsl"

            // ----------------------------------------------------------------
            // 【效果】草叶着色：根→梢颜色渐变 + 半透光 Lambert + 环境光 + 阴影
            // ----------------------------------------------------------------
            float4 Frag(GeometryVaryings input, half facing : VFACE) : SV_Target
            {
                // 双面：背向翻转法线
                float3 normalWS = facing > 0.0 ? input.normalWS : -input.normalWS;

                Light mainLight = GetMainLight(input.shadowCoord);
                half shadowAttenuation = mainLight.shadowAttenuation;

                // 透光：给 NdotL 加 bias，让背光面也有一点亮度
                float noL = saturate(saturate(dot(normalWS, _MainLightPosition.xyz)) + _TranslucentGain)
                    * shadowAttenuation;

                float3 ambient = SampleSH(normalWS);
                float3 lightIntensity = noL * _MainLightColor.rgb + ambient;
                // uv.y：0 根部用 Bottom，1 梢部用 Top * 光照
                float3 color = lerp(_BottomColor.rgb, _TopColor.rgb * lightIntensity, input.uv.y);

                return float4(color, 1.0);
            }
            ENDHLSL
        }

        // --------------------------------------------------------------------
        // ShadowCaster：写入 Shadowmap（平面基底投影；草叶几何不参与挤出）
        // --------------------------------------------------------------------
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }
        
            ZWrite On
            ZTest LEqual
            ColorMask 0
            Cull Off
        
            HLSLPROGRAM
            #pragma target 4.5
            #pragma exclude_renderers gles gles3 glcore metal
        
            #pragma vertex ShadowPassVertex
            #pragma fragment ShadowPassFragment
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW
        
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"
        
            float3 _LightDirection;
            float3 _LightPosition;
        
            struct ShadowAttributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
            };
        
            struct ShadowVaryings
            {
                float4 positionCS : SV_POSITION;
            };
        
            float4 GetShadowPositionHClip(ShadowAttributes input)
            {
                float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);
                float3 normalWS = TransformObjectToWorldNormal(input.normalOS);
        
            #if _CASTING_PUNCTUAL_LIGHT_SHADOW
                float3 lightDirectionWS = normalize(_LightPosition - positionWS);
            #else
                float3 lightDirectionWS = _LightDirection;
            #endif
        
                float4 positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, lightDirectionWS));
            #if UNITY_REVERSED_Z
                positionCS.z = min(positionCS.z, UNITY_NEAR_CLIP_VALUE);
            #else
                positionCS.z = max(positionCS.z, UNITY_NEAR_CLIP_VALUE);
            #endif
                return positionCS;
            }
        
            ShadowVaryings ShadowPassVertex(ShadowAttributes input)
            {
                ShadowVaryings output;
                output.positionCS = GetShadowPositionHClip(input);
                return output;
            }
        
            half4 ShadowPassFragment(ShadowVaryings input) : SV_Target
            {
                return 0;
            }
            ENDHLSL
        }
    }

    FallBack Off
}
