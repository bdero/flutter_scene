import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

/// The largest edge the shadow atlas may take. 8192 is the common limit on
/// mobile GPUs and WebGL.
// TODO(shadow-atlas-max-size): query the device limit once Flutter GPU
// exposes it, so desktop GPUs can keep full resolution in crowded scenes.
const int kShadowAtlasMaxDimension = 8192;

/// The smallest tile edge a light's shadow shrinks to when the atlas is full.
const int kShadowAtlasMinTile = 16;

/// A square tile of the shadow atlas, in texels from the atlas's top-left
/// corner (the atlas is stored top-down).
class ShadowAtlasTile {
  const ShadowAtlasTile(this.x, this.y, this.size);

  final int x;
  final int y;
  final int size;

  /// The tile in atlas UV for an atlas [width] by [height]: xy the top-left
  /// corner and zw the extent. A tile UV (u, v), with v up as in
  /// `ndc * 0.5 + 0.5`, samples `xy + vec2(u, 1 - v) * zw`.
  Vector4 uvRect(int width, int height) =>
      Vector4(x / width, y / height, size / width, size / height);

  @override
  bool operator ==(Object other) =>
      other is ShadowAtlasTile &&
      other.x == x &&
      other.y == y &&
      other.size == size;

  @override
  int get hashCode => Object.hash(x, y, size);

  @override
  String toString() => 'ShadowAtlasTile($x, $y, $size)';
}

/// Where every shadow of a frame lives in the shared shadow atlas.
///
/// The directional cascades fill a grid at the top-left corner, as many to a
/// row as fit. Each spot gets a tile of its own resolution, and each point
/// light two tiles of twice its face resolution, holding its six cube faces
/// in quadrants. Those tiles pack largest first into shelves, beside the
/// cascades and then below them, at whichever width tried gives the smallest
/// atlas. When they overflow the atlas limit, every spot and point tile halves
/// until they fit, and then the cascades.
class ShadowAtlasLayout {
  ShadowAtlasLayout._({
    required this.width,
    required this.height,
    required this.cascadeResolution,
    required this.cascadeColumns,
    required this.cascadeTiles,
    required this.spotTiles,
    required this.pointTiles,
  });

  /// Plans the atlas for [cascadeCount] cascades at [cascadeResolution], one
  /// spot per entry of [spotResolutions], and one point light per entry of
  /// [pointFaceResolutions]. Returns null when nothing casts.
  static ShadowAtlasLayout? plan({
    int cascadeCount = 0,
    int cascadeResolution = 0,
    List<int> spotResolutions = const [],
    List<int> pointFaceResolutions = const [],
    int maxDimension = kShadowAtlasMaxDimension,
  }) {
    if (cascadeResolution <= 0) cascadeCount = 0;
    if (cascadeCount == 0 &&
        spotResolutions.isEmpty &&
        pointFaceResolutions.isEmpty) {
      return null;
    }
    int clampEdge(int edge) => edge.clamp(kShadowAtlasMinTile, maxDimension);
    final requested = [
      for (final r in spotResolutions) clampEdge(r),
      for (final r in pointFaceResolutions) ...[
        clampEdge(r * 2),
        clampEdge(r * 2),
      ],
    ];
    final cascadeRequest = cascadeCount == 0 ? 0 : clampEdge(cascadeResolution);

    // Halve the spot and point tiles until they fit, and only once they are
    // at the minimum, the cascades.
    for (var cascadeShift = 0; ; cascadeShift++) {
      final cascadeEdge = cascadeCount == 0
          ? 0
          : math.max(cascadeRequest >> cascadeShift, kShadowAtlasMinTile);
      for (var shift = 0; ; shift++) {
        final sizes = [
          for (final edge in requested)
            math.max(edge >> shift, kShadowAtlasMinTile),
        ];
        final itemsAtMinimum = sizes.every((s) => s == kShadowAtlasMinTile);
        final atMinimum =
            itemsAtMinimum &&
            (cascadeCount == 0 || cascadeEdge == kShadowAtlasMinTile);
        final layout = _tryPack(
          cascadeCount,
          cascadeEdge,
          sizes,
          spotResolutions.length,
          // The caster budgets keep the minimum from overflowing; if it ever
          // does, the layout grows past the limit rather than failing.
          atMinimum ? 1 << 30 : maxDimension,
        );
        if (layout != null) return layout;
        if (itemsAtMinimum) break;
      }
    }
  }

  static ShadowAtlasLayout? _tryPack(
    int cascadeCount,
    int cascadeEdge,
    List<int> sizes,
    int spotCount,
    int maxDimension,
  ) {
    final columns = cascadeCount == 0
        ? 0
        : math.min(cascadeCount, math.max(1, maxDimension ~/ cascadeEdge));
    final rows = cascadeCount == 0
        ? 0
        : (cascadeCount + columns - 1) ~/ columns;
    final blockWidth = columns * cascadeEdge;
    final blockHeight = rows * cascadeEdge;
    final largest = sizes.fold(0, math.max);
    final minWidth = math.max(blockWidth, largest);
    if (minWidth > maxDimension || blockHeight > maxDimension) return null;

    // Try a few widths and keep the smallest atlas, then the squarest.
    final candidates = <int>{minWidth};
    for (final s in sizes) {
      candidates.add(blockWidth + s);
    }
    for (var w = 1; w <= maxDimension; w <<= 1) {
      if (w > minWidth) candidates.add(w);
    }
    ({int width, int height, List<ShadowAtlasTile> tiles})? best;
    for (final width in candidates) {
      if (width < minWidth || width > maxDimension) continue;
      final packed = _packShelves(sizes, width, blockWidth, blockHeight);
      if (packed.height > maxDimension) continue;
      if (best == null) {
        best = packed;
        continue;
      }
      final area = packed.width * packed.height;
      final bestArea = best.width * best.height;
      if (area < bestArea ||
          (area == bestArea &&
              math.max(packed.width, packed.height) <
                  math.max(best.width, best.height))) {
        best = packed;
      }
    }
    if (best == null) return null;
    return ShadowAtlasLayout._(
      width: best.width,
      height: best.height,
      cascadeResolution: cascadeEdge,
      cascadeColumns: columns,
      cascadeTiles: [
        for (var i = 0; i < cascadeCount; i++)
          ShadowAtlasTile(
            (i % columns) * cascadeEdge,
            (i ~/ columns) * cascadeEdge,
            cascadeEdge,
          ),
      ],
      spotTiles: best.tiles.sublist(0, spotCount),
      pointTiles: best.tiles.sublist(spotCount),
    );
  }

  /// Shelf-packs [sizes] largest first into [width], keeping their order in
  /// the result. The first shelf is the cascade block's row, to its right.
  static ({int width, int height, List<ShadowAtlasTile> tiles}) _packShelves(
    List<int> sizes,
    int width,
    int blockWidth,
    int blockHeight,
  ) {
    final order = List.generate(sizes.length, (i) => i)
      ..sort((a, b) {
        final bySize = sizes[b].compareTo(sizes[a]);
        return bySize != 0 ? bySize : a.compareTo(b);
      });
    // Each shelf is (top, height, next free x).
    final shelves = <List<int>>[
      if (blockHeight > 0) [0, blockHeight, blockWidth],
    ];
    var bottom = blockHeight;
    var right = blockWidth;
    final tiles = List<ShadowAtlasTile?>.filled(sizes.length, null);
    for (final i in order) {
      final size = sizes[i];
      List<int>? shelf;
      for (final candidate in shelves) {
        if (size <= candidate[1] && candidate[2] + size <= width) {
          shelf = candidate;
          break;
        }
      }
      if (shelf == null) {
        shelf = [bottom, size, 0];
        shelves.add(shelf);
        bottom += size;
      }
      tiles[i] = ShadowAtlasTile(shelf[2], shelf[0], size);
      shelf[2] += size;
      right = math.max(right, shelf[2]);
    }
    return (width: right, height: bottom, tiles: tiles.cast());
  }

  /// Atlas edge lengths in texels.
  final int width;
  final int height;

  /// Edge of each cascade tile, 0 without cascades.
  final int cascadeResolution;

  /// Cascades per row of the cascade grid, 0 without cascades.
  final int cascadeColumns;

  /// One tile per cascade, near to far.
  final List<ShadowAtlasTile> cascadeTiles;

  /// One tile per spot shadow slot.
  final List<ShadowAtlasTile> spotTiles;

  /// Two tiles per point shadow slot, at `slot * 2` and `slot * 2 + 1`. The
  /// first holds faces 0 to 3 in quadrants, the second faces 4 and 5 in its
  /// top half.
  final List<ShadowAtlasTile> pointTiles;

  /// A cascade tile's extent in atlas UV.
  Vector2 get cascadeUvExtent =>
      Vector2(cascadeResolution / width, cascadeResolution / height);
}
