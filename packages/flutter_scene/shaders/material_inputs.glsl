// The surface description a material's Surface() function fills in, consumed by
// the engine lighting framework (material_lighting.glsl) to produce the final
// fragment color. Mirrors Filament's "fill a struct, the engine runs the
// lighting" contract: a material populates these fields and the shared
// framework owns the BRDF, IBL, shadows, and output encoding.
//
// This file depends on the accessors from material_varyings.glsl.
// material_lighting.glsl (which consumes a MaterialInputs) additionally
// requires the FragInfo block, the IBL samplers, and pbr.glsl/texture.glsl to
// be declared before it is included.

// Applies offset/scale plus a cosine/sine rotation pair to texture coordinates.
vec2 ApplyMaterialUvTransform(vec2 uv, vec4 transform, vec2 rotation) {
  vec2 scaled = uv * transform.zw;
  return transform.xy +
         vec2(rotation.x * scaled.x - rotation.y * scaled.y,
              rotation.y * scaled.x + rotation.x * scaled.y);
}

// Applies a texture transform whose rotation is stored as an angle.
vec2 ApplyMaterialUvTransform(vec2 uv, vec4 transform, float rotation) {
  return ApplyMaterialUvTransform(
      uv, transform, vec2(cos(rotation), sin(rotation)));
}

// Selects the packed UV channel and applies its texture transform.
vec2 MaterialTextureUv(vec4 transform, vec4 rotation) {
  vec2 uv = GetUV(int(rotation.z + 0.5));
  return ApplyMaterialUvTransform(uv, transform, rotation.xy);
}

struct MaterialInputs {
  // Linear-space base color in rgb; straight (non-premultiplied) alpha in a.
  vec4 base_color;
  // World-space shading normal (perturbed by a normal map if present).
  vec3 normal;
  // Linear-space emissive radiance, added after lighting.
  vec3 emissive;
  // Metalness in [0, 1]: 0 dielectric, 1 conductor.
  float metallic;
  // Perceptual roughness in [0, 1].
  float roughness;
  // Scales the specular reflectance, direct and image-based (1 is the
  // physical default). Water-style materials lower it, or trade it
  // against reflections they trace themselves from the scene inputs.
  float specular;
  // Ambient occlusion in [0, 1]: 1 unoccluded.
  float occlusion;
#ifdef FLUTTER_SCENE_PHYSICAL_MATERIAL
  // Advanced physical fields. These exist only in physical shader variants,
  // so standard/unlit materials keep their original interface and cost.
  vec3 specular_color;
  float specular_weight;
  float ior;
  float clearcoat;
  float clearcoat_roughness;
  vec3 clearcoat_normal;
  vec3 sheen_color;
  float sheen_roughness;
  float transmission;
  vec3 transmission_color;
  float diffuse_transmission;
  vec3 diffuse_transmission_color;
  float anisotropy;
  vec2 anisotropy_direction;
  vec2 anisotropy_uv;
  float iridescence;
  float iridescence_ior;
  float iridescence_thickness;
#endif
};

// A MaterialInputs with neutral defaults. A Surface() function that leaves a
// field unset gets these values. The normal defaults to the interpolated
// surface normal (NOT a constant), so a lit Surface() that never assigns
// material.normal still shades with the geometry's curvature.
MaterialInputs InitMaterialInputs() {
  MaterialInputs material;
  material.base_color = vec4(1.0);
  material.normal = GetWorldNormal();
  material.emissive = vec3(0.0);
  material.metallic = 0.0;
  material.roughness = 1.0;
  material.specular = 1.0;
  material.occlusion = 1.0;
#ifdef FLUTTER_SCENE_PHYSICAL_MATERIAL
  material.specular_color = vec3(1.0);
  material.specular_weight = 1.0;
  material.ior = 1.5;
  material.clearcoat = 0.0;
  material.clearcoat_roughness = 0.0;
  material.clearcoat_normal = material.normal;
  material.sheen_color = vec3(0.0);
  material.sheen_roughness = 0.0;
  material.transmission = 0.0;
  material.transmission_color = vec3(0.0);
  material.diffuse_transmission = 0.0;
  material.diffuse_transmission_color = vec3(1.0);
  material.anisotropy = 0.0;
  material.anisotropy_direction = vec2(1.0, 0.0);
  material.anisotropy_uv = GetUV0();
  material.iridescence = 0.0;
  material.iridescence_ior = 1.3;
  material.iridescence_thickness = 0.0;
#endif
  return material;
}

// Finalization hook a Surface() function calls before returning. Currently a
// no-op; reserved so the framework can add derived-value setup later without
// changing the Surface() contract.
void PrepareMaterial(inout MaterialInputs material) {}
