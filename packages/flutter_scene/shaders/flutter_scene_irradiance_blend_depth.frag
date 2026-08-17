// Folds one frame of scattered distances into a probe's stored depth moments.
//
// Retention here is deliberately decoupled from the irradiance blend's change
// detector. Coupling them makes the visibility term move whenever the
// lighting does, which reads as reflections and shadow edges swimming at the
// frame rate.
//
// A direction no sample reached stores the maximum recorded distance with
// zero variance, which the receiver's Chebyshev test reads as "nothing known
// to be in the way" rather than as an occluder.

#include <irradiance_field.glsl>

uniform BlendDepthInfo {
  // x: retention at this frame's cadence. y: stored tile edge. z: interior
  // edge. w: this region's first atlas row.
  vec4 blend;
  // xyz: probe counts per axis. w: probe tiles per atlas row.
  vec4 counts;
  // xyz: the volume's minimum-corner lattice index. w: unused.
  vec4 anchor;
  // xyz: the previous frame's minimum-corner lattice index. w: 1 forces every
  // probe to snap.
  vec4 previous;
  // xy: the half-open range of tile rows this frame refreshes. z: the
  // region's total tile rows; the draw covers the whole atlas and discards
  // outside its own region.
  vec4 schedule;
}
info;

uniform highp sampler2D injection;
uniform highp sampler2D history;

out vec4 frag_color;

const float kCoverageWeight = 0.05;

void main() {
  vec2 frag = gl_FragCoord.xy;
  vec2 region = vec2(frag.x, frag.y - info.blend.w);
  float tile_size = info.blend.y;

  if (region.y < 0.0 || region.y >= info.schedule.z * tile_size ||
      region.x >= info.counts.w * tile_size) {
    discard;
  }

  vec2 tile_index = floor(region / tile_size);
  float probe_index = tile_index.y * info.counts.w + tile_index.x;

  vec4 stored = texelFetch(history, ivec2(floor(frag)), 0);
  if (tile_index.y < info.schedule.x || tile_index.y >= info.schedule.y) {
    frag_color = stored;
    return;
  }

  vec4 accumulated = texelFetch(injection, ivec2(floor(region)), 0);
  // Distances are normalized, so "nothing seen" is the far end of the range.
  vec2 target = vec2(1.0, 1.0);
  if (accumulated.a > 1e-6) {
    vec2 measured = accumulated.rg / accumulated.a;
    float coverage = clamp(accumulated.a / kCoverageWeight, 0.0, 1.0);
    target = mix(vec2(1.0, 1.0), measured, coverage);
  }

  vec3 slot = vec3(
      mod(probe_index, info.counts.x),
      mod(floor(probe_index / info.counts.x), info.counts.y),
      floor(probe_index / (info.counts.x * info.counts.y)));
  vec3 lattice = info.anchor.xyz +
                 ProbeWrapSlot(slot - info.anchor.xyz, info.counts.xyz);
  bool scrolled = any(lessThan(lattice, info.previous.xyz)) ||
                  any(greaterThanEqual(lattice,
                                       info.previous.xyz + info.counts.xyz));

  float retention = (scrolled || info.previous.w > 0.5) ? 0.0 : info.blend.x;
  vec2 blended = mix(target, stored.rg, retention);
  frag_color = vec4(blended, 0.0, 1.0);
}
