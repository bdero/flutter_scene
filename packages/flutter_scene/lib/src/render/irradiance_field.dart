import 'dart:math' as math;

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart';

/// Widest atlas edge the irradiance field will build.
///
/// GLES 3.0 and WebGL2 both guarantee only 2048, and the atlas is sampled by
/// every lit fragment, so the field clamps to the guaranteed minimum rather
/// than to whatever the device reports.
// TODO(gi-atlas-limit): raise this to the device's real
// `maxTextureDimension2D` once Flutter GPU exposes the limit.
const int kMaxIrradianceAtlasDimension = 2048;

/// Interior texels along one edge of a probe's irradiance tile. The stored
/// tile is one texel larger on every side (the gutter).
const int kIrradianceInterior = 6;

/// Interior texels along one edge of a probe's depth-moment tile.
const int kDepthMomentInterior = 14;

/// Exponent sharpening the depth-moment blend weight, so a probe's stored
/// distance tracks the nearest surface in a direction instead of averaging
/// the lobe. Matches the reference implementation's `probeDistanceExponent`.
const double kDepthMomentSharpness = 50.0;

/// Texel radius the depth scatter covers around a sample's octahedral texel.
///
/// `pow(cos, 50)` falls under a hundredth of its peak by about 24 degrees,
/// which is two texels on a 14-texel octahedral edge, so a 5x5 footprint
/// carries the whole lobe.
// TODO(gi-depth-wrap): a lobe centered on a tile edge is truncated instead of
// wrapping to the opposite edge. The gutter hides it at read time; scattering
// the wrapped remainder would fix it properly.
const int kDepthScatterRadius = 2;

/// Where each quantity lives in the single irradiance-field atlas, and how a
/// probe index maps to its tile.
///
/// One `r16g16b16a16Float` texture carries everything the lit shader needs,
/// so the field costs no additional sampler. Rows run
///
/// - 0 to 1, the environment's diffuse spherical-harmonic strip (9 texels
///   wide, primary in row 0 and the cross-fade secondary in row 1), byte
///   identical to the standalone coefficient texture the shader reads when
///   the field is off;
/// - the per-probe state strip, one texel per probe in the same tile grid the
///   probe regions use, carrying validity in alpha;
/// - the irradiance region, one [kIrradianceInterior] plus gutter tile per
///   probe, rgb irradiance and a luminance second moment in alpha;
/// - the depth region, one [kDepthMomentInterior] plus gutter tile per probe,
///   r the mean normalized distance and g its mean square.
class IrradianceFieldLayout {
  IrradianceFieldLayout._({
    required this.resolution,
    required this.tilesPerRow,
    required this.tileRows,
  });

  /// Builds the layout for [resolution] probes per axis, clamping the probe
  /// counts down until the atlas fits [kMaxIrradianceAtlasDimension].
  factory IrradianceFieldLayout(Vector3 resolution) {
    var x = resolution.x.round().clamp(2, 256);
    var y = resolution.y.round().clamp(2, 256);
    var z = resolution.z.round().clamp(2, 256);
    // Shrink the longest axis until the atlas fits. Halving one axis quarters
    // nothing else, so this terminates in a handful of steps.
    while (true) {
      final layout = IrradianceFieldLayout._forCounts(x, y, z);
      if (layout != null) return layout;
      if (x >= y && x >= z) {
        x = math.max(2, x ~/ 2);
      } else if (y >= z) {
        y = math.max(2, y ~/ 2);
      } else {
        z = math.max(2, z ~/ 2);
      }
      if (x == 2 && y == 2 && z == 2) {
        return IrradianceFieldLayout._forCounts(2, 2, 2)!;
      }
    }
  }

  static IrradianceFieldLayout? _forCounts(int x, int y, int z) {
    final probes = x * y * z;
    // A power-of-two tile stride keeps the shader's tile decode a scale and a
    // floor rather than a general integer divide, and a roughly square atlas
    // keeps both edges far from the dimension limit.
    var tilesPerRow = 1;
    while (tilesPerRow * tilesPerRow < probes) {
      tilesPerRow *= 2;
    }
    final maxTilesPerRow =
        kMaxIrradianceAtlasDimension ~/ (kDepthMomentInterior + 2);
    if (tilesPerRow > maxTilesPerRow) tilesPerRow = maxTilesPerRow;
    if (tilesPerRow < 1) return null;
    final tileRows = (probes + tilesPerRow - 1) ~/ tilesPerRow;
    final layout = IrradianceFieldLayout._(
      resolution: Vector3(x.toDouble(), y.toDouble(), z.toDouble()),
      tilesPerRow: tilesPerRow,
      tileRows: tileRows,
    );
    if (layout.atlasWidth > kMaxIrradianceAtlasDimension ||
        layout.atlasHeight > kMaxIrradianceAtlasDimension) {
      return null;
    }
    return layout;
  }

  /// Probe counts per axis, after clamping.
  final Vector3 resolution;

  /// Probe tiles across one atlas row. Always a power of two.
  final int tilesPerRow;

  /// Rows of probe tiles.
  final int tileRows;

  /// Total probes in the volume.
  int get probeCount =>
      resolution.x.toInt() * resolution.y.toInt() * resolution.z.toInt();

  /// Stored edge of an irradiance tile, interior plus the gutter.
  static const int irradianceTile = kIrradianceInterior + 2;

  /// Stored edge of a depth-moment tile, interior plus the gutter.
  static const int depthTile = kDepthMomentInterior + 2;

  /// First atlas row of the per-probe state strip.
  static const int stateOriginY = 2;

  /// First atlas row of the irradiance region.
  int get irradianceOriginY => stateOriginY + tileRows;

  /// First atlas row of the depth-moment region.
  int get depthOriginY => irradianceOriginY + tileRows * irradianceTile;

  /// Atlas width in texels.
  // TODO(gi-atlas-packing): pack irradiance tiles at double stride or separate
  // atlas textures to reclaim unused right-half space.
  int get atlasWidth => tilesPerRow * depthTile;

  /// Atlas height in texels.
  int get atlasHeight => depthOriginY + tileRows * depthTile;

  /// Bytes the atlas occupies at `r16g16b16a16Float`.
  int get atlasBytes => atlasWidth * atlasHeight * 8;

  /// Width of the irradiance accumulator, which holds one tile per probe with
  /// no gutter and no other regions.
  int get injectionIrradianceWidth => tilesPerRow * irradianceTile;

  /// Height of the irradiance accumulator.
  int get injectionIrradianceHeight => tileRows * irradianceTile;

  /// Width of the depth-moment accumulator.
  int get injectionDepthWidth => tilesPerRow * depthTile;

  /// Height of the depth-moment accumulator.
  int get injectionDepthHeight => tileRows * depthTile;

  /// Linear probe index for the storage coordinate [s], which is the probe's
  /// world lattice index wrapped into the volume.
  int probeIndex(int sx, int sy, int sz) =>
      sx + resolution.x.toInt() * (sy + resolution.y.toInt() * sz);

  /// Column of [index]'s tile in the atlas tile grid.
  int tileColumn(int index) => index % tilesPerRow;

  /// Row of [index]'s tile in the atlas tile grid.
  int tileRow(int index) => index ~/ tilesPerRow;

  @override
  bool operator ==(Object other) =>
      other is IrradianceFieldLayout &&
      other.resolution == resolution &&
      other.tilesPerRow == tilesPerRow &&
      other.tileRows == tileRows;

  @override
  int get hashCode => Object.hash(resolution, tilesPerRow, tileRows);
}

/// The world-space placement of the probe lattice for one frame.
///
/// Probes sit on an infinite lattice through the world origin at [spacing],
/// so the volume can scroll by whole cells without moving any probe that
/// stays inside it. [anchor] is the lattice index of the volume's minimum
/// corner; a probe's storage slot is its lattice index wrapped by the probe
/// counts, which is what makes a scroll invalidate only the slab that
/// entered.
class IrradianceGridPlacement {
  const IrradianceGridPlacement({required this.anchor, required this.spacing});

  /// Lattice index of the volume's minimum-corner probe, per axis.
  final Vector3 anchor;

  /// World-space distance between neighbouring probes, per axis.
  final Vector3 spacing;

  /// World position of the probe at lattice index [index].
  Vector3 probePosition(Vector3 index) =>
      Vector3(index.x * spacing.x, index.y * spacing.y, index.z * spacing.z);

  /// World position of the volume's minimum corner.
  Vector3 get origin => probePosition(anchor);

  /// The largest distance a probe records, 50 percent past a cell diagonal.
  /// Depth moments are normalized by this so both stay inside fp16's
  /// well-conditioned range.
  double get maxProbeDistance => spacing.length * 1.5;

  /// Smallest cell edge, the unit the bias knobs are expressed in.
  double get minCellEdge => math.min(spacing.x, math.min(spacing.y, spacing.z));

  @override
  bool operator ==(Object other) =>
      other is IrradianceGridPlacement &&
      other.anchor == anchor &&
      other.spacing == spacing;

  @override
  int get hashCode => Object.hash(anchor, spacing);
}

/// Derives the lattice placement for a volume of [extents] world units
/// centered on [center] and subdivided into [layout] probes.
///
/// The anchor is snapped to whole lattice cells, so translating the volume
/// (a camera-following field, or a scene whose bounds grew) shifts it by
/// whole probes and leaves every probe that stayed inside bit-identical.
/// A snap never escalates into a rebuild; a teleport simply invalidates every
/// probe once, which costs nothing beyond marking them stale.
IrradianceGridPlacement planIrradianceGrid({
  required Vector3 center,
  required Vector3 extents,
  required IrradianceFieldLayout layout,
}) {
  final counts = layout.resolution;
  final spacing = Vector3(
    _cellEdge(extents.x, counts.x),
    _cellEdge(extents.y, counts.y),
    _cellEdge(extents.z, counts.z),
  );
  final anchor = Vector3(
    ((center.x - extents.x * 0.5) / spacing.x).roundToDouble(),
    ((center.y - extents.y * 0.5) / spacing.y).roundToDouble(),
    ((center.z - extents.z * 0.5) / spacing.z).roundToDouble(),
  );
  return IrradianceGridPlacement(anchor: anchor, spacing: spacing);
}

double _cellEdge(double extent, double count) {
  final span = count > 1.0 ? count - 1.0 : 1.0;
  final edge = extent.abs() / span;
  return edge > 1e-6 ? edge : 1e-6;
}

/// Everything a lit draw needs to read one frame's irradiance field.
///
/// Null on [Lighting] when the field is off, which is what gates the
/// receiver's whole cost.
class IrradianceFieldBinding {
  const IrradianceFieldBinding({
    required this.atlas,
    required this.layout,
    required this.placement,
    required this.intensity,
    required this.shadowBias,
    required this.visibility,
    required this.visibilityBias,
  });

  /// The atlas the lit shader samples. Rows 0 and 1 hold the environment's
  /// coefficient strip, so this texture also stands in for the standalone
  /// spherical-harmonic texture.
  final gpu.Texture atlas;

  /// Where each quantity sits in [atlas].
  final IrradianceFieldLayout layout;

  /// Where the probe lattice sits in the world this frame.
  final IrradianceGridPlacement placement;

  /// Scales the field's contribution to indirect diffuse.
  final double intensity;

  /// Self-shadow bias as a fraction of the smallest cell edge.
  final double shadowBias;

  /// Chebyshev visibility strength.
  final double visibility;

  /// Chebyshev depth bias as a fraction of the smallest cell edge.
  final double visibilityBias;

  /// Width, in cells, of the band the field fades back to the environment
  /// over at the volume boundary.
  static const double boundaryFadeCells = 1.0;
}

/// Wraps a lattice index into its storage slot, the modulo that gives the
/// scroll its tank-tread behavior.
int wrapProbeSlot(int latticeIndex, int count) {
  final m = latticeIndex % count;
  return m < 0 ? m + count : m;
}

/// Whether the probe in storage slot [slot] on one axis holds data from
/// outside the volume after the anchor moved from [previousAnchor] to
/// [anchor], and so must blend at zero hysteresis on its next update.
///
/// The lattice index the slot now represents is the one congruent to [slot]
/// inside `[anchor, anchor + count)`. The probe scrolled in when that index
/// was outside the previous volume.
bool probeScrolledIn({
  required int slot,
  required int count,
  required int anchor,
  required int previousAnchor,
}) {
  final lattice = anchor + wrapProbeSlot(slot - anchor, count);
  return lattice < previousAnchor || lattice >= previousAnchor + count;
}
