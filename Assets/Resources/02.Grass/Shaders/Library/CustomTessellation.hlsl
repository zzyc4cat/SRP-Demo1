#ifndef DEMO_GRASS_CUSTOM_TESSELLATION_INCLUDED
#define DEMO_GRASS_CUSTOM_TESSELLATION_INCLUDED

struct Attributes
{
    float4 positionOS : POSITION;
    float3 normalOS   : NORMAL;
    float4 tangentOS  : TANGENT;
};

struct TessVaryings
{
    float4 positionOS : SV_POSITION;
    float3 normalOS   : NORMAL;
    float4 tangentOS  : TANGENT;
};

struct TessellationFactors
{
    float edge[3] : SV_TessFactor;
    float inside  : SV_InsideTessFactor;
};

float _TessellationUniform;

// 细分入口，原样传出控制点
Attributes Vert(Attributes input)
{
    return input;
}

// 把插值后的控制点交给几何阶段
TessVaryings TessellationVertex(Attributes input)
{
    TessVaryings output;
    output.positionOS = input.positionOS;
    output.normalOS = input.normalOS;
    output.tangentOS = input.tangentOS;
    return output;
}

// 为三角形补丁设置统一细分密度
TessellationFactors PatchConstantFunction(InputPatch<Attributes, 3> patch)
{
    TessellationFactors factors;
    factors.edge[0] = _TessellationUniform;
    factors.edge[1] = _TessellationUniform;
    factors.edge[2] = _TessellationUniform;
    factors.inside = _TessellationUniform;
    return factors;
}

// 按控制点序号输出外壳顶点
[domain("tri")]
[outputcontrolpoints(3)]
[outputtopology("triangle_cw")]
[partitioning("integer")]
[patchconstantfunc("PatchConstantFunction")]
Attributes Hull(InputPatch<Attributes, 3> patch, uint id : SV_OutputControlPointID)
{
    return patch[id];
}

// 用重心坐标插值出细分顶点
[domain("tri")]
TessVaryings Domain(
    TessellationFactors factors,
    OutputPatch<Attributes, 3> patch,
    float3 barycentricCoordinates : SV_DomainLocation)
{
    Attributes input;

    // 按重心坐标插值位置、法线和切线
    #define DEMO_DOMAIN_INTERPOLATE(fieldName) \
        input.fieldName = \
            patch[0].fieldName * barycentricCoordinates.x + \
            patch[1].fieldName * barycentricCoordinates.y + \
            patch[2].fieldName * barycentricCoordinates.z;

    DEMO_DOMAIN_INTERPOLATE(positionOS)
    DEMO_DOMAIN_INTERPOLATE(normalOS)
    DEMO_DOMAIN_INTERPOLATE(tangentOS)

    #undef DEMO_DOMAIN_INTERPOLATE

    return TessellationVertex(input);
}

#endif
