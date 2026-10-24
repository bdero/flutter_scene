// The 2D-array path: the hardware filters within a layer, and two layer reads
// are blended across depth.

#include "decode.glsl"

uniform sampler2DArray layers;

float SampleVolume(vec3 uvw) {
  float z = uvw.z * params.dims.z - 0.5;
  float below = floor(z);
  float last = params.dims.z - 1.0;
  float a = Decode(texture(layers, vec3(uvw.xy, clamp(below, 0.0, last))));
  float b = Decode(texture(layers, vec3(uvw.xy, clamp(below + 1.0, 0.0, last))));
  return mix(a, b, z - below);
}
