// Accumulates one scattered sample's radiance into a probe's octahedral
// irradiance tile.
//
// The fragment's own octahedral direction gives the cosine lobe weight, so a
// sample contributes to every texel whose direction it can be seen from, and
// the accumulator's alpha carries the weight sum the blend divides by. Blended
// additively into a persistent half-float accumulator.

#include <irradiance_field.glsl>

uniform InjectTileInfo {
  // x: stored tile edge. y: interior edge. zw: unused.
  vec4 tile;
}
tile_info;

in vec4 v_sample;
in vec3 v_radiance;
in float v_weight;

out vec4 frag_color;

void main() {
  vec2 tile_origin = floor(gl_FragCoord.xy / tile_info.tile.x) *
                     tile_info.tile.x;
  vec2 oct = clamp(ProbeInteriorCoord(gl_FragCoord.xy, tile_origin) /
                       tile_info.tile.y,
                   0.0, 1.0);
  vec3 texel_direction = ProbeOctDecode(oct);
  float weight = v_weight * max(0.0, dot(texel_direction, v_sample.xyz));
  frag_color = vec4(v_radiance * weight, weight);
}
