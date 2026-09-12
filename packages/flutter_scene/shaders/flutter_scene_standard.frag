// Fragment math defaults to mediump; positions, coordinates, depth, and the
// HDR accumulators opt back into highp (see PRECISION.md in this directory).
// The define lets an include that runs in highp restore the default.
#define FLUTTER_SCENE_DEFAULT_FLOAT_PRECISION mediump
precision mediump float;
precision highp int;

#include <material_varyings.glsl>
#include <normals.glsl>
#include <pbr.glsl>
#include <texture.glsl>
#include <material_engine_lighting.glsl>
#include <material_inputs.glsl>
#include <material_debug.glsl>
#include <material_lighting.glsl>
#include <lod_fade.glsl>

uniform sampler2D base_color_texture;
uniform sampler2D emissive_texture;
uniform sampler2D metallic_roughness_texture;
uniform sampler2D normal_texture;
uniform sampler2D occlusion_texture;

uniform TextureTransforms {
  highp vec4 base_color_transform;
  highp vec4 base_color_rotation;
  highp vec4 metallic_roughness_transform;
  highp vec4 metallic_roughness_rotation;
  highp vec4 normal_transform;
  highp vec4 normal_rotation;
  highp vec4 emissive_transform;
  highp vec4 emissive_rotation;
  highp vec4 occlusion_transform;
  highp vec4 occlusion_rotation;
}
texture_transforms;

// Fills the surface description for the standard glTF metallic-roughness
// material from the FragInfo parameters and the material textures. The shared
// lighting framework (material_lighting.glsl) consumes it.
void Surface(inout MaterialInputs material) {
  vec4 vertex_color = mix(vec4(1), v_color, frag_info.vertex_color_weight);
  // base_color_rotation.w (padding in each record) carries a single flag set
  // when any of the five records transforms its UVs or selects UV set 1.
  // Every record is identity for a default glTF material, and the identity
  // transform reproduces the raw UV bit-exactly, so the uniform branch only
  // skips work.
  bool transformed_uvs = texture_transforms.base_color_rotation.w > 0.5;
  highp vec2 base_color_uv = transformed_uvs
      ? MaterialTextureUv(
            texture_transforms.base_color_transform,
            texture_transforms.base_color_rotation)
      : GetUV0();
  vec4 base_color_srgb = texture(base_color_texture, base_color_uv);
  vec3 albedo = SRGBToLinear(base_color_srgb.rgb) * vertex_color.rgb *
                frag_info.color.rgb;
  float alpha = base_color_srgb.a * vertex_color.a * frag_info.color.a;
  // MASK alpha mode: discard fragments below the cutoff, render the
  // rest fully opaque (glTF treats MASK output as binary). Done here, before
  // the normal-map derivatives, so the discard's effect on screen-space
  // derivatives matches the original monolithic shader.
  if (frag_info.alpha_mode == 1.0) {
    if (alpha < frag_info.alpha_cutoff) {
      discard;
    }
    alpha = 1.0;
  }
  material.base_color = vec4(albedo, alpha);

  // Note: PerturbNormal needs the non-normalized view vector
  //       (camera_position - vertex_position).
  vec3 normal = GetWorldNormal();
  if (frag_info.has_normal_map > 0.5) {
    highp vec2 normal_uv = transformed_uvs
        ? MaterialTextureUv(
              texture_transforms.normal_transform,
              texture_transforms.normal_rotation)
        : GetUV0();
    normal = PerturbNormal(normal_texture, normal, v_viewvector,
                           normal_uv, frag_info.normal_scale);
  }
  material.normal = normal;

  highp vec2 metallic_roughness_uv = transformed_uvs
      ? MaterialTextureUv(
            texture_transforms.metallic_roughness_transform,
            texture_transforms.metallic_roughness_rotation)
      : GetUV0();
  vec4 metallic_roughness =
      texture(metallic_roughness_texture, metallic_roughness_uv);
  material.metallic = clamp(metallic_roughness.b * frag_info.metallic_factor,
                            0.0, 1.0);
  material.roughness =
      clamp(metallic_roughness.g * frag_info.roughness_factor, kMinRoughness,
            1.0);

  highp vec2 occlusion_uv = transformed_uvs
      ? MaterialTextureUv(
            texture_transforms.occlusion_transform,
            texture_transforms.occlusion_rotation)
      : GetUV0();
  float occlusion = texture(occlusion_texture, occlusion_uv).r;
  material.occlusion = 1.0 - (1.0 - occlusion) * frag_info.occlusion_strength;

  highp vec2 emissive_uv = transformed_uvs
      ? MaterialTextureUv(
            texture_transforms.emissive_transform,
            texture_transforms.emissive_rotation)
      : GetUV0();
  material.emissive = SRGBToLinear(texture(emissive_texture, emissive_uv).rgb) *
                      frag_info.emissive_factor.rgb *
                      frag_info.emissive_factor.a;

  PrepareMaterial(material);
}

void main() {
  ApplyLodFade(frag_info.fade);
  MaterialInputs material = InitMaterialInputs();
  Surface(material);
  // The surface debug view when one is active, the lit result otherwise, or
  // both selected per pixel for a split (uniform control flow throughout).
  float debug_mode = DebugViewMode();
  if (debug_mode > 1.5) {
    frag_color = DebugViewSplit(DebugSurfaceOutput(material),
                                EvaluateLighting(material));
  } else if (debug_mode > 0.5) {
    frag_color = DebugSurfaceOutput(material);
  } else {
    frag_color = EvaluateLighting(material);
  }
}
