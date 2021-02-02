using UnityEngine;
using UnityEngine.SceneManagement;
using UnityEngine.Rendering;
using UnityEngine.Rendering.HighDefinition;
using System;
using System.Linq;

[Serializable, VolumeComponentMenu("Post-processing/CloudsRenderTest")]
public sealed class CloudsRenderTest : CustomPostProcessVolumeComponent, IPostProcessComponent
{
    public TextureParameter ShapeNoise = new TextureParameter(null, true);
    public TextureParameter DetailNoise = new TextureParameter(null, true);
    public Vector3Parameter CloudOffset = new Vector3Parameter(Vector3.zero, true);
    public FloatParameter CloudScale = new FloatParameter(0.5f, true);
    public FloatParameter DensityThreshold = new FloatParameter(0.5f, true);
    public FloatParameter DensityMultiplier = new FloatParameter(0.5f, true);
    public IntParameter NumSteps = new IntParameter(100, true);
    public FloatParameter UpdateSpeed = new FloatParameter(0.5f, true);
    public ColorParameter color = new ColorParameter(Color.white, true);
    Transform Container;
    Material m_Material;
    Vector3 v;
    public bool IsActive() => m_Material != null && ShapeNoise.value != null && DetailNoise.value != null;
    float delta;
    // Do not forget to add this post process in the Custom Post Process Orders list (Project Settings > HDRP Default Settings).
    public override CustomPostProcessInjectionPoint injectionPoint => CustomPostProcessInjectionPoint.AfterPostProcess;

    const string kShaderName = "Hidden/Shader/VolumeClouds";

    public override void Setup()
    {
        delta = Time.time;
        if (Shader.Find(kShaderName) != null)
            m_Material = new Material(Shader.Find(kShaderName));
        else
            Debug.LogError($"Unable to find shader '{kShaderName}'. Post Process Volume CloudsRenderTest is unable to load.");
    }

    public override void Render(CommandBuffer cmd, HDCamera camera, RTHandle source, RTHandle destination)
    {
        delta = Time.time - delta;
        if (GameObject.Find("Volume_Container") == null && Container == null)
        {
            Container = new GameObject("Volume_Container").transform;
            Container.position = Vector3.zero;
        }
        else
            Container = GameObject.Find("Volume_Container").transform;
        if (m_Material == null || ShapeNoise.value == null || DetailNoise.value == null || Container == null || camera.camera.cameraType == CameraType.Preview)
            return;

        m_Material.SetTexture("_InputTexture", source);
        m_Material.SetVector("color", color.value);
        m_Material.SetTexture("ShapeNoise", ShapeNoise.value);
        m_Material.SetTexture("DetailNoise", DetailNoise.value);
        m_Material.SetVector("MinBound", Container.position - Container.localScale / 2f);
        m_Material.SetVector("MaxBound", Container.position + Container.localScale / 2f);
        m_Material.SetMatrix("BoxworldToObject", Container.worldToLocalMatrix);
        m_Material.SetVector("half_size", Container.localScale / 2);
        m_Material.SetFloat("CameraFar", camera.camera.farClipPlane);
        m_Material.SetFloat("CameraNear", camera.camera.nearClipPlane);
        m_Material.SetMatrix("_CamToWorldMatrix", camera.camera.cameraToWorldMatrix);
        m_Material.SetMatrix("_CamInvProjMatrix", camera.camera.projectionMatrix.inverse);
        v += new Vector3(UnityEngine.Random.Range(-1f,1f) * Time.deltaTime, 0, UnityEngine.Random.value * UpdateSpeed.value * Time.deltaTime);
        m_Material.SetVector("CloudOffset", v);
        m_Material.SetFloat("CloudScale", CloudScale.value);
        m_Material.SetFloat("DensityThreshold", DensityThreshold.value);
        m_Material.SetFloat("DensityMultiplier", DensityMultiplier.value);
        m_Material.SetInt("NumSteps", NumSteps.value);
        m_Material.SetVector("lightDirection", Light.GetLights(LightType.Directional,0)[0].transform.forward);
        HDUtils.DrawFullScreen(cmd, m_Material, destination);

        delta = Time.time;
    }

    public override void Cleanup()
    {
        CoreUtils.Destroy(m_Material);
    }
}
