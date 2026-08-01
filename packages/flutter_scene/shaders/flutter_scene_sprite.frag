uniform FragInfo {
  vec4 tint;     // linear RGBA, multiplied into the sampled color
  // x: 0 premultiplied source-over, 1 additive. y: reciprocal soft depth
  // fade distance (0 disables). z: reciprocal camera near fade distance
  // (0 disables). w: unused.
  vec4 params;
  // xy: reciprocal viewport size, for the gl_FragCoord screen UV. zw:
  // unused.
  vec4 viewport;
}
frag_info;

uniform sampler2D base_color_texture;
// The opaque linear (planar view-space) depth in world units, bound to a
// white placeholder when the depth prepass did not run (the fade is
// disabled then, so it is never sampled meaningfully).
uniform sampler2D scene_depth;

in vec2 v_uv;
in vec4 v_color;
in vec2 v_uv2;
in float v_frame_blend;
in float v_view_depth;

out vec4 frag_color;

vec3 SRGBToLinear(vec3 color) {
  return mix(color / 12.92,
             pow((color + 0.055) / 1.055, vec3(2.4)),
             step(0.04045, color));
}

void main() {
  // Crossfade between adjacent flipbook cells (v_frame_blend is zero when
  // the geometry has blending off, collapsing to a single sample's value).
  vec4 base = mix(
      texture(base_color_texture, v_uv),
      texture(base_color_texture, v_uv2),
      v_frame_blend);
  // Linearize the sRGB-encoded texture; the resolve pass applies display
  // encoding. The scene-color target stores linear HDR premultiplied alpha.
  vec3 rgb = SRGBToLinear(base.rgb) * v_color.rgb * frag_info.tint.rgb;
  float alpha = base.a * v_color.a * frag_info.tint.a;

  // Soft particles: fade out as the sprite approaches the opaque geometry
  // behind it, so intersections dissolve instead of cutting a hard edge.
  float soft_inv = frag_info.params.y;
  if (soft_inv > 0.0) {
    vec2 screen_uv = clamp(gl_FragCoord.xy * frag_info.viewport.xy,
                           vec2(0.001), vec2(0.999));
    float scene_d = texture(scene_depth, screen_uv).r;
    alpha *= clamp((scene_d - v_view_depth) * soft_inv, 0.0, 1.0);
  }
  // Camera near fade: dissolve sprites before the camera clips through them.
  float near_inv = frag_info.params.z;
  if (near_inv > 0.0) {
    alpha *= clamp(v_view_depth * near_inv - 0.35, 0.0, 1.0);
  }

  // The color encoder's translucent pass blends with premultiplied
  // source-over: out = src.rgb + (1 - src.a) * dst. Premultiplying the color
  // by alpha gives normal blending; forcing the output alpha to zero (while
  // keeping the premultiplied color) turns the same pass additive, so both
  // modes share one pipeline.
  float out_alpha = mix(alpha, 0.0, frag_info.params.x);
  frag_color = vec4(rgb * alpha, out_alpha);
}
