// Writes one material texture into its tile of the traced feed's material
// atlas, filtered down to the tile's resolution and decoded from sRGB as the
// lit shader decodes its color textures (after filtering). The draw covers
// the whole atlas and discards outside the tile.

#include <pbr.glsl>

uniform TileInfo {
  // xy: the tile's first texel. z: its edge in texels. w: the source mip
  // level whose texels best match a tile texel.
  vec4 tile;
}
info;

uniform highp sampler2D source;

in vec2 v_uv;

out vec4 frag_color;

void main() {
  vec2 local = gl_FragCoord.xy - info.tile.xy;
  float edge = info.tile.z;
  if (any(lessThan(local, vec2(0.0))) ||
      any(greaterThanEqual(local, vec2(edge)))) {
    discard;
  }
  // Texel k of the tile stands for texture coordinate k / (edge - 1), the
  // mapping the trace reads with. Four taps over its footprint stand in for
  // a missing mip chain.
  float step_uv = 1.0 / (edge - 1.0);
  vec2 center = floor(local) * step_uv;
  vec3 sum = vec3(0.0);
  for (int i = 0; i < 4; i++) {
    vec2 offset = (vec2(float(i & 1), float(i >> 1)) - 0.5) * 0.5 * step_uv;
    sum += textureLod(source, center + offset, info.tile.w).rgb;
  }
  frag_color = vec4(SRGBToLinear(sum * 0.25), 1.0);
}
