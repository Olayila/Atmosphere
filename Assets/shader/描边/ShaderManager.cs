using System.Collections;
using System.Collections.Generic;
using UnityEngine;

//[ExecuteInEditMode]
public class ShaderManager : MonoBehaviour
{
    public Material material;
    
    // Start is called before the first frame update
    void Start()
    {
        MeshRenderer renderer = GetComponent<MeshRenderer>();
        Bounds bounds = renderer.bounds;
        float minHeight = bounds.min.y;
        float maxHeight = bounds.max.y;
        Debug.Log($"MinHeight: {minHeight}, MaxHeight: {maxHeight}");
        //Material material = GetComponent<Renderer>().material;
        material.SetFloat("_MINH", minHeight);
        material.SetFloat("_MAXH", maxHeight);
    }

    // Update is called once per frame
    void Update()
    {

        MeshRenderer renderer = GetComponent<MeshRenderer>();
        Bounds bounds = renderer.bounds;
        float minHeight = bounds.min.y;
        float maxHeight = bounds.max.y;
        

        Debug.Log($"MinHeight: {minHeight}, MaxHeight: {maxHeight}");
        Material material = GetComponent<Renderer>().material;
        material.SetFloat("_MINH", minHeight);
        material.SetFloat("_MAXH", maxHeight);
    }
}
