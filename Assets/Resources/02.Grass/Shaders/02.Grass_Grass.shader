Shader "ZZY/02.Grass/Grass"
{
    Properties
    {
        [Header(Shading)]
        // 草坪顶部颜色
        _TopColor("草坪顶部颜色（Top Color）", Color) = (1, 1, 1, 1)
        // 草坪底部颜色
        _BottomColor("草坪底部颜色（Bottom Color）", Color) = (1, 1, 1, 1)
        // 背光面额外透出的亮度
        _TranslucentGain("透光增益（Translucent Gain）", Range(0, 1)) = 0.5

        // 草叶随机前倾的强度
        _BendRotationRandom("随机弯曲程度（Bend Rotation Random）", Range(0, 1)) = 0.2

        [Header(Blades)]
        // 草根宽度
        _BladeWidth("草根宽度（Blade Width）", Float) = 0.05
        // 草根宽度的随机幅度
        _BladeWidthRandom("草根宽度随机（Blade Width Random）", Float) = 0.02
        // 草叶高度
        _BladeHeight("草高度（Blade Height）", Float) = 0.5
        // 草叶高度的随机幅度
        _BladeHeightRandom("草高度随机（Blade Height Random）", Float) = 0.3

        // 曲面细分密度
        _TessellationUniform("草坪密度（Tessellation Uniform）", Range(1, 64)) = 1

        [Header(Wind)]
        // 风力噪声贴图
        _WindDistortionMap("风力噪声图（Wind Distortion Map）", 2D) = "white" {}
        // 风力噪声的滚动速度
        _WindFrequency("摆动频率（Wind Frequency）", Vector) = (0.05, 0.05, 0, 0)
        // 风力强度
        _WindStrength("风力强度（Wind Strength）", Float) = 1

        [Header(Depth)]
        // 是否写入深度
        [Enum(Off, 0, On, 1)] _ZWrite ("ZWrite", Float) = 1
        // 深度比较方式
        [Enum(UnityEngine.Rendering.CompareFunction)] _ZTest ("ZTest", Float) = 4
        // 阴影通道的颜色遮罩，默认不写颜色
        [Enum(None, 0, RGB, 7, RGBA, 15)] _ColorMask ("ColorMask", Float) = 0
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

        Pass
        {
            Name "GrassForward"
            Tags { "LightMode" = "UniversalForward" }

            ZWrite [_ZWrite]
            ZTest [_ZTest]

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

            // 草叶着色：根梢渐变、透光和阴影
            float4 Frag(GeometryVaryings input, half facing : VFACE) : SV_Target
            {
                // 背面翻转法线
                float3 normalWS = facing > 0.0 ? input.normalWS : -input.normalWS;

                // 读取主光阴影
                Light mainLight = GetMainLight(input.shadowCoord);
                half shadowAttenuation = mainLight.shadowAttenuation;

                // 背光面增加透光，并乘上阴影
                float noL = saturate(saturate(dot(normalWS, _MainLightPosition.xyz)) + _TranslucentGain)
                    * shadowAttenuation;

                // 环境光与主光混合，从根到梢插值颜色
                float3 ambient = SampleSH(normalWS);
                float3 lightIntensity = noL * _MainLightColor.rgb + ambient;
                float3 color = lerp(_BottomColor.rgb, _TopColor.rgb * lightIntensity, input.uv.y);

                return float4(color, 1.0);
            }
            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }
        
            ZWrite [_ZWrite]
            ZTest [_ZTest]
            ColorMask [_ColorMask]
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
        
            // 计算阴影投射用的裁剪位置
            float4 GetShadowPositionHClip(ShadowAttributes input)
            {
                // 转到世界空间，并取光源方向
                float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);
                float3 normalWS = TransformObjectToWorldNormal(input.normalOS);
        
            #if _CASTING_PUNCTUAL_LIGHT_SHADOW
                float3 lightDirectionWS = normalize(_LightPosition - positionWS);
            #else
                float3 lightDirectionWS = _LightDirection;
            #endif
        
                // 沿光照方向偏移，并夹在近裁剪面内
                float4 positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, lightDirectionWS));
            #if UNITY_REVERSED_Z
                positionCS.z = min(positionCS.z, UNITY_NEAR_CLIP_VALUE);
            #else
                positionCS.z = max(positionCS.z, UNITY_NEAR_CLIP_VALUE);
            #endif
                return positionCS;
            }
        
            // 阴影顶点输出裁剪位置
            ShadowVaryings ShadowPassVertex(ShadowAttributes input)
            {
                ShadowVaryings output;
                output.positionCS = GetShadowPositionHClip(input);
                return output;
            }
        
            // 阴影片元不写颜色
            half4 ShadowPassFragment(ShadowVaryings input) : SV_Target
            {
                return 0;
            }
            ENDHLSL
        }
    }

    FallBack Off
}
