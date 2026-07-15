// The surface description a material's Surface() function fills in, consumed by
// the engine lighting framework (material_lighting.glsl) to produce the final
// fragment color. Mirrors Filament's "fill a struct, the engine runs the
// lighting" contract: a material populates these fields and the shared
// framework owns the BRDF, IBL, shadows, and output encoding.
//
// This file declares only the struct and its helpers and has no dependencies.
// material_lighting.glsl (which consumes a MaterialInputs) additionally
// requires the FragInfo block, the standard world-space varyings, the IBL
// samplers, and pbr.glsl / texture.glsl to be declared before it is included.

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
  return material;
}

// Finalization hook a Surface() function calls before returning. Currently a
// no-op; reserved so the framework can add derived-value setup later without
// changing the Surface() contract.
void PrepareMaterial(inout MaterialInputs material) {}
