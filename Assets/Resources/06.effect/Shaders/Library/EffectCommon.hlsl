#ifndef EFFECT_COMMON_INCLUDED
#define EFFECT_COMMON_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

// 把数值从一个区间线性映射到另一个区间
float EffectRemap(float v, float inMin, float inMax, float outMin, float outMax)
{
    return lerp(outMin, outMax, saturate((v - inMin) / max(inMax - inMin, 1e-5)));
}

// 视角越贴着表面越亮。power 控制收边，intensity 控制亮度
float EffectFresnel(float3 normalWS, float3 viewWS, float power, float intensity)
{
    float ndv = saturate(dot(normalize(normalWS), normalize(viewWS)));
    return pow(1.0 - ndv, max(power, 0.01)) * intensity;
}

// UV 流光：按平铺和速度推动采样坐标
float2 EffectFlowUV(float2 uv, float2 tilling, float2 speed, float time)
{
    return uv * tilling + speed * time;
}

// 世界空间 XY 流光，相对物体枢轴，避免跟模型 UV 接缝绑在一起
float2 EffectWorldFlowUV(float3 posWS, float3 pivotWS, float2 tilling, float2 speed, float time)
{
    float2 uv = (posWS.xy - pivotWS.xy) * tilling;
    return uv + speed * time;
}

// 物体空间平面流光，贴在网格上并随物体移动
float2 EffectObjectFlowUV(float3 posOS, float2 tilling, float2 speed, float time)
{
    return posOS.xy * tilling + speed * time;
}

// 物体空间绕 Y 轴的柱面流光。接缝在背面
float2 EffectObjectCylinderFlowUV(float3 posOS, float2 tilling, float2 speed, float time)
{
    float u = atan2(posOS.x, posOS.z) / (2.0 * 3.14159265);
    float v = posOS.y;
    return float2(u, v) * tilling + speed * time;
}

// 用宽度把 0 附近的硬切边收成软过渡
float EffectSoftClip(float value, float edgeWidth)
{
    return saturate(value / max(edgeWidth, 1e-4));
}

// 噪声和阈值比较。keep 大于 0 保留，edge 为溶解前沿的亮边
void EffectDissolve(float noise, float threshold, float edgeWidth, out float keep, out float edge)
{
    float d = noise - threshold;
    keep = d;
    edge = 1.0 - saturate(d / max(edgeWidth, 1e-4));
}

// 网格与场景深度越接近，返回值越大。用于接触处的接缝光
float EffectDepthIntersection(float4 positionCS, float2 screenUV, float softPower)
{
    float rawDepth = SampleSceneDepth(screenUV);
    float sceneZ = LinearEyeDepth(rawDepth, _ZBufferParams);
    float partZ = LinearEyeDepth(positionCS.z / positionCS.w, _ZBufferParams);
    float diff = sceneZ - partZ;
    return saturate(1.0 - saturate(diff * softPower));
}

// 避免零向量归一化。长度过小时返回世界上方向
float3 EffectSafeNormalize(float3 v)
{
    float len = length(v);
    return len > 1e-5 ? v / len : float3(0, 1, 0);
}

// 序列帧 UV。cells 为列数和行数，帧序从左上角开始
float2 EffectFlipbookUV(float2 uv, float2 cells, float frame)
{
    float2 cellCount = max(cells, float2(1, 1));
    float total = cellCount.x * cellCount.y;
    float f = floor(fmod(frame, total));
    float col = fmod(f, cellCount.x);
    float row = floor(f / cellCount.x);
    float2 cellSize = 1.0 / cellCount;
    float2 local = uv * cellSize;
    local.y = cellSize.y - local.y;
    float2 offset = float2(col, cellCount.y - 1.0 - row) * cellSize;
    return offset + float2(uv.x * cellSize.x, (1.0 - uv.y) * cellSize.y);
}

// 序列帧 UV 的简化版，不做格子内的 V 翻转
float2 EffectFlipbookUVSimple(float2 uv, float2 cells, float frame)
{
    float2 cellCount = max(cells, float2(1, 1));
    float total = cellCount.x * cellCount.y;
    float f = floor(fmod(max(frame, 0.0), total));
    float col = fmod(f, cellCount.x);
    float row = floor(f / cellCount.x);
    float2 cellSize = 1.0 / cellCount;
    float2 offset = float2(col, (cellCount.y - 1.0 - row)) * cellSize;
    return offset + uv * cellSize;
}

// 从向量 a 中去掉沿 b 的分量
float3 EffectVectorRejection(float3 a, float3 b)
{
    float bb = max(dot(b, b), 1e-6);
    return a - (dot(a, b) / bb) * b;
}

// 由世界坐标和面法线还原这块平面六边形的面心
float3 EffectHexagonCenterWS(float3 positionWS, float3 normalWS, float3 objectPivotWS)
{
    float3 pointToCenter = -EffectVectorRejection(positionWS - objectPivotWS, normalWS);
    return positionWS + pointToCenter;
}

// 尖顶六边形距离场。p 为相对面心的 UV，外接圆半径 0.45
float EffectHexSDF(float2 p)
{
    p = abs(p);
    return max(p.x * 0.5 + p.y * 0.86602540378, p.x);
}

// 六边形边线遮罩。p 为 UV 减 0.5，1 在边上，0 在内部
float EffectHexEdge(float2 p, float edgeWidth, float soft)
{
    float d = EffectHexSDF(p);
    float outer = 0.45 * 0.86602540378;
    float w = max(edgeWidth, 1e-4);
    float s = max(soft, 1e-5);
    float bd = abs(d - outer);
    float core = saturate(1.0 - bd / w);
    float fringe = 1.0 - saturate((bd - w) / s);
    return max(core * core, 0.0) * saturate(fringe);
}

// 六边形内部填充。inset 越大，填充越往面心收
float EffectHexFill(float2 p, float inset)
{
    float d = EffectHexSDF(p);
    float outer = 0.45 * 0.86602540378;
    float inn = outer - max(inset, 1e-4);
    return 1.0 - smoothstep(inn, outer, d);
}

// 二维哈希，给噪声和格子相位提供稳定随机数
float EffectHash21(float2 p)
{
    p = frac(p * float2(123.34, 345.45));
    p += dot(p, p + 34.345);
    return frac(p.x * p.y);
}

// 值噪声，坐标取整后在四个角之间平滑插值
float EffectNoise2D(float2 uv)
{
    float2 i = floor(uv);
    float2 f = frac(uv);
    float a = EffectHash21(i);
    float b = EffectHash21(i + float2(1, 0));
    float c = EffectHash21(i + float2(0, 1));
    float d = EffectHash21(i + float2(1, 1));
    float2 u = f * f * (3.0 - 2.0 * f);
    return lerp(lerp(a, b, u.x), lerp(c, d, u.x), u.y);
}

// 四层分形噪声，用来做碎边和域扭曲
float EffectFBM(float2 uv)
{
    float v = 0.0;
    float a = 0.5;
    float2 p = uv;
    [unroll]
    for (int i = 0; i < 4; i++)
    {
        v += EffectNoise2D(p) * a;
        p = p * 2.03 + float2(17.1, 9.7);
        a *= 0.5;
    }
    return v;
}

#endif
