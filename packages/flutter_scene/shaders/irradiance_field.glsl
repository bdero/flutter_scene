// Addressing shared by every stage of the world-space irradiance field: the
// octahedral direction mapping a probe tile uses, and the tile-to-atlas
// arithmetic. Pure math, no uniforms, so the scatter, blend, filter, and the
// lit receiver all agree by construction.
//
// The atlas packs one probe tile per probe in a tile grid whose stride is a
// power of two, with the environment's spherical-harmonic strip in rows 0 and
// 1 and a one-texel-per-probe state strip below it. A tile is `interior + 2`
// texels on a side; the extra ring is the gutter, written as the mirror of
// the interior edge so bilinear reads across the octahedral seam land on the
// matching direction.

// Stored and interior edges of the two probe tiles. Fixed, because the
// receiver's addressing has to be compile-time constant folded and because a
// decade of shipped probe systems converged on these resolutions.
const float kProbeIrradianceTile = 8.0;
const float kProbeIrradianceInterior = 6.0;
const float kProbeDepthTile = 16.0;
const float kProbeDepthInterior = 14.0;

vec2 ProbeOctSign(vec2 v) {
  return vec2(v.x >= 0.0 ? 1.0 : -1.0, v.y >= 0.0 ? 1.0 : -1.0);
}

// Unit direction to the tile's [0, 1] square.
vec2 ProbeOctEncode(vec3 dir) {
  vec3 n = dir / (abs(dir.x) + abs(dir.y) + abs(dir.z));
  vec2 e = n.z >= 0.0 ? n.xy : (1.0 - abs(n.yx)) * ProbeOctSign(n.xy);
  return e * 0.5 + 0.5;
}

// The tile's [0, 1] square back to a unit direction.
vec3 ProbeOctDecode(vec2 uv) {
  vec2 e = uv * 2.0 - 1.0;
  vec3 n = vec3(e.x, e.y, 1.0 - abs(e.x) - abs(e.y));
  if (n.z < 0.0) {
    n.xy = (1.0 - abs(n.yx)) * ProbeOctSign(n.xy);
  }
  return normalize(n);
}

// Wraps a probe's world lattice index into its storage slot. The modulo is
// what lets the volume scroll without moving a probe that stayed inside it.
vec3 ProbeWrapSlot(vec3 lattice, vec3 counts) {
  return lattice - counts * floor(lattice / counts);
}

// Linear probe index from a storage slot.
float ProbeLinearIndex(vec3 slot, vec3 counts) {
  return slot.x + counts.x * (slot.y + counts.y * slot.z);
}

// Top-left texel of a probe's tile, in atlas texel coordinates measured from
// the top of the atlas.
vec2 ProbeTileOrigin(float index, float tiles_per_row, float region_origin_y,
                     float tile_size) {
  float row = floor(index / tiles_per_row);
  float column = index - row * tiles_per_row;
  return vec2(column * tile_size, region_origin_y + row * tile_size);
}

// Atlas UV of the interior texel a direction maps to, offset past the gutter
// and kept half a texel inside so a bilinear read never straddles the tile.
vec2 ProbeAtlasUv(vec3 dir, vec2 tile_origin, float interior,
                  vec2 inverse_atlas_size) {
  vec2 oct = ProbeOctEncode(dir);
  vec2 texel = tile_origin + vec2(1.0) + clamp(oct, 0.0, 1.0) * interior;
  // Keep the sample inside the interior's outer half-texel so the bilinear
  // footprint reaches the gutter (which mirrors the interior) rather than a
  // neighbouring probe.
  texel = clamp(texel, tile_origin + vec2(0.5),
                tile_origin + vec2(interior + 1.5));
  return texel * inverse_atlas_size;
}

// The interior texel coordinate, in [0, interior], of an atlas fragment whose
// window position is `frag` and whose tile starts at `tile_origin`.
vec2 ProbeInteriorCoord(vec2 frag, vec2 tile_origin) {
  return frag - tile_origin - vec2(1.0);
}

// Maps a gutter texel of a tile to the interior texel it mirrors. `local` is
// the texel's integer coordinate inside the stored tile, in [0, interior + 1].
// Returns the interior texel's integer coordinate in the same space. An
// interior texel maps to itself.
vec2 ProbeGutterSource(vec2 local, float interior) {
  float last = interior + 1.0;
  bool left = local.x < 0.5;
  bool right = local.x > last - 0.5;
  bool top = local.y < 0.5;
  bool bottom = local.y > last - 0.5;
  if ((left || right) && (top || bottom)) {
    // A corner mirrors through the tile center to the opposite interior
    // corner, which is the direction antipodal to it on the octahedron.
    return vec2(left ? interior : 1.0, top ? interior : 1.0);
  }
  if (top) return vec2(interior + 1.0 - local.x, 1.0);
  if (bottom) return vec2(interior + 1.0 - local.x, interior);
  if (left) return vec2(1.0, interior + 1.0 - local.y);
  if (right) return vec2(interior, interior + 1.0 - local.y);
  return local;
}

// Rec. 709 luminance, the scalar the temporal blend's change detector and the
// injection's firefly clamp both work in.
float ProbeLuminance(vec3 color) {
  return dot(color, vec3(0.2126, 0.7152, 0.0722));
}

// Clamps a color's luminance without moving its hue, so one very bright pixel
// cannot burn a probe while a bright-but-plausible one still contributes.
vec3 ProbeClampLuminance(vec3 color, float limit) {
  if (limit <= 0.0) return color;
  float luma = ProbeLuminance(color);
  return luma > limit ? color * (limit / max(luma, 1e-6)) : color;
}
