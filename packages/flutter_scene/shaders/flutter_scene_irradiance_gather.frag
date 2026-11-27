// Gathers each probe's screen samples into one texel of its octahedral tile in
// the irradiance or depth-moment accumulator, the same weighted sums the
// traced feed's gather writes, so the field's blend reads either feed.
//
// One fragment per accumulator texel, reading the 64 samples
// flutter_scene_irradiance_sample.frag picked for the texel's probe. Each
// texel is written once with no blending, so the cost is a fixed loop per
// texel rather than overdraw that grows with the screen. Gutters, unused
// tiles, and unscheduled rows write zero.

#include <irradiance_field.glsl>

uniform GatherInfo {
  // x: stored tile edge. y: interior edge. z: 1 for depth moments, 0 for
  // irradiance. w: probe tiles per row.
  vec4 region;
  // x: probe count. yz: the half-open range of tile rows this frame
  // refreshes. w: unused.
  vec4 grid;
  // xy: the sample texture's reciprocal size. zw: unused.
  vec4 samples;
}
info;

// Each sample's offset from its probe (normalized) and weight.
uniform highp sampler2D sample_geometry;
// Each sample's radiance.
uniform highp sampler2D sample_radiance;

out vec4 frag_color;

const float kSampleEdge = 8.0;

// The depth lobe's sharpness, matching the traced gather.
const float kDistanceSharpness = 50.0;

// The cosine below which the depth lobe (cos^50) is under 0.001.
const float kDistanceLobeCutoff = 0.87;

void main() {
  frag_color = vec4(0.0);
  highp vec2 frag = floor(gl_FragCoord.xy);
  float tile_edge = info.region.x;
  float interior = info.region.y;
  highp vec2 tile = floor(frag / tile_edge);
  highp vec2 local = frag - tile * tile_edge;
  highp float probe = tile.y * info.region.w + tile.x;
  if (tile.x >= info.region.w || probe >= info.grid.x ||
      tile.y < info.grid.y || tile.y >= info.grid.z || local.x < 1.0 ||
      local.y < 1.0 || local.x > interior || local.y > interior) {
    return;
  }

  vec2 oct = clamp((local - vec2(0.5)) / interior, 0.0, 1.0);
  vec3 texel_direction = ProbeOctDecode(oct);
  bool depth = info.region.z > 0.5;
  highp vec2 block = tile * kSampleEdge + vec2(0.5);
  vec4 sum = vec4(0.0);
  for (int y = 0; y < 8; y++) {
    for (int x = 0; x < 8; x++) {
      highp vec2 uv = (block + vec2(float(x), float(y))) * info.samples.xy;
      highp vec4 geometry = textureLod(sample_geometry, uv, 0.0);
      if (geometry.w <= 0.0) continue;
      highp float d = length(geometry.xyz);
      float cosine = dot(texel_direction, geometry.xyz / d);
      if (depth) {
        if (cosine < kDistanceLobeCutoff) continue;
        float lobe = pow(cosine, kDistanceSharpness) * geometry.w;
        sum += vec4(d * lobe, d * d * lobe, 0.0, lobe);
      } else {
        if (cosine <= 0.0) continue;
        float weight = cosine * geometry.w;
        sum += vec4(textureLod(sample_radiance, uv, 0.0).rgb * weight, weight);
      }
    }
  }
  frag_color = sum;
}
