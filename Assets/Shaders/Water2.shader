Shader "URPPractice/Flow/Water"
{
    Properties
    {
        [MainTexture] _MainTex("Albedo", 2D) = "white" {}
    	
    	// Color
        [MainColor] _BaseColor("Color", Color) = (1,1,1,1)
    	_ShallowColor("ShallowColor", Color) = (1,1,1,1)
    	_HorizonColor("HorizonColor", Color) = (1,1,1,1)
    	_DepthHorizontal("DepthHorizontal",float) = 1
    	
    	
        // Wave
        _WaveDirAB("Wave A(xy) B(zw)",Vector) = (1,1,1,1)
    	_WaveDirCD("Wave C(xy) D(zw)",Vector) = (1,1,1,1)
    	_ALSSWaveA("Amplitude(x),Length(y),Steepness(z),Speed(w)",Vector) = (1,20,0.25,1)
    	_ALSSWaveB("Amplitude(x),Length(y),Steepness(z),Speed(w)",Vector) = (1,20,0.25,1)
    	_ALSSWaveC("Amplitude(x),Length(y),Steepness(z),Speed(w)",Vector) = (1,20,0.25,1)
    	_ALSSWaveD("Amplitude(x),Length(y),Steepness(z),Speed(w)",Vector) = (1,20,0.25,1)
        _WaveCount("WaveCount",float) = 1
    	
        _WaterFogColor ("Water Fog Color", Color) = (0, 0, 0, 0)
		_WaterFogDensity ("Water Fog Density", Range(0, 2)) = 0.1
    	_Depth("Depth",float) = 20
    	_Environment("Environment",Cube) = ""{}
    }

    SubShader
    {
        Tags{"RenderType" = "Transparent" "Queue" = "Transparent" "RenderPipeline" = "UniversalPipeline" "IgnoreProjector" = "True" "ShaderModel"="4.5"}
        LOD 300
        Pass
        {
            Name "Water"
            Tags{"LightMode" = "UniversalForward"}
            
            Blend SrcAlpha OneMinusSrcAlpha
            Cull Off

            HLSLPROGRAM
            #pragma exclude_renderers gles gles3 glcore
            #pragma target 4.5

            // -------------------------------------
            // Universal Pipeline keywords
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            #pragma multi_compile_fragment _ _SCREEN_SPACE_OCCLUSION
            #pragma multi_compile _ LIGHTMAP_SHADOW_MIXING
            #pragma multi_compile _ SHADOWS_SHADOWMASK

            // -------------------------------------
            // Unity defined keywords
            #pragma multi_compile _ DIRLIGHTMAP_COMBINED
            #pragma multi_compile _ LIGHTMAP_ON
            #pragma multi_compile_fog

            //#pragma enable_d3d11_debug_symbols

            #pragma vertex WaterVertex
            #pragma fragment WaterFragment

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
			#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareOpaqueTexture.hlsl"
            #include "Shared/CustomInput.hlsl"
            #include "Shared/Wave.hlsl"
            #include "Shared/Common.hlsl"

            struct Attributes
            {
                float4 positionOS   : POSITION;
                float3 normalOS     : NORMAL;
                float4 tangentOS    : TANGENT;
                float2 texcoord     : TEXCOORD0;
            };

            struct Varyings
            {
                float2 uv                       : TEXCOORD0;
                float3 positionWS               : TEXCOORD2;
                float3 normalWS                 : TEXCOORD3;
                float4 tangentWS                : TEXCOORD4;    // xyz: tangent, w: sign
                float3 viewDirWS                : TEXCOORD5;
                float4 positionCS               : SV_POSITION;
            	float4 screenPos				: TEXCOORD6;
            };

            TEXTURE2D(_MainTex);            SAMPLER(sampler_MainTex);
            TEXTURECUBE(_Environment);            SAMPLER(sampler_Environment);

            CBUFFER_START(UnityPerMaterial)
            float4 _MainTex_ST;
            //half4 _BaseColor;
            //float4 _WaveA,_WaveB,_WaveC,_WaveD;
			float4 _WaterFogColor;
            float _WaterFogDensity,_Depth,_A;
            // float4 _WaveDirAB,_WaveDirCD,_ALSSWaveA,_ALSSWaveB,_ALSSWaveC,_ALSSWaveD;
            // float _WaveCount;
            half4 _BaseColor,_ShallowColor,_HorizonColor;
            float _DepthHorizontal;
            CBUFFER_END

            void InitializeInputData(Varyings input, half3 normalTS, out SimpleInputData inputData)
            {                
                inputData = (SimpleInputData)0;

                inputData.positionWS = input.positionWS;
                half3 viewDirWS = SafeNormalize(input.viewDirWS);
                float sgn = input.tangentWS.w;      // should be either +1 or -1
                float3 bitangent = sgn * cross(input.normalWS.xyz, input.tangentWS.xyz);
                inputData.normalWS = normalize(TransformTangentToWorld(normalTS, half3x3(input.tangentWS.xyz, bitangent.xyz, input.normalWS.xyz)));
                //inputData.normalWS = NormalizeNormalPerPixel(inputData.normalWS);
                inputData.viewDirectionWS = viewDirWS;
            }

            half3 SampleNormal(float2 uv, TEXTURE2D_PARAM(bumpMap, sampler_bumpMap), half scale = 1.0h)
            {
                half4 n = SAMPLE_TEXTURE2D(bumpMap, sampler_bumpMap, uv);
                return normalize(UnpackNormalScale(n, scale));
            }   

            inline void InitializeStandardLitSurfaceData(float2 uv, out SimpleSurfaceData outSurfaceData)
            {
                outSurfaceData.alpha = _BaseColor.a;
            	//outSurfaceData.albedo = SAMPLE_TEXTURE2D(_MainTex,sampler_MainTex,uv).xyz;
            	outSurfaceData.albedo = _BaseColor.rgb * (SAMPLE_TEXTURE2D(_MainTex,sampler_MainTex,uv).xyz);
                outSurfaceData.normalTS = float3(0,0,1);
            }

            ///////////////////////////////////////////////////////////////////////////////
            //                  Vertex and Fragment functions                            //
            ///////////////////////////////////////////////////////////////////////////////

            // Used in Standard (Physically Based) shader
            Varyings WaterVertex(Attributes input)
            {
                Varyings output = (Varyings)0;

            	// ***************** Wave **************************
                float3 p = input.positionOS.xyz;
            	float3 normal = float3(0,1,0);
				GerstnelWaveOffset(p);
            	GerstnelWaveNormal(normal,p);

            	//float4 freq = float4(2*PI/_WaveLength);
				//p = GerstnerOffset4(p.uv,_Steepness,_Amplitude,freq,_Speed,_WaveDirAB,_WaveDirCD);
            	//p = GerstnerOffset4(input.texcoord,_Steepness,_Amplitude,freq,_Speed,_WaveDirAB,_WaveDirCD);
            	//p += GerstnerWave(_WaveB, gridPoint, tangent, binormal);
                //p += GerstnerWave(_WaveC, gridPoint, tangent, binormal);
                //p += GerstnerWave(_WaveD, gridPoint, tangent, binormal);
                //float3 normal = normalize(cross(binormal,tangent));
            	
            	

            	VertexPositionInputs vertexInput = GetVertexPositionInputs(p.xyz);
            	//VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS.xyz);
                //VertexNormalInputs normalInput = GetVertexNormalInputs(normal, float4(tangent,1));
				half3 viewDirWS = GetWorldSpaceViewDir(vertexInput.positionWS);
                output.uv = TRANSFORM_TEX(input.texcoord, _MainTex);
                output.normalWS = TransformObjectToWorldNormal(normal);
                output.viewDirWS = viewDirWS;
                output.positionWS = vertexInput.positionWS;
                output.positionCS = vertexInput.positionCS;
                //output.tangentWS.xyz = normalInput.tangentWS;
                output.tangentWS.w = input.tangentOS.w;
            	output.screenPos = ComputeScreenPos(output.positionCS);

                return output;
            }

            // Used in Standard (Physically Based) shader
            half4 WaterFragment(Varyings input) : SV_Target
            {
                SimpleSurfaceData surfaceData;
                InitializeStandardLitSurfaceData(input.uv, surfaceData);

                SimpleInputData inputData;
                InitializeInputData(input, surfaceData.normalTS, inputData);

            	float3 normalWS = normalize(input.normalWS);

            	// ************** Color ***********************
				float3 viewDir = (_WorldSpaceCameraPos - input.positionWS);
				float3 viewDirNorm = SafeNormalize(viewDir);
            	//return float4(viewDir, 1);

            	SceneDepth dep = SampleDepth(input.screenPos);
				float3 opaqueWorldPos = ReconstructViewPos(input.screenPos, viewDir, dep);

				float normalSign = ceil(dot(viewDirNorm, normalWS));
				normalSign = normalSign == 0 ? -1 : 1;
            	float opaqueDist = DepthDistance(inputData.positionWS,opaqueWorldPos,normalWS * normalSign);
            	return half4(opaqueDist,opaqueDist,opaqueDist,1);	
            	float heightAttenuation = opaqueDist * _DepthHorizontal;

            	// ************** Water Fog *******************
                float2 UV = input.positionCS.xy / _ScaledScreenParams.xy;
                #if UNITY_REVERSED_Z
                    real depth = SampleSceneDepth(UV);
                #else
                    // Adjust Z to match NDC for OpenGL ([-1, 1])
                        real depth = lerp(UNITY_NEAR_CLIP_VALUE, 1, SampleSceneDepth(UV));
                #endif
                depth = LinearEyeDepth(depth,_ZBufferParams);
                //float waterDepth = UNITY_Z_0_FAR_FROM_CLIPSPACE(IN.positionHCS.z);
                float waterDepth = LinearEyeDepth(lerp(UNITY_NEAR_CLIP_VALUE, 1, input.positionCS.z),_ZBufferParams);
                float depthDifference = depth - waterDepth;
            	depthDifference/=_Depth;
                float4 backgroundColor = float4(SampleSceneColor(UV).xyz,1);
                float fogFactor = exp2(-_WaterFogDensity * depthDifference);
	            half3 color =lerp(_WaterFogColor, backgroundColor, fogFactor).xyz;

				// ************** refraction & reflection ********************
            	float3 ViewDirWS = GetWorldSpaceViewDir(input.positionWS);
                float3 relectionDir = reflect(-ViewDirWS,input.normalWS);
            	//float3 relectionDir = reflect(-ViewDirWS,normalize(float3(0,1,0)));
            	half3 reflectionColor = SAMPLE_TEXTURECUBE(_Environment,sampler_Environment,relectionDir);
            	float f0 = 0.3;
            	float fresnel = f0+(1-f0)*pow(1-saturate(dot(ViewDirWS,inputData.normalWS)),5);
            	color = lerp(backgroundColor,reflectionColor,fresnel);
            	
				
            	//half4 color = half4(depthDifference,depthDifference,depthDifference,0.1);
            	//return half4(input.normalWS,_BaseColor.a);
                //return half4(color,_BaseColor.a);
                //return half4(reflectionColor,_BaseColor.a);
                //return float4(depthDifference,depthDifference,depthDifference,1);
            	//return float4(fogFactor,fogFactor,fogFactor,1);
                //return float4(surfaceData.albedo,_BaseColor.a);
            	//return float4(fresnel,fresnel,fresnel,_BaseColor.a);
            	//return float4(ViewDirWS,_BaseColor.a);
            	//return float4(0.5,0.5,0.5,1);
            	//return float4(heightAttenuation,heightAttenuation,heightAttenuation,1);
            	//return float4(inputData.positionWS,1);
            }

            ENDHLSL
        }
//        Pass
//        {
//            Name "DepthOnly"
//            Tags{"LightMode" = "DepthOnly"}
//
//            ZWrite On
//            ColorMask 0
//            Cull[_Cull]
//
//            HLSLPROGRAM
//            #pragma exclude_renderers gles gles3 glcore
//            #pragma target 4.5
//
//            #pragma vertex DepthOnlyVertex
//            #pragma fragment DepthOnlyFragment
//
//            // -------------------------------------
//            // Material Keywords
//            #pragma shader_feature_local_fragment _ALPHATEST_ON
//            #pragma shader_feature_local_fragment _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A
//
//            //--------------------------------------
//            // GPU Instancing
//            #pragma multi_compile_instancing
//            #pragma multi_compile _ DOTS_INSTANCING_ON
//
//            #include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"
//            #include "Packages/com.unity.render-pipelines.universal/Shaders/DepthOnlyPass.hlsl"
//            ENDHLSL
//        }

    }
	//CustomEditor "Yamyii.CustomWaterUI"
    FallBack "Hidden/Universal Render Pipeline/FallbackError"
}
