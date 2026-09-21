Shader "ZZY/06.effect/Shield"
{
    Properties
    {
        // 罩膜颜色，Alpha 是膜的透明度
        _BaseColor ("Base Color", Color) = (0.55, 0.82, 1.0, 0.22)
        // 六边形边线颜色
        _HexLineColor ("Hex Line Color", Color) = (0.45, 1.25, 2.0, 1)
        // 边线亮度。大于 1 时走 HDR
        _HexLineIntensity ("Hex Line Intensity", Range(0, 8)) = 2.2
        // 边线在六边形 SDF 上的宽度
        _HexLineWidth ("Hex Line Width", Range(0.005, 0.15)) = 0.028
        // 边线外侧的软边
        _HexLineSoft ("Hex Line Soft", Range(0.0005, 0.05)) = 0.002
        // 格子内部填充颜色
        _HexFillColor ("Hex Fill Color", Color) = (0.12, 0.6, 1.15, 1)
        // 填充亮度。0 时只剩边线
        _HexFillIntensity ("Hex Fill Intensity", Range(0, 3)) = 0.35
        // 填充相对边线向内收的距离
        _HexInset ("Hex Fill Inset", Range(0.005, 0.15)) = 0.035
        // 流光明暗调制贴图，按法线方向采样
        _BlinkMap ("Blink Checker (UV2)", 2D) = "gray" {}
        // 流光绕球面走一圈的速度
        _BlinkSpeed ("Blink Speed", Float) = 0.06
        // 流光亮度。低于约 0.45 时逐渐熄灭
        _BlinkIntensity ("Blink Intensity", Range(0, 2)) = 0.7
        // 轨迹摆动幅度。越大转向越明显，但仍保持同向
        _BlinkRandom ("Blink Randomness", Range(0, 2)) = 1.2
        [Header(Rim)]
        // 正面 Fresnel 边缘光颜色
        _RimColor ("Rim Color", Color) = (0.45, 1.15, 2.0, 1)
        // 边缘光收束。越大越贴着剪影
        _RimPower ("Rim Power", Range(0.5, 8)) = 3.2
        // 边缘光强度
        _RimIntensity ("Rim Intensity", Range(0, 4)) = 1.35
        [Header(Intersection)]
        // 与其他物体相交处的亮缝颜色
        _EdgeColor ("Intersection Color", Color) = (0.55, 1.35, 2.2, 1)
        // 接缝衰减。越大亮缝越窄
        _EdgePower ("Intersection Power", Range(0.2, 12)) = 1.4
        // 接缝亮度。0 时不画接缝
        _EdgeIntensity ("Intersection Intensity", Range(0, 6)) = 2.2
        [Header(Dissolve)]
        // 溶解进度。0 完整，1 从顶端到底部全部消失
        _DissolveAmount ("Dissolve Amount", Range(0, 1)) = 0
        // 正在缩小的那一层高度范围
        _DissolveWidth ("Dissolve Width", Range(0.02, 0.45)) = 0.14
        // 正在缩小的格子边缘颜色
        _DissolveEdgeColor ("Dissolve Edge Color", Color) = (1.15, 1.55, 2.1, 1)
        [Header(Depth)]
        // 是否写入深度。默认关闭，正面网格才能透出背面网格
        [Enum(Off, 0, On, 1)] _ZWrite ("ZWrite", Float) = 0
        // 深度比较。默认 LEqual，方块仍能挡住它后面的网格
        [Enum(UnityEngine.Rendering.CompareFunction)] _ZTest ("ZTest", Float) = 4
    }

    SubShader
    {
        Tags
        {
            "RenderPipeline"="UniversalPipeline"
            "RenderType"="Transparent"
            "Queue"="Transparent"
        }

        HLSLINCLUDE
        #include "Library/EffectCommon.hlsl"

        TEXTURE2D(_BlinkMap); SAMPLER(sampler_BlinkMap);

        CBUFFER_START(UnityPerMaterial)
            half4 _BaseColor;
            half4 _HexLineColor;
            half _HexLineIntensity;
            half _HexLineWidth;
            half _HexLineSoft;
            half4 _HexFillColor;
            half _HexFillIntensity;
            half _HexInset;
            half _BlinkSpeed;
            half _BlinkIntensity;
            half _BlinkRandom;
            half4 _RimColor;
            half _RimPower;
            half _RimIntensity;
            half4 _EdgeColor;
            half _EdgePower;
            half _EdgeIntensity;
            half _DissolveAmount;
            half _DissolveWidth;
            half4 _DissolveEdgeColor;
        CBUFFER_END

        struct Attributes
        {
            float4 positionOS : POSITION;
            float3 normalOS : NORMAL;
            float2 uv : TEXCOORD0;
            float2 uv2 : TEXCOORD1;
        };

        struct Varyings
        {
            float4 positionCS : SV_POSITION;
            float2 uv : TEXCOORD0;
            float2 uv2 : TEXCOORD1;
            float3 positionWS : TEXCOORD2;
            float3 pivotWS : TEXCOORD3;
            float3 normalWS : TEXCOORD4;
        };

        // 顶点：变换到裁剪空间，并带上球心，供格子中心和流光使用
        Varyings vert(Attributes v)
        {
            Varyings o;
            float3 posWS = TransformObjectToWorld(v.positionOS.xyz);
            o.positionCS = TransformWorldToHClip(posWS);
            o.positionWS = posWS;
            o.pivotWS = TransformObjectToWorld(float3(0, 0, 0));
            o.normalWS = TransformObjectToWorldNormal(v.normalOS);
            o.uv = v.uv;
            o.uv2 = v.uv2;
            return o;
        }

        // 把速度和时间折进 0~1，长时间运行也不会精度丢失，且首尾相位相同
        float WrapTime(float speed)
        {
            float t = _Time.y;
            float s = max(speed, 0);
            return frac(s * frac(t) + frac(s) * floor(t));
        }

        // 按物体空间高度计算这一格缩了多少。0 完整，1 已缩没，从顶端往下推进
        float ShieldDissolve(float3 positionWS)
        {
            float3 posOS = TransformWorldToObject(positionWS);
            float y01 = saturate(posOS.y * 0.5 + 0.5);
            float amount = saturate(_DissolveAmount);
            float band = max((float)_DissolveWidth, 0.02);
            float front = 1.0 - amount * (1.0 + band);
            return saturate((y01 - front) / band);
        }

        // 两团流光关于球心对称：一团在方向 d，另一团始终在 -d。相位 0 和 1 重合。
        half ShieldFlow(float3 positionWS, float3 normalWS, float3 pivotWS)
        {
            float3 n = normalize(normalWS);
            float3 center = EffectHexagonCenterWS(positionWS, n, pivotWS);
            float3 dir = EffectSafeNormalize(center - pivotWS);

            // 闭合轨道：整数倍正弦，相位 0 和 1 的位置相同，且偏航始终往前
            float phase = WrapTime(max((float)_BlinkSpeed, 0.02));
            float a = phase * 6.2831853;
            float wobble = lerp(0.1, 0.24, saturate(_BlinkRandom));
            float yaw = a + wobble * sin(2.0 * a) + wobble * 0.4 * sin(3.0 * a);
            float pitch = 0.42 * sin(a) + wobble * 0.55 * sin(2.0 * a);
            float3 target = normalize(float3(cos(pitch) * sin(yaw), sin(pitch), cos(pitch) * cos(yaw)));

            // 点对称的两团光。半径约 28 度，和 180 度对点不会相交
            half spot = smoothstep(0.88, 0.965, saturate(dot(dir, target)));
            spot = max(spot, smoothstep(0.88, 0.965, saturate(dot(dir, -target))));
            float mapSample = SAMPLE_TEXTURE2D(_BlinkMap, sampler_BlinkMap, n.xy * 0.5 + 0.5).r;
            spot *= lerp(0.75, 1.0, smoothstep(0.15, 0.85, mapSample));
            return saturate(spot);
        }

        // 只在整个护盾缩得很小时压低线条，避免远侧球面因为单格更小而被抹掉
        half ShieldDistanceFade(float3 positionWS, float3 pivotWS)
        {
            float distCam = max(distance(_WorldSpaceCameraPos, pivotWS), 1e-3);
            float radius = max(distance(positionWS, pivotWS), 1e-3);
            float worldPerPixel = (2.0 * distCam) / max(unity_CameraProjection._m11 * _ScreenParams.y, 1e-3);
            float diameterPixels = (2.0 * radius) / max(worldPerPixel, 1e-5);
            return saturate(diameterPixels / 90.0);
        }

        // 外轮廓描边：按球面剪影取边，像素粗细和颜色对齐六边形网格线。
        half ShieldOutline(float3 positionWS, float3 pivotWS, float2 uv, float4 positionCS, float lineWidth, float lineSoft)
        {
            float3 cam = _WorldSpaceCameraPos;
            float3 toCenter = pivotWS - cam;
            float distCam = max(length(toCenter), 1e-3);
            float3 axis = toCenter / distCam;
            float radius = max(distance(positionWS, pivotWS), 1e-3);
            float silhouetteCos = sqrt(saturate(1.0 - (radius * radius) / (distCam * distCam)));
            float fragCos = dot(normalize(positionWS - cam), axis);
            float gap = max(fragCos - silhouetteCos, 0.0);

            float3 dpdx = ddx(positionWS);
            float3 dpdy = ddy(positionWS);
            float2 du = ddx(uv);
            float2 dv = ddy(uv);
            float worldArea = length(cross(dpdx, dpdy));
            float uvArea = abs(du.x * dv.y - du.y * dv.x);
            float worldPerUv = sqrt(worldArea / max(uvArea, 1e-8));
            worldPerUv = clamp(worldPerUv, radius * 0.015, radius * 0.45);

            float eye = LinearEyeDepth(positionCS.z / positionCS.w, _ZBufferParams);
            float worldPerPixel = (2.0 * max(eye, 1e-3)) / max(unity_CameraProjection._m11 * _ScreenParams.y, 1e-3);
            float linePixels = (2.0 * max(lineWidth, 1e-4) * worldPerUv) / max(worldPerPixel, 1e-5);
            linePixels = clamp(linePixels, 1.25, 48.0);

            float pixelsFromEdge = gap / max(fwidth(fragCos), 1e-5);
            float wPx = linePixels;
            float sPx = max(linePixels * (lineSoft / max(lineWidth, 1e-4)), 0.75);
            half stroke = saturate(1.0 - pixelsFromEdge / wPx);
            stroke = stroke * stroke;
            stroke *= 1.0 - saturate((pixelsFromEdge - wPx) / sPx);
            return stroke;
        }

        // 正面和背面共用的格子、流光、溶解、接缝。faceSign 大于 0 时才画轮廓和边缘光
        half4 fragCommon(Varyings i, float faceSign)
        {
            half3 col = 0;
            float3 faceCenter = EffectHexagonCenterWS(i.positionWS, normalize(i.normalWS), i.pivotWS);
            float shrink = ShieldDissolve(faceCenter);
            half alive = saturate(1.0 - shrink);

            // 六边形边线。溶解时整格边长一起缩小
            float2 p = i.uv - 0.5;
            float d = EffectHexSDF(p);
            float outerFull = 0.45 * 0.86602540378;
            float outer = outerFull * alive;
            float aa = max(fwidth(d), 1e-5);
            float w = max(_HexLineWidth, 1e-4);
            float s = max(max(_HexLineSoft, aa), 1e-5);
            float bd = abs(d - outer);
            half hexLine = saturate(1.0 - bd / max(w, aa * 1.5));
            hexLine = hexLine * hexLine;
            hexLine *= 1.0 - saturate((bd - w) / s);
            float pixelSize = fwidth(p.x) + fwidth(p.y);
            half distantFade = ShieldDistanceFade(i.positionWS, i.pivotWS);
            hexLine *= distantFade * alive;

            half hexFill = d < (outer - max(_HexInset, 1e-4) * alive) ? alive : 0.0;
            hexFill *= distantFade;
            // 整片格子，略收到边线内侧，线条仍叠在上面
            half interior = d < outer * 0.9 ? alive : 0.0;

            // 整格流光，不改边线透明度
            half spot = ShieldFlow(i.positionWS, i.normalWS, i.pivotWS);
            half flowAmp = smoothstep(0.0, 0.45, saturate(_BlinkIntensity));

            col += _HexFillColor.rgb * hexFill * _HexFillIntensity;
            col += _HexLineColor.rgb * _HexLineIntensity * spot * flowAmp * interior;
            col += _HexLineColor.rgb * hexLine * _HexLineIntensity;

            // 正在缩小的那一层加一圈亮边
            half dissolveEdge = saturate(shrink * alive * 4.0);
            col += _DissolveEdgeColor.rgb * dissolveEdge * max(hexLine, interior);

            half rimLine = 0;
            half fres = 0;
            // 轮廓和 Fresnel 只画在正面，避免背面半球被整片点亮
            if (faceSign > 0)
            {
                rimLine = ShieldOutline(i.positionWS, i.pivotWS, i.uv, i.positionCS, w, max(_HexLineSoft, 1e-5)) * alive;
                float3 viewWS = GetWorldSpaceNormalizeViewDir(i.positionWS);
                float3 sphereN = EffectSafeNormalize(i.positionWS - i.pivotWS);
                fres = EffectFresnel(sphereN, viewWS, _RimPower, _RimIntensity) * alive;
                col += _HexLineColor.rgb * rimLine * _HexLineIntensity;
                col += _RimColor.rgb * fres;
            }

            // 与场景深度相交的亮缝，正反面都画
            float2 screenUV = GetNormalizedScreenSpaceUV(i.positionCS);
            half intersect = EffectDepthIntersection(i.positionCS, screenUV, _EdgePower) * alive;
            half edgeVis = saturate(_EdgeIntensity);
            col += _EdgeColor.rgb * intersect * _EdgeIntensity;

            // 只在确实有发光时叠透明度，避免黑心、黑圈，也不把正面线条挖空
            half alpha = saturate(
                rimLine * 0.9
                + hexLine * 0.9
                + fres * 0.42 * saturate(_RimIntensity)
                + intersect * 0.55 * edgeVis
                + interior * spot * flowAmp * 0.78
                + dissolveEdge * 0.75
                + hexFill * 0.28 * saturate(_HexFillIntensity)
            );
            alpha = min(alpha, lerp(0.92, 0.75, saturate(pixelSize * 10.0)));
            return half4(col, alpha);
        }

        // 膜在下、线在上。溶解掉的高度不再留膜。
        half4 CompositeOverFilm(half4 grid, float shrink)
        {
            half keep = saturate(1.0 - shrink);
            half4 film = _BaseColor;
            film.a *= keep;
            half outA = saturate(grid.a + film.a * (1.0 - grid.a));
            if (outA < 1e-3)
                return 0;
            half3 premul = grid.rgb * grid.a + film.rgb * film.a * (1.0 - grid.a);
            half3 rgb = premul / outA;
            return half4(rgb, outA);
        }

        // 背面网格略压暗，膜叠在线下面
        half4 fragBack(Varyings i) : SV_Target
        {
            half4 grid = fragCommon(i, -1.0);
            grid.rgb *= 0.72;
            return CompositeOverFilm(grid, ShieldDissolve(EffectHexagonCenterWS(i.positionWS, normalize(i.normalWS), i.pivotWS)));
        }

        // 正面网格保持原亮度
        half4 fragFront(Varyings i) : SV_Target
        {
            return CompositeOverFilm(fragCommon(i, 1.0), ShieldDissolve(EffectHexagonCenterWS(i.positionWS, normalize(i.normalWS), i.pivotWS)));
        }
        ENDHLSL

        // 先画内侧面。Cull 固定为 Front，和正面 Pass 的 Back 不能合成同一个参数
        Pass
        {
            Name "ShieldBack"
            Tags { "LightMode"="SRPDefaultUnlit" }
            Cull Front
            ZWrite [_ZWrite]
            ZTest [_ZTest]
            Blend SrcAlpha OneMinusSrcAlpha

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment fragBack
            ENDHLSL
        }

        Pass
        {
            Name "ShieldFront"
            Tags { "LightMode"="UniversalForward" }
            Cull Back
            ZWrite [_ZWrite]
            ZTest [_ZTest]
            Blend SrcAlpha OneMinusSrcAlpha

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment fragFront
            ENDHLSL
        }
    }
    FallBack Off
}
