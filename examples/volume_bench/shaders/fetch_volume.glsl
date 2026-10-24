// The 3D-texture path: one hardware-trilinear fetch per sample.

#include "decode.glsl"

uniform sampler3D volume;

float SampleVolume(vec3 uvw) {
  return Decode(texture(volume, uvw));
}
