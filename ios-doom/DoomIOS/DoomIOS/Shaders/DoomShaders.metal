/*
 * DoomShaders.metal
 *
 * Renders the Doom 320×200 framebuffer onto a letterboxed quad using
 * nearest-neighbour sampling for authentic pixel rendering.
 *
 * QuadUniforms supplies the NDC rect so the CPU can control aspect-ratio
 * letterboxing without recompiling the shader.
 */

#include <metal_stdlib>
using namespace metal;

// ─── Structures ──────────────────────────────────────────────────────────────

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

/*
 * NDC bounding rect for the quad:
 *   x = left edge,  y = bottom edge
 *   z = right edge, w = top edge
 * All values in Normalised Device Coordinates (-1 … +1).
 *
 * For fullscreen: { -1, -1, 1, 1 }
 * For letterboxed: computed by DoomRenderer on resize.
 */
struct QuadUniforms {
    float4 ndcRect;  // x=left, y=bottom, z=right, w=top
};

// ─── Vertex Shader ────────────────────────────────────────────────────────────

/*
 * Triangle-strip quad: 4 vertices, 2 triangles.
 * vertex_id: 0=TL, 1=TR, 2=BL, 3=BR
 */
vertex VertexOut doom_vertex(
    uint vid [[vertex_id]],
    constant QuadUniforms &u [[buffer(0)]])
{
    float2 positions[4] = {
        float2(u.ndcRect.x, u.ndcRect.w),  // TL: left,  top
        float2(u.ndcRect.z, u.ndcRect.w),  // TR: right, top
        float2(u.ndcRect.x, u.ndcRect.y),  // BL: left,  bottom
        float2(u.ndcRect.z, u.ndcRect.y),  // BR: right, bottom
    };
    // UV origin (0,0) is top-left to match the Doom framebuffer layout
    float2 uvs[4] = {
        float2(0.0f, 0.0f),  // TL
        float2(1.0f, 0.0f),  // TR
        float2(0.0f, 1.0f),  // BL
        float2(1.0f, 1.0f),  // BR
    };

    VertexOut out;
    out.position = float4(positions[vid], 0.0f, 1.0f);
    out.uv       = uvs[vid];
    return out;
}

// ─── Fragment Shader ─────────────────────────────────────────────────────────

fragment float4 doom_fragment(
    VertexOut        in  [[stage_in]],
    texture2d<float> tex [[texture(0)]])
{
    constexpr sampler s(coord::normalized,
                        address::clamp_to_edge,
                        filter::nearest);
    return tex.sample(s, in.uv);
}
