Shader "ZZY/03.water/ProceduralSkybox" {
Properties {
    // 太阳圆盘质量
    [KeywordEnum(None, Simple, High Quality)] _SunDisk ("Sun", Int) = 2
    // 太阳尺寸
    _SunSize ("Sun Size", Range(0,1)) = 0.04
    // 太阳边缘收敛
    _SunSizeConvergence("Sun Size Convergence", Range(1,10)) = 5

    // 大气厚度
    _AtmosphereThickness ("Atmosphere Thickness", Range(0,5)) = 1.0
    // 天空染色
    _SkyTint ("Sky Tint", Color) = (.5, .5, .5, 1)
    // 地面颜色
    _GroundColor ("Ground", Color) = (.369, .349, .341, 1)

    // 曝光
    _Exposure("Exposure", Range(0, 8)) = 1.3
    [Header(Depth)]
    // 深度写入，默认关闭
    [Enum(Off, 0, On, 1)] _ZWrite ("ZWrite", Float) = 0
    // 深度测试，默认小于等于
    [Enum(UnityEngine.Rendering.CompareFunction)] _ZTest ("ZTest", Float) = 4
}

SubShader {
    Tags { "Queue"="Background" "RenderType"="Background" "PreviewType"="Skybox" }
    Cull Off
    ZWrite [_ZWrite]
    ZTest [_ZTest]

    Pass {

        HLSLPROGRAM
        #pragma vertex vert
        #pragma fragment frag

        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
        #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Color.hlsl"

        #pragma multi_compile_local _SUNDISK_NONE _SUNDISK_SIMPLE _SUNDISK_HIGH_QUALITY

        uniform half _Exposure;
        uniform half3 _GroundColor;
        uniform half _SunSize;
        uniform half _SunSizeConvergence;
        uniform half3 _SkyTint;
        uniform half _AtmosphereThickness;

    #if defined(UNITY_COLORSPACE_GAMMA)
        #define GAMMA 2
        #define COLOR_2_GAMMA(color) color
        #define COLOR_2_LINEAR(color) color*color
        #define LINEAR_2_OUTPUT(color) sqrt(color)
    #else
        #define GAMMA 2.2
        #define COLOR_2_GAMMA(color) pow(color,1.0/GAMMA)
        #define COLOR_2_LINEAR(color) color
        #define LINEAR_2_LINEAR(color) color
    #endif

        static const float3 kDefaultScatteringWavelength = float3(.65, .57, .475);
        static const float3 kVariableRangeForScatteringWavelength = float3(.15, .15, .15);

        #define OUTER_RADIUS 1.025
        static const float kOuterRadius = OUTER_RADIUS;
        static const float kOuterRadius2 = OUTER_RADIUS*OUTER_RADIUS;
        static const float kInnerRadius = 1.0;
        static const float kInnerRadius2 = 1.0;

        static const float kCameraHeight = 0.0001;

        #define kRAYLEIGH (lerp(0.0, 0.0025, pow(abs(_AtmosphereThickness),2.5)))
        #define kMIE 0.0010
        #define kSUN_BRIGHTNESS 20.0

        #define kMAX_SCATTER 50.0

        static const half kHDSundiskIntensityFactor = 15.0;
        static const half kSimpleSundiskIntensityFactor = 27.0;

        static const half kSunScale = 400.0 * kSUN_BRIGHTNESS;
        static const float kKmESun = kMIE * kSUN_BRIGHTNESS;
        static const float kKm4PI = kMIE * 4.0 * 3.14159265;
        static const float kScale = 1.0 / (OUTER_RADIUS - 1.0);
        static const float kScaleDepth = 0.25;
        static const float kScaleOverScaleDepth = (1.0 / (OUTER_RADIUS - 1.0)) / 0.25;
        static const float kSamples = 2.0;

        #define MIE_G (-0.990)
        #define MIE_G2 0.9801

        #define SKY_GROUND_THRESHOLD 0.02

        #define SKYBOX_SUNDISK_NONE 0
        #define SKYBOX_SUNDISK_SIMPLE 1
        #define SKYBOX_SUNDISK_HQ 2

    #ifndef SKYBOX_SUNDISK
        #if defined(_SUNDISK_NONE)
            #define SKYBOX_SUNDISK SKYBOX_SUNDISK_NONE
        #elif defined(_SUNDISK_SIMPLE)
            #define SKYBOX_SUNDISK SKYBOX_SUNDISK_SIMPLE
        #else
            #define SKYBOX_SUNDISK SKYBOX_SUNDISK_HQ
        #endif
    #endif

    #ifndef SKYBOX_COLOR_IN_TARGET_COLOR_SPACE
        #if defined(SHADER_API_MOBILE)
            #define SKYBOX_COLOR_IN_TARGET_COLOR_SPACE 1
        #else
            #define SKYBOX_COLOR_IN_TARGET_COLOR_SPACE 0
        #endif
    #endif

        // 瑞利相位，视线越背对太阳天空越亮
        half getRayleighPhase(half eyeCos2)
        {
            return 0.75 + 0.75*eyeCos2;
        }
        // 由光线和视线夹角计算瑞利相位
        half getRayleighPhase(half3 light, half3 ray)
        {
            half eyeCos = dot(light, ray);
            return getRayleighPhase(eyeCos * eyeCos);
        }


        struct appdata_t
        {
            float4 vertex : POSITION;
            UNITY_VERTEX_INPUT_INSTANCE_ID
        };

        struct v2f
        {
            float4  pos             : SV_POSITION;

        #if SKYBOX_SUNDISK == SKYBOX_SUNDISK_HQ
            float3  vertex          : TEXCOORD0;
        #elif SKYBOX_SUNDISK == SKYBOX_SUNDISK_SIMPLE
            half3   rayDir          : TEXCOORD0;
        #else
            half    skyGroundFactor : TEXCOORD0;
        #endif

            half3   groundColor     : TEXCOORD1;
            half3   skyColor        : TEXCOORD2;

        #if SKYBOX_SUNDISK != SKYBOX_SUNDISK_NONE
            half3   sunColor        : TEXCOORD3;
        #endif

            UNITY_VERTEX_OUTPUT_STEREO
        };


        // 大气密度随入射角的经验缩放
        float scale(float inCos)
        {
            float x = 1.0 - inCos;
            return 0.25 * exp(-0.00287 + x*(0.459 + x*(3.83 + x*(-6.80 + x*5.25))));
        }

        // 顶点：沿视线积分大气，得到天空色、地面色和太阳色
        v2f vert (appdata_t v)
        {
            v2f OUT;
            UNITY_SETUP_INSTANCE_ID(v);
            UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(OUT);

            VertexPositionInputs vertexPositions = GetVertexPositionInputs(v.vertex.xyz);
            OUT.pos = vertexPositions.positionCS;

            // 天空染色决定三通道散射波长
            float3 kSkyTintInGammaSpace = COLOR_2_GAMMA(abs(_SkyTint));
            float3 kScatteringWavelength = lerp (
                kDefaultScatteringWavelength-kVariableRangeForScatteringWavelength,
                kDefaultScatteringWavelength+kVariableRangeForScatteringWavelength,
                half3(1,1,1) - kSkyTintInGammaSpace);
            float3 kInvWavelength = 1.0 / pow(kScatteringWavelength, 4);

            float kKrESun = kRAYLEIGH * kSUN_BRIGHTNESS;
            float kKr4PI = kRAYLEIGH * 4.0 * 3.14159265;

            float3 cameraPos = float3(0,kInnerRadius + kCameraHeight,0);

            // 从大气球心射向顶点
            float3 eyeRay = normalize(mul((float3x3)unity_ObjectToWorld, v.vertex.xyz));

            float far = 0.0;
            half3 cIn, cOut;

            Light mainLight = GetMainLight();

            if(eyeRay.y >= 0.0)
            {
                // 天空射线与外层大气球求交
                far = sqrt(kOuterRadius2 + kInnerRadius2 * eyeRay.y * eyeRay.y - kInnerRadius2) - kInnerRadius * eyeRay.y;

                float3 pos = cameraPos + far * eyeRay;

                // 起点高度和散射偏移
                float height = kInnerRadius + kCameraHeight;
                float depth = exp(kScaleOverScaleDepth * (-kCameraHeight));
                float startAngle = dot(eyeRay, cameraPos) / height;
                float startOffset = depth*scale(startAngle);


                float sampleLength = far / kSamples;
                float scaledLength = sampleLength * kScale;
                float3 sampleRay = eyeRay * sampleLength;
                float3 samplePoint = cameraPos + sampleRay * 0.5;

                // 沿射线采两次，累加瑞利和米氏衰减
                float3 frontColor = float3(0.0, 0.0, 0.0);
                {
                    float height = length(samplePoint);
                    float depth = exp(kScaleOverScaleDepth * (kInnerRadius - height));
                    float lightAngle = dot(mainLight.direction, samplePoint) / height;
                    float cameraAngle = dot(eyeRay, samplePoint) / height;
                    float scatter = (startOffset + depth*(scale(lightAngle) - scale(cameraAngle)));
                    float3 attenuate = exp(-clamp(scatter, 0.0, kMAX_SCATTER) * (kInvWavelength * kKr4PI + kKm4PI));

                    frontColor += attenuate * (depth * scaledLength);
                    samplePoint += sampleRay;
                }
                {
                    float height = length(samplePoint);
                    float depth = exp(kScaleOverScaleDepth * (kInnerRadius - height));
                    float lightAngle = dot(mainLight.direction, samplePoint) / height;
                    float cameraAngle = dot(eyeRay, samplePoint) / height;
                    float scatter = (startOffset + depth*(scale(lightAngle) - scale(cameraAngle)));
                    float3 attenuate = exp(-clamp(scatter, 0.0, kMAX_SCATTER) * (kInvWavelength * kKr4PI + kKm4PI));

                    frontColor += attenuate * (depth * scaledLength);
                    samplePoint += sampleRay;
                }



                // 瑞利项是天空色，米氏项是太阳色
                cIn = frontColor * (kInvWavelength * kKrESun);
                cOut = frontColor * kKmESun;
            }
            else
            {
                // 地面射线打到内球，路径更短
                far = (-kCameraHeight) / (min(-0.001, eyeRay.y));

                float3 pos = cameraPos + far * eyeRay;

                // 地面射线的起点和散射偏移
                float depth = exp((-kCameraHeight) * (1.0/kScaleDepth));
                float cameraAngle = dot(-eyeRay, pos);
                float lightAngle = dot(mainLight.direction, pos);
                float cameraScale = scale(cameraAngle);
                float lightScale = scale(lightAngle);
                float cameraOffset = depth*cameraScale;
                float temp = (lightScale + cameraScale);

                float sampleLength = far / kSamples;
                float scaledLength = sampleLength * kScale;
                float3 sampleRay = eyeRay * sampleLength;
                float3 samplePoint = cameraPos + sampleRay * 0.5;

                // 地面只采一次
                float3 frontColor = float3(0.0, 0.0, 0.0);
                float3 attenuate;
                {
                    float height = length(samplePoint);
                    float depth = exp(kScaleOverScaleDepth * (kInnerRadius - height));
                    float scatter = depth*temp - cameraOffset;
                    attenuate = exp(-clamp(scatter, 0.0, kMAX_SCATTER) * (kInvWavelength * kKr4PI + kKm4PI));
                    frontColor += attenuate * (depth * scaledLength);
                    samplePoint += sampleRay;
                }

                cIn = frontColor * (kInvWavelength * kKrESun + kKmESun);
                cOut = clamp(attenuate, 0.0, 1.0);
            }

        #if SKYBOX_SUNDISK == SKYBOX_SUNDISK_HQ
            OUT.vertex          = -v.vertex;
        #elif SKYBOX_SUNDISK == SKYBOX_SUNDISK_SIMPLE
            OUT.rayDir          = half3(-eyeRay);
        #else
            OUT.skyGroundFactor = -eyeRay.y / SKY_GROUND_THRESHOLD;
        #endif

            // 曝光乘到顶点色上，天空再乘瑞利相位
            OUT.groundColor = _Exposure * (cIn + COLOR_2_LINEAR(_GroundColor) * cOut);
            OUT.skyColor    = _Exposure * (cIn * getRayleighPhase(mainLight.direction, -eyeRay));

        #if SKYBOX_SUNDISK != SKYBOX_SUNDISK_NONE
            // 太阳亮度跟随主光，并避免过暗时消失
            half lightColorIntensity = clamp(length(mainLight.color), 0.25, 1);
            #if SKYBOX_SUNDISK == SKYBOX_SUNDISK_SIMPLE
                OUT.sunColor    = kSimpleSundiskIntensityFactor * saturate(cOut * kSunScale) * mainLight.color / lightColorIntensity;
            #else
                OUT.sunColor    = kHDSundiskIntensityFactor * saturate(cOut) * mainLight.color / lightColorIntensity;
            #endif

        #endif

        #if defined(UNITY_COLORSPACE_GAMMA) && SKYBOX_COLOR_IN_TARGET_COLOR_SPACE
            OUT.groundColor = sqrt(OUT.groundColor);
            OUT.skyColor    = sqrt(OUT.skyColor);
            #if SKYBOX_SUNDISK != SKYBOX_SUNDISK_NONE
                OUT.sunColor= sqrt(OUT.sunColor);
            #endif
        #endif

            return OUT;
        }


        // 米氏相位，在太阳附近形成光晕
        half getMiePhase(half eyeCos, half eyeCos2)
        {
            half temp = 1.0 + MIE_G2 - 2.0 * MIE_G * eyeCos;
            temp = pow(temp, pow(_SunSize,0.65) * 10);
            temp = max(temp,1.0e-4);
            temp = 1.5 * ((1.0 - MIE_G2) / (2.0 + MIE_G2)) * (1.0 + eyeCos2) / temp;
            #if defined(UNITY_COLORSPACE_GAMMA) && SKYBOX_COLOR_IN_TARGET_COLOR_SPACE
                temp = pow(temp, .454545);
            #endif
            return temp;
        }

        // 简单模式用圆盘，高质量模式用米氏相位当太阳形状
        half calcSunAttenuation(half3 lightPos, half3 ray)
        {
        #if SKYBOX_SUNDISK == SKYBOX_SUNDISK_SIMPLE
            half3 delta = lightPos - ray;
            half dist = length(delta);
            half spot = 1.0 - smoothstep(0.0, _SunSize, dist);
            return spot * spot;
        #else
            half focusedEyeCos = pow(saturate(dot(lightPos, ray)), _SunSizeConvergence);
            return getMiePhase(-focusedEyeCos, focusedEyeCos * focusedEyeCos);
        #endif
        }

        // 片元：按地平线混合天空和地面，再叠加太阳
        half4 frag (v2f IN) : SV_Target
        {
            half3 col = half3(0.0, 0.0, 0.0);

            Light mainLight = GetMainLight();

        // 大于零偏地面，小于零偏天空
        #if SKYBOX_SUNDISK == SKYBOX_SUNDISK_HQ
            half3 ray = normalize(mul((float3x3)unity_ObjectToWorld, IN.vertex));
            half y = ray.y / SKY_GROUND_THRESHOLD;
        #elif SKYBOX_SUNDISK == SKYBOX_SUNDISK_SIMPLE
            half3 ray = IN.rayDir.xyz;
            half y = ray.y / SKY_GROUND_THRESHOLD;
        #else
            half y = IN.skyGroundFactor;
        #endif

            // 天空色和地面色按地平线混合
            col = lerp(IN.skyColor, IN.groundColor, saturate(y));

        #if SKYBOX_SUNDISK != SKYBOX_SUNDISK_NONE
            // 太阳只加在天空一侧
            if(y < 0.0)
            {
                col += IN.sunColor * calcSunAttenuation(mainLight.direction, -ray);
            }
        #endif

        #if defined(UNITY_COLORSPACE_GAMMA) && !SKYBOX_COLOR_IN_TARGET_COLOR_SPACE
            col = LINEAR_2_OUTPUT(col);
        #endif

            return half4(clamp(col, 0, 25),1.0);

        }
        ENDHLSL
    }
}


Fallback Off
CustomEditor "SkyboxProceduralShaderGUI"
}
