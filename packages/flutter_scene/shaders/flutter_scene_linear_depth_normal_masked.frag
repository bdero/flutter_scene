// Alpha-masked variant of the depth+normal prepass fragment shader (see
// flutter_scene_linear_depth_normal.frag): discards fragments the material's
// MASK coverage rejects, so screen-space reflections trace against cutout
// surfaces only where they are actually opaque.

#include <material_varyings.glsl>
#include <depth_mask.glsl>

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

uniform sampler2D metallic_roughness_texture;

// Octahedral-encode a unit vector into two components in [-1, 1]; matches
// the encoding in flutter_scene_linear_depth_normal.frag.
vec2 OctEncode(vec3 n) {
  n /= (abs(n.x) + abs(n.y) + abs(n.z));
  vec2 e = n.z >= 0.0
      ? n.xy
      : (1.0 - abs(n.yx)) *
            vec2(n.x >= 0.0 ? 1.0 : -1.0, n.y >= 0.0 ? 1.0 : -1.0);
  return e;
}

void main() {
  ApplyDepthAlphaMask();

  float view_depth = -dot(v_viewvector, info.camera_forward.xyz);

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
