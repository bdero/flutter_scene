// Depth-aware (bilateral) blur for the screen-space ambient occlusion
// buffer. Removes the per-pixel variation of the occlusion estimate while
// preserving edges at depth discontinuities, so occlusion does not bleed
// across silhouettes.
//
// Runs once per axis as a separable 9-tap Gaussian. The bilateral weight is
// plane-aware, so a sloped continuous surface filters while a depth step cuts
// the kernel. The wider non-box filter removes stochastic sample noise without
// imprinting a horizontal or vertical tile period.

uniform sampler2D ao_texture;
uniform sampler2D linear_depth;

uniform BlurInfo {
  // xy: texel size (reciprocal of the occlusion target size). z: depth
  // falloff scale (world units). w: 1 on the final pass, otherwise 0.
  vec4 texel;
  // xy: filter axis. z: 1 when ba carries an octahedrally packed bent normal
  // that must be renormalized after filtering. w: unused.
  vec4 axis;
}
blur;

in vec2 v_uv;
out vec4 frag_color;

#define BLUR_RADIUS 4

const float kEpsilon = 0.0001;

#include <interleaved_gradient_noise.glsl>
#include <octahedral.glsl>

float GaussianWeight(int offset) {
  int i = abs(offset);
  if (i == 0) return 0.153170;
  if (i == 1) return 0.144893;
  if (i == 2) return 0.122649;
  if (i == 3) return 0.092902;
  return 0.062970;
}

void main() {
  float center_depth = texture(linear_depth, v_uv).r;
  float depth_scale = max(blur.texel.z, kEpsilon);
  vec2 gradient = vec2(dFdx(center_depth), dFdy(center_depth));

  vec4 ao_sum = vec4(0.0);
  float weight_sum = 0.0;
  for (int i = -BLUR_RADIUS; i <= BLUR_RADIUS; i++) {
    vec2 pixel_offset = blur.axis.xy * float(i);
    vec2 uv = v_uv + pixel_offset * blur.texel.xy;
    float depth = texture(linear_depth, uv).r;
    float slope = clamp(dot(gradient, pixel_offset), -depth_scale, depth_scale);
    float delta = abs(depth - (center_depth + slope));
    float weight = GaussianWeight(i) * exp(-delta / depth_scale);
    ao_sum += texture(ao_texture, uv) * weight;
    weight_sum += weight;
  }

  vec4 result = ao_sum / max(weight_sum, kEpsilon);
  if (blur.texel.w > 0.5) {
    result.r += (InterleavedGradientNoise(gl_FragCoord.xy) - 0.5) / 255.0;
    if (blur.axis.z > 0.5) {
      // Filtering octahedral coordinates off-lattice skews the direction
      // slightly; a decode/encode round trip snaps it back to unit length.
      result.ba = OctEncode(OctDecode(result.ba));
    }
  }
  result.r = clamp(result.r, 0.0, 1.0);
  frag_color = result;
}
