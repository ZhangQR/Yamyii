#ifndef CUSTOM_INPUT_INCLUDED
#define CUSTOM_INPUT_INCLUDED
struct SimpleInputData
{
    float3  positionWS;
    half3   normalWS;
    half3   viewDirectionWS;
};

struct SimpleSurfaceData
{
    half3 albedo;
    half3 normalTS;
    half  alpha;
};
#endif