/// Telling which tiles a scene edit actually changed.
///
/// Tiling makes a world's bake divisible; this is what makes it *worth*
/// dividing while authoring. Moving one crate should cost the tiles the crate
/// touched, not the world, and the question "which tiles" has an exact answer:
/// a tile is stale when the triangles it would be baked from differ from the
/// ones it was baked from.
///
/// So each tile's input is fingerprinted at bake time and again at rebake
/// time, and the tiles whose fingerprints differ are the ones to redo. That
/// catches everything a region-based guess misses: a crate that moved is
/// caught in the tile it left as well as the one it arrived in, geometry
/// deleted anywhere is caught where it used to be, and a change that happened
/// to land inside one tile does not drag its neighbours along.
///
/// The fingerprint covers a tile's border as well as its interior, because
/// erosion and region growing reach outside the tile and a triangle just past
/// the edge does change what comes out.
library;

import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'package:scene/src/navigation/nav_config.dart';
import 'package:scene/src/navigation/nav_geometry.dart';
import 'package:scene/src/navigation/nav_tile_bake.dart';
import 'package:scene/src/navigation/nav_tiles.dart';

/// What each tile was baked from, as one number per tile.
///
/// Comparable across bakes of the same world; meaningless across different
/// tilings, which is why the tiling is carried alongside.
/// {@category Navigation}
class NavTileFingerprints {
  const NavTileFingerprints({required this.hashes, required this.tiling});

  /// One hash per tile that had any geometry reaching it.
  final Map<NavTileKey, int> hashes;

  /// The tiling the hashes were taken under. Two fingerprints are only
  /// comparable when these agree, since the tiles are different squares
  /// otherwise.
  final NavTileConfig tiling;

  bool get isEmpty => hashes.isEmpty;

  int get tileCount => hashes.length;
}

/// Fingerprints what every tile of [geometry] would be baked from.
///
/// Linear in the triangle count, and a fraction of a bake: it is one pass to
/// bucket and one pass over each tile's triangles.
/// {@category Navigation}
NavTileFingerprints fingerprintNavTiles(
  NavGeometry geometry,
  NavMeshConfig config, {
  NavTileConfig tiling = const NavTileConfig(),
  Vector3? origin,
}) {
  final buckets = bucketNavTriangles(
    geometry,
    config,
    tiling: tiling,
    origin: origin,
  );
  if (buckets.isEmpty) {
    return NavTileFingerprints(hashes: const {}, tiling: tiling);
  }

  // The float bits rather than the values: two positions are the same input
  // only when they are the same number, and reading the bits avoids deciding
  // on a tolerance that would then have to match the voxelizer's.
  final bits = ByteData.view(
    geometry.vertices.buffer,
    geometry.vertices.offsetInBytes,
    geometry.vertices.lengthInBytes,
  );
  final indices = geometry.indices;
  final areas = geometry.areas;

  final hashes = <NavTileKey, int>{};
  for (final entry in buckets.entries) {
    // Summed rather than chained, because the bucket's order comes from the
    // order the scene was walked in and a tile's input is a set. Summed
    // rather than xor-ed, because xor cancels: two identical triangles would
    // fingerprint as none.
    var sum = 0;
    for (final triangle in entry.value) {
      var h = 0x811c9dc5;
      for (var corner = 0; corner < 3; corner++) {
        final v = indices[triangle * 3 + corner] * 3;
        for (var axis = 0; axis < 3; axis++) {
          h = _mix(h, bits.getInt32((v + axis) * 4, Endian.host));
        }
      }
      sum = (sum + _mix(h, areas[triangle])) & 0xFFFFFFFF;
    }
    // The count, so a tile losing a triangle whose hash happened to be zero
    // still reads as changed.
    hashes[entry.key] = _mix(sum, entry.value.length);
  }
  return NavTileFingerprints(hashes: hashes, tiling: tiling);
}

/// The tiles that differ between [before] and [after], including tiles
/// present in one and absent from the other.
///
/// Returns every tile in [after] when the two were taken under different
/// tilings, since nothing about them lines up.
/// {@category Navigation}
Set<NavTileKey> changedNavTiles(
  NavTileFingerprints before,
  NavTileFingerprints after,
) {
  if (before.tiling.tileCells != after.tiling.tileCells ||
      before.tiling.borderCells != after.tiling.borderCells) {
    return {...after.hashes.keys, ...before.hashes.keys};
  }
  final changed = <NavTileKey>{};
  for (final entry in after.hashes.entries) {
    if (before.hashes[entry.key] != entry.value) changed.add(entry.key);
  }
  // A tile whose geometry is entirely gone has no entry to compare, and is
  // exactly the tile that has to be cleared.
  for (final key in before.hashes.keys) {
    if (!after.hashes.containsKey(key)) changed.add(key);
  }
  return changed;
}

/// A 32-bit mix built from shifts and adds only.
///
/// No multiply, so it computes the same on dart2js, where an int is a double
/// and a 32-bit product does not fit exactly.
int _mix(int hash, int value) {
  var h = (hash ^ value) & 0xFFFFFFFF;
  h = (h + ((h << 3) & 0xFFFFFFFF)) & 0xFFFFFFFF;
  h ^= h >> 11;
  h = (h + ((h << 15) & 0xFFFFFFFF)) & 0xFFFFFFFF;
  return h;
}
