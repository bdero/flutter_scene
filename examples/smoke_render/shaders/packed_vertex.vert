// A caller-defined vertex format, uploaded with Geometry.uploadVertexStreams:
// a float position in slot 0 and one packed code per vertex in slot 1, the
// face index plus eight times a palette index. The code is a float holding a
// small integer, since Impeller's OpenGL ES backend has no integer vertex
// formats. It writes the engine's standard varyings, so any engine material
// shades it.

uniform FrameInfo {
  mat4 camera_transform;
  vec3 camera_position;
}
frame_info;

in vec3 position;
in float packed_face;

// The engine's instance-rate record, in the slot after the vertex streams.
in vec4 model_transform_0;
in vec4 model_transform_1;
in vec4 model_transform_2;
in vec4 model_transform_3;
in vec4 instance_color;

// The standard varyings, in the order the fragment stage declares them.
out vec3 v_position;
out vec3 v_normal;
out vec3 v_viewvector;
out vec2 v_texture_coords;
out vec2 v_texture_coords_1;
out vec4 v_color;
out vec4 v_tangent;

vec3 Palette(uint index) {
  if (index == 0u) return vec3(0.9, 0.35, 0.1);
  if (index == 1u) return vec3(0.15, 0.6, 0.85);
  return vec3(0.35, 0.8, 0.3);
}

void main() {
  mat4 model_transform = mat4(model_transform_0, model_transform_1,
                              model_transform_2, model_transform_3);
  vec4 world_position = model_transform * vec4(position, 1.0);
  uint code = uint(packed_face + 0.5);
  uint face = code & 7u;
  // Faces run +X, -X, +Y, -Y, +Z, -Z.
  uint axis = face / 2u;
  float face_sign = (face & 1u) == 0u ? 1.0 : -1.0;
  vec3 normal = vec3(axis == 0u ? face_sign : 0.0, axis == 1u ? face_sign : 0.0,
                     axis == 2u ? face_sign : 0.0);

  v_position = world_position.xyz;
  v_normal = normalize(mat3(model_transform) * normal);
  v_viewvector = frame_info.camera_position - world_position.xyz;
  v_texture_coords = vec2(0.0);
  v_texture_coords_1 = vec2(0.0);
  v_color = vec4(Palette(code >> 3u), 1.0) * instance_color;
  v_tangent = vec4(0.0);
  gl_Position = frame_info.camera_transform * world_position;
}
