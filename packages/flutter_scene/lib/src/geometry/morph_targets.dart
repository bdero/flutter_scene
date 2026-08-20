import 'dart:math' show sqrt;
import 'dart:typed_data';

/// The number of morph targets the GPU blend path evaluates per draw.
///
/// A geometry may carry more targets than this; each frame the engine picks
/// the [kMaxGpuMorphTargets] nonzero weights with the largest magnitude and
/// uploads only those.
/// {@category Geometry}
const int kMaxGpuMorphTargets = 8;

/// The largest morph texture dimension the GPU blend path assumes, the
/// GLES 3.0 minimum guarantee. Geometry whose packed deltas do not fit
/// falls back to CPU blending.
const int kMorphTextureMaxDimension = 2048;

/// Morph target (blend shape) deltas for one geometry.
///
/// Targets store additive deltas against the base vertex attributes; the
/// blended result is `base + sum(weight_i * delta_i)` over every target, per
/// the glTF morph semantics. Deltas are target-major
/// (`[target][vertex][xyz]`) and aligned with the owning geometry's packed
/// vertex order.
///
/// Instances are usually built by the importers. The per-instance weights
/// live on the mesh-bearing [Node] ([Node.setMorphWeight]); this object
/// carries only the shared deltas, [targetNames], and [defaultWeights].
/// {@category Geometry}
class MorphTargetData {
  /// Creates morph data covering [targetCount] targets of [vertexCount]
  /// vertices each.
  ///
  /// [positionDeltas] holds `targetCount * vertexCount * 3` floats; the
  /// optional [normalDeltas] and [tangentDeltas] match that shape (tangent
  /// deltas are xyz only, the bitangent sign always comes from the base
  /// tangent). [targetNames] and [defaultWeights] are padded/truncated to
  /// [targetCount].
  MorphTargetData({
    required this.vertexCount,
    required this.targetCount,
    required this.positionDeltas,
    this.normalDeltas,
    this.tangentDeltas,
    List<String>? targetNames,
    List<double>? defaultWeights,
  }) : targetNames = List.unmodifiable([
         for (var i = 0; i < targetCount; i++)
           (targetNames != null && i < targetNames.length)
               ? targetNames[i]
               : '',
       ]),
       defaultWeights = Float32List(targetCount) {
    if (positionDeltas.length != targetCount * vertexCount * 3) {
      throw ArgumentError(
        'positionDeltas has ${positionDeltas.length} floats; expected '
        '${targetCount * vertexCount * 3} for $targetCount targets of '
        '$vertexCount vertices',
      );
    }
    for (final (name, deltas) in [
      ('normalDeltas', normalDeltas),
      ('tangentDeltas', tangentDeltas),
    ]) {
      if (deltas != null && deltas.length != positionDeltas.length) {
        throw ArgumentError(
          '$name has ${deltas.length} floats; expected '
          '${positionDeltas.length} to match positionDeltas',
        );
      }
    }
    if (defaultWeights != null) {
      for (var i = 0; i < targetCount && i < defaultWeights.length; i++) {
        this.defaultWeights[i] = defaultWeights[i];
      }
    }
  }

  /// The number of vertices each target's deltas cover.
  final int vertexCount;

  /// The number of morph targets.
  final int targetCount;

  /// Position deltas, target-major, `targetCount * vertexCount * 3` floats.
  final Float32List positionDeltas;

  /// Normal deltas (same shape as [positionDeltas]), or null when the
  /// targets carry none.
  final Float32List? normalDeltas;

  /// Tangent deltas, xyz only, or null when absent. Stored but not applied
  /// yet. TODO(morph-tangent-deltas): blend tangents on both paths.
  final Float32List? tangentDeltas;

  /// The target names (from the asset's `extras.targetNames`), empty
  /// strings for unnamed targets. Always [targetCount] entries.
  final List<String> targetNames;

  /// The mesh-default weights a fresh instance starts from. Always
  /// [targetCount] entries; zero for targets the asset gave no default.
  final Float32List defaultWeights;

  /// Blends [weights] worth of position deltas onto [basePositions]
  /// (`vertexCount * 3` floats), writing into [out] when given (must match
  /// the base length) or a fresh list otherwise.
  Float32List blendPositions(
    Float32List basePositions,
    Float32List weights, {
    Float32List? out,
  }) => _blendAdditive(basePositions, weights, positionDeltas, out);

  /// Blends [weights] worth of normal deltas onto [baseNormals] and
  /// renormalizes each result, keeping the base normal where the weighted
  /// sum collapses to near zero. Returns the base values unchanged when the
  /// targets carry no normal deltas.
  Float32List blendNormals(
    Float32List baseNormals,
    Float32List weights, {
    Float32List? out,
  }) {
    final deltas = normalDeltas;
    if (deltas == null) {
      if (out == null) return Float32List.fromList(baseNormals);
      out.setAll(0, baseNormals);
      return out;
    }
    final result = _blendAdditive(baseNormals, weights, deltas, out);
    for (var v = 0; v < vertexCount; v++) {
      final x = result[v * 3], y = result[v * 3 + 1], z = result[v * 3 + 2];
      final lengthSquared = x * x + y * y + z * z;
      if (lengthSquared > 1e-12) {
        final inverseLength = 1.0 / sqrt(lengthSquared);
        result[v * 3] = x * inverseLength;
        result[v * 3 + 1] = y * inverseLength;
        result[v * 3 + 2] = z * inverseLength;
      } else {
        result[v * 3] = baseNormals[v * 3];
        result[v * 3 + 1] = baseNormals[v * 3 + 1];
        result[v * 3 + 2] = baseNormals[v * 3 + 2];
      }
    }
    return result;
  }

  Float32List _blendAdditive(
    Float32List base,
    Float32List weights,
    Float32List deltas,
    Float32List? out,
  ) {
    if (base.length != vertexCount * 3) {
      throw ArgumentError(
        'base has ${base.length} floats; expected ${vertexCount * 3}',
      );
    }
    final result = out ?? Float32List(base.length);
    if (result.length != base.length) {
      throw ArgumentError(
        'out has ${result.length} floats; expected ${base.length}',
      );
    }
    result.setAll(0, base);
    final count = weights.length < targetCount ? weights.length : targetCount;
    for (var t = 0; t < count; t++) {
      final w = weights[t];
      if (w == 0.0) continue;
      final offset = t * vertexCount * 3;
      for (var i = 0; i < vertexCount * 3; i++) {
        result[i] += w * deltas[offset + i];
      }
    }
    return result;
  }

  /// Picks the morph targets to evaluate on the GPU: the nonzero entries of
  /// [weights] with the largest magnitudes, at most [cap] of them, ordered
  /// by descending magnitude (ties keep the lower index first).
  static List<({int index, double weight})> selectActiveTargets(
    Float32List weights, {
    int cap = kMaxGpuMorphTargets,
  }) {
    final active = <({int index, double weight})>[
      for (var i = 0; i < weights.length; i++)
        if (weights[i] != 0.0) (index: i, weight: weights[i]),
    ];
    active.sort((a, b) {
      final byMagnitude = b.weight.abs().compareTo(a.weight.abs());
      if (byMagnitude != 0) return byMagnitude;
      return a.index.compareTo(b.index);
    });
    return active.length > cap ? active.sublist(0, cap) : active;
  }
}

/// The layout of a morph delta texture: an `RGBA32F` 2D texture where every
/// target owns a contiguous band of rows.
///
/// Vertices wrap left to right inside a band, [width] per row, so a wrap
/// boundary never crosses into another target's rows. Within a band the
/// position rows come first, then (when [includesNormals]) the normal rows.
/// A texel's xyz carry one vertex's delta; w is unused padding.
class MorphTexturePacking {
  MorphTexturePacking({
    required this.width,
    required this.rowsPerAttribute,
    required this.includesNormals,
    required this.targetCount,
  });

  /// Texels per row, `min(vertexCount, max texture width)`.
  final int width;

  /// Rows one attribute of one target occupies, `ceil(vertexCount/width)`.
  final int rowsPerAttribute;

  /// Whether each band carries normal rows after its position rows.
  final bool includesNormals;

  /// The number of bands.
  final int targetCount;

  /// Rows per target band.
  int get bandRows => rowsPerAttribute * (includesNormals ? 2 : 1);

  /// Total texture height in rows.
  int get height => bandRows * targetCount;

  /// The first row of [target]'s band.
  int bandStart(int target) => target * bandRows;
}

/// Computes the delta-texture packing for [data], or null when the packed
/// texture would exceed [maxWidth] x [maxHeight] (the caller then blends on
/// the CPU instead).
MorphTexturePacking? computeMorphTexturePacking(
  MorphTargetData data, {
  int maxWidth = kMorphTextureMaxDimension,
  int maxHeight = kMorphTextureMaxDimension,
}) {
  if (data.vertexCount == 0 || data.targetCount == 0) return null;
  final width = data.vertexCount < maxWidth ? data.vertexCount : maxWidth;
  final rowsPerAttribute = (data.vertexCount + width - 1) ~/ width;
  final packing = MorphTexturePacking(
    width: width,
    rowsPerAttribute: rowsPerAttribute,
    includesNormals: data.normalDeltas != null,
    targetCount: data.targetCount,
  );
  if (packing.height > maxHeight) return null;
  return packing;
}

/// Fills the texel payload for [data] packed per [packing]: RGBA float32
/// texels, row-major, `packing.width * packing.height * 4` floats. Slots past
/// a band's last vertex stay zero.
Float32List buildMorphTexturePayload(
  MorphTargetData data,
  MorphTexturePacking packing,
) {
  final texels = Float32List(packing.width * packing.height * 4);
  void writeAttribute(Float32List deltas, int target, int firstRow) {
    final source = target * data.vertexCount * 3;
    for (var v = 0; v < data.vertexCount; v++) {
      final row = firstRow + v ~/ packing.width;
      final column = v % packing.width;
      final texel = (row * packing.width + column) * 4;
      texels[texel] = deltas[source + v * 3];
      texels[texel + 1] = deltas[source + v * 3 + 1];
      texels[texel + 2] = deltas[source + v * 3 + 2];
    }
  }

  for (var t = 0; t < data.targetCount; t++) {
    final band = packing.bandStart(t);
    writeAttribute(data.positionDeltas, t, band);
    final normals = data.normalDeltas;
    if (packing.includesNormals && normals != null) {
      writeAttribute(normals, t, band + packing.rowsPerAttribute);
    }
  }
  return texels;
}
