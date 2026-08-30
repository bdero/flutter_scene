/// Painting terrain: which surface shows where.
///
/// Sculpting decides the shape of the ground; this decides what it is made of.
/// A [TerrainSplatMap] holds, for every texel over the patch, how much each of
/// four layers shows through — grass under the trees, rock on the cliff faces,
/// sand where the two meet. The layers blend rather than switch, because a
/// hard boundary between grass and rock is the one thing that makes terrain
/// read as a grid.
///
/// **Four layers, one control texture.** The weights fit exactly one RGBA
/// texture, which is one sampler in the terrain shader and one payload in the
/// document. Reaching eight costs a second control map, and with it a second
/// sampler and a second blend in the inner loop of the most-drawn surface in
/// the scene; four covers the ground people actually paint.
///
/// **Its own resolution.** The control map is not the height grid. Painting
/// wants finer detail than sculpting — a footpath is narrower than any
/// sensible sculpting cell — and tying the two would mean either a heightmap
/// nobody needs that dense or a paintable resolution nobody can work at.
///
/// **Weights are kept as floats and stored as bytes.** Painting is many small
/// additions followed by a renormalization, and doing that arithmetic at
/// 1/255 would make a soft brush at low opacity do nothing at all. The
/// document and the GPU both take the quantized form, which is the same four
/// bytes per texel the texture needs anyway.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/src/geometry/terrain_brush.dart';

/// How many layers a splat map blends. One RGBA control texture's worth.
const int terrainSplatLayers = 4;

/// Per-texel layer weights over a terrain patch.
///
/// Weights at each texel sum to 1, always: a texel is entirely made of
/// something. Painting a layer up therefore paints the others down, which is
/// what makes a brush replace rather than accumulate into mud.
class TerrainSplatMap {
  /// Creates a map over [weights], `columns * rows * 4` of them in row-major
  /// order, four consecutive floats per texel.
  TerrainSplatMap({
    required this.weights,
    required this.columns,
    required this.rows,
    required this.width,
    required this.depth,
  }) : assert(columns >= 2 && rows >= 2, 'A splat map needs a 2x2 grid.'),
       assert(
         weights.length == columns * rows * terrainSplatLayers,
         'Expected columns * rows * $terrainSplatLayers weights.',
       ),
       assert(width > 0 && depth > 0, 'A splat map needs a positive size.');

  /// A map where every texel is entirely layer 0.
  ///
  /// The state a terrain starts in: one material everywhere, which is what
  /// there is to paint onto.
  factory TerrainSplatMap.base({
    required double width,
    required double depth,
    int columns = 256,
    int rows = 256,
  }) {
    final weights = Float32List(columns * rows * terrainSplatLayers);
    for (var i = 0; i < weights.length; i += terrainSplatLayers) {
      weights[i] = 1.0;
    }
    return TerrainSplatMap(
      weights: weights,
      columns: columns,
      rows: rows,
      width: width,
      depth: depth,
    );
  }

  /// Reads a map from packed RGBA bytes, one texel per four bytes.
  ///
  /// Returns null when the byte count does not match, since a truncated
  /// control map would otherwise be read as a terrain half-painted with
  /// nothing.
  static TerrainSplatMap? fromBytes(
    Uint8List bytes, {
    required int columns,
    required int rows,
    required double width,
    required double depth,
  }) {
    if (columns < 2 || rows < 2) return null;
    final count = columns * rows * terrainSplatLayers;
    if (bytes.lengthInBytes != count) return null;
    final weights = Float32List(count);
    for (var i = 0; i < count; i++) {
      weights[i] = bytes[i] / 255.0;
    }
    final map = TerrainSplatMap(
      weights: weights,
      columns: columns,
      rows: rows,
      width: width,
      depth: depth,
    );
    // Bytes that do not sum to 255 -- hand-edited, or written by a tool that
    // rounded differently -- would otherwise darken or blow out the ground.
    map.normalizeAll();
    return map;
  }

  /// The weights as packed RGBA bytes: the document payload, and the pixels
  /// the control texture is uploaded from.
  ///
  /// Rounds so the four channels of a texel still sum to 255. Rounding each
  /// channel on its own leaves texels summing to 254 or 256, which shows as a
  /// faint mottling across ground that was painted flat.
  Uint8List toBytes() {
    final bytes = Uint8List(columns * rows * terrainSplatLayers);
    for (var texel = 0; texel < columns * rows; texel++) {
      final base = texel * terrainSplatLayers;
      var remaining = 255;
      var largest = 0;
      var largestWeight = -1.0;
      for (var layer = 0; layer < terrainSplatLayers; layer++) {
        final weight = weights[base + layer];
        if (weight > largestWeight) {
          largestWeight = weight;
          largest = layer;
        }
      }
      for (var layer = 0; layer < terrainSplatLayers; layer++) {
        if (layer == largest) continue;
        final value = (weights[base + layer] * 255).round().clamp(0, 255);
        bytes[base + layer] = value;
        remaining -= value;
      }
      // The dominant layer absorbs the rounding, where a whole unit of 255 is
      // least visible.
      bytes[base + largest] = remaining.clamp(0, 255);
    }
    return bytes;
  }

  /// The weights, row-major, four per texel.
  final Float32List weights;

  /// Texels across X.
  final int columns;

  /// Texels across Z.
  final int rows;

  /// World size across X, matching the terrain it paints.
  final double width;

  /// World size across Z, matching the terrain it paints.
  final double depth;

  /// The weight of [layer] at texel ([c], [r]), clamped to the edge.
  double weightAt(int c, int r, int layer) =>
      weights[(r.clamp(0, rows - 1) * columns + c.clamp(0, columns - 1)) *
              terrainSplatLayers +
          layer];

  /// Writes the four interpolated weights at world ([x], [z]) into [out].
  ///
  /// The reason the map is kept and not only uploaded: a character controller
  /// asking what it is standing on — for a footstep sound, for friction, for
  /// whether a vehicle bogs down — is asking this, and it costs a bilinear
  /// sample rather than a readback from the GPU.
  void weightsAtWorld(double x, double z, Float32List out) {
    assert(out.length >= terrainSplatLayers);
    final u = ((x + width / 2) / width) * (columns - 1);
    final v = ((z + depth / 2) / depth) * (rows - 1);
    final c = u.floor();
    final r = v.floor();
    final fu = (u - c).clamp(0.0, 1.0);
    final fv = (v - r).clamp(0.0, 1.0);
    for (var layer = 0; layer < terrainSplatLayers; layer++) {
      final top =
          weightAt(c, r, layer) +
          (weightAt(c + 1, r, layer) - weightAt(c, r, layer)) * fu;
      final bottom =
          weightAt(c, r + 1, layer) +
          (weightAt(c + 1, r + 1, layer) - weightAt(c, r + 1, layer)) * fu;
      out[layer] = top + (bottom - top) * fv;
    }
  }

  /// Which layer shows most at world ([x], [z]).
  ///
  /// The question gameplay usually has — one surface, not a blend — so it is
  /// answered here rather than left to every caller to argmax for itself.
  int dominantLayerAtWorld(double x, double z) {
    final sample = Float32List(terrainSplatLayers);
    weightsAtWorld(x, z, sample);
    var best = 0;
    for (var layer = 1; layer < terrainSplatLayers; layer++) {
      if (sample[layer] > sample[best]) best = layer;
    }
    return best;
  }

  /// Sets [layer] at texel [index] to [value], taking the difference out of
  /// the other layers in proportion to what each already had.
  ///
  /// This, rather than a plain renormalization, is what painting means. A
  /// renormalization scales every layer including the one just painted, so
  /// asking for "half rock" over solid grass lands at a quarter rock and the
  /// brush never reaches what it was set to. Taking the difference from the
  /// others in proportion leaves the layer at exactly the value asked for and
  /// keeps the relative mix of everything underneath it.
  void setLayerWeight(int index, int layer, double value) {
    final base = index * terrainSplatLayers;
    final wanted = value.clamp(0.0, 1.0);
    var rest = 0.0;
    for (var other = 0; other < terrainSplatLayers; other++) {
      if (other == layer) continue;
      final weight = weights[base + other];
      if (weight > 0) rest += weight;
    }
    weights[base + layer] = wanted;
    if (rest <= 0) {
      // Nothing underneath to make room in: the texel is this layer alone.
      weights[base + layer] = 1.0;
      for (var other = 0; other < terrainSplatLayers; other++) {
        if (other != layer) weights[base + other] = 0.0;
      }
      return;
    }
    final scale = (1.0 - wanted) / rest;
    for (var other = 0; other < terrainSplatLayers; other++) {
      if (other == layer) continue;
      final weight = weights[base + other];
      weights[base + other] = weight > 0 ? weight * scale : 0.0;
    }
  }

  /// Renormalizes the texel at [index] (a texel index, not a weight index) so
  /// its four weights sum to 1.
  ///
  /// For weights that arrived from outside — a loaded payload, a hand-edited
  /// file — where no one layer is the one being changed. Painting uses
  /// [setLayerWeight] instead.
  void normalizeTexel(int index) {
    final base = index * terrainSplatLayers;
    var total = 0.0;
    for (var layer = 0; layer < terrainSplatLayers; layer++) {
      final weight = weights[base + layer];
      if (weight > 0) {
        total += weight;
      } else {
        // Painting can only push a weight below zero through accumulated
        // rounding, and a negative contribution would brighten the layers it
        // is normalized against rather than simply not showing.
        weights[base + layer] = 0.0;
      }
    }
    if (total <= 0) {
      // Nothing shows, which is not a surface. The base layer is the honest
      // fallback: it is what the terrain was before anyone painted.
      weights[base] = 1.0;
      for (var layer = 1; layer < terrainSplatLayers; layer++) {
        weights[base + layer] = 0.0;
      }
      return;
    }
    final scale = 1.0 / total;
    for (var layer = 0; layer < terrainSplatLayers; layer++) {
      weights[base + layer] *= scale;
    }
  }

  /// Renormalizes every texel.
  void normalizeAll() {
    for (var texel = 0; texel < columns * rows; texel++) {
      normalizeTexel(texel);
    }
  }
}

/// Paints [layer] into [map] with [brush], centred on world ([x], [z]).
///
/// Mirrors [sculptTerrain]: the same brush describes the reach and the
/// falloff, the stroke is scaled by [deltaSeconds] so holding still paints at
/// a rate rather than per event, and the touched texel range comes back so a
/// caller can re-upload a rectangle instead of the whole control texture.
///
/// [targetStrength] caps how far the layer gets: at `1` the brush eventually
/// covers what it touches completely, at `0.5` it stops half way and the
/// layers underneath keep showing through. That cap is what makes a brush able
/// to *tint* ground rather than only replace it.
///
/// Returns null when the stroke fell outside the map.
/// {@category Geometry}
({int minColumn, int minRow, int maxColumn, int maxRow})? paintTerrainSplat(
  TerrainSplatMap map, {
  required int layer,
  required TerrainBrush brush,
  required double x,
  required double z,
  double deltaSeconds = 1.0,
  double targetStrength = 1.0,
}) {
  if (layer < 0 || layer >= terrainSplatLayers) return null;
  if (brush.radius <= 0 || deltaSeconds <= 0) return null;

  final stepX = map.width / (map.columns - 1);
  final stepZ = map.depth / (map.rows - 1);
  final centreColumn = (x + map.width / 2) / stepX;
  final centreRow = (z + map.depth / 2) / stepZ;
  final spanColumns = (brush.radius / stepX).ceil();
  final spanRows = (brush.radius / stepZ).ceil();

  final minColumn = math.max(0, (centreColumn - spanColumns).floor());
  final maxColumn = math.min(
    map.columns - 1,
    (centreColumn + spanColumns).ceil(),
  );
  final minRow = math.max(0, (centreRow - spanRows).floor());
  final maxRow = math.min(map.rows - 1, (centreRow + spanRows).ceil());
  if (minColumn > maxColumn || minRow > maxRow) return null;

  final target = targetStrength.clamp(0.0, 1.0);
  var touched = false;

  for (var r = minRow; r <= maxRow; r++) {
    final sampleZ = -map.depth / 2 + stepZ * r;
    for (var c = minColumn; c <= maxColumn; c++) {
      final sampleX = -map.width / 2 + stepX * c;
      final dx = sampleX - x;
      final dz = sampleZ - z;
      final weight = brush.weightAt(math.sqrt(dx * dx + dz * dz));
      if (weight <= 0) continue;

      final texel = r * map.columns + c;
      final base = texel * terrainSplatLayers;
      final current = map.weights[base + layer];
      // Already at or past what this brush is for. Leaving it alone is what
      // stops a held brush creeping past its target through rounding.
      if (current >= target) continue;

      touched = true;
      final amount = weight * brush.strength.abs() * deltaSeconds;
      final wanted = current + (target - current) * amount.clamp(0.0, 1.0);
      map.setLayerWeight(texel, layer, math.min(wanted, target));
    }
  }

  if (!touched) return null;
  return (
    minColumn: minColumn,
    minRow: minRow,
    maxColumn: maxColumn,
    maxRow: maxRow,
  );
}
