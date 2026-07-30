// Auto exposure adaptation: turns the metered mean log-luminance into a
// clamped exposure-correction factor and eases the persistent one-pixel
// adaptation state toward it. The eased factor is what the resolve pass
// multiplies with the scene's base exposure. Mirrored in Dart by
// autoExposureTargetFactor/autoExposureBlend for unit testing; keep the
// curves in sync.

uniform AutoExposureAdaptInfo {
  // The strength exponent applied to the correction toward the reference.
  float strength;
  // exp2 of the EV compensation, min, and max settings.
  float compensation_factor;
  float min_factor;
  float max_factor;
  // Precomputed 1 - exp(-dt * speed) blend weights for a falling factor
  // (scene got brighter) and a rising one (scene got darker).
  float blend_up;
  float blend_down;
  // 1.0 -> land on the target immediately (first frame or reset()).
  float snap;
  float _pad0;
}
adapt_info;

// 1x1 metered result: (weight * mean log-luminance, weight, 0, 1).
uniform sampler2D metered;
// 1x1 previous adapted factor in r.
uniform sampler2D previous_adapted;

out vec4 frag_color;

const float kReferenceLuminance = 0.18;

void main() {
  vec2 m = texture(metered, vec2(0.5, 0.5)).rg;
  float mean_luminance = max(exp(m.x / max(m.y, 1e-6)), 1e-6);
  float target = pow(kReferenceLuminance / mean_luminance,
                     adapt_info.strength) *
                 adapt_info.compensation_factor;
  target = clamp(target, adapt_info.min_factor, adapt_info.max_factor);

  float previous = texture(previous_adapted, vec2(0.5, 0.5)).r;
  float blend =
      target < previous ? adapt_info.blend_up : adapt_info.blend_down;
  float adapted =
      adapt_info.snap > 0.5 ? target : mix(previous, target, blend);

  frag_color = vec4(adapted, 0.0, 0.0, 1.0);
}
