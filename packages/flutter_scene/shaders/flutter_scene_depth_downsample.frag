// Depth downsample for the ambient-occlusion depth chain. Halves the
// resolution by picking one source texel per target texel.
//
// Linear depth is fp32 and sampled with nearest filtering (float textures are
// not always filterable on GLES/WebGL2). Selecting one true source depth avoids
// the screen-axis and depth bias caused by min/max reduction while preserving
// discontinuities.
//
// The occlusion's base level takes a fixed texel, so a plane stays a plane and
// the occlusion pass knows where each sample sits. The coarser mips use the
// rotated grid of the Scalable Ambient Obscurance reference minifier.

uniform sampler2D source;

uniform DownsampleInfo {
  // x: 1 for the rotated grid, 0 for the fixed texel. yzw: unused.
  vec4 params;
}
downsample;

in vec2 v_uv;

out vec4 frag_color;

void main() {
  ivec2 target = ivec2(gl_FragCoord.xy);
  ivec2 maxCoord = textureSize(source, 0) - ivec2(1);
  ivec2 offset = downsample.params.x > 0.5
      ? ivec2(target.y & 1, target.x & 1)
      : ivec2(0);
  ivec2 sourceCoord = min(target * 2 + offset, maxCoord);
  float depth = texelFetch(source, sourceCoord, 0).r;
  frag_color = vec4(depth, 0.0, 0.0, 1.0);
}
