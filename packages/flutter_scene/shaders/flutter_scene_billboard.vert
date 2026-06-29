uniform FrameInfo {
  mat4 camera_transform; // view-projection
  mat4 model_transform;  // emitter / node world transform
  vec4 camera_position;  // world-space camera position (xyz)
  vec4 world_up;         // world up axis for the billboard basis (xyz)
  // x: facing mode (0 spherical, 1 axis-locked, 2 velocity-stretched).
  // y: flipbook columns. z: flipbook rows. w: velocity stretch factor.
  vec4 params;
}
frame_info;

// Per-vertex unit quad (slot 0): corner in [-0.5, 0.5] and its UV in [0, 1].
in vec2 corner;
in vec2 quad_uv;

// Per-instance attributes (slot 1).
in vec3 i_center;   // position in the geometry's local space
in vec2 i_size;     // width/height in world units
in float i_rotation; // in-plane rotation, radians
in vec4 i_color;    // linear RGBA tint
in float i_frame;   // flipbook frame index
in vec3 i_velocity; // local-space velocity, for velocity stretching

out vec2 v_uv;
out vec4 v_color;

const float kSpherical = 0.0;
const float kAxisLocked = 1.0;
const float kVelocityStretched = 2.0;

void main() {
  float facing = frame_info.params.x;
  vec2 grid = frame_info.params.yz;
  float stretch = frame_info.params.w;

  vec3 world_up = frame_info.world_up.xyz;
  vec3 world_center = (frame_info.model_transform * vec4(i_center, 1.0)).xyz;
  vec3 view_dir = world_center - frame_info.camera_position.xyz;
  // Guard the degenerate case of a particle at the eye.
  vec3 to_eye = dot(view_dir, view_dir) > 1e-12
      ? normalize(-view_dir)
      : vec3(0.0, 0.0, 1.0);

  vec3 right;
  vec3 up;
  vec2 scaled = corner * i_size;

  if (facing == kVelocityStretched) {
    vec3 world_vel = mat3(frame_info.model_transform) * i_velocity;
    float speed = length(world_vel);
    if (speed > 1e-5) {
      up = world_vel / speed;
      right = cross(up, to_eye);
      float rl = length(right);
      // Velocity pointing at the eye collapses the basis; fall back to a
      // stable camera-facing right vector.
      right = rl > 1e-5
          ? right / rl
          : normalize(cross(up, world_up));
      // Stretch the long axis (corner.y) by speed; rotation is ignored here.
      scaled = vec2(corner.x * i_size.x, corner.y * (i_size.y + speed * stretch));
    } else {
      vec3 fwd = to_eye;
      right = normalize(cross(world_up, fwd));
      up = cross(fwd, right);
    }
  } else if (facing == kAxisLocked) {
    up = normalize(world_up);
    right = cross(up, to_eye);
    float rl = length(right);
    right = rl > 1e-5 ? right / rl : vec3(1.0, 0.0, 0.0);
  } else {
    // Spherical: per-particle camera-position facing.
    vec3 fwd = to_eye;
    right = normalize(cross(world_up, fwd));
    up = cross(fwd, right);
  }

  // In-plane rotation (skipped for velocity stretching, which uses the
  // velocity direction as its up axis).
  if (facing != kVelocityStretched) {
    float s = sin(i_rotation);
    float c = cos(i_rotation);
    scaled = vec2(scaled.x * c - scaled.y * s, scaled.x * s + scaled.y * c);
  }

  vec3 world_pos = world_center + right * scaled.x + up * scaled.y;
  gl_Position = frame_info.camera_transform * vec4(world_pos, 1.0);

  // Flipbook cell. A 1x1 grid leaves the UV untouched.
  float cols = max(grid.x, 1.0);
  float rows = max(grid.y, 1.0);
  float frame = floor(i_frame + 0.5);
  float fx = mod(frame, cols);
  float fy = floor(frame / cols);
  vec2 cell = vec2(1.0 / cols, 1.0 / rows);
  v_uv = (vec2(fx, fy) + quad_uv) * cell;

  v_color = i_color;
}
