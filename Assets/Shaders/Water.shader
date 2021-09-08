Shader "URPPractice/Flow/Water"
{
    Properties
    {
        [MainTexture] _MainTex("Albedo", 2D) = "white" {}
        [MainColor] _BaseColor("Color", Color) = (1,1,1,1)
        _WaveA ("Wave A (dir, steepness(0,1), wavelength)", Vector) = (1,0,0.5,10)
        _WaveB ("Wave B", Vector) = (0,1,0.25,20)   // 两个波 steepness 不能超过 1
        _WaterFogColor ("Water Fog Color", Color) = (0, 0, 0, 0)
		_WaterFogDensity ("Water Fog Density", Range(0, 2)) = 0.1
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

            #pragma enable_d3d11_debug_symbols

            #pragma vertex WaterVertex
            #pragma fragment WaterFragment

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
			#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareOpaqueTexture.hlsl"
            #include "Shared/CustomInput.hlsl"

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
            };

            TEXTURE2D(_MainTex);            SAMPLER(sampler_MainTex);

            CBUFFER_START(UnityPerMaterial)
            float4 _MainTex_ST;
            half4 _BaseColor;
            float4 _WaveA,_WaveB,_WaveC,_WaveD;
			float4 _WaterFogColor;
            float _WaterFogDensity;
            CBUFFER_END

            void InitializeInputData(Varyings input, half3 normalTS, out SimpleInputData inputData)
            {                
                inputData = (SimpleInputData)0;

                inputData.positionWS = input.positionWS;
                half3 viewDirWS = SafeNormalize(input.viewDirWS);
                float sgn = input.tangentWS.w;      // should be either +1 or -1
                float3 bitangent = sgn * cross(input.normalWS.xyz, input.tangentWS.xyz);
                inputData.normalWS = TransformTangentToWorld(normalTS, half3x3(input.tangentWS.xyz, bitangent.xyz, input.normalWS.xyz));
                inputData.normalWS = NormalizeNormalPerPixel(inputData.normalWS);
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
            	outSurfaceData.albedo = _BaseColor.rgb * (SAMPLE_TEXTURE2D(_MainTex,sampler_MainTex,uv).xyz*0.1+0.9);
                outSurfaceData.normalTS = float3(0,0,1);
            }

            float3 GerstnerWave (
			float4 wave, float3 p, inout float3 tangent, inout float3 binormal)
			{
		        float steepness = wave.z;
		        float wavelength = wave.w;
		        float k = 2 * PI / wavelength;
			    float c = sqrt(9.8 / k);
			    float2 d = normalize(wave.xy);
			    float f = k * (dot(d, p.xz) - c * _Time.y);
			    float a = steepness / k;
			    
			    //p.x += d.x * (a * cos(f));
			    //p.y = a * sin(f);
			    //p.z += d.y * (a * cos(f));

			    tangent += float3(
				    -d.x * d.x * (steepness * sin(f)),
				    d.x * (steepness * cos(f)),
				    -d.x * d.y * (steepness * sin(f))
			    );
			    binormal += float3(
				    -d.x * d.y * (steepness * sin(f)),
				    d.y * (steepness * cos(f)),
				    -d.y * d.y * (steepness * sin(f))
			    );
			    return float3(
				    d.x * (a * cos(f)),
				    a * sin(f),
				    d.y * (a * cos(f))
			    );
		    }

            ///////////////////////////////////////////////////////////////////////////////
            //                  Vertex and Fragment functions                            //
            ///////////////////////////////////////////////////////////////////////////////

            // Used in Standard (Physically Based) shader
            Varyings WaterVertex(Attributes input)
            {
                Varyings output = (Varyings)0;
                float3 gridPoint = input.positionOS.xyz;
			    float3 tangent = float3(1, 0, 0);
			    float3 binormal = float3(0, 0, 1);
			    float3 p = gridPoint;
			    p += GerstnerWave(_WaveA, gridPoint, tangent, binormal);
                p += GerstnerWave(_WaveB, gridPoint, tangent, binormal);
                //p += GerstnerWave(_WaveC, gridPoint, tangent, binormal);
                //p += GerstnerWave(_WaveD, gridPoint, tangent, binormal);
                float3 normal = normalize(cross(binormal,tangent));
                VertexPositionInputs vertexInput = GetVertexPositionInputs(p.xyz);
                VertexNormalInputs normalInput = GetVertexNormalInputs(normal, float4(tangent,1));
				half3 viewDirWS = GetWorldSpaceViewDir(vertexInput.positionWS);
                output.uv = TRANSFORM_TEX(input.texcoord, _MainTex);
                output.normalWS = normalInput.normalWS;
                output.viewDirWS = viewDirWS;
                output.positionWS = vertexInput.positionWS;
                output.positionCS = vertexInput.positionCS;
                output.tangentWS.xyz = normalInput.tangentWS;
                output.tangentWS.w = input.tangentOS.w;

                return output;
            }

            // Used in Standard (Physically Based) shader
            half4 WaterFragment(Varyings input) : SV_Target
            {
                SimpleSurfaceData surfaceData;
                InitializeStandardLitSurfaceData(input.uv, surfaceData);

                SimpleInputData inputData;
                InitializeInputData(input, surfaceData.normalTS, inputData);

				// To calculate the UV coordinates for sampling the depth buffer,
                // divide the pixel location by the render target resolution
                // _ScaledScreenParams.
                float2 UV = input.positionCS.xy / _ScaledScreenParams.xy;

                // Sample the depth from the Camera depth texture.
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
            	//depthDifference/=20;

                float4 backgroundColor = float4(SampleSceneColor(UV).xyz,1);
                float fogFactor = exp2(-_WaterFogDensity * depthDifference);
	            half3 color =lerp(_WaterFogColor, backgroundColor, fogFactor).xyz;
                //half4 color = half4(depthDifference,depthDifference,depthDifference,0.1);
                return half4(color,_BaseColor.a);
                //return float4(depthDifference,depthDifference,depthDifference,1);
            	//return float4(fogFactor,fogFactor,fogFactor,1);
                //return float4(surfaceData.albedo,);
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

    FallBack "Hidden/Universal Render Pipeline/FallbackError"
}
