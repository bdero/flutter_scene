// Accumulates one scattered sample's distance into a probe's octahedral
// depth-moment tile.
//
// The lobe is sharpened hard (the reference implementation's distance
// exponent) so a probe's stored distance tracks the nearest surface in a
// direction rather than averaging over a wide cone, which is what makes the
// receiver's Chebyshev test able to tell a wall from open space. Distances
// arrive already normalized by the probe's maximum recorded distance, so the
// second moment stays inside fp16's well-conditioned range.

#include <irradiance_field.glsl>

uniform InjectTileInfo {
  vec4 tile;
}
tile_info;

in vec4 v_sample;
in vec3 v_radiance;
in float v_weight;

out vec4 frag_color;

const float kDistanceSharpness = 50.0;

void main() {
  vec2 tile_origin = floor(gl_FragCoord.xy / tile_info.tile.x) *
                     tile_info.tile.x;
  vec2 oct = clamp(ProbeInteriorCoord(gl_FragCoord.xy, tile_origin) /
                       tile_info.tile.y,
                   0.0, 1.0);
  vec3 texel_direction = ProbeOctDecode(oct);
  float lobe = pow(max(0.0, dot(texel_direction, v_sample.xyz)),
                   kDistanceSharpness);
  float weight = v_weight * lobe;
  float d = v_sample.w;
  frag_color = vec4(d * weight, d * d * weight, 0.0, weight);
}
