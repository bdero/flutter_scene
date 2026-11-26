// Packs planar view depth into two unorm8 channels of the occlusion texture,
// so the material can upsample a reduced-resolution occlusion buffer against
// its own depth without another sampler.
//
// 16 bits of signed log2(1 + |z| * 64), which keeps about 0.05% relative
// precision from a few centimeters out to hundreds of kilometers and handles
// the negative depths an orthographic camera can see.

#ifndef SSAO_DEPTH_PACK_GLSL_
#define SSAO_DEPTH_PACK_GLSL_

const highp float kOcclusionDepthScale = 64.0;
const highp float kOcclusionDepthOctaves = 24.0;

vec2 PackOcclusionDepth(highp float depth) {
  highp float octaves =
      sign(depth) * log2(1.0 + abs(depth) * kOcclusionDepthScale);
  highp float unit =
      clamp(0.5 + 0.5 * octaves / kOcclusionDepthOctaves, 0.0, 1.0);
  highp float word = floor(unit * 65535.0 + 0.5);
  highp float high = floor(word / 256.0);
  return vec2(high, word - high * 256.0) / 255.0;
}

highp float UnpackOcclusionDepth(highp vec2 packed) {
  highp vec2 bytes = floor(packed * 255.0 + 0.5);
  highp float unit = (bytes.x * 256.0 + bytes.y) / 65535.0;
  highp float octaves = (2.0 * unit - 1.0) * kOcclusionDepthOctaves;
  return sign(octaves) * (exp2(abs(octaves)) - 1.0) / kOcclusionDepthScale;
}

#endif  // SSAO_DEPTH_PACK_GLSL_
