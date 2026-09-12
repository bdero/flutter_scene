// Fragment math defaults to mediump; positions, coordinates, depth, and the
// HDR accumulators opt back into highp (see PRECISION.md in this directory).
// The define lets an include that runs in highp restore the default.
#define FLUTTER_SCENE_DEFAULT_FLOAT_PRECISION mediump
precision mediump float;
precision highp int;

uniform FragInfo {
  vec4 color;
  float vertex_color_weight;
  // LOD cross-fade coverage; see lod_fade.glsl.
  float fade;
}
frag_info;

#include <lod_fade.glsl>

uniform sampler2D base_color_texture;

uniform TextureTransform {
  highp vec4 uv_transform;
  highp vec4 uv_rotation;
}
texture_transform;

#include <material_varyings.glsl>
#include <material_inputs.glsl>
#include <material_debug.glsl>

// Distance fog (the FogInfo block + ApplyFog). Declared after the varyings it
// reads (v_position, v_viewvector).
#include <fog.glsl>

vec3 SRGBToLinear(vec3 color) {
  return mix(color / 12.92,
             pow((color + 0.055) / 1.055, vec3(2.4)),
             step(0.04045, color));
}

void main() {
  ApplyLodFade(frag_info.fade);
  vec4 vertex_color = mix(vec4(1), v_color, frag_info.vertex_color_weight);
  highp vec2 uv = MaterialTextureUv(texture_transform.uv_transform,
                              texture_transform.uv_rotation);
  vec4 base = texture(base_color_texture, uv);
  // Linearize the sRGB-encoded base color so what we write to the
  // floating-point scene-color target is linear; the tone-mapping resolve
  // pass applies display encoding. Output is premultiplied by alpha.
  vec3 rgb = SRGBToLinear(base.rgb) * vertex_color.rgb * frag_info.color.rgb;
  float alpha = base.a * vertex_color.a * frag_info.color.a;
  // Unlit has no environment bound, so pass the flat fog color as the sky color;
  // the sky-color mix in ApplyFog is then inert (sky-colored fog is a lit-path
  // feature).
  vec4 shaded = ApplyFog(vec4(rgb, 1.0) * alpha, fog.color.rgb);
  // The surface debug view sees the resolved unlit color as the base color.
  float debug_mode = DebugViewMode();
  if (debug_mode > 0.5) {
    MaterialInputs material = InitMaterialInputs();
    material.base_color = vec4(rgb, alpha);
    material.metallic = 0.0;
    material.roughness = 1.0;
    vec4 debug = DebugSurfaceOutput(material);
    frag_color = debug_mode > 1.5 ? DebugViewSplit(debug, shaded) : debug;
  } else {
    frag_color = shaded;
  }
}
