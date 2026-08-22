// The engine-provided fragment inputs every flutter_scene material shader
// receives: the interpolated per-vertex outputs (world space) and the color
// output. Plus convenience accessors a material's Surface() function can call
// instead of touching the raw varyings.

in vec3 v_position; // world-space position
in vec3 v_normal; // world-space normal, not normalized
in vec3 v_viewvector; // camera_position - vertex_position (world space)
in vec2 v_texture_coords;
in vec2 v_texture_coords_1;
in vec4 v_color;
in vec4 v_tangent;

out vec4 frag_color;

// World-space position of the fragment.
vec3 GetWorldPosition() { return v_position; }

// Normalized world-space geometric normal (before any normal-map perturbation).
// Back-facing fragments use the reversed normal required by two-sided lighting.
vec3 GetWorldNormal() {
  float face_direction = gl_FrontFacing ? 1.0 : -1.0;
  return normalize(v_normal) * face_direction;
}

// Normalized direction from the fragment toward the camera.
vec3 GetViewDirection() { return normalize(v_viewvector); }

// Primary texture coordinates.
vec2 GetUV0() { return v_texture_coords; }

// Secondary texture coordinates.
vec2 GetUV1() { return v_texture_coords_1; }

vec2 GetUV(int channel) { return channel == 1 ? GetUV1() : GetUV0(); }

// Interpolated per-vertex color (white if the mesh has none).
vec4 GetVertexColor() { return v_color; }

// World-space tangent and bitangent sign. A zero vector means the mesh did
// not provide tangents and the fragment shader derives its tangent frame.
vec4 GetWorldTangent() { return v_tangent; }
