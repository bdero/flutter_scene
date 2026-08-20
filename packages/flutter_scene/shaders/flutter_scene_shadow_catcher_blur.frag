// Separable Gaussian blur for the shadow catcher's baked visibility cache.
// Runs once per axis over the footprint render. The bake resolution is
// derived from the catcher's softness so this fixed kernel spans the wanted
// world-space penumbra (softer bakes are smaller, not wider).

uniform sampler2D source_texture;

uniform CatcherBlurInfo {
  // xy: filter step (axis direction * texel size). zw: unused.
  vec4 step;
}
blur_info;

in vec2 v_uv;
out vec4 frag_color;

#define BLUR_RADIUS 4

float GaussianWeight(int offset) {
  int i = abs(offset);
  if (i == 0) return 0.153170;
  if (i == 1) return 0.144893;
  if (i == 2) return 0.122649;
  if (i == 3) return 0.092902;
  return 0.062970;
}

void main() {
  float sum = 0.0;
  float weight_sum = 0.0;
  for (int i = -BLUR_RADIUS; i <= BLUR_RADIUS; i++) {
    float weight = GaussianWeight(i);
    sum += texture(source_texture, v_uv + blur_info.step.xy * float(i)).r *
           weight;
    weight_sum += weight;
  }
  float visibility = sum / weight_sum;
  frag_color = vec4(visibility, visibility, visibility, 1.0);
}
