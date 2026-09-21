// ============================================================================
// CustomTessellation.hlsl — 草地曲面细分（Hull / Domain）
// ----------------------------------------------------------------------------
// 命名规范（项目统一，对齐 URP）：
//   属性 / 常量缓冲 : _PascalCase
//   结构体           : PascalCase（Attributes / TessVaryings / …）
//   函数             : PascalCase
//   局部变量         : camelCase + 空间后缀（positionOS / normalWS / …）
//   宏               : UPPER_SNAKE_CASE
// ============================================================================
#ifndef DEMO_GRASS_CUSTOM_TESSELLATION_INCLUDED
#define DEMO_GRASS_CUSTOM_TESSELLATION_INCLUDED

// ----------------------------------------------------------------------------
// 顶点输入：模型空间几何属性（细分前）
// ----------------------------------------------------------------------------
struct Attributes
{
    float4 positionOS : POSITION; // 模型空间顶点
    float3 normalOS   : NORMAL;   // 模型空间法线
    float4 tangentOS  : TANGENT;  // 模型空间切线（xyz）+ 副切线符号（w）
};

// ----------------------------------------------------------------------------
// 细分后输出：仍保持「对象空间」，裁剪变换留给 Geometry 阶段
// ----------------------------------------------------------------------------
struct TessVaryings
{
    float4 positionOS : SV_POSITION; // 此处仅占语义槽，值仍是 OS 坐标
    float3 normalOS   : NORMAL;
    float4 tangentOS  : TANGENT;
};

// ----------------------------------------------------------------------------
// 曲面细分因子：每条边 + 面内细分次数
// ----------------------------------------------------------------------------
struct TessellationFactors
{
    float edge[3] : SV_TessFactor;
    float inside  : SV_InsideTessFactor;
};

// 草坪密度（整数分区下等于每边细分段数）
float _TessellationUniform;

// ----------------------------------------------------------------------------
// Vertex：曲面细分管线入口，原样传递控制点
// ----------------------------------------------------------------------------
Attributes Vert(Attributes input)
{
    return input;
}

// ----------------------------------------------------------------------------
// 将插值后的控制点打包为 Geometry 可用的 TessVaryings
// 注意：不做 MVP，草叶挤出在 Geometry 里完成
// ----------------------------------------------------------------------------
TessVaryings TessellationVertex(Attributes input)
{
    TessVaryings output;
    output.positionOS = input.positionOS;
    output.normalOS = input.normalOS;
    output.tangentOS = input.tangentOS;
    return output;
}

// ----------------------------------------------------------------------------
// Patch Constant：为三角形补丁提供细分因子
// ----------------------------------------------------------------------------
TessellationFactors PatchConstantFunction(InputPatch<Attributes, 3> patch)
{
    TessellationFactors factors;
    factors.edge[0] = _TessellationUniform;
    factors.edge[1] = _TessellationUniform;
    factors.edge[2] = _TessellationUniform;
    factors.inside = _TessellationUniform;
    return factors;
}

// ----------------------------------------------------------------------------
// Hull（外壳着色器）：输出控制点，绑定分区策略
// ----------------------------------------------------------------------------
[domain("tri")]
[outputcontrolpoints(3)]
[outputtopology("triangle_cw")]
[partitioning("integer")]
[patchconstantfunc("PatchConstantFunction")]
Attributes Hull(InputPatch<Attributes, 3> patch, uint id : SV_OutputControlPointID)
{
    return patch[id];
}

// ----------------------------------------------------------------------------
// Domain（域着色器）：按重心坐标插值属性，生成细分后顶点
// ----------------------------------------------------------------------------
[domain("tri")]
TessVaryings Domain(
    TessellationFactors factors,
    OutputPatch<Attributes, 3> patch,
    float3 barycentricCoordinates : SV_DomainLocation)
{
    Attributes input;

    // 对任意字段做三角形重心插值
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

#endif // DEMO_GRASS_CUSTOM_TESSELLATION_INCLUDED
