using System.Collections.Generic;
using Unity.Mathematics;
using UnityEngine;

namespace WaterSystem.Data
{
    /// <summary>
    /// 水面外观：可见深度、吸收/散射色、波浪列表和泡沫曲线。
    /// </summary>
    [System.Serializable][CreateAssetMenu(fileName = "WaterSurfaceData", menuName = "WaterSystem/Surface Data", order = 0)]
    public class WaterSurfaceData : ScriptableObject
    {
        public float _waterMaxVisibility = 40.0f; // 水色从浅到深的最大距离
        public Gradient _absorptionRamp; // 随深度变深的吸收色
        public Gradient _scatterRamp; // 浪尖透光用的散射色
        public List<Wave> _waves = new List<Wave>(); // 手写波列，_customWaves 为真时使用
        public bool _customWaves = false; // 假则按 BasicWaves 和种子随机生成
        public int randomSeed = 3234;
        public BasicWaves _basicWaveSettings = new BasicWaves(1.5f, 45.0f, 5.0f);
        public FoamSettings _foamSettings = new FoamSettings();
        [SerializeField]
        public bool _init = false; // 编辑器用来判断波浪列表是否已初始化
    }

    /// <summary>
    /// 单条 Gerstner 波。方向波和全向波共用这一结构。
    /// </summary>
    [System.Serializable]
    public struct Wave
    {
        public float amplitude; // 波高，米
        public float direction; // 传播方向，相对 +Z 的角度
        public float wavelength; // 波长，波峰到波峰
        public float2 origin; // 全向波的原点
        public float onmiDir; // 1 为全向波，0 为方向波

        public Wave(float amp, float dir, float length, float2 org, bool omni)
        {
            amplitude = amp;
            direction = dir;
            wavelength = length;
            origin = org;
            onmiDir = omni ? 1 : 0;
        }
    }

    /// <summary>
    /// 自动生成波列的种子参数。实际每条波会在此基础上随机偏移。
    /// </summary>
    [System.Serializable]
    public class BasicWaves
    {
        public int numWaves = 6;
        public float amplitude;
        public float direction;
        public float wavelength;

        public BasicWaves(float amp, float dir, float len)
        {
            numWaves = 6;
            amplitude = amp;
            direction = dir;
            wavelength = len;
        }
    }

    /// <summary>
    /// 泡沫密度曲线。烤进 ramp 贴图后，按浪尖、岸线和局部扰动取样。
    /// </summary>
    [System.Serializable]
    public class FoamSettings
    {
        public int foamType; // 0 默认贴图，1 简单曲线，2 自定义
        public AnimationCurve basicFoam;
        public AnimationCurve liteFoam;
        public AnimationCurve mediumFoam;
        public AnimationCurve denseFoam;

        public FoamSettings()
        {
            foamType = 0;
            basicFoam = new AnimationCurve(new Keyframe[2]{new Keyframe(0.25f, 0f),
                                                                    new Keyframe(1f, 1f)});
            liteFoam = new AnimationCurve(new Keyframe[3]{new Keyframe(0.2f, 0f),
                                                                    new Keyframe(0.4f, 1f),
                                                                    new Keyframe(0.7f, 0f)});
            mediumFoam = new AnimationCurve(new Keyframe[3]{new Keyframe(0.4f, 0f),
                                                                    new Keyframe(0.7f, 1f),
                                                                    new Keyframe(1f, 0f)});
            denseFoam = new AnimationCurve(new Keyframe[2]{new Keyframe(0.7f, 0f),
                                                                    new Keyframe(1f, 1f)});
        }
    }
}
