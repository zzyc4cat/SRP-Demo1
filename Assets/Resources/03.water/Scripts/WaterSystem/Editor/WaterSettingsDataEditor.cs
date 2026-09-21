using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEditor;
using UnityEditorInternal;

namespace WaterSystem.Data
{
    /// <summary>
    /// 反射类型用工具栏切换，平面反射才展开分辨率和裁剪偏移。
    /// </summary>
    [CustomEditor(typeof(WaterSettingsData))]
    public class WaterSettingsDataEditor : Editor
    {
		public override void OnInspectorGUI()
        {
			var geomType = serializedObject.FindProperty("waterGeomType");
			EditorGUILayout.PropertyField(geomType);

			var refType = serializedObject.FindProperty("refType");
			refType.enumValueIndex = GUILayout.Toolbar(refType.enumValueIndex, refType.enumDisplayNames);

			switch(refType.enumValueIndex)
			{
				case 0:
				{
					var cube = serializedObject.FindProperty("cubemapRefType");
					EditorGUILayout.PropertyField(cube, new GUIContent("Cubemap Texture"));
				}
				break;
				case 1:
				{
					EditorGUILayout.HelpBox("Reflection Probe setting has no options, it automatically uses the nearest reflection probe to the main camera", MessageType.Info);
				}
				break;
				case 2:
				{
					var planarSettings = serializedObject.FindProperty("planarSettings");
					EditorGUILayout.PropertyField(planarSettings, true);
				}
				break;
			}

			serializedObject.ApplyModifiedProperties();
		}
	}
}
