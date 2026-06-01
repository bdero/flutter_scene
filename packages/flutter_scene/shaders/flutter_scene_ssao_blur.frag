// Depth-aware (bilateral) blur for the screen-space ambient occlusion
// buffer. Removes the per-pixel variation of the occlusion estimate while
// preserving edges at depth discontinuities, so occlusion does not bleed
// across silhouettes.
//
// The kernel is a 4x4 box matching the occlusion pass's 4x4 interleaved
// rotation tile: averaging one full tile period sees all 16 rotations, which
// is what turns the interleaved pattern into a smooth result. A separable or
// Gaussian-weighted kernel would not average the rotations evenly and would
// leave residual structure.
//
// The bilateral weight is plane-aware: it subtracts the surface's own
// screen-space depth gradient before testing the difference, so a slanted or
// detailed (but continuous) surface still blurs, while a real depth step at a
// silhouette, far larger than the local gradient, still cuts the blur.

uniform sampler2D ao_texture;
uniform sampler2D linear_depth;

uniform BlurInfo {
  // xy: texel size (reciprocal of the occlusion target size). z: depth
  // falloff scale (world units) for the bilateral weight. w: unused.
  vec4 texel;
}
blur;

in vec2 v_uv;
out vec4 frag_color;

// Offsets span one 4x4 tile period (-2..1) so every interleaved rotation is
// covered exactly once. Constant bounds for the GLES 1.00 shader output.
#define BLUR_LO -2
#define BLUR_HI 1

const float kEpsilon = 0.0001;

void main() {
  float center_depth = texture(linear_depth, v_uv).r;
  float depth_scale = max(blur.texel.z, kEpsilon);
  // Per-pixel depth gradient, clamped so a silhouette (huge gradient) does not
  // open the bilateral up enough to bleed across it.
  float gradient = min(fwidth(center_depth), depth_scale);

  float ao_sum = 0.0;
  float weight_sum = 0.0;
  for (int y = BLUR_LO; y <= BLUR_HI; y++) {
    for (int x = BLUR_LO; x <= BLUR_HI; x++) {
      vec2 uv = v_uv + vec2(float(x), float(y)) * blur.texel.xy;
      float depth = texture(linear_depth, uv).r;
      // Depth difference beyond what the smooth surface gradient predicts.
      float expected = gradient * length(vec2(float(x), float(y)));
      float delta = max(abs(depth - center_depth) - expected, 0.0);
      float weight = exp(-delta / depth_scale);
      ao_sum += texture(ao_texture, uv).r * weight;
      weight_sum += weight;
    }
  }

  float ao = ao_sum / max(weight_sum, kEpsilon);
  frag_color = vec4(ao, ao, ao, 1.0);
}
