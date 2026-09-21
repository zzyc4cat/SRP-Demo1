using System.Collections.Generic;
using UnityEngine;
using Unity.Jobs;
using Unity.Burst;
using Unity.Mathematics;
using Unity.Collections;
using UnityEngine.Rendering.Universal;
using WaterSystem.Data;

namespace WaterSystem
{
	/// <summary>
	/// CPU 版 Gerstner。公式和着色器一致，只给登记过的浮力点算高度和法线，不推动画面顶点。
	/// </summary>
    public static class GerstnerWavesJobs
    {
        public static bool Initialized;
        private static bool _firstFrame = true;
        private static bool _processing;
        private static int _waveCount;
        private static NativeArray<Wave> _waveData;
        private static NativeArray<float3> _positions;
        private static int _positionCount;
        private static NativeArray<float3> _wavePos;
        private static NativeArray<float3> _waveNormal;
        private static JobHandle _waterHeightHandle;
        static readonly Dictionary<int, int2> Registry = new Dictionary<int, int2>();

        // 从当前水面拷一份波列，并预留最多 4096 个取样点
        public static void Init()
        {
            if(Debug.isDebugBuild)
                Debug.Log("Initializing Gerstner Waves Jobs");
            _waveCount = Water.Instance._waves.Length;
            _waveData = new NativeArray<Wave>(_waveCount, Allocator.Persistent);
            for (var i = 0; i < _waveData.Length; i++)
            {
                _waveData[i] = Water.Instance._waves[i];
            }

            _positions = new NativeArray<float3>(4096, Allocator.Persistent);
            _wavePos = new NativeArray<float3>(4096, Allocator.Persistent);
            _waveNormal = new NativeArray<float3>(4096, Allocator.Persistent);

            Initialized = true;
        }

        public static void Cleanup()
        {
            if(Debug.isDebugBuild)
                Debug.Log("Cleaning up Gerstner Wave Jobs");
            _waterHeightHandle.Complete();

            _waveData.Dispose();
            _positions.Dispose();
            _wavePos.Dispose();
            _waveNormal.Dispose();
        }

        // 把物体的取样点写进共享数组，同一 guid 会覆盖旧位置
        public static void UpdateSamplePoints(ref NativeArray<float3> samplePoints, int guid)
        {
            CompleteJobs();

            if (Registry.TryGetValue(guid, out var offsets))
            {
                for (var i = offsets.x; i < offsets.y; i++) _positions[i] = samplePoints[i - offsets.x];
            }
            else
            {
                if (_positionCount + samplePoints.Length >= _positions.Length) return;
                
                offsets = new int2(_positionCount, _positionCount + samplePoints.Length);
                Registry.Add(guid, offsets);
                _positionCount += samplePoints.Length;
            }
        }

        // 读回上一帧算好的位移和法线
        public static void GetData(int guid, ref float3[] outPos, ref float3[] outNorm)
        {
            if (!Registry.TryGetValue(guid, out var offsets)) return;
            
            _wavePos.Slice(offsets.x, offsets.y - offsets.x).CopyTo(outPos);
            if(outNorm != null)
                _waveNormal.Slice(offsets.x, offsets.y - offsets.x).CopyTo(outNorm);
        }

        // 派发本帧高度 Job。结果要到下一帧 Complete 后才能读
        public static void UpdateHeights()
        {
            if (_processing) return;
            
            _processing = true;

#if STATIC_EVERYTHING
            var t = 0.0f;
#else
            var t = Time.time;
#endif

            // 对全部已登记点做并行 Gerstner
            var waterHeight = new HeightJob()
            {
                WaveData = _waveData,
                Position = _positions,
                OffsetLength = new int2(0, _positions.Length),
                Time = t,
                OutPosition = _wavePos,
                OutNormal = _waveNormal
            };
                
            _waterHeightHandle = waterHeight.Schedule(_positionCount, 32);
                
            JobHandle.ScheduleBatchedJobs();

            _firstFrame = false;
        }

        private static void CompleteJobs()
        {
            if (_firstFrame || !_processing) return;
            
            _waterHeightHandle.Complete();
            _processing = false;
        }

        // 单点 Gerstner：水平用余弦推移，垂直用正弦，法线由偏导近似
        [BurstCompile]
        private struct HeightJob : IJobParallelFor
        {
            [ReadOnly]
            public NativeArray<Wave> WaveData;
            [ReadOnly]
            public NativeArray<float3> Position;

            [WriteOnly]
            public NativeArray<float3> OutPosition;
            [WriteOnly]
            public NativeArray<float3> OutNormal;

            [ReadOnly]
            public float Time;
            [ReadOnly]
            public int2 OffsetLength;

            public void Execute(int i)
            {
                if (i < OffsetLength.x || i >= OffsetLength.y - OffsetLength.x) return;
                
                var waveCountMulti = 1f / WaveData.Length;
                var wavePos = new float3(0f, 0f, 0f);
                var waveNorm = new float3(0f, 0f, 0f);

                for (var wave = 0; wave < WaveData.Length; wave++)
                {
                    var pos = Position[i].xz;

                    var amplitude = WaveData[wave].amplitude;
                    var direction = WaveData[wave].direction;
                    var wavelength = WaveData[wave].wavelength;
                    var omniPos = WaveData[wave].origin;
                    var w = 6.28318f / wavelength;
                    var wSpeed = math.sqrt(9.8f * w);
                    const float peak = 0.8f;
                    var qi = peak / (amplitude * w * WaveData.Length);

                    var windDir = new float2(0f, 0f);

                    direction = math.radians(direction);
                    var windDirInput = new float2(math.sin(direction), math.cos(direction)) * (1 - WaveData[wave].onmiDir);
                    var windOmniInput = (pos - omniPos) * WaveData[wave].onmiDir;

                    windDir += windDirInput;
                    windDir += windOmniInput;
                    windDir = math.normalize(windDir);
                    var dir = math.dot(windDir, pos - (omniPos * WaveData[wave].onmiDir));

                    var calc = dir * w + -Time * wSpeed;
                    var cosCalc = math.cos(calc);
                    var sinCalc = math.sin(calc);

                    wavePos.x += qi * amplitude * windDir.x * cosCalc;
                    wavePos.z += qi * amplitude * windDir.y * cosCalc;
                    wavePos.y += sinCalc * amplitude * waveCountMulti;

                    var wa = w * amplitude;
                    var norm = new float3(-(windDir.xy * wa * cosCalc),
                        1 - (qi * wa * sinCalc));
                    waveNorm += (norm * waveCountMulti) * amplitude;
                }
                OutPosition[i] = wavePos;
                OutNormal[i] = math.normalize(waveNorm.xzy);
            }
        }
    }
}
