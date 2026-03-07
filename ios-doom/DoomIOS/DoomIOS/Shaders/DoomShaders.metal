/*
 * DoomShaders.metal
 *
 * Minimal Metal shaders for rendering the Doom 320×200 framebuffer
 * to the full screen with nearest-neighbour (pixel-perfect) filtering.
 *
 * The vertex shader generates a fullscreen quad from vertex IDs —
 * no vertex buffer required. UV [0,0] is top-left, [1,1] is bottom-right
 * to match the Doom framebuffer layout.
 */

#include <metal_stdlib>
using namespace metal;

// ─── Structures ──────────────────────────────────────────────────────────────

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

// ─── Vertex Shader ────────────────────────────────────────────────────────────

/*
 * Produces a fullscreen triangle-pair (2 triangles = 6 vertices) covering
 * clip-space [-1,1]×[-1,1]. No vertex buffer is needed — vertex IDs 0-5
 * are used directly.
 *
 * Clip-space Y is flipped vs texture V, so UV.y = 1 - clip-y/2.
 */
vertex VertexOut doom_vertex(uint vid [[vertex_id]]) {
    // Two triangles covering NDC space
    constexpr float2 positions[6] = {
        { -1.0f, -1.0f },   // bottom-left
        {  1.0f, -1.0f },   // bottom-right
        { -1.0f,  1.0f },   // top-left
        {  1.0f, -1.0f },   // bottom-right
        {  1.0f,  1.0f },   // top-right
        { -1.0f,  1.0f },   // top-left
    };
    // UV: top-left = (0,0), bottom-right = (1,1)
    // NDC y=+1 → top of screen → UV.y=0
    constexpr float2 uvs[6] = {
        { 0.0f, 1.0f },
        { 1.0f, 1.0f },
        { 0.0f, 0.0f },
        { 1.0f, 1.0f },
        { 1.0f, 0.0f },
        { 0.0f, 0.0f },
    };

    VertexOut out;
    out.position = float4(positions[vid], 0.0f, 1.0f);
    out.uv       = uvs[vid];
    return out;
}

// ─── Fragment Shader ─────────────────────────────────────────────────────────

/*
 * Samples the Doom framebuffer texture with nearest-neighbour filtering
 * for authentic pixelated look. The texture is BGRA8Unorm (320×200).
 */
fragment float4 doom_fragment(VertexOut       in  [[stage_in]],
                               texture2d<float> tex [[texture(0)]]) {
    constexpr sampler s(coord::normalized,
                        address::clamp_to_edge,
                        filter::nearest);
    return tex.sample(s, in.uv);
}
