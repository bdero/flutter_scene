// Copies a blended probe region into the atlas the lit shader samples, and on
// the way writes the gutter and applies a variance-adaptive blur.
//
// Reading the blended history and writing a separate atlas is what keeps the
// denoise out of the temporal feedback; a filter that fed back would settle
// into a slow blur toward gray. Taps are clamped inside the probe's own tile,
// so radiance can never blur across a wall into a neighbouring probe.
//
// The gutter is the canonical mirror of the interior edge rather than an
// out-of-range octahedral evaluation, which is what keeps a bilinear read
// across the seam landing on the matching direction instead of drawing a
// world-axis cross on smooth surfaces.

#include <irradiance_field.glsl>

uniform FilterInfo {
  // x: this region's first atlas row. y: stored tile edge. z: interior edge.
  // w: blur strength, scaling the texel's own standard deviation into a
  // blend factor. 0 copies, which is what the depth moments want (blurring
  // them across directions inflates the variance the Chebyshev test reads).
  vec4 region;
  // x: probe tiles per atlas row. y: the region's tile rows. The draw covers
  // the whole atlas and discards outside its own region, rather than relying
  // on a render-target viewport whose vertical origin is not guaranteed to
  // agree across backends.
  vec4 extent;
}
info;

uniform highp sampler2D atlas;

out vec4 frag_color;

void main() {
  ivec2 coord = ivec2(floor(gl_FragCoord.xy));
  int origin = int(info.region.x);
  int tile = int(info.region.y);
  int interior = int(info.region.z);

  int region_y = coord.y - origin;
  if (region_y < 0 || region_y >= int(info.extent.y) * tile ||
      coord.x >= int(info.extent.x) * tile) {
    discard;
  }
  ivec2 local = ivec2(coord.x - (coord.x / tile) * tile,
                      region_y - (region_y / tile) * tile);
  ivec2 tile_base = coord - local;
  ivec2 source = ivec2(ProbeGutterSource(vec2(local), float(interior)));

  vec4 result;
  if (source == local) {
    vec4 center = texelFetch(atlas, coord, 0);
    result = center;
    if (info.region.w > 0.0) {
      vec4 sum = vec4(0.0);
      float total = 0.0;
      for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
          ivec2 tap = clamp(local + ivec2(dx, dy), ivec2(1), ivec2(interior));
          float weight = (dx == 0 ? 2.0 : 1.0) * (dy == 0 ? 2.0 : 1.0);
          sum += texelFetch(atlas, tile_base + tap, 0) * weight;
          total += weight;
        }
      }
      float luma = ProbeLuminance(center.rgb);
      float sigma = sqrt(max(0.0, center.a - luma * luma));
      result = mix(center, sum / total,
                   clamp(sigma * info.region.w, 0.0, 1.0));
    }
  } else {
    result = texelFetch(atlas, tile_base + source, 0);
  }
  frag_color = result;
}
