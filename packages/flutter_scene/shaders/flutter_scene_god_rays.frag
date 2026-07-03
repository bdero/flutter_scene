// Directional volumetric god rays (crepuscular rays) as a full-screen
// post-process. Marches the view ray from the camera to the depth-buffer
// surface, sampling the directional light's cascaded shadow map per step to
// decide where sunlight reaches, and accumulates single-scattering with a
// Henyey-Greenstein phase and Beer-Lambert extinction. The in-scattered light
// is added to the linear-HDR scene color before tone mapping.
//
// Runs through the custom-pass API: `input_color` is the scene color,
// `input_depth` the engine's linear (view-space) depth, `input_shadow` the
// cascaded shadow atlas, with PostCameraInfo/PostShadowInfo describing how to
// reconstruct world positions and sample the cascades.

uniform sampler2D input_color;
uniform sampler2D input_depth;
uniform sampler2D input_shadow;

// resolution: (w, h, 1/w, 1/h). frame: (time, -, -, -). Bound by applyShader.
uniform PostFrameInfo {
  vec4 resolution;
  vec4 frame;
}
post_frame;

// projection: (tan(fovX/2), tan(fovY/2), near, far). Then the view basis
// (right, up, forward) and the camera world position.
uniform PostCameraInfo {
  vec4 projection;
  vec4 camera_right;
  vec4 camera_up;
  vec4 camera_forward;
  vec4 camera_position;
}
cam;

// Per-cascade world->light-clip matrices, view-space split distances, the light
// travel direction (xyz) with the cascade count in w, and the light color.
uniform PostShadowInfo {
  mat4 light_space_matrix[4];
  vec4 cascade_splits;
  vec4 light_direction;
  vec4 light_color;
}
shadow;

// params0: (intensity, density, anisotropy g, step count).
// params1: (max distance, jitter, -, -). color: rgb tint * the light color.
uniform GodRaysInfo {
  vec4 params0;
  vec4 params1;
  vec4 color;
}
god;

in vec2 v_uv;
out vec4 frag_color;

const float kPi = 3.14159265359;
const int kMaxSteps = 64;
// A small light-clip-space bias so a lit volume sample does not shadow itself
// against the surface that cast into the same texel.
const float kShadowBias = 0.0015;

// Reconstructs the view-space position at [uv] from the linear depth (the eye
// at the origin looking down +forward; see PostCameraInfo).
vec3 ViewPositionAt(vec2 uv) {
  float z = texture(input_depth, uv).r;
  vec2 ndc = vec2(2.0 * uv.x - 1.0, 1.0 - 2.0 * uv.y);
  return vec3(ndc.x * z * cam.projection.x, ndc.y * z * cam.projection.y, z);
}

// One cascade's shadow test for world point P: transform into the cascade's
// clip space; if the point lies inside the tile, sample the atlas and return
// 1 (lit) or 0 (shadowed) through [result]. Returns whether the point was
// inside this cascade. Unrolled with literal indices at the call sites, since
// dynamic indexing of the uniform matrix array is invalid on GLES 1.00.
#define TRY_CASCADE(IDX, P, COUNT, RESULT)                                 \
  {                                                                        \
    vec4 lc = shadow.light_space_matrix[IDX] * vec4(P, 1.0);               \
    vec3 proj = lc.xyz / lc.w;                                             \
    if (abs(proj.x) < 1.0 && abs(proj.y) < 1.0) {                          \
      vec2 tile_uv = proj.xy * 0.5 + 0.5;                                  \
      vec2 atlas_uv = vec2((float(IDX) + tile_uv.x) / float(COUNT),        \
                           tile_uv.y);                                     \
      atlas_uv.y = 1.0 - atlas_uv.y; /* atlas stored top-down */           \
      float caster = texture(input_shadow, atlas_uv).r;                    \
      RESULT = (proj.z - kShadowBias) <= caster ? 1.0 : 0.0;               \
      return RESULT;                                                       \
    }                                                                      \
  }

// Sunlight visibility at world point P (1 lit, 0 shadowed). Points outside all
// cascades are treated as lit.
float ShadowVisibility(vec3 p, int count) {
  float result = 1.0;
  TRY_CASCADE(0, p, count, result);
  if (count > 1) TRY_CASCADE(1, p, count, result);
  if (count > 2) TRY_CASCADE(2, p, count, result);
  if (count > 3) TRY_CASCADE(3, p, count, result);
  return 1.0;
}

// Interleaved gradient noise (Jimenez), animated by frame time, to jitter the
// ray start and trade banding for fine noise.
float DitherNoise(vec2 frag) {
  vec3 magic = vec3(0.06711056, 0.00583715, 52.9829189);
  return fract(magic.z * fract(dot(frag + post_frame.frame.x, magic.xy)));
}

void main() {
  vec4 scene = texture(input_color, v_uv);

  float density = god.params0.y;
  int steps = int(god.params0.w + 0.5);
  float max_distance = god.params1.x;

  // The ray from the camera to the reconstructed surface (clamped to the fog
  // range). Where no geometry drew (depth at the far plane) the ray still
  // marches the full range, so shafts cross the open sky.
  vec3 view_pos = ViewPositionAt(v_uv);
  vec3 world_end = cam.camera_position.xyz +
                   cam.camera_right.xyz * view_pos.x +
                   cam.camera_up.xyz * view_pos.y +
                   cam.camera_forward.xyz * view_pos.z;
  vec3 to_end = world_end - cam.camera_position.xyz;
  float ray_len = min(length(to_end), max_distance);
  vec3 ray_dir = to_end / max(length(to_end), 1e-4);

  float step_len = ray_len / float(steps);
  float offset = DitherNoise(gl_FragCoord.xy) * step_len * god.params1.y;

  // Henyey-Greenstein phase toward the light: brightest looking into the sun.
  vec3 to_sun = -normalize(shadow.light_direction.xyz);
  float cos_theta = dot(ray_dir, to_sun);
  float g = god.params0.z;
  float denom = 1.0 + g * g - 2.0 * g * cos_theta;
  float phase = (1.0 - g * g) / (4.0 * kPi * pow(max(denom, 1e-4), 1.5));

  int count = int(shadow.light_direction.w + 0.5);
  float scatter = 0.0;
  float transmittance = 1.0;
  for (int i = 0; i < kMaxSteps; i++) {
    if (i >= steps) break;
    vec3 p =
        cam.camera_position.xyz + ray_dir * (offset + float(i) * step_len);
    float visible = ShadowVisibility(p, count);
    transmittance *= exp(-density * step_len);
    scatter += visible * density * step_len * transmittance;
  }

  vec3 sun_color = shadow.light_color.rgb * god.color.rgb;
  vec3 in_scatter = sun_color * scatter * phase * god.params0.x;
  // Additive single-scattering: adds light along the view path; coverage
  // (alpha) is unchanged. Premultiplied HDR, before tone mapping.
  frag_color = vec4(scene.rgb + in_scatter, scene.a);
}
