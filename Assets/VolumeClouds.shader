Shader "Hidden/Shader/VolumeClouds"
{
    HLSLINCLUDE

    #pragma target 4.5
    #pragma only_renderers d3d11 playstation xboxone vulkan metal switch

    #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
    #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Color.hlsl"
    #include "Packages/com.unity.render-pipelines.high-definition/Runtime/ShaderLibrary/ShaderVariables.hlsl"
    #include "Packages/com.unity.render-pipelines.high-definition/Runtime/PostProcessing/Shaders/FXAA.hlsl"
    #include "Packages/com.unity.render-pipelines.high-definition/Runtime/PostProcessing/Shaders/RTUpscale.hlsl"
    #include "Packages/com.unity.render-pipelines.high-definition/Runtime/Material/NormalBuffer.hlsl"

    struct Attributes
    {
        uint vertexID : SV_VertexID;
        UNITY_VERTEX_INPUT_INSTANCE_ID
    };

    struct Varyings
    {
        float4 positionCS : SV_POSITION;
        float2 texcoord   : TEXCOORD0;
        float3 viewVector   : TEXCOORD1;
        float3 worlddir   : TEXCOORD2;
        float3 ray   : TEXCOORD3;
        UNITY_VERTEX_OUTPUT_STEREO
    };
    
    float4x4 _CamInvProjMatrix;
    float4x4 _CamToWorldMatrix;

    Varyings Vert(Attributes input)
    {
    
        // Render settings
        float far = _ProjectionParams.z;
        float2 orthoSize = unity_OrthoParams.xy;
        float isOrtho = unity_OrthoParams.w; // 0: perspective, 1: orthographic

        // Vertex ID -> clip space vertex position
        float x = (input.vertexID != 1) ? -1 : 3;
        float y = (input.vertexID == 2) ? -3 : 1;
        float3 vpos = float3(x, y, 1.0);

        // Perspective: view space vertex position of the far plane
        float3 rayPers = mul(_CamInvProjMatrix, vpos.xyzz * far).xyz;

        // Orthographic: view space vertex position
        float3 rayOrtho = float3(orthoSize * vpos.xy, 0);

        Varyings output;
        UNITY_SETUP_INSTANCE_ID(input);
        UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);
        output.positionCS = GetFullScreenTriangleVertexPosition(input.vertexID);
        output.texcoord = (vpos.xy + 1) / 2;
        float2 uv = float2(output.texcoord.xy * 2.0f - 1.0f);
        float3 _viewVector = mul(_CamInvProjMatrix, float4(uv, 0.0f, 1.0f));
        output.viewVector = mul(_CamToWorldMatrix, float4(_viewVector, 0.0f)).xyz;
        
        output.ray = lerp(rayPers, rayOrtho, isOrtho);
        return output;
    }

    // List of properties to control your post process effect
    
    float4 color;
    float3 lightPosition;
    float3 lightDirection;
    float3 MaxBound;
    float3 MinBound;
    float4x4 BoxworldToObject;
    float3 half_size;
    float CameraFar;
    float CameraNear;
    TEXTURE2D_X(_InputTexture);
    TEXTURE2D(_DepthTexture);
    float3 CloudOffset;
    float CloudScale;
    float DensityThreshold;
    float DensityMultiplier;
    int NumSteps;

    Texture3D<float4> ShapeNoise;
    Texture3D<float4> DetailNoise;
            
    SamplerState samplerShapeNoise;
    SamplerState samplerDetailNoise;


	float SampleDensity (float3 position) 
	{
        float3 uvw = position * CloudScale * 0.001+CloudOffset *0.01;
        float4 shape = ShapeNoise.SampleLevel(samplerShapeNoise,uvw,0);
        float density = max(0,shape.r - DensityThreshold) * DensityMultiplier;

        return density;
    }

    bool BoxIntersection (float3 rayOrigin, float3 invRaydir, out float2 Out) 
    {
        float3 o = mul(BoxworldToObject, float4(rayOrigin, 1.0)).xyz; // world to object space
        float3 d = mul((float3x3)BoxworldToObject, invRaydir);
        // ref: https://www.iquilezles.org/www/articles/boxfunctions/boxfunctions.htm
        float3 m = 1.0 / d;
        float3 n = m * o;
        float3 k = abs(m) * half_size;
        float3 t1 = -n - k;
        float3 t2 = -n + k;

        float tN = max(max(t1.x, t1.y), t1.z);
        float tF = min(t2.x, min(t2.y, t2.z));
        
       float dstToBox = max(0, tN);
       float dstInsideBox = max(0, tF - dstToBox);
        Out = float2(dstToBox, dstInsideBox);
        return tN > tF || tF < CameraNear || tN > CameraFar;
    }

    float LinearEye_Depth(float depth, float4 zBufferParam)
    {
        return 1.0 / (zBufferParam.z * depth + zBufferParam.w);
    }

    float LinearToDepth(float linearDepth)
    {
        return (1.0 - _ZBufferParams.w * linearDepth) / (linearDepth * _ZBufferParams.z);
    }

    float lenght(float3 In)
    {
        return sqrt(In.x * In.x + In.y * In.y + In.z * In.z);
	}



    float3 ComputeViewSpacePosition(Varyings input, float depth)
    {
        // Render settings
        float near = _ProjectionParams.y;
        float far = _ProjectionParams.z;
        float isOrtho = unity_OrthoParams.w; // 0: perspective, 1: orthographic

        // Z buffer sample
        float z = depth;

        // Far plane exclusion
        #if !defined(EXCLUDE_FAR_PLANE)
        float mask = 1;
        #elif defined(UNITY_REVERSED_Z)
        float mask = z > 0;
        #else
        float mask = z < 1;
        #endif

        // Perspective: view space position = ray * depth
        float3 vposPers = input.ray * Linear01Depth(z,_ZBufferParams);

        // Orthographic: linear depth (with reverse-Z support)
        #if defined(UNITY_REVERSED_Z)
        float depthOrtho = -lerp(far, near, z);
        #else
        float depthOrtho = -lerp(near, far, z);
        #endif

        // Orthographic: view space position
        float3 vposOrtho = float3(input.ray.xy, depthOrtho);

        // Result: view space position
        return lerp(vposPers, vposOrtho, isOrtho) * mask;
    }

    float3 getNormalWorldSpace(uint2 positionSS, float depth){
        float3 normal = 0;
        if(depth > 0)
        {
            NormalData data;
            const float4 normalbuffer = LOAD_TEXTURE2D_X(_NormalBufferTexture,positionSS); 
            DecodeFromNormalBuffer(normalbuffer,positionSS,data);
            normal = data.normalWS;
		}
        return normal;
	}

    float4 Shadow(float texcoord,float3 rayOrgin,float depth,float3 viewdir,float3 col){
        float3 ro = rayOrgin;
        float3 rd = 1 - lightDirection;
        float2 rayboxinfo = 0;
        bool rayHitBox = BoxIntersection (ro,rd,rayboxinfo);
        float dstToBox = rayboxinfo.x;
        float dstInsideBox = rayboxinfo.y;

        float dstTravelled = 0;
        float stepSize = dstInsideBox / NumSteps;
        float dstLimit = min((dstToBox + dstToBox) - dstToBox,dstInsideBox);

        float totalDensity = 0;

        while (dstTravelled < dstLimit){
            float3 rayPos = ro + rd * (dstToBox + dstTravelled);
            totalDensity += SampleDensity(rayPos) * stepSize;
            dstTravelled += stepSize;
		}
        float transmittance = exp(-totalDensity*7);
        float4 coll = lerp(0, float4(col, 1), transmittance);
        if(LinearEyeDepth(depth, _ZBufferParams) * lenght(viewdir) > CameraFar)
            coll = float4(col, 1);
        return coll;
	}

    float4 CustomPostProcess(Varyings input) : SV_Target
    {
        UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

        uint2 positionSS = input.texcoord * _ScreenSize.xy;
        float3 outColor = LOAD_TEXTURE2D_X(_InputTexture, positionSS).xyz;
        float NonlinearEyeDepth = LoadCameraDepth(positionSS);
        float depth = LinearEyeDepth(NonlinearEyeDepth, _ZBufferParams) * lenght(input.viewVector);
        float3 rayOrgin = _WorldSpaceCameraPos;
        float3 rayDir = normalize(input.viewVector);
        // _dir = raydir;
        //float2 rayboxinfo = rayBoxDst(MinBound,MaxBound,rayOrgin,raydir);
        //float dstInsideBox = rayboxinfo.y;
        // just invert the colors
        //bool rayHitBox = rayboxinfo.y > 0 && rayboxinfo.x < rayboxinfo.y;
        
        float2 rayboxinfo = 0;
        bool rayHitBox = BoxIntersection (rayOrgin,rayDir,rayboxinfo); 
        float dstToBox = rayboxinfo.x;
        float dstInsideBox = rayboxinfo.y;

        float dstTravelled = 0;
        float stepSize = dstInsideBox / NumSteps;
        float dstLimit = min(depth - dstToBox,dstInsideBox);

        float totalDensity = 0;

        while (dstTravelled < dstLimit){
            float3 rayPos = rayOrgin + rayDir * (dstToBox + dstTravelled);
            totalDensity += SampleDensity(rayPos) * stepSize;
            dstTravelled += stepSize;
		}
        float transmittance = exp(-totalDensity);
        float3 vpos = ComputeViewSpacePosition(input, NonlinearEyeDepth);
        float3 wpos = mul(_CamToWorldMatrix, float4(vpos, 1)).xyz;
        float4 col = Shadow(input.texcoord,wpos,NonlinearEyeDepth, input.viewVector,outColor);
        col = lerp(color, col, transmittance);
        return col;
    }

    ENDHLSL

    SubShader
    {
        Pass
        {
            Name "VolumeClouds"

            ZWrite Off
            ZTest Always
            Blend Off
            Cull Off

            HLSLPROGRAM
                #pragma fragment CustomPostProcess
                #pragma vertex Vert
            ENDHLSL
        }
    }
    Fallback Off
}
