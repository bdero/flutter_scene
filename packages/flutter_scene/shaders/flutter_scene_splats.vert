// Gaussian splat vertex stage.
//
// Each instance is one splat; the per-instance attribute is the splat's
// index into the parameter texture (a float, since the broadest GLES tier
// has no integer attributes). The unit quad is expanded to cover the
// splat's projected footprint: the local 3D covariance (prefetched from the
// parameter texture) is pushed through the Jacobian of the full
// local-to-pixel mapping, and the resulting 2D covariance's eigenvectors
// give the quad axes. Instances arrive presorted back to front.

uniform FrameInfo {
  mat4 mvp_transform;   // camera view-projection * node world transform
  mat4 model_transform; // node world transform (for SH view direction)
  mat4 crop_transform;  // splat-local -> crop-box space (unit cube, +/-1)
  vec4 camera_position; // xyz: world camera; w: color mode (0 sRGB-encoded, 1 linear)
  vec4 params_texture;  // x: width, y: height (texels)
  vec4 sh_texture;      // x: width, y: height, z: texels per splat, w: SH degree
  vec4 viewport;        // xy: size in pixels; z: kernel mode (0 classic, 1 antialiased); w: splat scale
  vec4 params;          // x: opacity scale; y: crop mode (0 off, 1 include, 2 exclude); zw: reserved
  vec4 tint;            // linear RGBA multiplier
}
frame_info;

uniform sampler2D splat_params_texture;
uniform sampler2D splat_sh_texture;

// Slot 0: the unit quad, corners in [-1, 1].
in vec2 corner;
// Slot 1 (instance rate): this instance's splat index.
in float splat_index;

// Position within the footprint in standard-deviation units, and the
// splat's color (linear RGB) with its final opacity.
out vec2 v_quad;
out vec4 v_color;

// The largest footprint half-extent in standard deviations.
// exp(-0.5 * 3.33^2) is just under 1/255, so the cut is invisible at 8-bit
// blending precision. Dimmer splats use a tighter cut (their falloff drops
// below 1/255 sooner), which sharply reduces blended fill area in
// low-opacity clouds.
const float kSigmaCut = 3.33;

// Low-pass dilation applied to the projected covariance (in pixel^2),
// matching the training-time rasterizer's anti-aliasing convolution.
const float kKernel2D = 0.3;

const float kShC1 = 0.4886025119029199;
const float kShC2x = 1.0925484305920792;
const float kShC2z = 0.31539156525252005;
const float kShC2w = 0.5462742152960396;

vec4 fetchTexel(sampler2D tex, float index, vec2 dims) {
  float y = floor(index / dims.x);
  float x = index - y * dims.x;
  return texture(tex, vec2((x + 0.5) / dims.x, (y + 0.5) / dims.y));
}

void cull() {
  gl_Position = vec4(0.0, 0.0, 2.0, 1.0);
  v_quad = vec2(0.0);
  v_color = vec4(0.0);
}

void main() {
  float base = splat_index * 4.0;
  vec2 dims = frame_info.params_texture.xy;
  vec4 t0 = fetchTexel(splat_params_texture, base, dims);
  vec4 t1 = fetchTexel(splat_params_texture, base + 1.0, dims);
  vec4 t2 = fetchTexel(splat_params_texture, base + 2.0, dims);
  vec4 t3 = fetchTexel(splat_params_texture, base + 3.0, dims);

  // Crop volume: drop splats outside an include box or inside an exclude
  // box (the box is the unit cube in crop space).
  float crop_mode = frame_info.params.y;
  if (crop_mode > 0.5) {
    vec3 crop_pos = (frame_info.crop_transform * vec4(t0.xyz, 1.0)).xyz;
    bool inside = all(lessThanEqual(abs(crop_pos), vec3(1.0)));
    if (crop_mode < 1.5 ? !inside : inside) {
      cull();
      return;
    }
  }

  vec4 clip = frame_info.mvp_transform * vec4(t0.xyz, 1.0);
  vec3 ndc = clip.xyz / clip.w;
  // Cull splats behind the camera or far outside the frustum (the margin
  // leaves room for large footprints straddling the edge).
  if (clip.w <= 0.0 || abs(ndc.x) > 1.3 || abs(ndc.y) > 1.3 || ndc.z > 1.0) {
    cull();
    return;
  }

  // Local 3D covariance, scaled by the footprint multiplier.
  float s2 = frame_info.viewport.w * frame_info.viewport.w;
  mat3 cov3d =
      mat3(t1.x, t1.y, t1.z, t1.y, t1.w, t2.x, t1.z, t2.x, t2.y) * s2;

  // Rows of the MVP needed for the Jacobian of local -> NDC (the analytic
  // derivative of the projective divide).
  mat4 m = frame_info.mvp_transform;
  vec3 row_x = vec3(m[0][0], m[1][0], m[2][0]);
  vec3 row_y = vec3(m[0][1], m[1][1], m[2][1]);
  vec3 row_w = vec3(m[0][3], m[1][3], m[2][3]);
  vec2 half_viewport = 0.5 * frame_info.viewport.xy;
  // d(pixel)/d(local), one row per screen axis. This composes the model
  // transform, the view-projection, and the perspective divide in one step,
  // so the covariance below lands directly in pixel^2.
  vec3 jx = (row_x - ndc.x * row_w) * (half_viewport.x / clip.w);
  vec3 jy = (row_y - ndc.y * row_w) * (half_viewport.y / clip.w);

  // 2D covariance: J * cov3d * J^T, expanded through the symmetric product.
  vec3 cx = cov3d * jx;
  float cov_a = dot(jx, cx);
  float cov_b = dot(jy, cx);
  float cov_d = dot(jy, cov3d * jy);

  // Low-pass kernel: dilate by kKernel2D pixels^2. The antialiased mode
  // compensates opacity by the footprint growth so small splats dim instead
  // of shimmering.
  float det_raw = cov_a * cov_d - cov_b * cov_b;
  cov_a += kKernel2D;
  cov_d += kKernel2D;
  float det = cov_a * cov_d - cov_b * cov_b;
  float opacity = t0.w * frame_info.params.x;
  if (frame_info.viewport.z > 0.5) {
    opacity *= sqrt(max(det_raw / det, 0.0));
  }

  // The final blended alpha bounds the useful footprint: past the radius
  // where the falloff drops under 1/255, fragments only discard. Tighten
  // the cut per splat so dim splats rasterize far fewer pixels.
  float alpha = clamp(opacity, 0.0, 1.0) * frame_info.tint.a;
  if (alpha < 1.0 / 255.0) {
    cull();
    return;
  }
  float sigma_cut = min(kSigmaCut, sqrt(2.0 * log(alpha * 255.0)));

  // Eigen-decomposition of the symmetric 2x2 covariance.
  float mid = 0.5 * (cov_a + cov_d);
  float delta = sqrt(max(mid * mid - det, 0.0));
  float lambda1 = mid + delta;
  float lambda2 = max(mid - delta, 0.01);
  vec2 axis1 = abs(cov_b) > 1e-6
      ? normalize(vec2(cov_b, lambda1 - cov_a))
      : (cov_a >= cov_d ? vec2(1.0, 0.0) : vec2(0.0, 1.0));
  vec2 axis2 = vec2(-axis1.y, axis1.x);
  // Clamp against a pathological footprint (the camera sitting inside a
  // giant Gaussian) so one splat cannot rasterize far past the screen.
  float max_radius = frame_info.viewport.x + frame_info.viewport.y;
  float radius1 = min(sigma_cut * sqrt(lambda1), max_radius);
  float radius2 = min(sigma_cut * sqrt(lambda2), max_radius);

  vec2 offset_px = corner.x * radius1 * axis1 + corner.y * radius2 * axis2;
  gl_Position =
      vec4(ndc.xy * clip.w + offset_px / half_viewport * clip.w, clip.zw);
  v_quad = corner * sigma_cut;

  // Color: the base (degree 0) term plus the view-dependent rest bands.
  vec3 color = t3.rgb;
  float degree = frame_info.sh_texture.w;
  if (degree >= 1.0) {
    vec3 world_pos = (frame_info.model_transform * vec4(t0.xyz, 1.0)).xyz;
    vec3 dir = normalize(world_pos - frame_info.camera_position.xyz);
    float x = dir.x;
    float y = dir.y;
    float z = dir.z;
    float sh_base = splat_index * frame_info.sh_texture.z;
    vec2 sh_dims = frame_info.sh_texture.xy;
    vec3 c0 = fetchTexel(splat_sh_texture, sh_base, sh_dims).rgb;
    vec3 c1 = fetchTexel(splat_sh_texture, sh_base + 1.0, sh_dims).rgb;
    vec3 c2 = fetchTexel(splat_sh_texture, sh_base + 2.0, sh_dims).rgb;
    color += kShC1 * (-y * c0 + z * c1 - x * c2);
    if (degree >= 2.0) {
      vec3 c3 = fetchTexel(splat_sh_texture, sh_base + 3.0, sh_dims).rgb;
      vec3 c4 = fetchTexel(splat_sh_texture, sh_base + 4.0, sh_dims).rgb;
      vec3 c5 = fetchTexel(splat_sh_texture, sh_base + 5.0, sh_dims).rgb;
      vec3 c6 = fetchTexel(splat_sh_texture, sh_base + 6.0, sh_dims).rgb;
      vec3 c7 = fetchTexel(splat_sh_texture, sh_base + 7.0, sh_dims).rgb;
      color += kShC2x * x * y * c3;
      color += -kShC2x * y * z * c4;
      color += kShC2z * (2.0 * z * z - x * x - y * y) * c5;
      color += -kShC2x * x * z * c6;
      color += kShC2w * (x * x - y * y) * c7;
    }
  }
  color = max(color, vec3(0.0));
  // Captured splats are trained against display-encoded images; decode to
  // linear for the scene's linear HDR pipeline. Mode 1 skips the decode.
  if (frame_info.camera_position.w < 0.5) {
    color = pow(color, vec3(2.2));
  }
  v_color = vec4(color * frame_info.tint.rgb, alpha);
}
