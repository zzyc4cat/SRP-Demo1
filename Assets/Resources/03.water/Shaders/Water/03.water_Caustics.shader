Shader "ZZY/03.water/Caustics"
{
    Properties
    {
        _Size("Size", Float) = 0.5
        [NoScaleOffset]_CausticMap("Caustics", 2D) = "white" {}
        _WaterLevel("WaterLevel", Float) = 0
        _BlendDistance("BlendDistance", Float) = 3

        [HideInInspector] _SrcBlend("__src", Float) = 2.0
        [HideInInspector] _DstBlend("__dst", Float) = 0.0
    }
    SubShader
    {
        ZWrite Off

        Pass
        {
            Blend [_SrcBlend] [_DstBlend], One Zero

            HLSLPROGRAM
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

            #pragma multi_compile _ _DEBUG
            #pragma multi_compile _ _STATIC_SHADER

            #pragma vertex vert
            #pragma fragment frag

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct Varyings
            {
                float4 screenpos : TEXCOORD0;
                float4 positionCS : SV_POSITION;
            };

            TEXTURE2D(_CausticMap); SAMPLER(sampler_CausticMap);
            TEXTURE2D(_AbsorptionScatteringRamp); SAMPLER(sampler_AbsorptionScatteringRamp);

            half _Size;
            half _WaterLevel;
            half _MaxDepth;
            half _BlendDistance;
            half4x4 _MainLightDir;

            // 用深度和逆投影还原世界坐标。反向 Z 时翻转矩阵对应行
            float3 ReconstructWorldPos(half2 screenPos, float depth)
            {
                float4x4 mat = UNITY_MATRIX_I_VP;
#if UNITY_REVERSED_Z
                mat._12_22_32_42 = -mat._12_22_32_42;              
#else
                depth = depth * 2 - 1;
#endif
                float4 raw = mul(mat, float4(screenPos * 2 - 1, depth, 1));
                float3 worldPos = raw.rgb / raw.a;
                return worldPos;
            }

            // 沿主光方向铺焦散 UV，再加一点噪声偏移
            float2 CausticUVs(float2 rawUV, float2 offset)
            {
                float2 uv = rawUV * _Size;
                return uv + offset * 0.1;
            }

            Varyings vert (Attributes input)
            {
                Varyings output;
                
                VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS.xyz);
                output.positionCS = vertexInput.positionCS;
                output.screenpos = ComputeScreenPos(output.positionCS);
                
                return output;
            }
            
            real4 frag (Varyings input) : SV_Target
            {
                float4 screenPos = input.screenpos / input.screenpos.w;
                
                // 场景深度还原水下位置，再转到主光空间采样焦散
                real depth = SampleSceneDepth(screenPos.xy);
                
                Light MainLight = GetMainLight();
                
                float4 WorldPos = ReconstructWorldPos(screenPos.xy, depth).xyzz;
                
                float3 LightUVs = mul(WorldPos, _MainLightDir).xyz;

#if defined(_STATIC_SHADER)
	            float time = 0;
#else
	            float time = _Time.x;
#endif

                // 表面贴图的 W 当噪声，打散焦散 UV
                float2 uv = WorldPos.xz * 0.025 + time * 0.25;
                float waveOffset = SAMPLE_TEXTURE2D(_CausticMap, sampler_CausticMap, uv).w - 0.5;

                float2 causticUV = CausticUVs(LightUVs.xy, waveOffset);

                float LodLevel = abs(WorldPos.y - _WaterLevel) * 4 / _BlendDistance;
                float4 A = SAMPLE_TEXTURE2D_LOD(_CausticMap, sampler_CausticMap, causticUV + time, LodLevel);
                float4 B = SAMPLE_TEXTURE2D_LOD(_CausticMap, sampler_CausticMap, causticUV * 2.0, LodLevel);
                
                float CausticsDriver = (A.z * B.z) * 10 + A.z + B.z;
                
                // 水面以上不要焦散，水下按距离淡出
                half upperMask = saturate(-WorldPos.y + _WaterLevel);
                half lowerMask = saturate((WorldPos.y - _WaterLevel) / _BlendDistance + _BlendDistance);
                CausticsDriver *= min(upperMask, lowerMask);
                
                // 用贴图不同通道假装色散
                half3 Caustics = CausticsDriver * half3(A.w * 0.5, B.w * 0.75, B.x) * MainLight.color;
                
#ifdef _DEBUG
                return real4(Caustics, 1.0);
#endif
                // 加 1 后再乘目标颜色，亮处变亮、暗处保持
                return real4(Caustics + 1.0, 1.0);
            }
            ENDHLSL
        }
    }
}
