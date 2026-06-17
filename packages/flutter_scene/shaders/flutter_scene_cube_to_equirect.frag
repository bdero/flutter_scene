// Assembles an equirectangular image from six cube-face textures rendered by
// the sky bake. For each equirect texel it reconstructs the world direction
// and samples the face whose axis is dominant.
//
// The face bases here must match the view matrices the bake renders each face
// with (see sky_bake.dart): for each face, right R = up x forward, and a quad
// corner (nx, ny) maps to direction normalize(F + nx*R + ny*U). Sampling uses
// nx = R.d / F.d, ny = U.d / F.d, with V flipped to match the render target's
// top-down storage.

uniform sampler2D face_px;
uniform sampler2D face_nx;
uniform sampler2D face_py;
uniform sampler2D face_ny;
uniform sampler2D face_pz;
uniform sampler2D face_nz;

uniform CubeFaceInfo {
  // Half-texel overscan inset that removes the seam between faces. The bake
  // renders each face with a slightly wider field of view so the outermost
  // texel centers fall exactly on the cube-edge directions; the same scale
  // maps a sampled edge direction back onto those centers, so adjacent faces
  // agree at the boundary. Equals (N - 1) / N for an N x N face.
  float face_uv_scale;
}
cube_face_info;

in vec2 v_uv;

out vec4 frag_color;

#include <texture.glsl>  // EquirectangularToSpherical

vec2 _faceUv(float nx, float ny) {
  float s = cube_face_info.face_uv_scale;
  return vec2(0.5 + 0.5 * nx * s, 0.5 - 0.5 * ny * s);
}

vec3 _sampleFaces(vec3 d) {
  vec3 a = abs(d);
  if (a.x >= a.y && a.x >= a.z) {
    if (d.x > 0.0) {
      // +X: F=(1,0,0) R=(0,0,-1) U=(0,1,0)
      return texture(face_px, _faceUv(-d.z / d.x, d.y / d.x)).rgb;
    }
    // -X: F=(-1,0,0) R=(0,0,1) U=(0,1,0)
    return texture(face_nx, _faceUv(d.z / -d.x, d.y / -d.x)).rgb;
  } else if (a.y >= a.z) {
    if (d.y > 0.0) {
      // +Y: F=(0,1,0) R=(1,0,0) U=(0,0,-1)
      return texture(face_py, _faceUv(d.x / d.y, -d.z / d.y)).rgb;
    }
    // -Y: F=(0,-1,0) R=(1,0,0) U=(0,0,1)
    return texture(face_ny, _faceUv(d.x / -d.y, d.z / -d.y)).rgb;
  } else {
    if (d.z > 0.0) {
      // +Z: F=(0,0,1) R=(1,0,0) U=(0,1,0)
      return texture(face_pz, _faceUv(d.x / d.z, d.y / d.z)).rgb;
    }
    // -Z: F=(0,0,-1) R=(-1,0,0) U=(0,1,0)
    return texture(face_nz, _faceUv(-d.x / -d.z, d.y / -d.z)).rgb;
  }
}

void main() {
  // The prefilter samples its source equirect with the up pole at the top row
  // (the standard convention loaded images use), so write that convention
  // here: flip V before mapping the output texel to a direction. Without this
  // the baked atlas is vertically inverted relative to the visible sky.
  vec3 d = normalize(EquirectangularToSpherical(vec2(v_uv.x, 1.0 - v_uv.y)));
  frag_color = vec4(_sampleFaces(d), 1.0);
}
