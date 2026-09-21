#ifndef COMMON_UTILITIES_INCLUDED
#define COMMON_UTILITIES_INCLUDED

// 把数值从一个区间映射到另一个区间
float Remap(half value, half4 remap)
{
	return remap.z + (value - remap.x) * (remap.w - remap.z) / (remap.y - remap.x);
}

// 灰度高度图转切线法线
float3 HeightToNormal(Texture2D _tex, SamplerState _sampler, float2 _uv, half _intensity)
{
	// 采样中心与左右相邻像素的高度
	float3 bumpSamples;
	bumpSamples.x = _tex.Sample(_sampler, _uv).x;
	bumpSamples.y = _tex.Sample(_sampler, float2(_uv.x + _intensity / _ScreenParams.x, _uv.y)).x;
	bumpSamples.z = _tex.Sample(_sampler, float2(_uv.x, _uv.y + _intensity / _ScreenParams.y)).x;
	// 用高度差得到切线方向的法线
	half dHdU = bumpSamples.z - bumpSamples.x;
	half dHdV = bumpSamples.y - bumpSamples.x;
	return float3(-dHdU, dHdV, 0.5);
}

// 二维哈希，给噪声提供随机梯度
float2 random(float2 st){
    st = float2( dot(st,float2(127.1,311.7)), dot(st,float2(269.5,183.3)) );
    return -1.0 + 2.0 * frac(sin(st) * 43758.5453123);
}

// 值噪声，用来打散细小波纹的采样位置
float noise (float2 st) {
    // 拆成格子坐标和平滑权重
    float2 i = floor(st);
    float2 f = frac(st);

    float2 u = f*f*(3.0-2.0*f);

    // 四个角的梯度做双线性插值
    return lerp( lerp( dot( random(i), f),
                     dot( random(i + float2(1.0,0.0) ), f - float2(1.0,0.0) ), u.x),
                lerp( dot( random(i + float2(0.0,1.0) ), f - float2(0.0,1.0) ),
                     dot( random(i + float2(1.0,1.0) ), f - float2(1.0,1.0) ), u.x), u.y);
}

#endif
