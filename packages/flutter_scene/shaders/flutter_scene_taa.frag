// Temporal Anti-Aliasing (TAA) resolve shader.
//
// Performs 3x3 velocity dilation, camera reprojection from linear depth,
// Catmull-Rom history sampling, YCoCg variance clipping, tone-mapped history
// mix, and optional sharpening.

uniform TaaInfo {
  mat4 current_to_previous_view_projection;
  vec4 camera_position;
  vec4 projection_params; // xy: tanHalfFovX, tanHalfFovY, z: far, w: near
  vec4 jitter_params; // xy: current jitter NDC, zw: previous jitter NDC
  vec4 taa_settings; // x: minimumCurrentWeight, y: varianceGamma, z: sharpness, w: objectMotion
  vec4 screen_size; // xy: width, height, zw: 1.0/width, 1.0/height
} info;

uniform sampler2D current_color;
uniform sampler2D history_color;
uniform sampler2D velocity_texture;
uniform sampler2D current_depth;
uniform sampler2D previous_depth;

in vec2 v_uv;

out vec4 frag_color;

vec3 RGB2YCoCg(vec3 c) {
  return vec3(
    0.25 * c.r + 0.5 * c.g + 0.25 * c.b,
    0.5 * c.r - 0.5 * c.b,
    -0.25 * c.r + 0.5 * c.g - 0.25 * c.b
  );
}

vec3 YCoCg2RGB(vec3 c) {
  return vec3(
    c.x + c.y - c.z,
    c.x + c.z,
    c.x - c.y - c.z
  );
}

vec3 ToneMap(vec3 c) {
  c = max(vec3(0.0), c);
  float luma = dot(c, vec3(0.2126, 0.7152, 0.0722));
  return c / (1.0 + luma);
}

vec3 UnToneMap(vec3 c) {
  c = max(vec3(0.0), c);
  float luma = dot(c, vec3(0.2126, 0.7152, 0.0722));
  return c / max(1.0 - luma, 1e-4);
}

// 5-tap Catmull-Rom history filter to prevent texture softening.
vec4 SampleCatmullRom(sampler2D tex, vec2 uv, vec2 texel_size) {
  vec2 sample_pos = uv / texel_size;
  vec2 tc = floor(sample_pos - 0.5) + 0.5;
  vec2 f = sample_pos - tc;
  vec2 f2 = f * f;
  vec2 f3 = f2 * f;

  vec2 w0 = f2 - 0.5 * (f3 + f);
  vec2 w1 = 1.5 * f3 - 2.5 * f2 + 1.0;
  vec2 w3 = 0.5 * (f3 - f2);
  vec2 w2 = 1.0 - w0 - w1 - w3;

  vec2 w12 = w1 + w2;
  vec2 tc12 = tc + w2 / w12;

  vec2 tc0 = tc - 1.0;
  vec2 tc3 = tc + 2.0;

  vec4 result =
      textureLod(tex, vec2(tc12.x, tc0.y) * texel_size, 0.0) * (w12.x * w0.y) +
      textureLod(tex, vec2(tc0.x, tc12.y) * texel_size, 0.0) * (w0.x * w12.y) +
      textureLod(tex, vec2(tc12.x, tc12.y) * texel_size, 0.0) * (w12.x * w12.y) +
      textureLod(tex, vec2(tc3.x, tc12.y) * texel_size, 0.0) * (w3.x * w12.y) +
      textureLod(tex, vec2(tc12.x, tc3.y) * texel_size, 0.0) * (w12.x * w3.y);

  return result / (w12.x * w0.y + w0.x * w12.y + w12.x * w12.y + w3.x * w12.y + w12.x * w3.y);
}

void main() {
  vec2 uv = v_uv;
  vec2 texel_size = info.screen_size.zw;

  // 1. Velocity dilation: find closest depth in 3x3 neighborhood.
  float closest_depth = 1e8;
  vec2 closest_uv = uv;
  for (int dy = -1; dy <= 1; dy++) {
    for (int dx = -1; dx <= 1; dx++) {
      vec2 tap_uv = uv + vec2(float(dx), float(dy)) * texel_size;
      float d = textureLod(current_depth, tap_uv, 0.0).r;
      if (d > 0.0 && d < closest_depth) {
        closest_depth = d;
        closest_uv = tap_uv;
      }
    }
  }

  // 2. Sample object velocity.
  vec4 obj_vel = textureLod(velocity_texture, closest_uv, 0.0);
  vec2 object_delta = (obj_vel.b > 0.5 && info.taa_settings.w > 0.5) ? obj_vel.rg : vec2(0.0);

  // 3. Compute camera velocity at closest depth.
  float depth = closest_depth < 1e7 ? closest_depth : textureLod(current_depth, uv, 0.0).r;
  vec2 screen_ndc = vec2(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0);
  vec2 unjittered_ndc = screen_ndc - info.jitter_params.xy;

  vec4 prev_clip;
  if (depth > 0.0 && depth < info.projection_params.z) {
    vec3 view_pos = vec3(unjittered_ndc.x * depth * info.projection_params.x,
                         unjittered_ndc.y * depth * info.projection_params.y, depth);
    prev_clip = info.current_to_previous_view_projection * vec4(view_pos, 1.0);
  } else {
    vec3 view_dir = vec3(unjittered_ndc.x * info.projection_params.x,
                         unjittered_ndc.y * info.projection_params.y, 1.0);
    prev_clip = info.current_to_previous_view_projection * vec4(view_dir, 0.0);
  }

  bool history_valid = true;
  vec2 total_velocity_uv;
  vec2 history_uv;
  vec2 unjittered_uv = vec2(unjittered_ndc.x * 0.5 + 0.5, 0.5 - unjittered_ndc.y * 0.5);

  if (prev_clip.w <= 1e-6) {
    history_valid = false;
    history_uv = unjittered_uv;
    total_velocity_uv = vec2(0.0);
  } else {
    vec2 prev_screen_ndc = prev_clip.xy / prev_clip.w;
    vec2 prev_uv_camera = vec2(prev_screen_ndc.x * 0.5 + 0.5, 0.5 - prev_screen_ndc.y * 0.5);
    vec2 camera_velocity_uv = unjittered_uv - prev_uv_camera;

    total_velocity_uv = camera_velocity_uv + object_delta;
    history_uv = unjittered_uv - total_velocity_uv;

    // 4. History rejection.
    if (history_uv.x < 0.0 || history_uv.x > 1.0 || history_uv.y < 0.0 || history_uv.y > 1.0) {
      history_valid = false;
    } else if (depth > 0.0 && depth < info.projection_params.z) {
      float prev_depth = textureLod(previous_depth, history_uv, 0.0).r;
      float expected_depth = prev_clip.w;
      if (prev_depth > 0.0 && abs(prev_depth - expected_depth) / max(depth, 1.0) > 0.2) {
        history_valid = false;
      }
    }
  }

  // 5. Neighborhood sampling and variance clipping in YCoCg space.
  vec3 current_center = textureLod(current_color, uv, 0.0).rgb;
  vec3 m1 = vec3(0.0);
  vec3 m2 = vec3(0.0);
  vec3 neighbor_min = vec3(1e6);
  vec3 neighbor_max = vec3(-1e6);

  vec3 cross_blur = vec3(0.0);
  for (int dy = -1; dy <= 1; dy++) {
    for (int dx = -1; dx <= 1; dx++) {
      vec2 tap_uv = uv + vec2(float(dx), float(dy)) * texel_size;
      vec3 col = textureLod(current_color, tap_uv, 0.0).rgb;
      if (abs(dx) + abs(dy) == 1) {
        cross_blur += col;
      }
      vec3 ycocg = RGB2YCoCg(col);
      m1 += ycocg;
      m2 += ycocg * ycocg;
      neighbor_min = min(neighbor_min, ycocg);
      neighbor_max = max(neighbor_max, ycocg);
    }
  }

  vec3 mu = m1 / 9.0;
  vec3 sigma = sqrt(max(vec3(0.0), m2 / 9.0 - mu * mu));
  float gamma = info.taa_settings.y;
  vec3 box_min = max(neighbor_min, mu - sigma * gamma);
  vec3 box_max = min(neighbor_max, mu + sigma * gamma);

  // 6. History sampling and clamping.
  vec3 history_sample = SampleCatmullRom(history_color, history_uv, texel_size).rgb;
  vec3 history_ycocg = RGB2YCoCg(history_sample);
  vec3 clamped_history_ycocg = clamp(history_ycocg, box_min, box_max);
  vec3 clamped_history = max(vec3(0.0), YCoCg2RGB(clamped_history_ycocg));

  // 7. Tone-mapped mix.
  float vel_len = length(total_velocity_uv * info.screen_size.xy);
  float weight = max(info.taa_settings.x, min(0.2, vel_len * 0.02));
  if (!history_valid) {
    weight = 1.0;
  }

  vec3 tm_curr = ToneMap(current_center);
  vec3 tm_hist = ToneMap(clamped_history);
  vec3 resolved_tm = mix(tm_hist, tm_curr, weight);
  float tm_luma = dot(resolved_tm, vec3(0.2126, 0.7152, 0.0722));
  if (tm_luma > 0.999) {
    resolved_tm *= 0.999 / tm_luma;
  }
  vec3 resolved = max(vec3(0.0), UnToneMap(resolved_tm));

  // 8. Optional sharpening.
  if (info.taa_settings.z > 0.0) {
    vec3 blur = cross_blur * 0.25;
    vec3 sharpened = resolved + (resolved - blur) * info.taa_settings.z;
    resolved = max(vec3(0.0), sharpened);
  }

  frag_color = vec4(resolved, 1.0);
}
