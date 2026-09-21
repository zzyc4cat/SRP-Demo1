#ifndef GERSTNER_WAVES_INCLUDED
#define GERSTNER_WAVES_INCLUDED

uniform uint 	_WaveCount;

struct Wave
{
	float amplitude;
	float direction;
	float wavelength;
	float2 origin;
	float omni;
};

#if defined(USE_STRUCTURED_BUFFER)
StructuredBuffer<Wave> _WaveDataBuffer;
#else
half4 waveData[20];
#endif

struct WaveStruct
{
	float3 position;
	float3 normal;
};

// 单条格斯特纳波的水平推移、高度和法线
WaveStruct GerstnerWave(half2 pos, float waveCountMulti, half amplitude, half direction, half wavelength, half omni, half2 omniPos)
{
	WaveStruct waveOut;
#if defined(_STATIC_SHADER)
	float time = 0;
#else
	float time = _Time.y;
#endif

	// 波数、波速和陡度，高度会按波数均分
	half3 wave = 0;
	half w = 6.28318 / wavelength;
	half wSpeed = sqrt(9.8 * w);
	half peak = 1.5;
	half qi = peak / (amplitude * w * _WaveCount);

	// 方向波和全向波合成传播方向
	direction = radians(direction);
	half2 dirWaveInput = half2(sin(direction), cos(direction)) * (1 - omni);
	half2 omniWaveInput = (pos - omniPos) * omni;

	half2 windDir = normalize(dirWaveInput + omniWaveInput);
	half dir = dot(windDir, pos - (omniPos * omni));

	half calc = dir * w + -time * wSpeed;
	half cosCalc = cos(calc);
	half sinCalc = sin(calc);

	// 余弦推开水平位置，正弦抬起波高
	wave.xz = qi * amplitude * windDir.xy * cosCalc;
	wave.y = ((sinCalc * amplitude)) * waveCountMulti;

	// 用偏导得到这条波的法线
	half wa = w * amplitude;
	half3 n = half3(-(windDir.xy * wa * cosCalc),
					1-(qi * wa * sinCalc));

	waveOut.position = wave * saturate(amplitude * 10000);
	waveOut.normal = (n.xzy * waveCountMulti);

	return waveOut;
}

// 把所有波的位移和法线叠在一起
inline void SampleWaves(float3 position, half opacity, out WaveStruct waveOut)
{
	half2 pos = position.xz;
	waveOut.position = 0;
	waveOut.normal = 0;
	half waveCountMulti = 1.0 / _WaveCount;
	half3 opacityMask = saturate(half3(3, 3, 1) * opacity);

	// 逐条取样并累加
	UNITY_LOOP
	for(uint i = 0; i < _WaveCount; i++)
	{
#if defined(USE_STRUCTURED_BUFFER)
		Wave w = _WaveDataBuffer[i];
#else
		Wave w;
		w.amplitude = waveData[i].x;
		w.direction = waveData[i].y;
		w.wavelength = waveData[i].z;
		w.omni = waveData[i].w;
		w.origin = waveData[i + 10].xy;
#endif
		WaveStruct wave = GerstnerWave(pos,
								waveCountMulti,
								w.amplitude,
								w.direction,
								w.wavelength,
								w.omni,
								w.origin);

		waveOut.position += wave.position;
		waveOut.normal += wave.normal;
	}
	// 浅水处压低水平位移，避免岸边网格被推穿
	waveOut.position *= opacityMask;
	waveOut.normal *= half3(opacity, 1, opacity);
}

#endif
