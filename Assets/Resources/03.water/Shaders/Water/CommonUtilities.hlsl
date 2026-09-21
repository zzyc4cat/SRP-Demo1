#ifndef COMMON_UTILITIES_INCLUDED
#define COMMON_UTILITIES_INCLUDED

// 把 value 从 remap.xy 映到 remap.zw
float Remap(half value, half4 remap)
{
	return remap.z + (value - remap.x) * (remap.w - remap.z) / (remap.y - remap.x);
}

// 灰度高度图转切线法线，强度按屏幕像素偏移采样
float3 HeightToNormal(Texture2D _tex, SamplerState _sampler, float2 _uv, half _intensity)
{
	float3 bumpSamples;
	bumpSamples.x = _tex.Sample(_sampler, _uv).x;
	bumpSamples.y = _tex.Sample(_sampler, float2(_uv.x + _intensity / _ScreenParams.x, _uv.y)).x;
	bumpSamples.z = _tex.Sample(_sampler, float2(_uv.x, _uv.y + _intensity / _ScreenParams.y)).x;
	half dHdU = bumpSamples.z - bumpSamples.x;
	half dHdV = bumpSamples.y - bumpSamples.x;
	return float3(-dHdU, dHdV, 0.5);
}

// 二维哈希，给噪声用
float2 random(float2 st){
    st = float2( dot(st,float2(127.1,311.7)), dot(st,float2(269.5,183.3)) );
    return -1.0 + 2.0 * frac(sin(st) * 43758.5453123);
}

// 值噪声，顶点里用来打散细波 UV
float noise (float2 st) {
    float2 i = floor(st);
    float2 f = frac(st);

    float2 u = f*f*(3.0-2.0*f);

    return lerp( lerp( dot( random(i), f),
                     dot( random(i + float2(1.0,0.0) ), f - float2(1.0,0.0) ), u.x),
                lerp( dot( random(i + float2(0.0,1.0) ), f - float2(0.0,1.0) ),
                     dot( random(i + float2(1.0,1.0) ), f - float2(1.0,1.0) ), u.x), u.y);
}

#endif // COMMON_UTILITIES_INCLUDED