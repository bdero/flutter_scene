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
  // 1 when the base color is display-referred and passes through unchanged
  // (see Material.displayReferred); 0 for ordinary scene-referred shading.
  float display_referred;
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
  //
  // A display-referred surface skips that: it draws into the display-referred
  // layer, which is composited after the resolve has already encoded, so its
  // texel has to arrive unchanged.
  bool display_referred = frag_info.display_referred > 0.5;
  vec3 decoded = display_referred ? base.rgb : SRGBToLinear(base.rgb);
  vec3 rgb = decoded * vertex_color.rgb * frag_info.color.rgb;
  float alpha = base.a * vertex_color.a * frag_info.color.a;
  // Unlit has no environment bound, so pass the flat fog color as the sky color;
  // the sky-color mix in ApplyFog is then inert (sky-colored fog is a lit-path
  // feature).
  // Fog is scene-referred depth cueing; it would tint UI that is meant to
  // read as an overlay, so a display-referred surface takes none.
  vec4 premultiplied = vec4(rgb, 1.0) * alpha;
  vec4 shaded = display_referred
                    ? premultiplied
                    : ApplyFog(premultiplied, fog.color.rgb);
  // The surface debug view sees the resolved unlit color as the base color.
  float debug_mode = DebugViewMode();
  if (debug_mode > 0.5) {
    MaterialInputs material = InitMaterialInputs();
    // MaterialInputs is linear and the debug views encode it themselves, so a
    // display-referred color has to come back to linear here or it would be
    // encoded twice.
    vec3 debug_rgb = display_referred ? SRGBToLinear(rgb) : rgb;
    material.base_color = vec4(debug_rgb, alpha);
    material.metallic = 0.0;
    material.roughness = 1.0;
    vec4 debug = DebugSurfaceOutput(material);
    frag_color = debug_mode > 1.5 ? DebugViewSplit(debug, shaded) : debug;
  } else {
    frag_color = shaded;
  }
}
