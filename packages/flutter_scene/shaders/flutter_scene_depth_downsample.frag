// Depth downsample for the ambient-occlusion depth mip chain (Scalable Ambient
// Obscurance). Halves the resolution, writing the nearest (minimum) view-space
// depth of each source 2x2 block into the target level.
//
// Linear depth is fp32 and sampled with nearest filtering (float textures are
// not always filterable on GLES/WebGL2, and depth must not be averaged across a
// silhouette), so this reads the four source texels exactly with texelFetch
// rather than a filtered tap. Taking the minimum is conservative: a coarse level
// never hides an occluder, it can only slightly over-darken, which the
// per-sample level selection keeps to the far, low-weight samples.

uniform sampler2D source;

in vec2 v_uv;

out vec4 frag_color;

void main() {
  ivec2 base = ivec2(gl_FragCoord.xy) * 2;
  ivec2 maxCoord = textureSize(source, 0) - ivec2(1);
  float d0 = texelFetch(source, min(base + ivec2(0, 0), maxCoord), 0).r;
  float d1 = texelFetch(source, min(base + ivec2(1, 0), maxCoord), 0).r;
  float d2 = texelFetch(source, min(base + ivec2(0, 1), maxCoord), 0).r;
  float d3 = texelFetch(source, min(base + ivec2(1, 1), maxCoord), 0).r;
  frag_color = vec4(min(min(d0, d1), min(d2, d3)), 0.0, 0.0, 1.0);
}
