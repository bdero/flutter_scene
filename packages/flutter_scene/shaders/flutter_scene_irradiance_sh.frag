// Fits each probe's octahedral irradiance tile to linear spherical harmonics
// for the field's cheap receiver.
//
// The output is laid out in lattice order relative to the volume's anchor,
// one 2D slice per lattice z, so hardware bilinear filtering interpolates
// neighbouring probes within a slice and the receiver blends two slices by
// hand. Storage-slot order would put the scroll's wraparound seam between
// neighbours. Three blocks hold the twelve coefficients, and rows 0 and 1
// copy the environment strip so this texture can stand in for the atlas.
//
// A probe the traced feed retired takes the mean of its active face
// neighbours instead, so filtering does not pull its stale value into the
// surfaces around it.
// TODO(gi-sh-receiver): nudge the sample point away from retired probes and
// apply each probe's relocation offset, which this tier ignores.

#include <irradiance_field.glsl>

uniform ShInfo {
  // xyz: probe counts per axis. w: probe tiles per atlas row.
  vec4 counts;
  // xyz: the volume's minimum-corner lattice index. w: the atlas' first
  // irradiance row.
  vec4 anchor;
  // x: lattice slices per row. y: one coefficient block's height. zw: unused.
  vec4 packing;
}
info;

// The field's sampled atlas.
uniform highp sampler2D atlas;

out vec4 frag_color;

// Atlas index of the probe at [relative] lattice coordinates.
highp float ProbeIndexAt(highp vec3 relative) {
  highp vec3 lattice = info.anchor.xyz + relative;
  return ProbeLinearIndex(ProbeWrapSlot(lattice, info.counts.xyz),
                          info.counts.xyz);
}

bool ProbeRetired(highp float index) {
  highp vec2 texel =
      ProbeTileOrigin(index, info.counts.w, kProbeStateOriginY, 1.0);
  return texelFetch(atlas, ivec2(texel), 0).a > 0.5;
}

// The probe's E(n)/pi as c0 + (dot(r, n), dot(g, n), dot(b, n)), a solid
// angle weighted least-squares fit over its tile's interior.
void ProjectProbe(highp float index, out vec3 c0, out vec3 r, out vec3 g,
                  out vec3 b) {
  highp vec2 tile = ProbeTileOrigin(index, info.counts.w, info.anchor.w,
                                    kProbeIrradianceTile);
  vec3 sum0 = vec3(0.0);
  vec3 sum_r = vec3(0.0);
  vec3 sum_g = vec3(0.0);
  vec3 sum_b = vec3(0.0);
  float total = 0.0;
  for (int y = 0; y < 6; y++) {
    for (int x = 0; x < 6; x++) {
      vec2 e = (vec2(float(x), float(y)) + vec2(0.5)) /
                   kProbeIrradianceInterior * 2.0 -
               vec2(1.0);
      vec3 n = vec3(e.x, e.y, 1.0 - abs(e.x) - abs(e.y));
      if (n.z < 0.0) {
        n.xy = (1.0 - abs(n.yx)) * ProbeOctSign(n.xy);
      }
      // The octahedral map is piecewise linear onto the octahedron, so a
      // texel's solid angle is proportional to 1/|n|^3 of its point there.
      float length_n = length(n);
      float weight = 1.0 / (length_n * length_n * length_n);
      n /= length_n;
      vec3 irradiance = max(
          texelFetch(atlas, ivec2(tile) + ivec2(x + 1, y + 1), 0).rgb,
          vec3(0.0));
      sum0 += irradiance * weight;
      sum_r += n * (irradiance.r * weight);
      sum_g += n * (irradiance.g * weight);
      sum_b += n * (irradiance.b * weight);
      total += weight;
    }
  }
  c0 = sum0 / total;
  // The linear band of a least-squares fit over the sphere is three times
  // the mean of f(n) n.
  r = sum_r * (3.0 / total);
  g = sum_g * (3.0 / total);
  b = sum_b * (3.0 / total);
}

void main() {
  ivec2 coord = ivec2(floor(gl_FragCoord.xy));
  if (coord.y < 2) {
    frag_color = coord.x < 9 ? texelFetch(atlas, coord, 0) : vec4(0.0);
    return;
  }
  highp vec3 counts = info.counts.xyz;
  float block_height = info.packing.y;
  highp float row = float(coord.y - 2);
  float block = floor(row / block_height);
  highp float in_block = row - block * block_height;
  highp float slice_row = floor(in_block / counts.y);
  highp float slice_column = floor(float(coord.x) / counts.x);
  highp vec3 relative =
      vec3(float(coord.x) - slice_column * counts.x,
           in_block - slice_row * counts.y,
           slice_row * info.packing.x + slice_column);
  if (block > 2.0 || relative.z >= counts.z || slice_column >= info.packing.x) {
    frag_color = vec4(0.0);
    return;
  }

  vec3 c0;
  vec3 r;
  vec3 g;
  vec3 b;
  highp float index = ProbeIndexAt(relative);
  ProjectProbe(index, c0, r, g, b);
  if (ProbeRetired(index)) {
    vec3 sum0 = vec3(0.0);
    vec3 sum_r = vec3(0.0);
    vec3 sum_g = vec3(0.0);
    vec3 sum_b = vec3(0.0);
    float found = 0.0;
    for (int i = 0; i < 6; i++) {
      int axis = i / 2;
      vec3 step_offset =
          vec3(axis == 0 ? 1.0 : 0.0, axis == 1 ? 1.0 : 0.0,
               axis == 2 ? 1.0 : 0.0) *
          ((i - axis * 2) == 0 ? -1.0 : 1.0);
      highp vec3 neighbour = relative + step_offset;
      if (any(lessThan(neighbour, vec3(0.0))) ||
          any(greaterThanEqual(neighbour, counts))) {
        continue;
      }
      highp float neighbour_index = ProbeIndexAt(neighbour);
      if (ProbeRetired(neighbour_index)) continue;
      vec3 n0;
      vec3 nr;
      vec3 ng;
      vec3 nb;
      ProjectProbe(neighbour_index, n0, nr, ng, nb);
      sum0 += n0;
      sum_r += nr;
      sum_g += ng;
      sum_b += nb;
      found += 1.0;
    }
    if (found > 0.0) {
      c0 = sum0 / found;
      r = sum_r / found;
      g = sum_g / found;
      b = sum_b / found;
    }
  }

  if (block < 0.5) {
    frag_color = vec4(c0, r.x);
  } else if (block < 1.5) {
    frag_color = vec4(r.y, r.z, g.x, g.y);
  } else {
    frag_color = vec4(g.z, b.x, b.y, b.z);
  }
}
