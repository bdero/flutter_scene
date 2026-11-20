// Alpha-mask test shared by the depth-writing passes (the shadow map and the
// camera depth prepass), so cutout surfaces occlude and cast only where they
// are actually opaque. Mirrors the standard material's MASK coverage,
// `texture.a * vertex_color.a (weighted) * constant alpha`, tested against the
// material's cutoff. Requires the full-vertex varyings (material_varyings.glsl).

uniform MaskInfo {
  // x: alpha cutoff   y: constant alpha factor (the material's base color
  // factor alpha)   z: vertex-color alpha weight   w: unused
  highp vec4 params;
  // xy: UV offset, zw: UV scale.
  highp vec4 uv_transform;
  // xy: cosine and sine of the UV rotation, z: UV channel.
  highp vec4 uv_rotation;
}
mask_info;

// The texture whose alpha carries the mask (the material's base color map).
uniform sampler2D mask_texture;

#ifdef FLUTTER_SCENE_PARALLAX_SILHOUETTE
// Silhouette parallax: the surface is also cut where the marched view ray
// leaves its silhouette box before hitting the height field, so the depth
// passes and the coverage pre-draw see the relief's outline.
// TODO(parallax-depth-offset): write the displaced depth here and in the
// lit silhouette entries, so intersections, ambient occlusion, and shadow
// self-occlusion see the relief rather than the flat surface. The color draw
// re-tests the coverage depth with an equal compare, so both programs must
// produce the same depth; nudge the coverage depth farther and shade with a
// nearer-or-equal compare rather than rely on bit-exact results.
#define FLUTTER_SCENE_PARALLAX_OCCLUSION
#include <normals.glsl>
#include <parallax.glsl>

uniform ParallaxSurfaceInfo {
  // The normal slot's texture transform, offset in xy and scale in zw.
  highp vec4 normal_transform;
  // Cosine and sine of its rotation in xy, its UV channel in z.
  highp vec4 normal_rotation;
  // The pass camera, the eye for perspective.
  highp vec4 camera_position;
  // xyz: the pass camera's forward. w: 1 for an orthographic pass camera.
  highp vec4 camera_forward;
}
parallax_surface;

// The normal texture, whose alpha carries the height field.
uniform sampler2D normal_texture;

// Whether the marched view ray hits the field inside the silhouette box.
bool ParallaxSilhouetteKeeps() {
  highp vec2 uv = MaterialTextureUv(parallax_surface.normal_transform,
                                    parallax_surface.normal_rotation);
  highp vec3 view_vector = parallax_surface.camera_position.xyz - v_position;
  highp vec3 view_dir = parallax_surface.camera_forward.w > 0.5
      ? -parallax_surface.camera_forward.xyz
      : normalize(view_vector);
  ParallaxRay ray = ParallaxBeginEngineRay(normal_texture, GetWorldNormal(),
                                           view_vector, view_dir, uv);
  return ParallaxEngineInsideSilhouette(ray,
                                        ParallaxEngineMarch(normal_texture, ray));
}
#endif  // FLUTTER_SCENE_PARALLAX_SILHOUETTE

// Discards the fragment when its masked alpha falls below the cutoff.
void ApplyDepthAlphaMask() {
#ifdef FLUTTER_SCENE_PARALLAX_SILHOUETTE
  // Decided before any discard, since the march takes derivatives.
  bool keep = ParallaxSilhouetteKeeps();
#endif
  highp vec2 uv = MaterialTextureUv(mask_info.uv_transform, mask_info.uv_rotation);
  float alpha = texture(mask_texture, uv).a *
                mix(1.0, v_color.a, mask_info.params.z) * mask_info.params.y;
#ifdef FLUTTER_SCENE_PARALLAX_SILHOUETTE
  if (!keep) {
    discard;
  }
#endif
  if (alpha < mask_info.params.x) {
    discard;
  }
}
