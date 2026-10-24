// The workaround: slices tiled across up to four RGBA8 pages, two 16-bit
// voxels per texel (RG = voxel 2n, BA = voxel 2n + 1, high byte first), read
// with exact texel fetches and filtered by hand: eight fetches per sample.

uniform sampler2D page0;
uniform sampler2D page1;
uniform sampler2D page2;
uniform sampler2D page3;

float Voxel(ivec3 voxel) {
  ivec3 last = ivec3(params.dims.xyz) - 1;
  voxel = clamp(voxel, ivec3(0), last);
  int slices_per_row = int(params.atlas.x);
  int slices_per_page = int(params.atlas.y);
  int page = voxel.z / slices_per_page;
  int tile = voxel.z - page * slices_per_page;
  ivec2 texel = ivec2((tile % slices_per_row) * int(params.atlas.z) + voxel.x / 2,
                      (tile / slices_per_row) * int(params.atlas.w) + voxel.y);
  vec4 pair;
  if (page == 0) {
    pair = texelFetch(page0, texel, 0);
  } else if (page == 1) {
    pair = texelFetch(page1, texel, 0);
  } else if (page == 2) {
    pair = texelFetch(page2, texel, 0);
  } else {
    pair = texelFetch(page3, texel, 0);
  }
  vec2 bytes = (voxel.x - (voxel.x / 2) * 2) == 0 ? pair.rg : pair.ba;
  return (bytes.x * 65280.0 + bytes.y * 255.0) / 65535.0;
}

float SampleVolume(vec3 uvw) {
  vec3 position = uvw * params.dims.xyz - 0.5;
  vec3 base = floor(position);
  vec3 f = position - base;
  ivec3 i = ivec3(base);
  float c000 = Voxel(i);
  float c100 = Voxel(i + ivec3(1, 0, 0));
  float c010 = Voxel(i + ivec3(0, 1, 0));
  float c110 = Voxel(i + ivec3(1, 1, 0));
  float c001 = Voxel(i + ivec3(0, 0, 1));
  float c101 = Voxel(i + ivec3(1, 0, 1));
  float c011 = Voxel(i + ivec3(0, 1, 1));
  float c111 = Voxel(i + ivec3(1, 1, 1));
  float c00 = mix(c000, c100, f.x);
  float c10 = mix(c010, c110, f.x);
  float c01 = mix(c001, c101, f.x);
  float c11 = mix(c011, c111, f.x);
  return mix(mix(c00, c10, f.y), mix(c01, c11, f.y), f.z);
}
