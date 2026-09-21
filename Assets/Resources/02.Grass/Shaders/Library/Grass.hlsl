#ifndef DEMO_GRASS_LIBRARY_INCLUDED
#define DEMO_GRASS_LIBRARY_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
#include "CustomTessellation.hlsl"

#define GRASS_MAX_PLAYERS 100

float _BendRotationRandom;

float _BladeHeight;
float _BladeHeightRandom;
float _BladeWidth;
float _BladeWidthRandom;

TEXTURE2D(_WindDistortionMap);
SAMPLER(sampler_WindDistortionMap);
float4 _WindDistortionMap_ST;

float2 _WindFrequency;
float _WindStrength;

float4 _TopColor;
float4 _BottomColor;
float _TranslucentGain;

float4 _Players[GRASS_MAX_PLAYERS];

// 由三维种子生成零到一的伪随机数
float Hash01(float3 seed)
{
    return frac(sin(dot(seed, float3(12.9898, 78.233, 53.539))) * 43758.5453);
}

struct GeometryVaryings
{
    float4 positionCS  : SV_POSITION;
    float2 uv          : TEXCOORD0;
    float3 normalWS    : NORMAL;
    float4 shadowCoord : TEXCOORD1;
};

// 把对象空间草叶顶点打包到裁剪空间
GeometryVaryings PackGeometryVaryings(float3 positionOS, float2 uv, float3 normalOS)
{
    GeometryVaryings output;
    // 裁剪空间位置和纹理坐标
    output.positionCS = TransformObjectToHClip(positionOS);
    output.uv = uv;

    // 世界空间阴影坐标和法线
    float3 positionWS = TransformObjectToWorld(positionOS);
    output.shadowCoord = TransformWorldToShadowCoord(positionWS);
    output.normalWS = TransformObjectToWorldNormal(normalOS);
    return output;
}

// 求与输入方向垂直的单位向量
float3 GetPerpendicularVector(float3 direction)
{
    // 先在水平面上取一个垂直方向
    float3 perpendicular = float3(-direction.y, direction.x, 0.0);
    // 接近竖直时改用另一组轴
    if (length(perpendicular) < 0.001)
    {
        perpendicular = float3(0.0, -direction.z, direction.y);
    }
    return normalize(perpendicular);
}

// 绕任意轴生成旋转矩阵
float3x3 AngleAxis3x3(float angle, float3 axis)
{
    float sine;
    float cosine;
    sincos(angle, sine, cosine);

    float t = 1.0 - cosine;
    float x = axis.x;
    float y = axis.y;
    float z = axis.z;

    return float3x3(
        t * x * x + cosine,     t * x * y - sine * z, t * x * z + sine * y,
        t * x * y + sine * z,   t * y * y + cosine,   t * y * z - sine * x,
        t * x * z - sine * y,   t * y * z + sine * x, t * z * z + cosine);
}

// 在角色列表里找最近或已进入半径的人
float4 FindNearestPlayer(float3 positionWS)
{
    float4 nearest = float4(0.0, 0.0, 0.0, 0.0);
    float minDistance = 1e5;

    [unroll]
    for (int index = 0; index < GRASS_MAX_PLAYERS; index++)
    {
        float3 playerPositionWS = _Players[index].xyz;
        float playerRadius = _Players[index].w;
        float3 offset = playerPositionWS - positionWS;
        float distanceToPlayer = length(offset);

        // 已在影响半径内，直接采用该角色
        if (distanceToPlayer < playerRadius)
        {
            return float4(playerPositionWS, playerRadius);
        }

        // 否则记下更近的角色
        if (distanceToPlayer < minDistance)
        {
            minDistance = distanceToPlayer;
            nearest = float4(playerPositionWS, playerRadius);
        }
    }

    return nearest;
}

// 由细分三角形挤出一片草叶
[maxvertexcount(3)]
void GrassGeometry(triangle TessVaryings input[3], inout TriangleStream<GeometryVaryings> triangleStream)
{
    // 以第一个顶点为草根，搭建切线到对象空间的矩阵
    float3 positionOS = input[0].positionOS.xyz;
    float3 normalOS = input[0].normalOS;
    float4 tangentOS = input[0].tangentOS;
    float3 bitangentOS = cross(normalOS, tangentOS.xyz) * tangentOS.w;

    float3x3 tangentToObject = float3x3(
        tangentOS.x, bitangentOS.x, normalOS.x,
        tangentOS.y, bitangentOS.y, normalOS.y,
        tangentOS.z, bitangentOS.z, normalOS.z);

    // 随机绕法线朝向，并随机向前弯曲
    float3x3 facingRotationMatrix = AngleAxis3x3(Hash01(positionOS) * TWO_PI, float3(0.0, 0.0, 1.0));
    float3x3 bendRotationMatrix = AngleAxis3x3(
        Hash01(positionOS.zzx) * _BendRotationRandom * PI * 0.5,
        float3(-1.0, 0.0, 0.0));

    // 按世界水平位置采样随时间滚动的风力
    float3 positionWS = TransformObjectToWorld(positionOS);
    float2 windUV = positionWS.xz * _WindDistortionMap_ST.xy
        + _WindDistortionMap_ST.zw
        + _WindFrequency * _Time.y;

    // 靠近角色时绕垂直轴倾倒
    float4 nearestPlayer = FindNearestPlayer(positionWS);
    float3 playerPositionWS = nearestPlayer.xyz;
    float playerRadius = nearestPlayer.w;
    float3 toPlayer = playerPositionWS - positionWS;
    float playerDistance = length(toPlayer);
    float3 playerDirection = playerDistance > 1e-4 ? toPlayer / playerDistance : float3(0.0, 0.0, 1.0);
    float3 playerAxis = GetPerpendicularVector(float3(playerDirection.x, playerDirection.z, playerDirection.y));

    float playerBend = max(playerRadius - playerDistance, 0.0);
    float3x3 playerRotationMatrix = AngleAxis3x3(PI * playerBend, playerAxis);

    // 把风力噪声变成绕轴旋转
    float2 windSample = (SAMPLE_TEXTURE2D_LOD(_WindDistortionMap, sampler_WindDistortionMap, windUV, 0).xy * 2.0 - 1.0)
        * _WindStrength;
    float3 windAxis = float3(windSample.x, windSample.y, 0.0);
    float windLength = length(windAxis);
    windAxis = windLength > 1e-4 ? windAxis / windLength : float3(1.0, 0.0, 0.0);
    float3x3 windRotationMatrix = AngleAxis3x3(PI * windSample.x, windAxis);

    // 梢部叠加风、挤压和弯曲，根部只保留朝向
    float3x3 tipTransform = mul(
        mul(mul(mul(tangentToObject, windRotationMatrix), playerRotationMatrix), facingRotationMatrix),
        bendRotationMatrix);
    float3x3 rootTransform = mul(tangentToObject, facingRotationMatrix);

    // 随机草叶高度和宽度
    float bladeHeight = (Hash01(positionOS.zyx) * 2.0 - 1.0) * _BladeHeightRandom + _BladeHeight;
    float bladeWidth = (Hash01(positionOS.xzy) * 2.0 - 1.0) * _BladeWidthRandom + _BladeWidth;

    // 切线空间朝下的法线，变换后用于光照
    float3 tangentNormal = float3(0.0, -1.0, 0.0);
    float3 rootNormalOS = mul(rootTransform, tangentNormal);

    // 底部左右两个顶点
    triangleStream.Append(PackGeometryVaryings(
        positionOS + mul(rootTransform, float3(bladeWidth, 0.0, 0.0)),
        float2(0.0, 0.0),
        rootNormalOS));
    triangleStream.Append(PackGeometryVaryings(
        positionOS + mul(rootTransform, float3(-bladeWidth, 0.0, 0.0)),
        float2(1.0, 0.0),
        rootNormalOS));

    // 梢部顶点
    float3 tipNormalOS = mul(tipTransform, tangentNormal);
    triangleStream.Append(PackGeometryVaryings(
        positionOS + mul(tipTransform, float3(0.0, 0.0, bladeHeight)),
        float2(0.5, 1.0),
        tipNormalOS));
}

#endif
