


// Shader Graph 自定义函数：取主光方向、颜色和阴影，预览窗口给固定值

void MainLight_half(float3 WorldPos, out half3 Direction, out half3 Color, out half DistanceAtten, out half ShadowAtten)
{
#ifdef SHADERGRAPH_PREVIEW
   Direction = half3(0.5, 0.5, 0);
   Color = 1;
   DistanceAtten = 1;
   ShadowAtten = 1;
#else
   half4 shadowCoord = TransformWorldToShadowCoord(WorldPos);
   Light mainLight = GetMainLight(shadowCoord);
   Direction = mainLight.direction;
   Color = mainLight.color;
   DistanceAtten = mainLight.distanceAttenuation;
   ShadowAtten = mainLight.shadowAttenuation;
#endif
}

// 不带世界坐标的主光，阴影衰减固定为 1
void MainLight_half(out half3 Direction, out half3 Color, out half DistanceAtten, out half ShadowAtten)
{
#ifdef SHADERGRAPH_PREVIEW
   Direction = half3(0.5, 0.5, 0);
   Color = 1;
   DistanceAtten = 1;
   ShadowAtten = 1;
#else
   Light mainLight = GetMainLight();
   Direction = mainLight.direction;
   Color = mainLight.color;
   DistanceAtten = mainLight.distanceAttenuation;
   ShadowAtten = mainLight.shadowAttenuation;
#endif
}

// 球谐环境光，half 精度版本
void SampleSH_half(half3 normalWS, out half3 Ambient)
{
    real4 SHCoefficients[7];
    SHCoefficients[0] = unity_SHAr;
    SHCoefficients[1] = unity_SHAg;
    SHCoefficients[2] = unity_SHAb;
    SHCoefficients[3] = unity_SHBr;
    SHCoefficients[4] = unity_SHBg;
    SHCoefficients[5] = unity_SHBb;
    SHCoefficients[6] = unity_SHC;

    Ambient = max(half3(0, 0, 0), SampleSH9(SHCoefficients, normalWS));
}

// 球谐环境光，给植被和悬崖用
void SampleSH_float(float3 normalWS, out float3 Ambient)
{
    real4 SHCoefficients[7];
    SHCoefficients[0] = unity_SHAr;
    SHCoefficients[1] = unity_SHAg;
    SHCoefficients[2] = unity_SHAb;
    SHCoefficients[3] = unity_SHBr;
    SHCoefficients[4] = unity_SHBg;
    SHCoefficients[5] = unity_SHBb;
    SHCoefficients[6] = unity_SHC;

    Ambient = max(float3(0, 0, 0), SampleSH9(SHCoefficients, normalWS));
}