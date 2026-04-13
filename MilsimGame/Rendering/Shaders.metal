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

struct World3DVertex {
    float3 position;
    float3 normal;
};

struct World3DInstance {
    float3 position;
    float yaw;
    float3 size;
    float lighting;
    float4 color;
};

struct World3DUniforms {
    float4x4 viewProjectionMatrix;
    float3 cameraPosition;
    float fogStart;
    float3 lightDirection;
    float fogEnd;
    float4 fogColor;
    float4 sunColor;
    float4 ambientColor;
    float4 shadowColor;
    float4 hazeColor;
};

struct World3DRasterizerData {
    float4 position [[position]];
    float3 normal;
    float4 color;
    float fogAmount;
    float3 worldPosition;
    float viewFacing;
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

vertex World3DRasterizerData firstPersonWorldVertex(uint vertexID [[vertex_id]],
                                                    uint instanceID [[instance_id]],
                                                    const device World3DVertex *vertices [[buffer(0)]],
                                                    const device World3DInstance *instances [[buffer(1)]],
                                                    constant World3DUniforms &uniforms [[buffer(2)]]) {
    World3DRasterizerData out;
    World3DVertex cubeVertex = vertices[vertexID];
    World3DInstance instance = instances[instanceID];

    float sy = sin(instance.yaw);
    float cy = cos(instance.yaw);

    float3 scaledPosition = cubeVertex.position * instance.size;
    float3 rotatedPosition = float3(
        scaledPosition.x * cy - scaledPosition.z * sy,
        scaledPosition.y,
        scaledPosition.x * sy + scaledPosition.z * cy
    );
    float3 worldPosition = instance.position + rotatedPosition;

    float3 rotatedNormal = normalize(float3(
        cubeVertex.normal.x * cy - cubeVertex.normal.z * sy,
        cubeVertex.normal.y,
        cubeVertex.normal.x * sy + cubeVertex.normal.z * cy
    ));

    float distanceToCamera = distance(worldPosition, uniforms.cameraPosition);
    float3 viewDirection = normalize(uniforms.cameraPosition - worldPosition);

    out.position = uniforms.viewProjectionMatrix * float4(worldPosition, 1.0);
    out.normal = rotatedNormal;
    out.color = float4(instance.color.rgb * instance.lighting, instance.color.a);
    out.fogAmount = smoothstep(uniforms.fogStart, uniforms.fogEnd, distanceToCamera);
    out.worldPosition = worldPosition;
    out.viewFacing = clamp(dot(rotatedNormal, viewDirection), 0.0, 1.0);
    return out;
}

fragment float4 firstPersonWorldFragment(World3DRasterizerData in [[stage_in]],
                                         constant World3DUniforms &uniforms [[buffer(0)]]) {
    float sunAmount = max(dot(normalize(in.normal), normalize(-uniforms.lightDirection)), 0.0);
    float skyBounce = clamp(in.normal.y * 0.5 + 0.5, 0.0, 1.0);
    float rim = pow(max(1.0 - in.viewFacing, 0.0), 2.0);
    float heightHaze = smoothstep(-0.6, 2.8, in.worldPosition.y);

    float3 ambient = mix(uniforms.shadowColor.rgb, uniforms.ambientColor.rgb, skyBounce);
    float3 litColor = in.color.rgb * ambient;
    litColor += in.color.rgb * uniforms.sunColor.rgb * (0.16 + sunAmount * 0.7);
    litColor += uniforms.hazeColor.rgb * rim * 0.06 * (1.0 - in.fogAmount);
    litColor = clamp(litColor, 0.0, 1.4);

    float hazeMix = clamp(heightHaze * 0.35 + sunAmount * 0.12, 0.0, 1.0);
    float3 fogTarget = mix(uniforms.fogColor.rgb, uniforms.hazeColor.rgb, hazeMix);
    float3 foggedColor = mix(litColor, fogTarget, in.fogAmount);
    return float4(foggedColor, in.color.a);
}
