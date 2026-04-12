#include <metal_stdlib>
using namespace metal;

struct InstanceData {
    float2 position;
    float2 size;
    float4 color;
    float rotation;
    uint shape;
    float2 padding;
};

struct RenderUniforms {
    float2 camera;
    float2 worldViewport;
};

struct RasterizerData {
    float4 position [[position]];
    float4 color;
    float2 localPosition;
    uint shape;
};

vertex RasterizerData instancedVertex(uint vertexID [[vertex_id]],
                                      uint instanceID [[instance_id]],
                                      const device float2 *quadVertices [[buffer(0)]],
                                      const device InstanceData *instances [[buffer(1)]],
                                      constant RenderUniforms &uniforms [[buffer(2)]]) {
    RasterizerData out;
    float2 quad = quadVertices[vertexID];
    InstanceData instance = instances[instanceID];

    float s = sin(instance.rotation);
    float c = cos(instance.rotation);
    float2 rotated = float2((quad.x * c) - (quad.y * s), (quad.x * s) + (quad.y * c));
    float2 worldPosition = instance.position + (rotated * instance.size);

    float2 clip = (worldPosition - uniforms.camera) / (uniforms.worldViewport * 0.5);
    clip.y = -clip.y;

    out.position = float4(clip, 0.0, 1.0);
    out.color = instance.color;
    out.localPosition = quad;
    out.shape = instance.shape;
    return out;
}

fragment float4 instancedFragment(RasterizerData in [[stage_in]]) {
    float alpha = in.color.a;

    if (in.shape == 1) {
        float distanceToCenter = length(in.localPosition);
        alpha *= smoothstep(0.52, 0.46, distanceToCenter);
    } else if (in.shape == 2) {
        float distanceToCenter = length(in.localPosition);
        float outer = smoothstep(0.53, 0.46, distanceToCenter);
        float inner = smoothstep(0.34, 0.39, distanceToCenter);
        alpha *= max(outer - inner, 0.0);
    }

    return float4(in.color.rgb, alpha);
}

