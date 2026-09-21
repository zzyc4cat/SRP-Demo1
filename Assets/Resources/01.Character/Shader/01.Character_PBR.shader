// =============================================================================
// URP 原神风格角色 Shader
// 功能：身体 Ramp 明暗 / 脸部 SDF 阴影 / 金属高光 / 边缘光 / 自发光 / 双面 / 描边
// =============================================================================
Shader "ZZY/01.Character/PBR"
{
    // -------------------------------------------------------------------------
    // Properties：Inspector 面板参数
    // -------------------------------------------------------------------------
    Properties
    {
        // --- 模式开关 ---
        [Space(20.0)]
        [Toggle] _genshinShader("是否是脸部", Float) = 0.0

        // --- Diffuse / 边缘光 / Alpha 用途 ---
        [Space(15.0)]
        [NoScaleOffset] _diffuse("Diffuse", 2D) = "white" {}
        _fresnel("边缘光范围", Range(0.0, 10.0)) = 1.7
        _edgeLight("边缘光强度", Range(0.0, 1.0)) = 0.02

        [Space(8.0)]
        _diffuseA("Alpha(1透明, 2自发光)", Range(0.0, 2.0)) = 0.0
        _Cutoff("透明阈值", Range(0.0, 1.0)) = 1.0
        [HDR] _glow("自发光强度", Color) = (1.0, 1.0, 1.0, 1.0)
        _flicker("发光闪烁速度", Float) = 0.8

        // --- Lightmap / 脸部 SDF ---
        [Space(30.0)]
        [NoScaleOffset] _lightmap("Lightmap/FaceLightmap", 2D) = "white" {}
        _bright("亮面范围", Float) = 0.99
        _grey("灰面范围", Float) = 1.14
        _dark("暗面范围", Float) = 0.5

        // --- 法线 ---
        [Space(30.0)]
        [NoScaleOffset] _bumpMap("Normalmap", 2D) = "bump" {}
        _bumpScale("法线强度", Float) = 1.0

        // --- Shadow Ramp（昼夜与材质条带） ---
        [Space(30.0)]
        [NoScaleOffset] _ramp("Shadow_Ramp", 2D) = "white" {}
        [Toggle] _dayAndNight("是否是白天", Float) = 0.0

        [Space(8.0)]
        _lightmapA0("1.0_Ramp条数", Range(1, 5)) = 1
        _lightmapA1("0.7_Ramp条数", Range(1, 5)) = 4
        _lightmapA2("0.5_Ramp条数", Range(1, 5)) = 3
        _lightmapA3("0.3_Ramp条数", Range(1, 5)) = 5
        _lightmapA4("0.0_Ramp条数", Range(1, 5)) = 2

        // --- 金属 / 高光 ---
        [Space(30.0)]
        [NoScaleOffset] _metalMap("MetalMap", 2D) = "white" {}
        _gloss("高光范围", Range(1, 256.0)) = 1
        _glossStrength("高光强度", Range(0.0, 1.0)) = 1
        _metalMapColor("金属反射颜色", Color) = (1.0, 1.0, 1.0, 1.0)

        // --- 描边（按 lightmap.a 材质分区上色） ---
        [Space(30.0)]
        _outline("描边粗细", Range(0.0, 1.0)) = 0.4
        _outlineColor0("描边颜色1", Color) = (1.0, 0.0, 0.0, 0.0)
        _outlineColor1("描边颜色2", Color) = (0.0, 1.0, 0.0, 0.0)
        _outlineColor2("描边颜色3", Color) = (0.0, 0.0, 1.0, 0.0)
        _outlineColor3("描边颜色4", Color) = (1.0, 1.0, 0.0, 0.0)
        _outlineColor4("描边颜色5", Color) = (0.5, 0.0, 1.0, 0.0)
    }

    SubShader
    {
        // ---------------------------------------------------------------------
        // SubShader 标签：声明 URP 不透明物体
        // ---------------------------------------------------------------------
        Tags
        {
            "RenderPipeline" = "UniversalPipeline"
            "RenderType" = "Opaque"
            "Queue" = "Geometry"
        }

        // =====================================================================
        // HLSLINCLUDE：各 Pass 共用的常量、贴图与光照函数
        // =====================================================================
        HLSLINCLUDE
        // --- URP 核心 / 光照库 ---
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

        // --- 材质常量缓冲区（SRP Batcher） ---
        CBUFFER_START(UnityPerMaterial)
            float _genshinShader;

            float _fresnel;
            float _edgeLight;
            float _diffuseA;
            float _Cutoff;
            float4 _glow;
            float _flicker;

            float _bright;
            float _grey;
            float _dark;

            float _bumpScale;

            float _dayAndNight;
            float _lightmapA0;
            float _lightmapA1;
            float _lightmapA2;
            float _lightmapA3;
            float _lightmapA4;

            float _gloss;
            float _glossStrength;
            float3 _metalMapColor;

            float _outline;
            float3 _outlineColor0;
            float3 _outlineColor1;
            float3 _outlineColor2;
            float3 _outlineColor3;
            float3 _outlineColor4;
        CBUFFER_END

        // --- 贴图与采样器声明 ---
        TEXTURE2D(_diffuse);    SAMPLER(sampler_diffuse);
        TEXTURE2D(_lightmap);   SAMPLER(sampler_lightmap);
        TEXTURE2D(_bumpMap);    SAMPLER(sampler_bumpMap);
        TEXTURE2D(_ramp);       SAMPLER(sampler_ramp);
        TEXTURE2D(_metalMap);   SAMPLER(sampler_metalMap);

        // ---------------------------------------------------------------------
        // Shadow Ramp：根据半 Lambert + lightmap.a 材质分区采样阴影色带
        // ---------------------------------------------------------------------
        float3 CalcShadowRamp(float4 lightmap, float NdotL)
        {
            // lightmap.g：AO / 阴影遮罩，压成软边
            lightmap.g = smoothstep(0.2, 0.3, lightmap.g);

            // 半 Lambert，再乘 AO
            float halfLambert = smoothstep(0.0, _grey, NdotL + _dark) * lightmap.g;
            float brightMask = step(_bright, halfLambert);

            // 夜晚采样下半张 Ramp（V 偏移 0.5）
            float rampSampling = (_dayAndNight < 0.5) ? 0.5 : 0.0;

            // 各材质对应的 Ramp V 坐标（条数越大越靠下）
            float ramp0 = _lightmapA0 * -0.1 + 1.05 - rampSampling;
            float ramp1 = _lightmapA1 * -0.1 + 1.05 - rampSampling;
            float ramp2 = _lightmapA2 * -0.1 + 1.05 - rampSampling;
            float ramp3 = _lightmapA3 * -0.1 + 1.05 - rampSampling;
            float ramp4 = _lightmapA4 * -0.1 + 1.05 - rampSampling;

            // 用 step 拆分 lightmap.a 材质区间，再 lerp 选出对应条带
            float lightmapA2 = step(0.25, lightmap.a);
            float lightmapA3 = step(0.45, lightmap.a);
            float lightmapA4 = step(0.65, lightmap.a);
            float lightmapA5 = step(0.95, lightmap.a);

            float rampV = ramp0;
            rampV = lerp(rampV, ramp1, lightmapA2);
            rampV = lerp(rampV, ramp2, lightmapA3);
            rampV = lerp(rampV, ramp3, lightmapA4);
            rampV = lerp(rampV, ramp4, lightmapA5);

            float3 ramp = SAMPLE_TEXTURE2D(_ramp, sampler_ramp, float2(halfLambert, rampV)).rgb;

            // 亮面区域直接用半 Lambert（保持高光区干净）
            return lerp(ramp, halfLambert.xxx, brightMask);
        }

        // ---------------------------------------------------------------------
        // 高光：Blinn-Phong，受 lightmap.r/b 与亮面遮罩控制
        // ---------------------------------------------------------------------
        float3 CalcSpecular(float NdotL, float NdotH, float4 lightmap, float3 baseColor)
        {
            float blinnPhong = pow(saturate(NdotH), _gloss);
            float3 specular = blinnPhong * lightmap.r * _glossStrength;
            specular *= lightmap.b;
            specular *= baseColor;

            lightmap.g = smoothstep(0.2, 0.3, lightmap.g);
            float halfLambert = smoothstep(0.0, _grey, NdotL + _dark) * lightmap.g;
            float brightMask = step(_bright, halfLambert);

            return specular * brightMask;
        }

        // ---------------------------------------------------------------------
        // 金属：用视角空间法线采样 MetalMap，lightmap.r 高值区为金属
        // ---------------------------------------------------------------------
        float3 CalcMetal(float3 nDirVS, float4 lightmap, float3 baseColor)
        {
            float metalMask = 1.0 - step(lightmap.r, 0.9);
            float metalMap = SAMPLE_TEXTURE2D(_metalMap, sampler_metalMap, nDirVS.xy * 0.5 + 0.5).r;
            float3 metalColor = lerp(_metalMapColor, baseColor, metalMap);
            return lerp(0.0, metalColor, metalMask);
        }

        // ---------------------------------------------------------------------
        // 边缘光：阈值化菲涅尔，形成卡通外轮廓亮边
        // ---------------------------------------------------------------------
        float3 CalcRimLight(float NdotV, float3 baseColor)
        {
            float fresnel = pow(saturate(1.0 - NdotV), _fresnel);
            return step(0.5, fresnel) * _edgeLight * baseColor;
        }

        // ---------------------------------------------------------------------
        // 自发光：diffuse.a 作遮罩，按时间正弦闪烁
        // （不可命名为 light，HLSL 大小写不敏感，会与 Lighting.hlsl 的 Light 冲突）
        // ---------------------------------------------------------------------
        float3 CalcEmission(float3 baseColor, float diffuseA)
        {
            diffuseA = smoothstep(0.0, 1.0, diffuseA);
            float flicker = sin(_Time.w * _flicker) * 0.5 + 0.5;
            return lerp(0.0, baseColor * (flicker * _glow.rgb), diffuseA);
        }

        // ---------------------------------------------------------------------
        // 身体着色：Ramp 漫反射 + 金属 + 高光 + 边缘光
        // ---------------------------------------------------------------------
        float3 ShadeBody(float NdotL, float NdotH, float NdotV, float4 lightmap, float3 baseColor, float3 nDirVS)
        {
            float3 ramp = CalcShadowRamp(lightmap, NdotL);
            float3 specular = CalcSpecular(NdotL, NdotH, lightmap, baseColor);
            float3 metal = CalcMetal(nDirVS, lightmap, baseColor);
            float3 diffuse = baseColor * ramp;

            // lightmap.r 高值留给金属，漫反射侧剔除
            diffuse *= step(lightmap.r, 0.9);

            float3 rim = CalcRimLight(NdotV, baseColor);
            return diffuse + metal + specular + rim;
        }

        // ---------------------------------------------------------------------
        // 脸部着色：水平面 SDF 阴影（左右翻转采样）+ Ramp
        // ---------------------------------------------------------------------
        float3 ShadeFace(float3 lDirWS, float3 baseColor, float2 uv)
        {
            float sdfL = SAMPLE_TEXTURE2D(_lightmap, sampler_lightmap, uv).r;
            float sdfR = SAMPLE_TEXTURE2D(_lightmap, sampler_lightmap, float2(1.0 - uv.x, uv.y)).r;

            // 角色局部朝向：前 / 左 / 右（世界空间 XZ 平面）
            float3 up = float3(0.0, 1.0, 0.0);
            float3 front = unity_ObjectToWorld._13_23_33;
            float3 left = cross(front, up);
            float3 right = -left;

            float frontL = dot(normalize(front.xz), normalize(lDirWS.xz));
            float leftL = dot(normalize(left.xz), normalize(lDirWS.xz));
            float rightL = dot(normalize(right.xz), normalize(lDirWS.xz));

            // 脸朝向光时，用 SDF 阈值得到硬边面部阴影
            float lightAttenuation = (frontL > 0.0) * min((sdfL > leftL), 1.0 - (sdfR < rightL));

            float rampSampling = (_dayAndNight < 0.5) ? 0.5 : 0.0;
            float rampV = _lightmapA4 * -0.1 + 1.05 - rampSampling;
            float3 rampColor = SAMPLE_TEXTURE2D(_ramp, sampler_ramp, float2(lightAttenuation, rampV)).rgb;

            return lerp(baseColor * rampColor, baseColor, lightAttenuation);
        }

        // ---------------------------------------------------------------------
        // diffuse.a 用途：1 = Alpha Clip，2 = 自发光叠加
        // ---------------------------------------------------------------------
        void ApplyDiffuseAlpha(inout float3 col, float3 baseColor, float diffuseA)
        {
            if (_diffuseA > 1.5)
            {
                col += CalcEmission(baseColor, diffuseA);
            }
            else if (_diffuseA > 0.5)
            {
                diffuseA = smoothstep(0.05, 0.7, diffuseA);
                clip(diffuseA - _Cutoff);
            }
        }
        ENDHLSL

        // =====================================================================
        // Pass 1：正面（UV0）— 身体 / 脸部主着色
        // LightMode 必须是 URP 会绘制的标签，否则整材质不可见
        // =====================================================================
        Pass
        {
            Name "GenshinForward"
            Tags { "LightMode" = "UniversalForward" }

            Cull Back
            ZWrite On
            ZTest LEqual

            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex Vert
            #pragma fragment Frag

            // --- 顶点输入 ---
            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv0 : TEXCOORD0;
                float3 normalOS : NORMAL;
                float4 tangentOS : TANGENT;
            };

            // --- 顶点 → 片元：TBN + 世界坐标打包到三行矩阵 ---
            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv0 : TEXCOORD0;
                float4 TtoW0 : TEXCOORD1;
                float4 TtoW1 : TEXCOORD2;
                float4 TtoW2 : TEXCOORD3;
            };

            Varyings Vert(Attributes v)
            {
                Varyings o;
                o.positionCS = TransformObjectToHClip(v.positionOS.xyz);
                o.uv0 = v.uv0;

                float3 nDirWS = TransformObjectToWorldNormal(v.normalOS);
                float3 tDirWS = TransformObjectToWorldDir(v.tangentOS.xyz);
                float3 bDirWS = cross(nDirWS, tDirWS) * v.tangentOS.w * GetOddNegativeScale();
                float3 posWS = TransformObjectToWorld(v.positionOS.xyz);

                o.TtoW0 = float4(tDirWS.x, bDirWS.x, nDirWS.x, posWS.x);
                o.TtoW1 = float4(tDirWS.y, bDirWS.y, nDirWS.y, posWS.y);
                o.TtoW2 = float4(tDirWS.z, bDirWS.z, nDirWS.z, posWS.z);
                return o;
            }

            half4 Frag(Varyings i) : SV_Target
            {
                // --- 贴图采样 ---
                float4 diffuseSample = SAMPLE_TEXTURE2D(_diffuse, sampler_diffuse, i.uv0);
                float3 baseColor = diffuseSample.rgb;
                float diffuseA = diffuseSample.a;
                float4 lightmap = SAMPLE_TEXTURE2D(_lightmap, sampler_lightmap, i.uv0);

                // --- 法线：切线空间 → 世界空间 ---
                float3 nDirTS = UnpackNormal(SAMPLE_TEXTURE2D(_bumpMap, sampler_bumpMap, i.uv0));
                nDirTS.xy *= _bumpScale;
                nDirTS.z = sqrt(1.0 - saturate(dot(nDirTS.xy, nDirTS.xy)));

                float3 posWS = float3(i.TtoW0.w, i.TtoW1.w, i.TtoW2.w);
                float3 nDirWS = normalize(float3(
                    dot(i.TtoW0.xyz, nDirTS),
                    dot(i.TtoW1.xyz, nDirTS),
                    dot(i.TtoW2.xyz, nDirTS)));

                // --- 光照向量 ---
                Light mainLight = GetMainLight();
                float3 lDirWS = normalize(mainLight.direction);
                float3 vDirWS = normalize(GetCameraPositionWS() - posWS);
                float3 nDirVS = normalize(mul((float3x3)UNITY_MATRIX_V, nDirWS));
                float3 hDirWS = normalize(vDirWS + lDirWS);

                float NdotL = dot(nDirWS, lDirWS);
                float NdotH = dot(nDirWS, hDirWS);
                float NdotV = saturate(dot(nDirWS, vDirWS));

                // --- 身体 or 脸部 ---
                float3 col = 0.0;
                if (_genshinShader < 0.5)
                    col = ShadeBody(NdotL, NdotH, NdotV, lightmap, baseColor, nDirVS);
                else
                    col = ShadeFace(lDirWS, baseColor, i.uv0);

                ApplyDiffuseAlpha(col, baseColor, diffuseA);
                return half4(col, 1.0);
            }
            ENDHLSL
        }

        // =====================================================================
        // Pass 2：背面（UV1）— 衣服内里等双面区域
        // 使用 UniversalForwardOnly，URP Forward 路径会一并绘制
        // =====================================================================
        Pass
        {
            Name "GenshinBackface"
            Tags { "LightMode" = "UniversalForwardOnly" }

            Cull Front
            ZWrite On
            ZTest LEqual

            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex Vert
            #pragma fragment Frag

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv1 : TEXCOORD1;
                float3 normalOS : NORMAL;
                float4 tangentOS : TANGENT;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv1 : TEXCOORD0;
                float4 TtoW0 : TEXCOORD1;
                float4 TtoW1 : TEXCOORD2;
                float4 TtoW2 : TEXCOORD3;
            };

            Varyings Vert(Attributes v)
            {
                Varyings o;
                o.positionCS = TransformObjectToHClip(v.positionOS.xyz);
                o.uv1 = v.uv1;

                float3 nDirWS = TransformObjectToWorldNormal(v.normalOS);
                float3 tDirWS = TransformObjectToWorldDir(v.tangentOS.xyz);
                float3 bDirWS = cross(nDirWS, tDirWS) * v.tangentOS.w * GetOddNegativeScale();
                float3 posWS = TransformObjectToWorld(v.positionOS.xyz);

                o.TtoW0 = float4(tDirWS.x, bDirWS.x, nDirWS.x, posWS.x);
                o.TtoW1 = float4(tDirWS.y, bDirWS.y, nDirWS.y, posWS.y);
                o.TtoW2 = float4(tDirWS.z, bDirWS.z, nDirWS.z, posWS.z);
                return o;
            }

            half4 Frag(Varyings i) : SV_Target
            {
                float4 diffuseSample = SAMPLE_TEXTURE2D(_diffuse, sampler_diffuse, i.uv1);
                float3 baseColor = diffuseSample.rgb;
                float diffuseA = diffuseSample.a;
                float4 lightmap = SAMPLE_TEXTURE2D(_lightmap, sampler_lightmap, i.uv1);

                float3 nDirTS = UnpackNormal(SAMPLE_TEXTURE2D(_bumpMap, sampler_bumpMap, i.uv1));
                nDirTS.xy *= _bumpScale;
                nDirTS.z = sqrt(1.0 - saturate(dot(nDirTS.xy, nDirTS.xy)));

                float3 posWS = float3(i.TtoW0.w, i.TtoW1.w, i.TtoW2.w);
                float3 nDirWS = normalize(float3(
                    dot(i.TtoW0.xyz, nDirTS),
                    dot(i.TtoW1.xyz, nDirTS),
                    dot(i.TtoW2.xyz, nDirTS)));

                Light mainLight = GetMainLight();
                float3 lDirWS = normalize(mainLight.direction);
                float3 vDirWS = normalize(GetCameraPositionWS() - posWS);
                float3 nDirVS = normalize(mul((float3x3)UNITY_MATRIX_V, nDirWS));
                float3 hDirWS = normalize(vDirWS + lDirWS);

                float NdotL = dot(nDirWS, lDirWS);
                float NdotH = dot(nDirWS, hDirWS);
                float NdotV = saturate(dot(nDirWS, vDirWS));

                // 背面只渲染身体，不做脸部 SDF
                float3 col = 0.0;
                if (_genshinShader < 0.5)
                    col = ShadeBody(NdotL, NdotH, NdotV, lightmap, baseColor, nDirVS);

                ApplyDiffuseAlpha(col, baseColor, diffuseA);
                return half4(col, 1.0);
            }
            ENDHLSL
        }

        // =====================================================================
        // Pass 3：描边 — 反向外壳沿切线挤出（屏幕空间等比）
        // SRPDefaultUnlit 会被 URP Opaque 绘制列表包含
        // =====================================================================
        Pass
        {
            Name "GenshinOutline"
            Tags { "LightMode" = "SRPDefaultUnlit" }

            Cull Front
            ZWrite On
            ZTest LEqual

            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex Vert
            #pragma fragment Frag

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float4 tangentOS : TANGENT;
                float2 uv0 : TEXCOORD0;
                float4 color : COLOR;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv0 : TEXCOORD0;
            };

            Varyings Vert(Attributes v)
            {
                Varyings o;
                float4 posCS = TransformObjectToHClip(v.positionOS.xyz);
                o.uv0 = v.uv0;

                // 平滑法线存在切线里时，用切线方向做挤出更稳
                float3 viewNormal = mul((float3x3)UNITY_MATRIX_IT_MV, v.tangentOS.xyz);
                float3 clipNormal = mul((float3x3)UNITY_MATRIX_P, viewNormal);
                float3 ndcNormal = normalize(clipNormal) * posCS.w;

                // 按屏幕宽高比校正，避免描边横向被拉扁
                float4 nearUpperRight = mul(unity_CameraInvProjection, float4(1.0, 1.0, UNITY_NEAR_CLIP_VALUE, 1.0));
                float aspect = abs(nearUpperRight.y / nearUpperRight.x);
                ndcNormal.x *= aspect;

                // 顶点色 a 控制局部描边粗细
                posCS.xy += 0.01 * _outline * ndcNormal.xy * v.color.a;
                o.positionCS = posCS;
                return o;
            }

            half4 Frag(Varyings i) : SV_Target
            {
                float4 lightmap = SAMPLE_TEXTURE2D(_lightmap, sampler_lightmap, i.uv0);
                float diffuseA = SAMPLE_TEXTURE2D(_diffuse, sampler_diffuse, i.uv0).a;

                // 按 lightmap.a 材质分区选择描边色
                float lightmapA2 = step(0.25, lightmap.a);
                float lightmapA3 = step(0.45, lightmap.a);
                float lightmapA4 = step(0.65, lightmap.a);
                float lightmapA5 = step(0.95, lightmap.a);

                float3 outlineColor = _outlineColor0;
                outlineColor = lerp(outlineColor, _outlineColor1, lightmapA2);
                outlineColor = lerp(outlineColor, _outlineColor2, lightmapA3);
                outlineColor = lerp(outlineColor, _outlineColor3, lightmapA4);
                outlineColor = lerp(outlineColor, _outlineColor4, lightmapA5);

                if (_diffuseA > 0.5 && _diffuseA < 1.5)
                {
                    diffuseA = smoothstep(0.05, 0.7, diffuseA);
                    clip(diffuseA - _Cutoff);
                }

                return half4(outlineColor, 1.0);
            }
            ENDHLSL
        }

        // --- 阴影投射：复用 URP Lit 的 ShadowCaster ---
        UsePass "Universal Render Pipeline/Lit/ShadowCaster"
    }

    FallBack Off
}
