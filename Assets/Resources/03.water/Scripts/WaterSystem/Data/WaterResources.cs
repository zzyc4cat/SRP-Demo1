using System.Collections;
using System.Collections.Generic;
using UnityEngine;

namespace WaterSystem
{
	/// <summary>
	/// 水面运行时共用资源。由 Water 通过 Resources.Load 取用，没有它就画不出海面网格。
	/// </summary>
	[System.Serializable][CreateAssetMenu(fileName = "WaterResources", menuName = "WaterSystem/Resource", order = 0)]
	public class WaterResources : ScriptableObject 
	{
		public Texture2D defaultFoamRamp; // 泡沫密度到厚/中/薄三层的默认查找图
        public Texture2D defaultFoamMap; // 岸线和浪尖采样的泡沫贴图，RGB 分别是厚、中、薄
        public Texture2D defaultSurfaceMap; // 表面细法线，也给焦散当噪声
        public Material defaultSeaMaterial; // 实际绘制海面用的材质
        public Mesh[] defaultWaterMeshes; // 贴在相机前方的多块海面网格
	}
}
