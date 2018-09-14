
#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Uniforms {
    float4x4 projectionMatrix;
    float4x4 modelViewMatrix;
};

struct Vertex {
    float3 position [[attribute(0)]];
    float3 normal   [[attribute(1)]];
    float2 texCoord [[attribute(2)]];
};

struct VertexOut {
    float4 position [[position]];
    float3 eyeNormal;
    float2 texCoord;
};

vertex VertexOut vertex_main(Vertex in [[stage_in]],
                             constant Uniforms & uniforms [[ buffer(1) ]])
{
    VertexOut out;
    float4 position = float4(in.position, 1.0);
    out.position = uniforms.projectionMatrix * uniforms.modelViewMatrix * position;
    out.eyeNormal = (uniforms.modelViewMatrix * float4(in.normal, 0)).xyz;
    out.texCoord = in.texCoord;
    return out;
}

fragment half4 fragment_main(VertexOut in [[stage_in]],
                             texture2d<half, access::sample> texture [[texture(0)]])
{
    constexpr sampler linearSampler(filter::linear);
    half4 baseColor = texture.sample(linearSampler, in.texCoord);
    float3 L = normalize(float3(0, 0, 1)); // light direction in view space
    float3 N = normalize(in.eyeNormal);
    half diffuse = saturate(dot(N, L));
    half3 color = diffuse * baseColor.rgb;
    return half4(color, baseColor.a);
}
