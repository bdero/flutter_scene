// Alpha-mask test shared by the depth-writing passes (the shadow map and the
// camera depth prepass), so cutout surfaces occlude and cast only where they
// are actually opaque. Mirrors the standard material's MASK coverage,
// `texture.a * vertex_color.a (weighted) * constant alpha`, tested against the
// material's cutoff. Requires the full-vertex varyings (material_varyings.glsl).

uniform MaskInfo {
  // x: alpha cutoff   y: constant alpha factor (the material's base color
  // factor alpha)   z: vertex-color alpha weight   w: unused
  vec4 params;
}
mask_info;

// The texture whose alpha carries the mask (the material's base color map).
uniform sampler2D mask_texture;

// Discards the fragment when its masked alpha falls below the cutoff.
void ApplyDepthAlphaMask() {
  float alpha = texture(mask_texture, v_texture_coords).a *
                mix(1.0, v_color.a, mask_info.params.z) * mask_info.params.y;
  if (alpha < mask_info.params.x) {
    discard;
  }
}
