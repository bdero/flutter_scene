// Folds one frame of scattered radiance into a probe's stored irradiance.
//
// The accumulator's weighted mean is a cosine-weighted average of incoming
// radiance, which is E(n)/pi, the same quantity the environment's spherical
// harmonics give, so the two compose without a scale factor. A texel no
// sample reached falls back to the environment, which makes an empty field
// read exactly like the image without one and makes the transition per texel
// and continuous.
//
// The temporal blend follows the reference implementation. Retention is
// authored at a 60 Hz cadence and raised to the probe's real service
// interval, a texel whose luminance moved more than a variance-scaled sigma
// drops toward a floor so real lighting changes are not smeared, the history
// is soft-clamped into a wide band before mixing, and the step is floored at
// one storage quantum so a high-retention probe cannot stall short of its
// target.

#include <diffuse_sh.glsl>
#include <irradiance_field.glsl>

uniform BlendInfo {
  // Rotates a probe's octahedral direction into the environment's frame
  // before the spherical-harmonic fallback is evaluated.
  mat4 environment_transform;
  // x: retention at this frame's cadence. y: change-detector sigma scale.
  // z: how far retention drops on a detected change. w: the retention floor.
  vec4 blend;
  // x: cross-fade toward the secondary environment. y: environment intensity,
  // premultiplied into the fallback so the receiver never scales the field.
  // z: stored tile edge. w: interior edge.
  vec4 environment;
  // xyz: probe counts per axis. w: probe tiles per atlas row.
  vec4 counts;
  // xyz: the volume's minimum-corner lattice index. w: this region's first
  // atlas row.
  vec4 anchor;
  // xyz: the previous frame's minimum-corner lattice index. w: 1 forces every
  // probe to snap, for the frame after the field is created or invalidated.
  vec4 previous;
  // xy: the half-open range of tile rows this frame refreshes. Rows outside
  // it carry their history through, so an amortized update still leaves the
  // whole atlas valid for the ping-ponged buffers. z: the region's total tile
  // rows. Each draw covers the whole atlas and discards outside its own
  // region, rather than relying on a render-target viewport, whose vertical
  // origin is not guaranteed to agree across backends.
  vec4 schedule;
}
info;

// This frame's scattered samples, one tile per probe and nothing else.
uniform highp sampler2D injection;
// The previous frame's blended atlas.
uniform highp sampler2D history;
// The environment's 9-coefficient diffuse strip, the fallback content.
uniform highp sampler2D sh_strip;

out vec4 frag_color;

// Weight sum at which a texel is considered fully covered by this frame's
// samples. Below it the fallback fades back in, so one grazing sample cannot
// speak for a whole direction.
const float kCoverageWeight = 0.25;

// Width of the band the history is soft-clamped into, in standard
// deviations. Wide enough to leave a converging probe alone and narrow
// enough to catch a stale value.
const float kClampSigmas = 6.0;

// Relative quantum the blend step is floored at, so `(1 - retention) * delta`
// cannot round to nothing and strand a probe short of its target.
const float kProgressQuantum = 1.0 / 1024.0;

void main() {
  vec2 frag = gl_FragCoord.xy;
  vec2 region = vec2(frag.x, frag.y - info.anchor.w);
  float tile_size = info.environment.z;
  float interior = info.environment.w;

  if (region.y < 0.0 || region.y >= info.schedule.z * tile_size ||
      region.x >= info.counts.w * tile_size) {
    discard;
  }

  vec2 tile_index = floor(region / tile_size);
  vec2 tile_origin = tile_index * tile_size;
  float probe_index = tile_index.y * info.counts.w + tile_index.x;

  vec4 stored = texelFetch(history, ivec2(floor(frag)), 0);
  if (tile_index.y < info.schedule.x || tile_index.y >= info.schedule.y) {
    frag_color = stored;
    return;
  }

  vec2 oct = clamp(ProbeInteriorCoord(region, tile_origin) / interior, 0.0,
                   1.0);
  vec3 direction = ProbeOctDecode(oct);

  vec4 accumulated = texelFetch(injection, ivec2(floor(region)), 0);
  vec3 environment_direction = mat3(info.environment_transform) * direction;
  vec3 fallback = max(EvaluateDiffuseSH(sh_strip, environment_direction, 0),
                      vec3(0.0));
  if (info.environment.x > 0.0) {
    vec3 secondary = max(
        EvaluateDiffuseSH(sh_strip, environment_direction, 1), vec3(0.0));
    fallback = mix(fallback, secondary, info.environment.x);
  }
  fallback *= info.environment.y;

  vec3 injected = accumulated.a > 1e-6
      ? max(accumulated.rgb / accumulated.a, vec3(0.0))
      : vec3(0.0);
  float coverage = clamp(accumulated.a / kCoverageWeight, 0.0, 1.0);
  vec3 target = mix(fallback, injected, coverage);

  // A probe whose lattice index left the previous volume holds another
  // location's lighting, so it snaps instead of lerping up from it. The test
  // is exact per probe and never escalates into a rebuild.
  vec3 slot = vec3(
      mod(probe_index, info.counts.x),
      mod(floor(probe_index / info.counts.x), info.counts.y),
      floor(probe_index / (info.counts.x * info.counts.y)));
  vec3 lattice = info.anchor.xyz +
                 ProbeWrapSlot(slot - info.anchor.xyz, info.counts.xyz);
  bool scrolled = any(lessThan(lattice, info.previous.xyz)) ||
                  any(greaterThanEqual(lattice,
                                       info.previous.xyz + info.counts.xyz));

  float retention = info.blend.x;
  if (scrolled || info.previous.w > 0.5) {
    retention = 0.0;
  }

  float stored_luma = ProbeLuminance(stored.rgb);
  float target_luma = ProbeLuminance(target);
  float sigma = sqrt(max(0.0, stored.a - stored_luma * stored_luma));
  retention = abs(target_luma - stored_luma) > sigma * info.blend.y
      ? max(info.blend.w, retention - info.blend.z)
      : min(1.0, retention + 0.25 * (1.0 - retention));
  if (scrolled || info.previous.w > 0.5) {
    retention = 0.0;
  }

  float band = kClampSigmas * sigma;
  vec3 clamped = clamp(stored.rgb, target - vec3(band), target + vec3(band));
  vec3 blended = mix(target, clamped, retention);

  vec3 delta = target - stored.rgb;
  vec3 step_taken = blended - stored.rgb;
  vec3 quantum = max(abs(target), vec3(1e-4)) * kProgressQuantum;
  step_taken = min(max(quantum, abs(step_taken)), abs(delta)) * sign(step_taken);
  blended = stored.rgb + step_taken;

  // The luminance second moment rides the free channel, so the filter's
  // variance-adaptive blur and the change detector above both come free.
  float second_moment = min(
      mix(target_luma * target_luma, stored.a, retention), 65000.0);
  frag_color = vec4(blended, second_moment);
}
