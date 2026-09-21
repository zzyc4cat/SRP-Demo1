using UnityEngine;
using UnityEngine.Rendering.Universal;

namespace WaterSystem.Data
{
	/// <summary>
	/// 水面渲染开关：几何方式、反射来源、是否无限延伸。不存水色和波浪外形。
	/// </summary>
    [System.Serializable][CreateAssetMenu(fileName = "WaterSettingsData", menuName = "WaterSystem/Settings", order = 0)]
    public class WaterSettingsData : ScriptableObject
    {
		public GeometryType waterGeomType; // 顶点偏移或曲面细分。当前场景走顶点偏移
        public ReflectionType refType = ReflectionType.PlanarReflection; // 反射来源，决定着色器开哪组关键字
		public PlanarReflections.PlanarReflectionSettings planarSettings; // 平面反射分辨率、裁剪偏移、反射图层
		public Cubemap cubemapRefType; // 反射类型为 Cubemap 时使用的贴图

		public bool isInfinite; // 是否画跟随相机的无限海面。对应着色器尚未做完
		public Vector4 originOffset = new Vector4(0f, 0f, 500f, 500f); // 无限水面的原点偏移，xy 未用，zw 为水平范围
	}

	/// <summary>
	/// 反射来源：自定义 Cubemap、最近的反射探针，或实时平面反射。
	/// </summary>
	[System.Serializable]
	public enum ReflectionType
	{
		Cubemap,
		ReflectionProbe,
		PlanarReflection
	}

	/// <summary>
	/// 波浪几何：在顶点里直接偏移，或用曲面细分增加顶点再偏移。
	/// </summary>
	[System.Serializable]
	public enum GeometryType
	{
		VertexOffset,
		Tesselation
	}
}
