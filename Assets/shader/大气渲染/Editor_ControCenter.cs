using UnityEngine;
using UnityEditor;
using System.IO;

//给ControlCenter的editor文件，提供更新场景和debug内容
[CustomEditor(typeof(ControlCenter))]
public class Editor_ControCenter : Editor
{
    private SerializedProperty saveFileName;
    private SerializedProperty saveAsHDR;
    private SerializedProperty saveWidth;
    private SerializedProperty saveHeight;

    // 添加对RenderTexture的SerializedProperty引用
    private SerializedProperty transmittanceLutRT;   
    private SerializedProperty skyScatterRT;
    private SerializedProperty aerialLutRT;
   /// <summary>
   /// 绑定editor与controlcenter中的相关属性，方便编辑
   /// </summary>
    private void OnEnable()
    {
        saveFileName = serializedObject.FindProperty("saveFileName");
        saveAsHDR = serializedObject.FindProperty("saveAsHDR");


        saveWidth = serializedObject.FindProperty("saveWidth");
        saveHeight = serializedObject.FindProperty("saveHeight");

        // 获取RenderTexture的SerializedProperty
        transmittanceLutRT = serializedObject.FindProperty("transmittanceLut");
        skyScatterRT = serializedObject.FindProperty("skyScatterRT");
        aerialLutRT = serializedObject.FindProperty("aerialLutRT");
        
    }

    public override void OnInspectorGUI()
    {
        // 绘制默认的Inspector
        DrawDefaultInspector();

        EditorGUILayout.Space(20);
        EditorGUILayout.LabelField("场景更新控制", EditorStyles.boldLabel);

        EditorGUILayout.Space(10);
        ControlCenter script = (ControlCenter)target;

        if (GUILayout.Button("加载预计算与模板", GUILayout.Height(30)))
        {
            script.Func_LoadPrecomputeTex($"{script.saveFileName}_TransmittanceLUT", saveWidth.intValue / 2, saveHeight.intValue / 4, rt =>
            {
                if (rt != null)
                {
                    script.transmittanceLutRT = rt;
                    Debug.Log("LUT 加载成功，已设置全局纹理");
                }
                else
                {
                    Debug.LogWarning("加载失败，启动实时计算");
                    script.Func_ComputeTransmittanceLut();

                }
            });
        }
        EditorGUILayout.Space(5);
        if (GUILayout.Button("保存Aerial LUT", GUILayout.Height(25)))
        {
            var aerialValue = aerialLutRT.objectReferenceValue as RenderTexture;
            if (aerialValue != null)
            {
                script.SaveSpecificRT(aerialValue, $"{script.saveFileName}_AerialLUT");
            }
            else
            {
                EditorUtility.DisplayDialog("错误", "Aerial LUT为空！", "确定");
            }
        }

        // 打开保存文件夹的按钮
        EditorGUILayout.Space(10);

        // 说明文本
        EditorGUILayout.Space(10);
        EditorGUILayout.HelpBox(
            "保存说明：\n" +
            "• 保存当前天空盒：保存最终渲染的天空盒\n" +
            "• 保存LUT：保存各个计算阶段的RenderTexture\n" +
            "• 文件保存在 Assets/SavedSkyboxes/ 文件夹中",
            MessageType.Info
        );
    }

    
}
