// The lit shader's read of the world-space irradiance field.
//
// Eight probes of the cage enclosing the shading point are fetched and
// combined, each weighted by its trilinear share, a wrap-shading term that
// fades a probe behind the surface instead of cutting it, and (when the
// visibility term is on) a Chebyshev bound on whether the probe can see this
// point at all. The taps are unrolled as a plain expression tree with no loop
// and no early return, which is what keeps the ANGLE and FXC translation
// paths safe.
//
// Requires the FragInfo block, the `irradiance_field` sampler, and
// irradiance_field.glsl.

// Weights below this are crushed rather than cut, suppressing contributions
// too small to matter without introducing a hard boundary.
const float kProbeCrushThreshold = 0.2;

// Floor on the Chebyshev term. A fully zeroed weight leaves the receiver no
// fallback and reads as a hard black seam, so this is not an optimization to
// remove.
const float kProbeVisibilityFloor = 0.05;

// One cage probe's contribution, premultiplied by its weight in rgb with the
// weight itself in alpha. Single return; a probe outside the volume falls out
// as a zero rather than an early exit.
vec4 IrradianceCageTap(vec3 offset, vec3 base_lattice, vec3 alpha,
                       vec3 biased_position, vec3 direction) {
  vec3 counts = frag_info.gi_counts.xyz;
  vec3 lattice = base_lattice + offset;
  // TODO(gi-far-origin): subtract anchor on CPU and upload relative lattice
  // to avoid fp32 precision loss far from origin.
  vec3 relative = lattice - frag_info.gi_anchor.xyz;
  float inside =
      (any(lessThan(relative, vec3(0.0))) ||
       any(greaterThanEqual(relative, counts)))
          ? 0.0
          : 1.0;

  // Trilinear weights are floored per axis for the same reason the wrap
  // weight has a floor: a receiver whose whole cage sits on one side needs
  // something left to normalize by.
  vec3 trilinear = max(mix(vec3(1.0) - alpha, alpha, offset), vec3(0.001));
  float trilinear_weight = trilinear.x * trilinear.y * trilinear.z;

  vec3 probe_position = lattice * frag_info.gi_grid.xyz;
  vec3 to_probe = probe_position - biased_position;
  float probe_distance = length(to_probe);
  vec3 probe_direction =
      probe_distance > 1e-5 ? to_probe / probe_distance : direction;

  // The +0.2 floor is load-bearing. Without it a receiver whose whole cage
  // faces away has no contribution left and goes black.
  float weight = pow(dot(probe_direction, direction) * 0.5 + 0.5, 2.0) + 0.2;

  float index = ProbeLinearIndex(ProbeWrapSlot(lattice, counts), counts);
  vec2 inverse_atlas = frag_info.gi_atlas.zw;

  if (frag_info.gi_visibility.x > 0.0) {
    vec2 depth_tile = ProbeTileOrigin(index, frag_info.gi_counts.w,
                                      frag_info.gi_atlas.y, kProbeDepthTile);
    // Moments are stored normalized by the probe's maximum recorded distance,
    // so both are scaled back before the comparison. Skipping that produces
    // banded, distance-dependent leaking that reads as a bias problem.
    float scale = frag_info.gi_visibility.z;
    vec2 moments = texture(irradiance_field,
                           ProbeAtlasUv(-probe_direction, depth_tile,
                                        kProbeDepthInterior, inverse_atlas))
                       .rg;
    float mean = moments.x * scale;
    float mean_square = moments.y * scale * scale;
    // Filtering pushes the difference slightly negative, hence the abs.
    float variance = abs(mean * mean - mean_square);
    float excess = probe_distance - mean - frag_info.gi_visibility.y;
    float chebyshev =
        excess <= 0.0 ? 1.0 : variance / (variance + excess * excess);
    chebyshev = max(kProbeVisibilityFloor,
                    chebyshev * chebyshev * chebyshev);
    weight *= mix(1.0, chebyshev, frag_info.gi_visibility.x);
  }

  weight = max(1e-6, weight);
  if (weight < kProbeCrushThreshold) {
    weight *= weight * weight / (kProbeCrushThreshold * kProbeCrushThreshold);
  }
  weight *= trilinear_weight * inside;

  vec2 irradiance_tile =
      ProbeTileOrigin(index, frag_info.gi_counts.w, frag_info.gi_atlas.x,
                      kProbeIrradianceTile);
  vec3 irradiance =
      texture(irradiance_field,
              ProbeAtlasUv(direction, irradiance_tile,
                           kProbeIrradianceInterior, inverse_atlas))
          .rgb;
  return vec4(max(irradiance, vec3(0.0)) * weight, weight);
}

// How much of the field applies at [world_position], fading to zero across
// the outermost cell so the volume boundary is continuous rather than a seam.
// Zero when the field is off.
float IrradianceFieldCoverage(vec3 world_position) {
  if (frag_info.gi_grid.w <= 0.0) return 0.0;
  vec3 lattice = world_position / frag_info.gi_grid.xyz;
  vec3 relative = lattice - frag_info.gi_anchor.xyz;
  vec3 inset = min(relative, frag_info.gi_counts.xyz - vec3(1.0) - relative);
  float edge = min(inset.x, min(inset.y, inset.z));
  return clamp(edge / max(frag_info.gi_visibility.w, 1e-3), 0.0, 1.0);
}

// The field's E(n)/pi in [direction] at [world_position]. [view] points from
// the surface toward the camera.
vec3 SampleIrradianceField(vec3 world_position, vec3 direction, vec3 view) {
  vec3 spacing = frag_info.gi_grid.xyz;
  float cell = min(spacing.x, min(spacing.y, spacing.z));
  // The 2021 unified self-shadow bias, expressed as a fraction of the cell
  // edge so one default holds across scene scales.
  vec3 biased_position =
      world_position +
      (direction * 0.2 + view * 0.8) * (0.75 * cell * frag_info.gi_anchor.w);
  vec3 lattice = biased_position / spacing;
  vec3 base = floor(lattice);
  vec3 alpha = clamp(lattice - base, 0.0, 1.0);

  vec4 total =
      IrradianceCageTap(vec3(0.0, 0.0, 0.0), base, alpha, biased_position,
                        direction) +
      IrradianceCageTap(vec3(1.0, 0.0, 0.0), base, alpha, biased_position,
                        direction) +
      IrradianceCageTap(vec3(0.0, 1.0, 0.0), base, alpha, biased_position,
                        direction) +
      IrradianceCageTap(vec3(1.0, 1.0, 0.0), base, alpha, biased_position,
                        direction) +
      IrradianceCageTap(vec3(0.0, 0.0, 1.0), base, alpha, biased_position,
                        direction) +
      IrradianceCageTap(vec3(1.0, 0.0, 1.0), base, alpha, biased_position,
                        direction) +
      IrradianceCageTap(vec3(0.0, 1.0, 1.0), base, alpha, biased_position,
                        direction) +
      IrradianceCageTap(vec3(1.0, 1.0, 1.0), base, alpha, biased_position,
                        direction);

  vec3 result = total.a > 1e-6 ? total.rgb / total.a : vec3(0.0);
  return result * frag_info.gi_grid.w;

}
