// Depth downsample for the ambient-occlusion depth mip chain (Scalable Ambient
// Obscurance). Halves the resolution with rotated-grid subsampling.
//
// Linear depth is fp32 and sampled with nearest filtering (float textures are
// not always filterable on GLES/WebGL2). Selecting one true source depth avoids
// the screen-axis and depth bias caused by min/max reduction while preserving
// discontinuities. The alternating offset follows the SAO reference minifier.

uniform sampler2D source;

in vec2 v_uv;

out vec4 frag_color;

void main() {
  ivec2 target = ivec2(gl_FragCoord.xy);
  ivec2 maxCoord = textureSize(source, 0) - ivec2(1);
  ivec2 offset = ivec2(target.y & 1, target.x & 1);
  ivec2 sourceCoord = min(target * 2 + offset, maxCoord);
  float depth = texelFetch(source, sourceCoord, 0).r;
  frag_color = vec4(depth, 0.0, 0.0, 1.0);
}
