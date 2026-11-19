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
#ifdef FLUTTER_SCENE_PARALLAX_OCCLUSION
#include <parallax.glsl>
#endif

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

// A material slot's lookup. The parallax entries displace it by the march's
// offset and keep the undisplaced gradients; every other entry preprocesses
// to a plain texture() call.
#ifdef FLUTTER_SCENE_PARALLAX_OCCLUSION
#define SLOT_TEXTURE(tex, uv, transform, rotation)                       \
  ParallaxSlotTexture(tex, uv, transformed_uvs, parallax_offset, transform, \
                      rotation)
#else
#define SLOT_TEXTURE(tex, uv, transform, rotation) texture(tex, uv)
#endif

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
#ifdef FLUTTER_SCENE_PARALLAX_OCCLUSION
  // One march against the height field in the normal texture's alpha, in
  // the normal slot's UVs, carried back to raw channel space so every slot
  // applies its own transform on top. Only materials with a parallax depth
  // and a normal texture draw with this entry.
  // TODO(parallax-uv-channels): the offset is measured on the normal slot's
  // channel; a slot reading the other channel is displaced by it anyway.
  highp vec2 parallax_uv = transformed_uvs
      ? MaterialTextureUv(
            texture_transforms.normal_transform,
            texture_transforms.normal_rotation)
      : GetUV0();
  ParallaxRay parallax_ray = ParallaxBeginEngineRay(
      normal_texture, GetWorldNormal(), v_viewvector, GetViewDirection(),
      parallax_uv);
  ParallaxHit parallax_hit = ParallaxEngineMarch(normal_texture, parallax_ray);
  highp vec2 parallax_offset = transformed_uvs
      ? UntransformMaterialUvOffset(parallax_hit.offset,
                                    texture_transforms.normal_transform,
                                    texture_transforms.normal_rotation.xy)
      : parallax_hit.offset;
  if (parallax_info.params.z > 0.0 &&
      frag_info.has_directional_light > 0.5) {
    material.parallax_sun_visibility = mix(
        1.0,
        ParallaxSelfShadow(normal_texture, parallax_ray, parallax_hit,
                           -normalize(frag_info.directional_light_direction.xyz)),
        parallax_info.params.z);
  }
#endif
  highp vec2 base_color_uv = transformed_uvs
      ? MaterialTextureUv(
            texture_transforms.base_color_transform,
            texture_transforms.base_color_rotation)
      : GetUV0();
  vec4 base_color_srgb = SLOT_TEXTURE(base_color_texture, base_color_uv,
                                      texture_transforms.base_color_transform,
                                      texture_transforms.base_color_rotation);
  vec3 albedo = SRGBToLinear(base_color_srgb.rgb) * vertex_color.rgb *
                frag_info.color.rgb;
  float alpha = base_color_srgb.a * vertex_color.a * frag_info.color.a;
  // MASK alpha mode renders fully opaque (glTF treats MASK output as binary).
  // The cutout itself comes from the main pass's coverage pre-draw, so this
  // shader never discards; a discard would turn off early depth testing and
  // hidden-surface removal for every draw on tiled GPUs.
  if (frag_info.alpha_mode == 1.0) {
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
#ifdef FLUTTER_SCENE_PARALLAX_OCCLUSION
    normal = ParallaxPerturbNormal(normal_texture, normal, v_viewvector,
                                   normal_uv, parallax_hit.offset,
                                   vec2(frag_info.normal_scale));
#else
    normal = PerturbNormal(normal_texture, normal, v_viewvector,
                           normal_uv, frag_info.normal_scale);
#endif
  }
  material.normal = normal;

  highp vec2 metallic_roughness_uv = transformed_uvs
      ? MaterialTextureUv(
            texture_transforms.metallic_roughness_transform,
            texture_transforms.metallic_roughness_rotation)
      : GetUV0();
  vec4 metallic_roughness = SLOT_TEXTURE(
      metallic_roughness_texture, metallic_roughness_uv,
      texture_transforms.metallic_roughness_transform,
      texture_transforms.metallic_roughness_rotation);
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
  // A zero strength (also what a material without an occlusion texture
  // packs) leaves the occlusion at 1, so the read is skipped.
  float occlusion = 1.0;
  if (frag_info.occlusion_strength != 0.0) {
    occlusion = SLOT_TEXTURE(occlusion_texture, occlusion_uv,
                             texture_transforms.occlusion_transform,
                             texture_transforms.occlusion_rotation).r;
  }
  material.occlusion = 1.0 - (1.0 - occlusion) * frag_info.occlusion_strength;

  highp vec2 emissive_uv = transformed_uvs
      ? MaterialTextureUv(
            texture_transforms.emissive_transform,
            texture_transforms.emissive_rotation)
      : GetUV0();
  // Most materials emit nothing, so they skip the read and the sRGB decode.
  material.emissive = vec3(0.0);
  vec3 emissive_scale = frag_info.emissive_factor.rgb * frag_info.emissive_factor.a;
  if (dot(abs(emissive_scale), vec3(1.0)) > 0.0) {
    material.emissive =
        SRGBToLinear(SLOT_TEXTURE(emissive_texture, emissive_uv,
                                  texture_transforms.emissive_transform,
                                  texture_transforms.emissive_rotation).rgb) *
        emissive_scale;
  }

  PrepareMaterial(material);
}

void main() {
  MaterialInputs material = InitMaterialInputs();
  Surface(material);
  // The surface debug view when one is active, the lit result otherwise, or
  // both selected per pixel for a split. The lighting runs under a uniform
  // branch. EvaluateLighting has one call site on purpose. Every call is
  // inlined, and a second copy of the lighting pushes the shadowed variant past
  // what Apple's M3 and newer GPU compilers can build under fast math.
  vec4 lit = vec4(0.0);
  if (DebugViewNeedsShaded()) {
    lit = EvaluateLighting(material);
  }
  frag_color = DebugViewOutput(material, lit);
  frag_color *= LodFadeOpacity(frag_info.fade);
}
