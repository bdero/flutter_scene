// Moves between planar view depth and view-space position for any camera
// projection, perspective or orthographic, centered or off-center.
//
// `scale` xy is the view-space extent per unit of NDC (the half-fov tangents
// for perspective, the half extents for orthographic). `offset` xy is the NDC
// position of the view axis, and `offset` z is 1 for an orthographic
// projection and 0 for a perspective one. View space has the eye at the origin
// looking down +Z, the convention the depth prepass writes.

#ifndef VIEW_PROJECTION_GLSL_
#define VIEW_PROJECTION_GLSL_

// View rays are parallel under an orthographic projection, so x/y do not grow
// with depth there.
highp float ViewProjectionDepthFactor(highp float view_z, highp vec3 offset) {
  return mix(view_z, 1.0, offset.z);
}

// The view-space position at NDC [ndc] and planar depth [view_z].
highp vec3 ViewPositionFromNdc(highp vec2 ndc, highp float view_z,
                               highp vec2 scale, highp vec3 offset) {
  highp float k = ViewProjectionDepthFactor(view_z, offset);
  return vec3((ndc - offset.xy) * scale * k, view_z);
}

// The view-space position under screen UV [uv] (V grows downward) at planar
// depth [view_z].
highp vec3 ViewPositionFromUv(highp vec2 uv, highp float view_z,
                              highp vec2 scale, highp vec3 offset) {
  return ViewPositionFromNdc(vec2(2.0 * uv.x - 1.0, 1.0 - 2.0 * uv.y), view_z,
                             scale, offset);
}

// The NDC position of view-space point [p]. Undefined for a perspective point
// at or behind the eye; callers test `p.z` first.
highp vec2 NdcFromViewPosition(highp vec3 p, highp vec2 scale,
                               highp vec3 offset) {
  highp float k = ViewProjectionDepthFactor(p.z, offset);
  return p.xy / (scale * k) + offset.xy;
}

// The screen UV (V grows downward) of view-space point [p].
highp vec2 UvFromViewPosition(highp vec3 p, highp vec2 scale,
                              highp vec3 offset) {
  highp vec2 ndc = NdcFromViewPosition(p, scale, offset);
  return vec2(0.5 + 0.5 * ndc.x, 0.5 - 0.5 * ndc.y);
}

// The view-space direction from point [p] toward the viewer.
highp vec3 ViewDirectionAt(highp vec3 p, highp vec3 offset) {
  return offset.z > 0.5 ? vec3(0.0, 0.0, -1.0) : -normalize(p);
}

// Whether view-space depth [view_z] can be projected: in front of the eye for
// perspective, anywhere for orthographic.
bool ViewDepthProjectable(highp float view_z, highp vec3 offset) {
  return offset.z > 0.5 || view_z > 1e-5;
}

#endif  // VIEW_PROJECTION_GLSL_
