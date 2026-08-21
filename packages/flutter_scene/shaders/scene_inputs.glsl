// Engine scene inputs for a raw ShaderMaterial.
//
// A `.fmat` material gets these accessors generated against the lit
// framework's FragInfo block. A ShaderMaterial owns its whole pipeline and has
// no FragInfo, so it includes this instead. Same names, same gate semantics,
// same screen mapping, so a shader ported between the two paths reads alike.
//
// Declare only what the material declared in Dart. A sampler the shader
// declares but never samples is eliminated by the compiler while the runtime
// reflection still lists it, which fails at bind time, so each one is behind
// the define that asks for it:
//
//   #define FLUTTER_SCENE_SCENE_COLOR
//   #define FLUTTER_SCENE_SCENE_DEPTH
//   #include <scene_inputs.glsl>
//
// The defines must match the material's `sceneInputs` set exactly.

// Per-frame engine state for the samplers below. Bound automatically whenever
// the material declares any scene input and the shader references this block.
uniform SceneInputInfo {
  // Which inputs exist this frame. x scene color, y depth, z filtered color.
  // An input can go missing for a frame (a non-perspective camera produces no
  // depth), which is what the accessors gate on. w is reserved.
  vec4 available;

  // xy: the color-pass render-target size in pixels. zw: its reciprocal.
  vec4 screen;

  // xyz: the camera's world-space forward axis. w: tan(fovY / 2), zero for a
  // non-perspective camera.
  vec4 camera_forward;

  // xyz: the camera's world-space right axis. w: tan(fovX / 2).
  vec4 camera_right;

  // xyz: the camera's world-space up axis. w is reserved.
  vec4 camera_up;
}
scene_input_info;

// This fragment's screen UV, for sampling the screen-space inputs below.
vec2 GetScreenUv() { return gl_FragCoord.xy * scene_input_info.screen.zw; }

// This fragment's planar view-space depth in world units, directly comparable
// against GetSceneDepth. Pass the world-space vector from the fragment to the
// camera. The engine vertex shaders emit it as `v_viewvector`; a material with
// its own vertex stage passes whatever it computed.
float GetFragmentViewDepth(vec3 view_vector) {
  return dot(-view_vector, scene_input_info.camera_forward.xyz);
}

// Projects a world-space offset from this fragment back into screen UV, for
// refraction that exits the volume somewhere other than where it entered.
// Leaves the sample at this fragment when the camera is not perspective.
vec2 ProjectWorldOffsetToScreenUv(vec3 world_offset, vec3 view_vector) {
  vec2 result = GetScreenUv();
  if (scene_input_info.camera_right.w > 0.0 &&
      scene_input_info.camera_forward.w > 0.0) {
    vec3 from_camera = -view_vector + world_offset;
    float view_z = dot(from_camera, scene_input_info.camera_forward.xyz);
    if (view_z > 1e-5) {
      float view_x = dot(from_camera, scene_input_info.camera_right.xyz);
      float view_y = dot(from_camera, scene_input_info.camera_up.xyz);
      result = vec2(
          0.5 + 0.5 * view_x / (view_z * scene_input_info.camera_right.w),
          0.5 - 0.5 * view_y / (view_z * scene_input_info.camera_forward.w));
    }
  }
  return result;
}

#ifdef FLUTTER_SCENE_SCENE_COLOR
// The scene composed behind this draw, linear HDR.
uniform sampler2D scene_opaque_color;

// The scene behind this fragment, offset in screen UV (pass vec2(0.0) for no
// distortion). Black when the snapshot is unavailable, so an effect fades out
// instead of sampling a placeholder.
vec3 GetSceneColor(vec2 uv_offset) {
  vec3 result = vec3(0.0);
  if (scene_input_info.available.x >= 0.5) {
    vec2 uv = clamp(GetScreenUv() + uv_offset, vec2(0.001), vec2(0.999));
    result = texture(scene_opaque_color, uv).rgb;
  }
  return result;
}
#endif

#ifdef FLUTTER_SCENE_SCENE_DEPTH
// The opaque geometry's linear (planar view-space) depth, in world units.
// highp because fp16 quantizes depth hard enough to break the comparison.
uniform highp sampler2D scene_depth;

// The opaque depth behind this fragment, offset in screen UV. Returns a huge
// depth when unavailable, so a depth difference reads as "nothing behind" and
// the effect fades out instead of popping.
float GetSceneDepth(vec2 uv_offset) {
  float result = 1.0e8;
  if (scene_input_info.available.y >= 0.5) {
    vec2 uv = clamp(GetScreenUv() + uv_offset, vec2(0.001), vec2(0.999));
    result = texture(scene_depth, uv).r;
  }
  return result;
}
#endif

#ifdef FLUTTER_SCENE_FILTERED_SCENE_COLOR
// The roughness-filtered atlas of the scene color, for rough refraction.
// Sampling it needs the band layout, so this exposes the atlas rather than a
// ready-made accessor.
uniform sampler2D scene_filtered_color;
#endif
