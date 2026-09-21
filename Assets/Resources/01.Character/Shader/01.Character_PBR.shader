Shader "ZZY/01.Character/PBR"
{
    Properties
    {
        [Space(20.0)]
        // 是否按脸部材质着色
        [Toggle] _genshinShader("是否是脸部", Float) = 0.0

        [Space(15.0)]
        // 漫反射颜色贴图
        [NoScaleOffset] _diffuse("Diffuse", 2D) = "white" {}
        // 边缘光的衰减范围
        _fresnel("边缘光范围", Range(0.0, 10.0)) = 1.7
        // 边缘光强度
        _edgeLight("边缘光强度", Range(0.0, 1.0)) = 0.02

        [Space(8.0)]
        // 透明度通道用途，一为裁剪，二为自发光
        _diffuseA("Alpha(1透明, 2自发光)", Range(0.0, 2.0)) = 0.0
        // 透明裁剪阈值
        _Cutoff("透明阈值", Range(0.0, 1.0)) = 1.0
        // 自发光颜色
        [HDR] _glow("自发光强度", Color) = (1.0, 1.0, 1.0, 1.0)
        // 发光闪烁速度
        _flicker("发光闪烁速度", Float) = 0.8

        [Space(30.0)]
        // 身体光照贴图，或脸部距离场
        [NoScaleOffset] _lightmap("Lightmap/FaceLightmap", 2D) = "white" {}
        // 亮面判定范围
        _bright("亮面范围", Float) = 0.99
        // 灰面过渡范围
        _grey("灰面范围", Float) = 1.14
        // 暗面偏移
        _dark("暗面范围", Float) = 0.5

        [Space(30.0)]
        // 法线贴图
        [NoScaleOffset] _bumpMap("Normalmap", 2D) = "bump" {}
        // 法线强度
        _bumpScale("法线强度", Float) = 1.0

        [Space(30.0)]
        // 阴影色带贴图
        [NoScaleOffset] _ramp("Shadow_Ramp", 2D) = "white" {}
        // 是否使用白天色带
        [Toggle] _dayAndNight("是否是白天", Float) = 0.0

        [Space(8.0)]
        // 第一档材质对应的色带行
        _lightmapA0("1.0_Ramp条数", Range(1, 5)) = 1
        // 第二档材质对应的色带行
        _lightmapA1("0.7_Ramp条数", Range(1, 5)) = 4
        // 第三档材质对应的色带行
        _lightmapA2("0.5_Ramp条数", Range(1, 5)) = 3
        // 第四档材质对应的色带行
        _lightmapA3("0.3_Ramp条数", Range(1, 5)) = 5
        // 第五档材质对应的色带行
        _lightmapA4("0.0_Ramp条数", Range(1, 5)) = 2

        [Space(30.0)]
        // 金属贴图
        [NoScaleOffset] _metalMap("MetalMap", 2D) = "white" {}
        // 高光范围
        _gloss("高光范围", Range(1, 256.0)) = 1
        // 高光强度
        _glossStrength("高光强度", Range(0.0, 1.0)) = 1
        // 金属反射颜色
        _metalMapColor("金属反射颜色", Color) = (1.0, 1.0, 1.0, 1.0)

        [Space(30.0)]
        // 描边粗细
        _outline("描边粗细", Range(0.0, 1.0)) = 0.4
        // 第一档描边颜色
        _outlineColor0("描边颜色1", Color) = (1.0, 0.0, 0.0, 0.0)
        // 第二档描边颜色
        _outlineColor1("描边颜色2", Color) = (0.0, 1.0, 0.0, 0.0)
        // 第三档描边颜色
        _outlineColor2("描边颜色3", Color) = (0.0, 0.0, 1.0, 0.0)
        // 第四档描边颜色
        _outlineColor3("描边颜色4", Color) = (1.0, 1.0, 0.0, 0.0)
        // 第五档描边颜色
        _outlineColor4("描边颜色5", Color) = (0.5, 0.0, 1.0, 0.0)

        [Header(Depth)]
        // 是否写入深度
        [Enum(Off, 0, On, 1)] _ZWrite ("ZWrite", Float) = 1
        // 深度比较方式
        [Enum(UnityEngine.Rendering.CompareFunction)] _ZTest ("ZTest", Float) = 4
    }

    SubShader
    {
        Tags
        {
            "RenderPipeline" = "UniversalPipeline"
            "RenderType" = "Opaque"
            "Queue" = "Geometry"
        }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

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

        TEXTURE2D(_diffuse);    SAMPLER(sampler_diffuse);
        TEXTURE2D(_lightmap);   SAMPLER(sampler_lightmap);
        TEXTURE2D(_bumpMap);    SAMPLER(sampler_bumpMap);
        TEXTURE2D(_ramp);       SAMPLER(sampler_ramp);
        TEXTURE2D(_metalMap);   SAMPLER(sampler_metalMap);

        // 按材质分区采样阴影色带
        float3 CalcShadowRamp(float4 lightmap, float NdotL)
        {
            // 光照贴图绿色通道压成软边遮罩
            lightmap.g = smoothstep(0.2, 0.3, lightmap.g);

            // 半兰伯特乘遮罩，并标出亮面
            float halfLambert = smoothstep(0.0, _grey, NdotL + _dark) * lightmap.g;
            float brightMask = step(_bright, halfLambert);

            // 夜晚把采样偏到色带下半张
            float rampSampling = (_dayAndNight < 0.5) ? 0.5 : 0.0;

            // 各材质分区对应的色带行
            float ramp0 = _lightmapA0 * -0.1 + 1.05 - rampSampling;
            float ramp1 = _lightmapA1 * -0.1 + 1.05 - rampSampling;
            float ramp2 = _lightmapA2 * -0.1 + 1.05 - rampSampling;
            float ramp3 = _lightmapA3 * -0.1 + 1.05 - rampSampling;
            float ramp4 = _lightmapA4 * -0.1 + 1.05 - rampSampling;

            // 用光照贴图透明度选出对应色带行
            float lightmapA2 = step(0.25, lightmap.a);
            float lightmapA3 = step(0.45, lightmap.a);
            float lightmapA4 = step(0.65, lightmap.a);
            float lightmapA5 = step(0.95, lightmap.a);

            float rampV = ramp0;
            rampV = lerp(rampV, ramp1, lightmapA2);
            rampV = lerp(rampV, ramp2, lightmapA3);
            rampV = lerp(rampV, ramp3, lightmapA4);
            rampV = lerp(rampV, ramp4, lightmapA5);

            // 采样色带，亮面直接用半兰伯特
            float3 ramp = SAMPLE_TEXTURE2D(_ramp, sampler_ramp, float2(halfLambert, rampV)).rgb;

            return lerp(ramp, halfLambert.xxx, brightMask);
        }

        // 亮面才保留的布林冯高光
        float3 CalcSpecular(float NdotL, float NdotH, float4 lightmap, float3 baseColor)
        {
            // 高光受光照贴图红蓝通道和底色控制
            float blinnPhong = pow(saturate(NdotH), _gloss);
            float3 specular = blinnPhong * lightmap.r * _glossStrength;
            specular *= lightmap.b;
            specular *= baseColor;

            // 只留在亮面区域
            lightmap.g = smoothstep(0.2, 0.3, lightmap.g);
            float halfLambert = smoothstep(0.0, _grey, NdotL + _dark) * lightmap.g;
            float brightMask = step(_bright, halfLambert);

            return specular * brightMask;
        }

        // 用视角法线采样金属反射
        float3 CalcMetal(float3 nDirVS, float4 lightmap, float3 baseColor)
        {
            // 光照贴图红色高值区才是金属
            float metalMask = 1.0 - step(lightmap.r, 0.9);
            float metalMap = SAMPLE_TEXTURE2D(_metalMap, sampler_metalMap, nDirVS.xy * 0.5 + 0.5).r;
            float3 metalColor = lerp(_metalMapColor, baseColor, metalMap);
            return lerp(0.0, metalColor, metalMask);
        }

        // 阈值化菲涅尔，形成轮廓亮边
        float3 CalcRimLight(float NdotV, float3 baseColor)
        {
            float fresnel = pow(saturate(1.0 - NdotV), _fresnel);
            return step(0.5, fresnel) * _edgeLight * baseColor;
        }

        // 漫反射透明度做遮罩，并按时间闪烁
        float3 CalcEmission(float3 baseColor, float diffuseA)
        {
            diffuseA = smoothstep(0.0, 1.0, diffuseA);
            float flicker = sin(_Time.w * _flicker) * 0.5 + 0.5;
            return lerp(0.0, baseColor * (flicker * _glow.rgb), diffuseA);
        }

        // 身体的色带漫反射、金属、高光和边缘光
        float3 ShadeBody(float NdotL, float NdotH, float NdotV, float4 lightmap, float3 baseColor, float3 nDirVS)
        {
            float3 ramp = CalcShadowRamp(lightmap, NdotL);
            float3 specular = CalcSpecular(NdotL, NdotH, lightmap, baseColor);
            float3 metal = CalcMetal(nDirVS, lightmap, baseColor);
            float3 diffuse = baseColor * ramp;

            // 金属区域去掉漫反射
            diffuse *= step(lightmap.r, 0.9);

            float3 rim = CalcRimLight(NdotV, baseColor);
            return diffuse + metal + specular + rim;
        }

        // 脸部距离场硬边阴影
        float3 ShadeFace(float3 lDirWS, float3 baseColor, float2 uv)
        {
            // 采样左右翻转的脸部距离场
            float sdfL = SAMPLE_TEXTURE2D(_lightmap, sampler_lightmap, uv).r;
            float sdfR = SAMPLE_TEXTURE2D(_lightmap, sampler_lightmap, float2(1.0 - uv.x, uv.y)).r;

            // 用角色前方和左右方向判断光照
            float3 up = float3(0.0, 1.0, 0.0);
            float3 front = unity_ObjectToWorld._13_23_33;
            float3 left = cross(front, up);
            float3 right = -left;

            float frontL = dot(normalize(front.xz), normalize(lDirWS.xz));
            float leftL = dot(normalize(left.xz), normalize(lDirWS.xz));
            float rightL = dot(normalize(right.xz), normalize(lDirWS.xz));

            // 朝向光源时切出硬边阴影
            float lightAttenuation = (frontL > 0.0) * min((sdfL > leftL), 1.0 - (sdfR < rightL));

            // 按昼夜取色带并与底色混合
            float rampSampling = (_dayAndNight < 0.5) ? 0.5 : 0.0;
            float rampV = _lightmapA4 * -0.1 + 1.05 - rampSampling;
            float3 rampColor = SAMPLE_TEXTURE2D(_ramp, sampler_ramp, float2(lightAttenuation, rampV)).rgb;

            return lerp(baseColor * rampColor, baseColor, lightAttenuation);
        }

        // 按透明度通道做裁剪或叠加自发光
        void ApplyDiffuseAlpha(inout float3 col, float3 baseColor, float diffuseA)
        {
            // 用途为自发光时叠上闪烁
            if (_diffuseA > 1.5)
            {
                col += CalcEmission(baseColor, diffuseA);
            }
            // 用途为裁剪时按阈值剔除
            else if (_diffuseA > 0.5)
            {
                diffuseA = smoothstep(0.05, 0.7, diffuseA);
                clip(diffuseA - _Cutoff);
            }
        }
        ENDHLSL

        Pass
        {
            Name "GenshinForward"
            Tags { "LightMode" = "UniversalForward" }

            Cull Back
            ZWrite [_ZWrite]
            ZTest [_ZTest]

            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex Vert
            #pragma fragment Frag

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv0 : TEXCOORD0;
                float3 normalOS : NORMAL;
                float4 tangentOS : TANGENT;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv0 : TEXCOORD0;
                float4 TtoW0 : TEXCOORD1;
                float4 TtoW1 : TEXCOORD2;
                float4 TtoW2 : TEXCOORD3;
            };

            // 正面顶点：裁剪空间位置和切线基
            Varyings Vert(Attributes v)
            {
                Varyings o;
                // 变换到裁剪空间并传递纹理坐标
                o.positionCS = TransformObjectToHClip(v.positionOS.xyz);
                o.uv0 = v.uv0;

                // 构建切线到世界的基向量，并打包世界坐标
                float3 nDirWS = TransformObjectToWorldNormal(v.normalOS);
                float3 tDirWS = TransformObjectToWorldDir(v.tangentOS.xyz);
                float3 bDirWS = cross(nDirWS, tDirWS) * v.tangentOS.w * GetOddNegativeScale();
                float3 posWS = TransformObjectToWorld(v.positionOS.xyz);

                o.TtoW0 = float4(tDirWS.x, bDirWS.x, nDirWS.x, posWS.x);
                o.TtoW1 = float4(tDirWS.y, bDirWS.y, nDirWS.y, posWS.y);
                o.TtoW2 = float4(tDirWS.z, bDirWS.z, nDirWS.z, posWS.z);
                return o;
            }

            // 正面片元：身体或脸部着色
            half4 Frag(Varyings i) : SV_Target
            {
                // 采样漫反射和光照贴图
                float4 diffuseSample = SAMPLE_TEXTURE2D(_diffuse, sampler_diffuse, i.uv0);
                float3 baseColor = diffuseSample.rgb;
                float diffuseA = diffuseSample.a;
                float4 lightmap = SAMPLE_TEXTURE2D(_lightmap, sampler_lightmap, i.uv0);

                // 把切线空间法线转到世界空间
                float3 nDirTS = UnpackNormal(SAMPLE_TEXTURE2D(_bumpMap, sampler_bumpMap, i.uv0));
                nDirTS.xy *= _bumpScale;
                nDirTS.z = sqrt(1.0 - saturate(dot(nDirTS.xy, nDirTS.xy)));

                float3 posWS = float3(i.TtoW0.w, i.TtoW1.w, i.TtoW2.w);
                float3 nDirWS = normalize(float3(
                    dot(i.TtoW0.xyz, nDirTS),
                    dot(i.TtoW1.xyz, nDirTS),
                    dot(i.TtoW2.xyz, nDirTS)));

                // 计算主光、视线和半角方向
                Light mainLight = GetMainLight();
                float3 lDirWS = normalize(mainLight.direction);
                float3 vDirWS = normalize(GetCameraPositionWS() - posWS);
                float3 nDirVS = normalize(mul((float3x3)UNITY_MATRIX_V, nDirWS));
                float3 hDirWS = normalize(vDirWS + lDirWS);

                float NdotL = dot(nDirWS, lDirWS);
                float NdotH = dot(nDirWS, hDirWS);
                float NdotV = saturate(dot(nDirWS, vDirWS));

                // 按开关选择身体或脸部着色
                float3 col = 0.0;
                if (_genshinShader < 0.5)
                    col = ShadeBody(NdotL, NdotH, NdotV, lightmap, baseColor, nDirVS);
                else
                    col = ShadeFace(lDirWS, baseColor, i.uv0);

                // 处理裁剪或自发光
                ApplyDiffuseAlpha(col, baseColor, diffuseA);
                return half4(col, 1.0);
            }
            ENDHLSL
        }

        Pass
        {
            Name "GenshinBackface"
            Tags { "LightMode" = "UniversalForwardOnly" }

            Cull Front
            ZWrite [_ZWrite]
            ZTest [_ZTest]

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

            // 背面顶点：使用第二套纹理坐标
            Varyings Vert(Attributes v)
            {
                Varyings o;
                // 变换到裁剪空间并传递第二套纹理坐标
                o.positionCS = TransformObjectToHClip(v.positionOS.xyz);
                o.uv1 = v.uv1;

                // 构建切线到世界的基向量，并打包世界坐标
                float3 nDirWS = TransformObjectToWorldNormal(v.normalOS);
                float3 tDirWS = TransformObjectToWorldDir(v.tangentOS.xyz);
                float3 bDirWS = cross(nDirWS, tDirWS) * v.tangentOS.w * GetOddNegativeScale();
                float3 posWS = TransformObjectToWorld(v.positionOS.xyz);

                o.TtoW0 = float4(tDirWS.x, bDirWS.x, nDirWS.x, posWS.x);
                o.TtoW1 = float4(tDirWS.y, bDirWS.y, nDirWS.y, posWS.y);
                o.TtoW2 = float4(tDirWS.z, bDirWS.z, nDirWS.z, posWS.z);
                return o;
            }

            // 背面片元：只做身体着色
            half4 Frag(Varyings i) : SV_Target
            {
                // 用第二套纹理坐标采样漫反射和光照贴图
                float4 diffuseSample = SAMPLE_TEXTURE2D(_diffuse, sampler_diffuse, i.uv1);
                float3 baseColor = diffuseSample.rgb;
                float diffuseA = diffuseSample.a;
                float4 lightmap = SAMPLE_TEXTURE2D(_lightmap, sampler_lightmap, i.uv1);

                // 把切线空间法线转到世界空间
                float3 nDirTS = UnpackNormal(SAMPLE_TEXTURE2D(_bumpMap, sampler_bumpMap, i.uv1));
                nDirTS.xy *= _bumpScale;
                nDirTS.z = sqrt(1.0 - saturate(dot(nDirTS.xy, nDirTS.xy)));

                float3 posWS = float3(i.TtoW0.w, i.TtoW1.w, i.TtoW2.w);
                float3 nDirWS = normalize(float3(
                    dot(i.TtoW0.xyz, nDirTS),
                    dot(i.TtoW1.xyz, nDirTS),
                    dot(i.TtoW2.xyz, nDirTS)));

                // 计算主光、视线和半角方向
                Light mainLight = GetMainLight();
                float3 lDirWS = normalize(mainLight.direction);
                float3 vDirWS = normalize(GetCameraPositionWS() - posWS);
                float3 nDirVS = normalize(mul((float3x3)UNITY_MATRIX_V, nDirWS));
                float3 hDirWS = normalize(vDirWS + lDirWS);

                float NdotL = dot(nDirWS, lDirWS);
                float NdotH = dot(nDirWS, hDirWS);
                float NdotV = saturate(dot(nDirWS, vDirWS));

                // 背面只做身体着色
                float3 col = 0.0;
                if (_genshinShader < 0.5)
                    col = ShadeBody(NdotL, NdotH, NdotV, lightmap, baseColor, nDirVS);

                // 处理裁剪或自发光
                ApplyDiffuseAlpha(col, baseColor, diffuseA);
                return half4(col, 1.0);
            }
            ENDHLSL
        }

        Pass
        {
            Name "GenshinOutline"
            Tags { "LightMode" = "SRPDefaultUnlit" }

            Cull Front
            ZWrite [_ZWrite]
            ZTest [_ZTest]

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

            // 沿切线把外壳挤出到裁剪空间
            Varyings Vert(Attributes v)
            {
                Varyings o;
                float4 posCS = TransformObjectToHClip(v.positionOS.xyz);
                o.uv0 = v.uv0;

                // 用切线方向把法线变到裁剪空间
                float3 viewNormal = mul((float3x3)UNITY_MATRIX_IT_MV, v.tangentOS.xyz);
                float3 clipNormal = mul((float3x3)UNITY_MATRIX_P, viewNormal);
                float3 ndcNormal = normalize(clipNormal) * posCS.w;

                // 按屏幕宽高比校正，避免横向被拉扁
                float4 nearUpperRight = mul(unity_CameraInvProjection, float4(1.0, 1.0, UNITY_NEAR_CLIP_VALUE, 1.0));
                float aspect = abs(nearUpperRight.y / nearUpperRight.x);
                ndcNormal.x *= aspect;

                // 顶点色透明度控制局部描边粗细
                posCS.xy += 0.01 * _outline * ndcNormal.xy * v.color.a;
                o.positionCS = posCS;
                return o;
            }

            // 按材质分区给描边上色
            half4 Frag(Varyings i) : SV_Target
            {
                // 采样材质分区和漫反射透明度
                float4 lightmap = SAMPLE_TEXTURE2D(_lightmap, sampler_lightmap, i.uv0);
                float diffuseA = SAMPLE_TEXTURE2D(_diffuse, sampler_diffuse, i.uv0).a;

                // 按光照贴图透明度混合五档描边颜色
                float lightmapA2 = step(0.25, lightmap.a);
                float lightmapA3 = step(0.45, lightmap.a);
                float lightmapA4 = step(0.65, lightmap.a);
                float lightmapA5 = step(0.95, lightmap.a);

                float3 outlineColor = _outlineColor0;
                outlineColor = lerp(outlineColor, _outlineColor1, lightmapA2);
                outlineColor = lerp(outlineColor, _outlineColor2, lightmapA3);
                outlineColor = lerp(outlineColor, _outlineColor3, lightmapA4);
                outlineColor = lerp(outlineColor, _outlineColor4, lightmapA5);

                // 半透明用途时裁剪描边
                if (_diffuseA > 0.5 && _diffuseA < 1.5)
                {
                    diffuseA = smoothstep(0.05, 0.7, diffuseA);
                    clip(diffuseA - _Cutoff);
                }

                return half4(outlineColor, 1.0);
            }
            ENDHLSL
        }

        UsePass "Universal Render Pipeline/Lit/ShadowCaster"
    }

    FallBack Off
}
