#ifndef Wave_INCLUDED
#define Wave_INCLUDED

#define WAVE_COUNT _WaveCount
#define MAX_WAVE_COUNT 4

//CBUFFER_START(UnityPerMaterial)
float4 _WaveDirAB,_WaveDirCD,_ALSSWaveA,_ALSSWaveB,_ALSSWaveC,_ALSSWaveD;
float _WaveCount; 
//CBUFFER_END

struct Wave
{
    float Length;    // 波长，波峰到波峰的距离，角速度 Ω=2pi/L
    float Amplitude;    // 振幅
    float Phi;    // 相常数 Phi=S*2pi/L, S 为速度，每秒钟波峰移动的距离
    float2 Dir;   // 方向，与波阵面垂直
    float steepness;    // 陡度
};

void GerstnelSingleWave(inout float3 position,Wave wave)
{
    float t = -_Time.y;
    wave.Dir = normalize(wave.Dir);
    float fre = sqrt(2 * 9.8 * PI / wave.Length);
    float x = wave.steepness * wave.Amplitude * wave.Dir.x * cos(fre * dot(wave.Dir,position.xz) + wave.Phi*t);
    float z = wave.steepness * wave.Amplitude * wave.Dir.y * cos(fre * dot(wave.Dir,position.xz) + wave.Phi*t);
    float y = wave.Amplitude * sin(fre * dot(wave.Dir,position.xz)+wave.Phi*t);
    position += float3(x,y,z);
}


inline Wave GetWave(float4 alss,float2 dir)
{
    Wave wave;
    wave.Dir = dir;
    wave.Amplitude = alss.x;
    wave.Length = alss.y;
    wave.steepness = alss.z;
    wave.Phi = alss.w * 2 * PI / alss.y;
    return wave;
}

inline Wave GetWaveA()
{
     return GetWave(_ALSSWaveA,_WaveDirAB.xy);
}
inline Wave GetWaveB()
{
    return GetWave(_ALSSWaveB,_WaveDirAB.zw);
}
inline Wave GetWaveC()
{
    return GetWave(_ALSSWaveC,_WaveDirCD.xy);
}
inline Wave GetWaveD()
{
    return GetWave(_ALSSWaveD,_WaveDirCD.zw);
}

void GerstnelSingleWaveNormal(inout float3 normal,float3 position,Wave wave)
{
    float t = -_Time.y;
    //wave.Dir = normalize(wave.Dir);
    float2 p = position.xz;
    float fre = sqrt(2 * 9.8 * PI / wave.Length);
    float WA = fre * wave.Amplitude;
    // float SIN = sin(fre * dot(wave.Dir,p) + wave.Phi * t);
    float COS = cos(fre * dot(wave.Dir,p) + wave.Phi * t);
    normal.x -= wave.Dir.x * WA * COS;
    normal.z -= wave.Dir.y * WA * COS;
    //normal.y -= wave.steepness * WA * SIN;
    normal = normalize(normal);
}

// waveA: Amplitude(x),Length(y),Steepness(z),Speed(w)
void GerstnelWaveOffset(inout float3 position)
{   
    GerstnelSingleWave(position,GetWaveA());
    GerstnelSingleWave(position,GetWaveB());
    GerstnelSingleWave(position,GetWaveC());
    GerstnelSingleWave(position,GetWaveD());
}

// waveA: Amplitude(x),Length(y),Steepness(z),Speed(w)
void GerstnelWaveNormal(inout float3 normal,float3 position)
{   
    GerstnelSingleWaveNormal(normal,position,GetWaveA());
    GerstnelSingleWaveNormal(normal,position,GetWaveB());
    GerstnelSingleWaveNormal(normal,position,GetWaveC());
    GerstnelSingleWaveNormal(normal,position,GetWaveD());
}
#endif
