// ============================================================================
// Grass.hlsl — 草地几何生成 / 风力 / 交互压草
// ----------------------------------------------------------------------------
// 依赖：URP Lighting + CustomTessellation.hlsl
// 命名规范见 CustomTessellation.hlsl 文件头
// ============================================================================
#ifndef DEMO_GRASS_LIBRARY_INCLUDED
#define DEMO_GRASS_LIBRARY_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
#include "CustomTessellation.hlsl"

// 交互角色缓冲容量（与 C# GetPlayerPos 上传数组长度一致）
#define GRASS_MAX_PLAYERS 100

// ----------------------------------------------------------------------------
// 材质属性（由 Properties / Material 注入）
// ----------------------------------------------------------------------------
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

// xyz = 角色世界坐标，w = 影响半径；由脚本 Material.SetVectorArray 写入
float4 _Players[GRASS_MAX_PLAYERS];

// ----------------------------------------------------------------------------
// 工具：伪随机 [0,1]
// ----------------------------------------------------------------------------
float Hash01(float3 seed)
{
    return frac(sin(dot(seed, float3(12.9898, 78.233, 53.539))) * 43758.5453);
}

// ----------------------------------------------------------------------------
// Geometry → Fragment 插值数据
// ----------------------------------------------------------------------------
struct GeometryVaryings
{
    float4 positionCS  : SV_POSITION;
    float2 uv          : TEXCOORD0;
    float3 normalWS    : NORMAL;
    float4 shadowCoord : TEXCOORD1;
};

// ----------------------------------------------------------------------------
// 将对象空间草叶顶点打包为裁剪空间输出，并计算阴影坐标
// ----------------------------------------------------------------------------
GeometryVaryings PackGeometryVaryings(float3 positionOS, float2 uv, float3 normalOS)
{
    GeometryVaryings output;
    output.positionCS = TransformObjectToHClip(positionOS);
    output.uv = uv;

    float3 positionWS = TransformObjectToWorld(positionOS);
    output.shadowCoord = TransformWorldToShadowCoord(positionWS);
    output.normalWS = TransformObjectToWorldNormal(normalOS);
    return output;
}

// ----------------------------------------------------------------------------
// 求与输入向量垂直的单位向量（用于压草旋转轴）
// ----------------------------------------------------------------------------
float3 GetPerpendicularVector(float3 direction)
{
    float3 perpendicular = float3(-direction.y, direction.x, 0.0);
    if (length(perpendicular) < 0.001)
    {
        perpendicular = float3(0.0, -direction.z, direction.y);
    }
    return normalize(perpendicular);
}

// ----------------------------------------------------------------------------
// 绕任意轴旋转的 3x3 矩阵（Rodrigues）
// ----------------------------------------------------------------------------
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

// ----------------------------------------------------------------------------
// 【效果】交互压草：在 _Players 中找最近（或已进入半径）的角色
// 返回 float4(positionWS.xyz, radius)
// ----------------------------------------------------------------------------
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

        // 已在影响半径内：直接采用该角色
        if (distanceToPlayer < playerRadius)
        {
            return float4(playerPositionWS, playerRadius);
        }

        if (distanceToPlayer < minDistance)
        {
            minDistance = distanceToPlayer;
            nearest = float4(playerPositionWS, playerRadius);
        }
    }

    return nearest;
}

// ----------------------------------------------------------------------------
// 【效果】几何着色器：每个细分三角形挤出一片草叶（双底点 + 梢）
// 叠加：随机朝向、自然弯曲、风力、角色挤压
// ----------------------------------------------------------------------------
[maxvertexcount(3)]
void GrassGeometry(triangle TessVaryings input[3], inout TriangleStream<GeometryVaryings> triangleStream)
{
    // ---- 以三角形第一个顶点为草根，构建 TBN（切线空间 → 对象空间）----
    float3 positionOS = input[0].positionOS.xyz;
    float3 normalOS = input[0].normalOS;
    float4 tangentOS = input[0].tangentOS;
    float3 bitangentOS = cross(normalOS, tangentOS.xyz) * tangentOS.w;

    float3x3 tangentToObject = float3x3(
        tangentOS.x, bitangentOS.x, normalOS.x,
        tangentOS.y, bitangentOS.y, normalOS.y,
        tangentOS.z, bitangentOS.z, normalOS.z);

    // ---- 随机朝向（绕法线）+ 随机前倾弯曲 ----
    float3x3 facingRotationMatrix = AngleAxis3x3(Hash01(positionOS) * TWO_PI, float3(0.0, 0.0, 1.0));
    float3x3 bendRotationMatrix = AngleAxis3x3(
        Hash01(positionOS.zzx) * _BendRotationRandom * PI * 0.5,
        float3(-1.0, 0.0, 0.0));

    // ---- 风力：世界 XZ 采样噪声图，随时间滚动 ----
    float3 positionWS = TransformObjectToWorld(positionOS);
    float2 windUV = positionWS.xz * _WindDistortionMap_ST.xy
        + _WindDistortionMap_ST.zw
        + _WindFrequency * _Time.y;

    // ---- 角色挤压：靠近时绕垂直于角色方向的轴倾倒 ----
    float4 nearestPlayer = FindNearestPlayer(positionWS);
    float3 playerPositionWS = nearestPlayer.xyz;
    float playerRadius = nearestPlayer.w;
    float3 toPlayer = playerPositionWS - positionWS;
    float playerDistance = length(toPlayer);
    float3 playerDirection = playerDistance > 1e-4 ? toPlayer / playerDistance : float3(0.0, 0.0, 1.0);
    float3 playerAxis = GetPerpendicularVector(float3(playerDirection.x, playerDirection.z, playerDirection.y));

    float playerBend = max(playerRadius - playerDistance, 0.0);
    float3x3 playerRotationMatrix = AngleAxis3x3(PI * playerBend, playerAxis);

    float2 windSample = (SAMPLE_TEXTURE2D_LOD(_WindDistortionMap, sampler_WindDistortionMap, windUV, 0).xy * 2.0 - 1.0)
        * _WindStrength;
    float3 windAxis = float3(windSample.x, windSample.y, 0.0);
    float windLength = length(windAxis);
    windAxis = windLength > 1e-4 ? windAxis / windLength : float3(1.0, 0.0, 0.0);
    float3x3 windRotationMatrix = AngleAxis3x3(PI * windSample.x, windAxis);

    // 梢部：风 + 角色 + 朝向 + 弯曲；根部：仅朝向，避免根部滑动
    float3x3 tipTransform = mul(
        mul(mul(mul(tangentToObject, windRotationMatrix), playerRotationMatrix), facingRotationMatrix),
        bendRotationMatrix);
    float3x3 rootTransform = mul(tangentToObject, facingRotationMatrix);

    float bladeHeight = (Hash01(positionOS.zyx) * 2.0 - 1.0) * _BladeHeightRandom + _BladeHeight;
    float bladeWidth = (Hash01(positionOS.xzy) * 2.0 - 1.0) * _BladeWidthRandom + _BladeWidth;

    // 切线空间中「朝下」的法线，变换后用于光照
    float3 tangentNormal = float3(0.0, -1.0, 0.0);
    float3 rootNormalOS = mul(rootTransform, tangentNormal);

    // 底部左右顶点
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

#endif // DEMO_GRASS_LIBRARY_INCLUDED
