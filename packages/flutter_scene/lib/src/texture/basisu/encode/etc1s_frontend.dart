// Quantizes 4x4 blocks into shared endpoint and selector codebooks: cluster
// endpoints, refit and reassign; then the same for selectors; then refit the
// endpoints to the final selectors.

import 'dart:typed_data';

import 'package:flutter_scene/src/texture/basisu/etc1s_tables.dart';

import 'package:flutter_scene/src/texture/basisu/encode/etc1s_fit.dart';
import 'package:flutter_scene/src/texture/basisu/encode/vector_quantizer.dart';

/// The blocks to encode: [count] blocks of 16 RGB pixels, row-major within
/// the block, 48 bytes each.
class Etc1sSourceBlocks {
  Etc1sSourceBlocks(this.rgb, this.count)
    : assert(rgb.length >= count * 48, 'rgb holds fewer than count blocks');

  final Uint8List rgb;
  final int count;
}

/// Codebook sizes and effort for [quantizeEtc1s].
class Etc1sQuantizerOptions {
  const Etc1sQuantizerOptions({
    required this.endpointClusters,
    required this.selectorClusters,
    this.metric = Etc1sMetric.perceptual,
    this.refinementPasses = 2,
    this.endpointCandidates = 16,
    this.selectorCandidates = 16,
  });

  final int endpointClusters;
  final int selectorClusters;
  final Etc1sMetric metric;
  final int refinementPasses;

  /// Nearby clusters a block tries when reassigned.
  final int endpointCandidates;
  final int selectorCandidates;
}

/// The quantized image: codebooks plus one endpoint and one selector entry
/// per source block.
class Etc1sQuantized {
  Etc1sQuantized({
    required this.endpoints,
    required this.selectors,
    required this.blockEndpoints,
    required this.blockSelectors,
    required this.uniqueBlocks,
    required this.blockToUnique,
  });

  /// Endpoint codebook: red, green, blue (5-bit) and intensity per entry.
  final Uint8List endpoints;

  /// Selector codebook: 16 selectors (0-3, ETC1S order) per entry, texel
  /// (x, y) at y * 4 + x.
  final Uint8List selectors;

  /// Endpoint and selector entry per source block.
  final Int32List blockEndpoints;
  final Int32List blockSelectors;

  /// The distinct source blocks, and each source block's index among them.
  final Uint8List uniqueBlocks;
  final Int32List blockToUnique;
}

/// Quantizes [blocks] to ETC1S codebooks.
Etc1sQuantized quantizeEtc1s(
  Etc1sSourceBlocks blocks,
  Etc1sQuantizerOptions options,
) => _Frontend(blocks, options).run();

class _Frontend {
  _Frontend(this.source, this.options)
    : space = MetricSpace(options.metric),
      fitter = Etc1sFitter(MetricSpace(options.metric));

  final Etc1sSourceBlocks source;
  final Etc1sQuantizerOptions options;
  final MetricSpace space;
  final Etc1sFitter fitter;

  late Uint8List unique; // 48 bytes per distinct block
  late Float64List uniqueWeight; // how many source blocks each stands for
  late Int32List blockToUnique;
  late int uniqueCount;

  // Per distinct block: its endpoint cluster and its selector cluster.
  late Int32List endpointOf;
  late Int32List selectorOf;

  // Codebooks as they evolve.
  final endpointBook = <Etc1sEndpoint>[];
  late Uint8List selectorBook;

  late final FitPixels _blockPixels = FitPixels(space, 16);

  Etc1sQuantized run() {
    _dedupe();
    _clusterEndpoints(_quickFits());
    for (var pass = 0; pass < options.refinementPasses; pass++) {
      _fitEndpointCodebook();
      _reassignEndpoints();
    }
    _fitEndpointCodebook();
    _clusterSelectors();
    for (var pass = 0; pass < options.refinementPasses; pass++) {
      _fitSelectorCodebook();
      _reassignSelectors();
    }
    _fitSelectorCodebook();
    _refitEndpointsToSelectors();
    return _output();
  }

  void _dedupe() {
    final index = <int, List<int>>{};
    final firstOf = <int>[];
    blockToUnique = Int32List(source.count);
    final weights = <double>[];
    final rgb = source.rgb;
    for (var b = 0; b < source.count; b++) {
      // Kept below 2^30 so it stays exact on the web.
      var h = 0;
      for (var i = b * 48; i < b * 48 + 48; i++) {
        h = (h * 31 + rgb[i]) & 0x3FFFFFFF;
      }
      final bucket = index[h];
      var found = -1;
      if (bucket != null) {
        for (final u in bucket) {
          final o = firstOf[u] * 48;
          var same = true;
          for (var i = 0; i < 48; i++) {
            if (rgb[o + i] != rgb[b * 48 + i]) {
              same = false;
              break;
            }
          }
          if (same) {
            found = u;
            break;
          }
        }
      }
      if (found < 0) {
        found = firstOf.length;
        firstOf.add(b);
        weights.add(0);
        (index[h] ??= []).add(found);
      }
      weights[found] += 1;
      blockToUnique[b] = found;
    }
    uniqueCount = firstOf.length;
    unique = Uint8List(uniqueCount * 48);
    for (var u = 0; u < uniqueCount; u++) {
      unique.setRange(u * 48, u * 48 + 48, rgb, firstOf[u] * 48);
    }
    uniqueWeight = Float64List.fromList(weights);
  }

  /// Loads distinct block [u]'s pixels into the reusable fit buffer.
  FitPixels _pixelsOf(int u) {
    final p = _blockPixels..clear();
    for (var i = 0; i < 16; i++) {
      final o = u * 48 + i * 3;
      p.add(unique[o], unique[o + 1], unique[o + 2]);
    }
    return p;
  }

  List<Etc1sEndpoint> _quickFits() => [
    for (var u = 0; u < uniqueCount; u++) fitter.fit(_pixelsOf(u)).endpoint,
  ];

  void _clusterEndpoints(List<Etc1sEndpoint> quick) {
    // Many blocks share a quick fit; cluster the distinct endpoints.
    final ids = <Etc1sEndpoint, int>{};
    final vectorOf = Int32List(uniqueCount);
    final weights = <double>[];
    for (var u = 0; u < uniqueCount; u++) {
      final id = ids.putIfAbsent(quick[u], () {
        weights.add(0);
        return ids.length;
      });
      vectorOf[u] = id;
      weights[id] += uniqueWeight[u];
    }
    final count = ids.length;
    final vectors = Float64List(count * 6);
    for (final entry in ids.entries) {
      final e = entry.key;
      final m = etc1IntenTables[e.inten];
      final o = entry.value * 6;
      final channels = [e.r, e.g, e.b];
      for (var c = 0; c < 3; c++) {
        final base = expand5(channels[c]);
        vectors[o + c] = _clamp255(base + m[0]) / 255;
        vectors[o + 3 + c] = _clamp255(base + m[3]) / 255;
      }
    }
    final q = quantize(
      vectors,
      Float64List.fromList(weights),
      count,
      6,
      options.endpointClusters,
    );
    _endpointTree = q;
    endpointOf = Int32List(uniqueCount);
    for (var u = 0; u < uniqueCount; u++) {
      endpointOf[u] = q.assignments[vectorOf[u]];
    }
    endpointBook
      ..clear()
      ..addAll(List.filled(q.clusterCount, Etc1sEndpoint(0, 0, 0, 0)));
  }

  late Quantization _endpointTree;
  bool _endpointsFitted = false;

  /// Refits every endpoint cluster to all of its blocks' pixels.
  void _fitEndpointCodebook() {
    final members = _membersOf(endpointOf, endpointBook.length);
    final pixels = FitPixels(space, 16 * _largest(members));
    for (var c = 0; c < endpointBook.length; c++) {
      final list = members[c];
      if (list.isEmpty) continue;
      pixels.clear();
      for (final u in list) {
        final w = uniqueWeight[u];
        for (var i = 0; i < 16; i++) {
          final o = u * 48 + i * 3;
          pixels.add(unique[o], unique[o + 1], unique[o + 2], w);
        }
      }
      // Later fits start from the previous endpoint.
      endpointBook[c] = fitter
          .fit(
            pixels,
            thorough: true,
            start: _endpointsFitted ? endpointBook[c] : null,
          )
          .endpoint;
    }
    _endpointsFitted = true;
  }

  /// Moves every block to the nearby endpoint cluster that fits it best.
  void _reassignEndpoints() {
    for (var u = 0; u < uniqueCount; u++) {
      final pixels = _pixelsOf(u);
      var best = endpointOf[u];
      final e = endpointBook[best];
      var bestError = fitter.evaluate(pixels, e.r, e.g, e.b, e.inten);
      for (final c in _endpointTree.relatives(
        endpointOf[u],
        options.endpointCandidates,
      )) {
        if (c == endpointOf[u]) continue;
        final t = endpointBook[c];
        final error = fitter.evaluate(
          pixels,
          t.r,
          t.g,
          t.b,
          t.inten,
          limit: bestError,
        );
        if (error < bestError) {
          bestError = error;
          best = c;
        }
      }
      endpointOf[u] = best;
    }
  }

  late Quantization _selectorTree;
  late Uint8List _bestSelectors; // 16 per distinct block

  void _clusterSelectors() {
    _bestSelectors = Uint8List(uniqueCount * 16);
    final scratch = Uint8List(16);
    for (var u = 0; u < uniqueCount; u++) {
      final e = endpointBook[endpointOf[u]];
      fitter.evaluate(_pixelsOf(u), e.r, e.g, e.b, e.inten, selectors: scratch);
      _bestSelectors.setRange(u * 16, u * 16 + 16, scratch);
    }
    // Weight each block by contrast, as basis_universal does: selectors
    // barely matter in flat blocks.
    final contrast = Float64List(endpointBook.length);
    final low = Float64List(3), high = Float64List(3);
    for (var c = 0; c < endpointBook.length; c++) {
      final e = endpointBook[c];
      final m = etc1IntenTables[e.inten];
      final r = expand5(e.r), g = expand5(e.g), b = expand5(e.b);
      space.transform(
        _clamp255(r + m[0]),
        _clamp255(g + m[0]),
        _clamp255(b + m[0]),
        low,
        0,
      );
      space.transform(
        _clamp255(r + m[3]),
        _clamp255(g + m[3]),
        _clamp255(b + m[3]),
        high,
        0,
      );
      var d = 0.0;
      for (var k = 0; k < 3; k++) {
        d += (high[k] - low[k]) * (high[k] - low[k]);
      }
      contrast[c] = (d * 128 / 300).clamp(1, 4096).toDouble();
    }
    final ids = <int, int>{};
    final vectorOf = Int32List(uniqueCount);
    final weights = <double>[];
    final patterns = <int>[];
    for (var u = 0; u < uniqueCount; u++) {
      var key = 0;
      for (var i = 0; i < 16; i++) {
        key |= _bestSelectors[u * 16 + i] << (i * 2);
      }
      final id = ids.putIfAbsent(key, () {
        weights.add(0);
        patterns.add(key);
        return ids.length;
      });
      vectorOf[u] = id;
      weights[id] += uniqueWeight[u] * contrast[endpointOf[u]];
    }
    final count = patterns.length;
    final vectors = Float64List(count * 16);
    for (var p = 0; p < count; p++) {
      for (var i = 0; i < 16; i++) {
        vectors[p * 16 + i] = ((patterns[p] >> (i * 2)) & 3).toDouble();
      }
    }
    final q = quantize(
      vectors,
      Float64List.fromList(weights),
      count,
      16,
      options.selectorClusters,
    );
    _selectorTree = q;
    selectorOf = Int32List(uniqueCount);
    for (var u = 0; u < uniqueCount; u++) {
      selectorOf[u] = q.assignments[vectorOf[u]];
    }
    selectorBook = Uint8List(q.clusterCount * 16);
  }

  /// Sets every selector entry, texel by texel, to the selector with the
  /// least error over the blocks using it.
  void _fitSelectorCodebook() {
    final members = _membersOf(selectorOf, selectorBook.length ~/ 16);
    final errors = Float64List(64);
    final palette = Float64List(12);
    final coords = Float64List(3);
    for (var c = 0; c < members.length; c++) {
      final list = members[c];
      if (list.isEmpty) continue;
      errors.fillRange(0, 64, 0);
      for (final u in list) {
        final e = endpointBook[endpointOf[u]];
        _paletteCoords(e, palette);
        final w = uniqueWeight[u];
        for (var i = 0; i < 16; i++) {
          final o = u * 48 + i * 3;
          space.transform(unique[o], unique[o + 1], unique[o + 2], coords, 0);
          for (var s = 0; s < 4; s++) {
            final dx = coords[0] - palette[s * 3];
            final dy = coords[1] - palette[s * 3 + 1];
            final dz = coords[2] - palette[s * 3 + 2];
            errors[i * 4 + s] += (dx * dx + dy * dy + dz * dz) * w;
          }
        }
      }
      for (var i = 0; i < 16; i++) {
        var best = 0;
        for (var s = 1; s < 4; s++) {
          if (errors[i * 4 + s] < errors[i * 4 + best]) best = s;
        }
        selectorBook[c * 16 + i] = best;
      }
    }
  }

  void _paletteCoords(Etc1sEndpoint e, Float64List out) {
    final m = etc1IntenTables[e.inten];
    final r = expand5(e.r), g = expand5(e.g), b = expand5(e.b);
    for (var s = 0; s < 4; s++) {
      space.transform(
        _clamp255(r + m[s]),
        _clamp255(g + m[s]),
        _clamp255(b + m[s]),
        out,
        s * 3,
      );
    }
  }

  /// Moves every block to the nearby selector entry that fits it best under
  /// its endpoint.
  void _reassignSelectors() {
    final candidate = Uint8List(16);
    for (var u = 0; u < uniqueCount; u++) {
      final pixels = _pixelsOf(u);
      final e = endpointBook[endpointOf[u]];
      var best = selectorOf[u];
      double errorOf(int c, [double limit = double.infinity]) {
        candidate.setRange(0, 16, selectorBook, c * 16);
        return fitter.evaluateWithSelectors(
          pixels,
          e.r,
          e.g,
          e.b,
          e.inten,
          candidate,
          limit: limit,
        );
      }

      var bestError = errorOf(best);
      for (final c in _selectorTree.relatives(
        selectorOf[u],
        options.selectorCandidates,
      )) {
        if (c == selectorOf[u]) continue;
        final error = errorOf(c, bestError);
        if (error < bestError) {
          bestError = error;
          best = c;
        }
      }
      selectorOf[u] = best;
    }
  }

  /// Refits each endpoint to its blocks' final selectors.
  void _refitEndpointsToSelectors() {
    final members = _membersOf(endpointOf, endpointBook.length);
    final pixels = FitPixels(space, 16 * _largest(members));
    final selectors = Uint8List(pixels.weights.length);
    for (var c = 0; c < endpointBook.length; c++) {
      final list = members[c];
      if (list.isEmpty) continue;
      pixels.clear();
      var k = 0;
      for (final u in list) {
        final w = uniqueWeight[u];
        final s = selectorOf[u];
        for (var i = 0; i < 16; i++) {
          final o = u * 48 + i * 3;
          pixels.add(unique[o], unique[o + 1], unique[o + 2], w);
          selectors[k++] = selectorBook[s * 16 + i];
        }
      }
      final current = endpointBook[c];
      var best = current;
      var bestError = fitter.evaluateWithSelectors(
        pixels,
        current.r,
        current.g,
        current.b,
        current.inten,
        selectors,
      );
      // The answer lies at or next to the current intensity.
      for (var t = current.inten - 1; t <= current.inten + 1; t++) {
        if (t < 0 || t > 7) continue;
        final m = etc1IntenTables[t];
        var sw = 0.0, sr = 0.0, sg = 0.0, sb = 0.0;
        for (var i = 0; i < pixels.length; i++) {
          final w = pixels.weights[i];
          final d = m[selectors[i]];
          sw += w;
          sr += (pixels.rgb[i * 3] - d) * w;
          sg += (pixels.rgb[i * 3 + 1] - d) * w;
          sb += (pixels.rgb[i * 3 + 2] - d) * w;
        }
        final r0 = _q5(sr / sw), g0 = _q5(sg / sw), b0 = _q5(sb / sw);
        // The least-squares base and its axis neighbors.
        for (final (dr, dg, db) in const [
          (0, 0, 0),
          (-1, 0, 0),
          (1, 0, 0),
          (0, -1, 0),
          (0, 1, 0),
          (0, 0, -1),
          (0, 0, 1),
        ]) {
          final r = r0 + dr, g = g0 + dg, b = b0 + db;
          if (r < 0 || r > 31 || g < 0 || g > 31 || b < 0 || b > 31) continue;
          final error = fitter.evaluateWithSelectors(
            pixels,
            r,
            g,
            b,
            t,
            selectors,
          );
          if (error < bestError) {
            bestError = error;
            best = Etc1sEndpoint(r, g, b, t);
          }
        }
      }
      endpointBook[c] = best;
    }
  }

  /// Drops unused entries and maps every source block to its entries.
  Etc1sQuantized _output() {
    final endpointUsed = Int32List(endpointBook.length)
      ..fillRange(0, endpointBook.length, -1);
    final selectorUsed = Int32List(selectorBook.length ~/ 16)
      ..fillRange(0, selectorBook.length ~/ 16, -1);
    var endpoints = 0, selectors = 0;
    for (var u = 0; u < uniqueCount; u++) {
      if (endpointUsed[endpointOf[u]] < 0) {
        endpointUsed[endpointOf[u]] = endpoints++;
      }
      if (selectorUsed[selectorOf[u]] < 0) {
        selectorUsed[selectorOf[u]] = selectors++;
      }
    }
    final endpointBytes = Uint8List(endpoints * 4);
    for (var c = 0; c < endpointBook.length; c++) {
      final i = endpointUsed[c];
      if (i < 0) continue;
      final e = endpointBook[c];
      endpointBytes
        ..[i * 4] = e.r
        ..[i * 4 + 1] = e.g
        ..[i * 4 + 2] = e.b
        ..[i * 4 + 3] = e.inten;
    }
    final selectorBytes = Uint8List(selectors * 16);
    for (var c = 0; c < selectorUsed.length; c++) {
      final i = selectorUsed[c];
      if (i < 0) continue;
      selectorBytes.setRange(i * 16, i * 16 + 16, selectorBook, c * 16);
    }
    final blockEndpoints = Int32List(source.count);
    final blockSelectors = Int32List(source.count);
    for (var b = 0; b < source.count; b++) {
      final u = blockToUnique[b];
      blockEndpoints[b] = endpointUsed[endpointOf[u]];
      blockSelectors[b] = selectorUsed[selectorOf[u]];
    }
    return Etc1sQuantized(
      endpoints: endpointBytes,
      selectors: selectorBytes,
      blockEndpoints: blockEndpoints,
      blockSelectors: blockSelectors,
      uniqueBlocks: unique,
      blockToUnique: blockToUnique,
    );
  }

  List<List<int>> _membersOf(Int32List assignment, int clusters) {
    final members = List.generate(clusters, (_) => <int>[]);
    for (var u = 0; u < uniqueCount; u++) {
      members[assignment[u]].add(u);
    }
    return members;
  }

  int _largest(List<List<int>> members) =>
      members.fold<int>(1, (m, l) => l.length > m ? l.length : m);
}

int _clamp255(int v) => v < 0 ? 0 : (v > 255 ? 255 : v);

int _q5(double v) {
  final i = (v * 31 / 255 + 0.5).floor();
  return i < 0 ? 0 : (i > 31 ? 31 : i);
}
