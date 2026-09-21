#ifndef EFFECT_COMMON_INCLUDED
#define EFFECT_COMMON_INCLUDED

// =============================================================================
// 06.effect 共用 HLSL 库（各效果 Shader #include "Library/EffectCommon.hlsl"）
// -----------------------------------------------------------------------------
// 流光 / 溶解 / 管道：EffectFlowUV · EffectObjectFlowUV · EffectFresnel · EffectFBM
// 真实火焰：EffectNoise2D · EffectFBM · EffectFlipbookUVSimple（可选）
// 护盾：EffectHexSDF · EffectHexEdge · EffectHexFill · EffectDepthIntersection
//        EffectHexagonCenterWS · EffectSafeNormalize
// =============================================================================

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

// ------------------------------------------------------------
// 通用数学
// ------------------------------------------------------------

float EffectRemap(float v, float inMin, float inMax, float outMin, float outMax)
{
    return lerp(outMin, outMax, saturate((v - inMin) / max(inMax - inMin, 1e-5)));
}

float EffectFresnel(float3 normalWS, float3 viewWS, float power, float intensity)
{
    float ndv = saturate(dot(normalize(normalWS), normalize(viewWS)));
    return pow(1.0 - ndv, max(power, 0.01)) * intensity;
}

float2 EffectFlowUV(float2 uv, float2 tilling, float2 speed, float time)
{
    return uv * tilling + speed * time;
}

float2 EffectWorldFlowUV(float3 posWS, float3 pivotWS, float2 tilling, float2 speed, float time)
{
    float2 uv = (posWS.xy - pivotWS.xy) * tilling;
    return uv + speed * time;
}

// Object-space planar flow — stays attached to the mesh and tiles with seamless maps.
float2 EffectObjectFlowUV(float3 posOS, float2 tilling, float2 speed, float time)
{
    return posOS.xy * tilling + speed * time;
}

// Object-space cylindrical flow around Y — continuous on the front of a character
// (single wrap seam sits on the back). Requires a seamless flow map.
float2 EffectObjectCylinderFlowUV(float3 posOS, float2 tilling, float2 speed, float time)
{
    float u = atan2(posOS.x, posOS.z) / (2.0 * 3.14159265); // [-0.5, 0.5]
    float v = posOS.y;
    return float2(u, v) * tilling + speed * time;
}

float EffectSoftClip(float value, float edgeWidth)
{
    return saturate(value / max(edgeWidth, 1e-4));
}

// Soft dissolve mask: noise compared against threshold, returns clip factor and edge glow 0..1
void EffectDissolve(float noise, float threshold, float edgeWidth, out float keep, out float edge)
{
    float d = noise - threshold;
    keep = d;
    edge = 1.0 - saturate(d / max(edgeWidth, 1e-4));
}

// Screen-space depth intersection (eye-space). Larger when mesh is close to scene geometry.
float EffectDepthIntersection(float4 positionCS, float2 screenUV, float softPower)
{
    float rawDepth = SampleSceneDepth(screenUV);
    float sceneZ = LinearEyeDepth(rawDepth, _ZBufferParams);
    float partZ = LinearEyeDepth(positionCS.z / positionCS.w, _ZBufferParams);
    float diff = sceneZ - partZ;
    return saturate(1.0 - saturate(diff * softPower));
}

float3 EffectSafeNormalize(float3 v)
{
    float len = length(v);
    return len > 1e-5 ? v / len : float3(0, 1, 0);
}

// Flipbook UV: columns x rows atlas
float2 EffectFlipbookUV(float2 uv, float2 cells, float frame)
{
    float2 cellCount = max(cells, float2(1, 1));
    float total = cellCount.x * cellCount.y;
    float f = floor(fmod(frame, total));
    float col = fmod(f, cellCount.x);
    float row = floor(f / cellCount.x);
    // Unity texture v=0 bottom; flipbook often top-left origin
    float2 cellSize = 1.0 / cellCount;
    float2 local = uv * cellSize;
    local.y = cellSize.y - local.y; // invert within cell if needed
    float2 offset = float2(col, cellCount.y - 1.0 - row) * cellSize;
    return offset + float2(uv.x * cellSize.x, (1.0 - uv.y) * cellSize.y);
}

float2 EffectFlipbookUVSimple(float2 uv, float2 cells, float frame)
{
    float2 cellCount = max(cells, float2(1, 1));
    float total = cellCount.x * cellCount.y;
    float f = floor(fmod(max(frame, 0.0), total));
    float col = fmod(f, cellCount.x);
    float row = floor(f / cellCount.x);
    float2 cellSize = 1.0 / cellCount;
    // Top-left first frame
    float2 offset = float2(col, (cellCount.y - 1.0 - row)) * cellSize;
    return offset + uv * cellSize;
}

float3 EffectVectorRejection(float3 a, float3 b)
{
    // a projected onto b, then rejected: a - proj_b(a)
    float bb = max(dot(b, b), 1e-6);
    return a - (dot(a, b) / bb) * b;
}

// Flat-face honeycomb: recover face center from world position + face normal.
float3 EffectHexagonCenterWS(float3 positionWS, float3 normalWS, float3 objectPivotWS)
{
    float3 pointToCenter = -EffectVectorRejection(positionWS - objectPivotWS, normalWS);
    return positionWS + pointToCenter;
}

// ------------------------------------------------------------
// 护盾：尖顶六边形 SDF（与 ShieldHexSphere 面 UV 约定一致）
// ------------------------------------------------------------

// Pointy-top hexagon SDF. For UV regular hex with circumradius R=0.45,
// the straight borders lie on the iso-contour d = R * sqrt(3)/2 ≈ 0.3897.
float EffectHexSDF(float2 p)
{
    p = abs(p);
    return max(p.x * 0.5 + p.y * 0.86602540378, p.x);
}

// Edge mask: 1 on hex border, 0 elsewhere. p = uv - 0.5 for overlapped face UV.
// Pointy-top regular hex with circumradius 0.45 (matches ShieldHexSphere_equalUV).
float EffectHexEdge(float2 p, float edgeWidth, float soft)
{
    float d = EffectHexSDF(p);
    float outer = 0.45 * 0.86602540378; // apothem
    float w = max(edgeWidth, 1e-4);
    float s = max(soft, 1e-5);
    float bd = abs(d - outer);
    // Two-sided soft band around the hex perimeter.
    float core = saturate(1.0 - bd / w);
    float fringe = 1.0 - saturate((bd - w) / s);
    return max(core * core, 0.0) * saturate(fringe);
}

// Interior fill inside hex: 1 inside, 0 outside
float EffectHexFill(float2 p, float inset)
{
    float d = EffectHexSDF(p);
    float outer = 0.45 * 0.86602540378;
    float inn = outer - max(inset, 1e-4);
    return 1.0 - smoothstep(inn, outer, d);
}

// ------------------------------------------------------------
// 火焰 / 管道：程序噪声
// ------------------------------------------------------------

float EffectHash21(float2 p)
{
    p = frac(p * float2(123.34, 345.45));
    p += dot(p, p + 34.345);
    return frac(p.x * p.y);
}

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

// Soft fractal noise — avoid hard pow thresholds that create jaggies
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
