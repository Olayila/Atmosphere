// VolumeFogBoundsController.cs
// 挂载在这个 GameObject 上，它代表体积雾的包围盒
// 在 Edit Mode 下实时计算并传递 boundsMin / boundsMax 给 Render Feature

using UnityEngine;
using UnityEngine.Rendering.Universal;

[ExecuteInEditMode]                  // 允许在编辑器中运行（不进入 Play 模式也能更新）
[RequireComponent(typeof(Transform))] // 必须有 Transform
public class VolumeCube : MonoBehaviour
{
    [Header("目标 Renderer Feature")]
    [Tooltip("把这个组件拖到你的 VolumeFogRendererFeature 实例上")]
    [SerializeField]
    private VolumeFogRendererFeature targetFeature;
    [SerializeField]
    private UniversalRendererData rendererData;  // ← 拖这个 Asset
  

    private Vector3 boundsMin;  
    private Vector3 boundsMax;

    // 只在 Inspector 显示，不允许修改
    [System.Serializable]
    private class ReadOnlyAttribute : PropertyAttribute { }
#if UNITY_EDITOR
    private class ReadOnlyDrawer : UnityEditor.PropertyDrawer
    {
        public override void OnGUI(Rect position, UnityEditor.SerializedProperty property, GUIContent label)
        {
            GUI.enabled = false;
            UnityEditor.EditorGUI.PropertyField(position, property, label, true);
            GUI.enabled = true;
        }
    }
#endif

    private void OnValidate()
    {
        // 组件刚挂上或 Inspector 修改时触发
        FindFeature();
        // UpdateBoundsAndPassToFeature();
    }

    private void Update()
    {

        // Edit Mode 下没有 Update，所以我们用 LateUpdate 或直接在 OnValidate 已经够了
        // 但如果你希望场景中拖动物体时实时更新，也可以保留
        if (!Application.isPlaying)
        {
            //UpdateBoundsAndPassToFeature();
            //Debug.Log("更新bounds信息");
        }
    }

    private void LateUpdate()
    {
        boundsMin = transform.position - transform.localScale / 2;
        boundsMax = transform.position + transform.localScale / 2;
        //Debug.Log("边界位置"+boundsMin+ "边界位置" + boundsMax);
        // Play 模式下如果需要实时跟随，也可以用 LateUpdate
        UpdateBoundsAndPassToFeature();
    }

    private void UpdateBoundsAndPassToFeature()
    {
        

        // 计算当前物体的 AABB（世界空间）
        //Vector3 center = transform.position;
        //Vector3 halfSize = transform.localScale * 0.5f;

        //Vector3 min = center - halfSize;
        //Vector3 max = center + halfSize;

        //boundsMin = min;
        //boundsMax = max;

        // 传递给 Feature（假设你的 Feature 有公开方法或字段）
        targetFeature.SetFogBounds(boundsMin, boundsMax);
    }
    private void FindFeature()
    {
        if (rendererData == null) return;

        foreach (var feature in rendererData.rendererFeatures)
        {
            if (feature is VolumeFogRendererFeature vf)
            {
                targetFeature = vf;
                return;
            }
        }

        Debug.LogWarning("在 RendererData 中找不到 VolumeFogRendererFeature", this);
    }

#if UNITY_EDITOR
    // 在 Scene 视图画出包围盒，便于调试
    //private void OnDrawGizmos()
    //{
    //    if (targetFeature == null) return;

    //    Gizmos.color = new Color(0.2f, 0.8f, 1.0f, 0.4f);
    //    Gizmos.matrix = Matrix4x4.identity;

    //    Vector3 center = (boundsMin + boundsMax) * 0.5f;
    //    Vector3 size = boundsMax - boundsMin;

    //    Gizmos.DrawWireCube(center, size);
    //    Gizmos.color = new Color(0.2f, 0.8f, 1.0f, 0.15f);
    //    //Gizmos.DrawCube(center, size);
    //}
#endif
}