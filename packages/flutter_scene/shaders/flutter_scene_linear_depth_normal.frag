// Fragment shader for the camera depth prepass when a consumer also needs
// per-pixel normals and roughness (screen-space reflections).
//
// Like LinearDepthFragment it writes planar view-space depth into the red
// channel, but it also packs the smooth interpolated view-space normal
// (octahedral, two components) into green/blue and the perceptual roughness
// into alpha of the same floating-point target, at no extra attachment cost.
// Reflections need the shaded vertex normal, not a face normal reconstructed
// from depth, so that curved surfaces reflect smoothly rather than
// per-triangle; the roughness lets the trace fade out on rough surfaces
// (which have no coherent screen-space reflection) and fall back to the
// image-based reflection.
//
// Pairs with the engine's full vertex shaders (UnskinnedVertex /
// SkinnedVertex), which provide the world-space v_normal and v_viewvector.
// The world normal is rotated into view space with the camera basis passed
// in, matching the lookAt view matrix (+X right, +Y up, +Z forward).

#include <material_varyings.glsl>

uniform DepthNormalInfo {
  // xyz: normalized world-space camera forward (eye into the scene).
  // w: perceptual roughness multiplier (the material's roughnessFactor).
  vec4 camera_forward;
  // xyz: world-space camera right axis.
  vec4 camera_right;
  // xyz: world-space camera up axis.
  vec4 camera_up;
}
info;

// The material's metallic-roughness map (roughness in G), so the trace has a
// per-pixel roughness. A white placeholder is bound for materials without one,
// leaving roughness at the factor.
uniform sampler2D metallic_roughness_texture;

// Octahedral-encode a unit vector into two components in [-1, 1]. The prepass
// target is float, so the encoding is stored directly; SsrFragment decodes it.
vec2 OctEncode(vec3 n) {
  n /= (abs(n.x) + abs(n.y) + abs(n.z));
  vec2 e = n.z >= 0.0
      ? n.xy
      : (1.0 - abs(n.yx)) *
            vec2(n.x >= 0.0 ? 1.0 : -1.0, n.y >= 0.0 ? 1.0 : -1.0);
  return e;
}

void main() {
  // v_viewvector is (camera_position - world_position); negating it and
  // projecting onto the forward axis gives planar view-space depth.
  float view_depth = -dot(v_viewvector, info.camera_forward.xyz);

  // Rotate the interpolated world normal into view space (eye looking down
  // +Z), the space the reflection trace works in.
  vec3 n = normalize(v_normal);
  vec3 view_normal = normalize(vec3(dot(n, info.camera_right.xyz),
                                    dot(n, info.camera_up.xyz),
                                    dot(n, info.camera_forward.xyz)));

  float roughness = clamp(
      texture(metallic_roughness_texture, v_texture_coords).g *
          info.camera_forward.w,
      0.0, 1.0);

  vec2 oct = OctEncode(view_normal);
  frag_color = vec4(view_depth, oct.x, oct.y, roughness);
}
