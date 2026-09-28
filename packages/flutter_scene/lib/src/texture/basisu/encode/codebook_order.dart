// Codebook orderings that make the BasisLZ stream smaller.

import 'dart:typed_data';

/// A new position per endpoint entry, keeping entries that neighbor each
/// other in [sequences] (block endpoints per slice) close, so deltas stay
/// small. basis_universal's palette reorderer, with sparse counts.
Int32List orderEndpoints(int count, List<Int32List> sequences) {
  final order = Int32List(count);
  if (count <= 2) {
    for (var i = 0; i < count; i++) {
      order[i] = i;
    }
    return order;
  }
  // Symmetric adjacency counts between entries, both directions.
  final adjacency = List.generate(count, (_) => <int, int>{});
  for (final sequence in sequences) {
    for (var i = 0; i + 1 < sequence.length; i++) {
      final a = sequence[i], b = sequence[i + 1];
      if (a == b) continue;
      adjacency[a][b] = (adjacency[a][b] ?? 0) + 1;
      adjacency[b][a] = (adjacency[b][a] ?? 0) + 1;
    }
  }
  // Seed with the most frequent pair (lowest indices on ties).
  var seedA = 0, seedB = 1, seedCount = -1;
  for (var a = 0; a < count; a++) {
    for (final MapEntry(key: b, value: n) in adjacency[a].entries) {
      if (n > seedCount ||
          (n == seedCount && (a < seedA || (a == seedA && b < seedB)))) {
        seedA = a;
        seedB = b;
        seedCount = n;
      }
    }
  }
  final placed = <int>[seedA, seedB];
  final picked = Uint8List(count)
    ..[seedA] = 1
    ..[seedB] = 1;
  // How often each unplaced entry is adjacent to placed ones.
  final affinity = Int32List(count);
  for (final s in [seedA, seedB]) {
    for (final MapEntry(key: other, value: n) in adjacency[s].entries) {
      affinity[other] += n;
    }
  }
  // Front and back of the growing order, as a deque built in two lists.
  final front = <int>[];
  final back = <int>[...placed];
  for (var step = 2; step < count; step++) {
    var best = -1;
    for (var i = 0; i < count; i++) {
      if (picked[i] != 0) continue;
      if (best < 0 || affinity[i] > affinity[best]) best = i;
    }
    // Put it at the end it borders more often.
    final total = front.length + back.length;
    var side = 0;
    var position = 0;
    int weightAt(int p) => total + 1 - 2 * (p + 1);
    for (var k = front.length - 1; k >= 0; k--, position++) {
      side += weightAt(position) * (adjacency[best][front[k]] ?? 0);
    }
    for (var k = 0; k < back.length; k++, position++) {
      side += weightAt(position) * (adjacency[best][back[k]] ?? 0);
    }
    if (side <= 0) {
      back.add(best);
    } else {
      front.add(best);
    }
    picked[best] = 1;
    for (final MapEntry(key: other, value: n) in adjacency[best].entries) {
      affinity[other] += n;
    }
  }
  var position = 0;
  for (var k = front.length - 1; k >= 0; k--) {
    order[front[k]] = position++;
  }
  for (final entry in back) {
    order[entry] = position++;
  }
  return order;
}

/// A new position per selector entry: a greedy chain of nearest Hamming
/// neighbors, since entries are XOR coded. An entry within 3 bits shares a
/// byte, so per-byte buckets find it without a full scan.
Int32List orderSelectors(Uint32List rows) {
  final count = rows.length;
  final order = Int32List(count);
  if (count == 0) return order;
  // Remaining entries, removable in O(1), and per-byte buckets.
  final remaining = Int32List(count);
  final slot = Int32List(count);
  final buckets = List.generate(4 * 256, (_) => <int>{});
  var remainingCount = 0;
  for (var i = 1; i < count; i++) {
    slot[i] = remainingCount;
    remaining[remainingCount++] = i;
    for (var k = 0; k < 4; k++) {
      buckets[k * 256 + ((rows[i] >> (k * 8)) & 0xFF)].add(i);
    }
  }
  void remove(int entry) {
    final at = slot[entry];
    final last = remaining[--remainingCount];
    remaining[at] = last;
    slot[last] = at;
    for (var k = 0; k < 4; k++) {
      buckets[k * 256 + ((rows[entry] >> (k * 8)) & 0xFF)].remove(entry);
    }
  }

  var previous = 0;
  for (var position = 1; position < count; position++) {
    final from = rows[previous];
    var best = -1;
    var bestDistance = 33;
    void consider(int entry) {
      final distance = _popCount(from ^ rows[entry]);
      if (distance < bestDistance ||
          (distance == bestDistance && entry < best)) {
        bestDistance = distance;
        best = entry;
      }
    }

    for (var k = 0; k < 4; k++) {
      for (final entry in buckets[k * 256 + ((from >> (k * 8)) & 0xFF)]) {
        consider(entry);
      }
    }
    if (bestDistance > 3) {
      for (var j = 0; j < remainingCount; j++) {
        consider(remaining[j]);
      }
    }
    order[best] = position;
    remove(best);
    previous = best;
  }
  return order;
}

int _popCount(int v) =>
    _bitsSet[v & 0xFF] +
    _bitsSet[(v >> 8) & 0xFF] +
    _bitsSet[(v >> 16) & 0xFF] +
    _bitsSet[(v >> 24) & 0xFF];

final Uint8List _bitsSet = Uint8List.fromList([
  for (var i = 0; i < 256; i++)
    [for (var b = 0; b < 8; b++) (i >> b) & 1].reduce((a, b) => a + b),
]);
