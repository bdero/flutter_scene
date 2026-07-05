import 'dart:typed_data';

/// Sorts splats back to front along a view direction.
///
/// Returns the splat indices as a [Float32List] (largest view depth first),
/// ready to upload verbatim as the instance-rate index attribute (the
/// attribute is a float because the broadest GLES tier has no integer vertex
/// attributes; float indices are exact up to 2^24 splats).
///
/// [viewRow] is the direction the depth key is measured along, in the same
/// (local) space as [positions]. The caller derives it from the
/// view-projection w row transformed into local space, so the key is exact
/// view-space depth. Ordering along a fixed direction is unaffected by
/// camera translation, so a re-sort is only needed when the direction
/// changes.
///
/// A 16-bit counting sort over the normalized depth range: two O(n) passes
/// and a 65536-bucket histogram, no comparison sort.
Float32List sortSplatsBackToFront(
  Float32List positions,
  int count,
  double dirX,
  double dirY,
  double dirZ,
) {
  final keys = Float32List(count);
  var minKey = double.infinity;
  var maxKey = double.negativeInfinity;
  for (var i = 0; i < count; i++) {
    final o = i * 3;
    final k =
        positions[o] * dirX + positions[o + 1] * dirY + positions[o + 2] * dirZ;
    keys[i] = k;
    if (k < minKey) minKey = k;
    if (k > maxKey) maxKey = k;
  }

  final out = Float32List(count);
  final range = maxKey - minKey;
  if (count == 0) return out;
  if (range <= 0 || !range.isFinite) {
    for (var i = 0; i < count; i++) {
      out[i] = i.toDouble();
    }
    return out;
  }

  const buckets = 1 << 16;
  final scale = (buckets - 1) / range;
  final histogram = Uint32List(buckets);
  final quantized = Uint16List(count);
  for (var i = 0; i < count; i++) {
    final q = ((keys[i] - minKey) * scale).toInt();
    quantized[i] = q;
    histogram[q]++;
  }

  // Back to front: the largest depth bucket writes first. Convert the
  // histogram into each bucket's starting output offset, walking buckets
  // from far to near.
  var offset = 0;
  for (var b = buckets - 1; b >= 0; b--) {
    final n = histogram[b];
    histogram[b] = offset;
    offset += n;
  }
  for (var i = 0; i < count; i++) {
    out[histogram[quantized[i]]++] = i.toDouble();
  }
  return out;
}

/// The top-level `compute` entry point for [sortSplatsBackToFront].
Float32List sortSplatsForIsolate(
  ({Float32List positions, int count, double dirX, double dirY, double dirZ})
  args,
) {
  return sortSplatsBackToFront(
    args.positions,
    args.count,
    args.dirX,
    args.dirY,
    args.dirZ,
  );
}
