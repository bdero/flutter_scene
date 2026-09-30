// Writes quantized ETC1S images as a BasisLZ payload (global data plus one
// slice per image), the stream etc1s.dart and basis_universal read.

import 'dart:typed_data';

import 'package:flutter_scene/src/texture/basisu/encode/bit_writer.dart';
import 'package:flutter_scene/src/texture/basisu/encode/codebook_order.dart';

/// One image's blocks: [blocksX] x [blocksY] endpoint and selector indices,
/// row-major.
class Etc1sSlice {
  Etc1sSlice(this.blocksX, this.blocksY, this.endpoints, this.selectors);

  final int blocksX;
  final int blocksY;
  final Int32List endpoints;
  final Int32List selectors;
}

/// An image of the payload: its color slice and, for images with alpha, its
/// alpha slice.
class Etc1sImage {
  Etc1sImage(this.rgb, [this.alpha]);

  final Etc1sSlice rgb;
  final Etc1sSlice? alpha;
}

/// The encoded payload: the KTX2 supercompression global data, and the
/// bytes of each image (its color slice, then its alpha slice).
class BasisLzPayload {
  BasisLzPayload(this.globalData, this.images);

  final Uint8List globalData;
  final List<Uint8List> images;
}

/// History entries the selector coder keeps (the decoder reads the size).
const int selectorHistorySize = 64;

// Bitstream constants shared with the decoder.
const int _endpointPredRepeatSymbol = 256;
const int _endpointPredMinRepeat = 3;
const int _endpointPredCountVlcBits = 4;
const int _noEndpointPred = 3;
const int _selectorRleMin = 3;
const int _selectorRleSymbols = 64;
const int _selectorRleVlcBits = 7;

/// Measures a block's error under other codebook entries, for
/// rate-distortion choices. [load] selects the block.
abstract class Etc1sBlockErrors {
  void load(int slice, int block);

  /// Prepares [selectorError] for the loaded block under one endpoint.
  void fixEndpoint(int r5, int g5, int b5, int inten);

  /// The loaded block's error with [selectors] under the endpoint given to
  /// [fixEndpoint], or any value >= [limit] once it is known to reach it.
  double selectorError(Uint8List selectors, {double limit = double.infinity});

  /// The error, or any value >= [limit] once it is known to reach it.
  double error(
    int r5,
    int g5,
    int b5,
    int inten,
    Uint8List selectors, {
    double limit = double.infinity,
  });
}

/// How much a block's error may grow (as a factor) to take a cheaper
/// endpoint or selector. basis_universal's defaults.
class Etc1sRdo {
  const Etc1sRdo(
    this.errors, {
    this.endpointThreshold = 1.5,
    this.selectorThreshold = 1.25,
  });

  final Etc1sBlockErrors errors;
  final double endpointThreshold;
  final double selectorThreshold;
}

/// The most entries either codebook may hold. Huffman symbol counts are 14
/// bits, and the selector model adds 65 history symbols to the codebook size.
const int maxEtc1sCodebookEntries = 16128;

/// Writes the payload for [images] against the endpoint codebook (4 bytes
/// per entry) and selector codebook (16 selectors per entry).
BasisLzPayload writeBasisLz({
  required Uint8List endpoints,
  required Uint8List selectors,
  required List<Etc1sImage> images,
  Etc1sRdo? rdo,
}) {
  final endpointCount = endpoints.length ~/ 4;
  final selectorCount = selectors.length ~/ 16;
  if (endpointCount == 0 || selectorCount == 0) {
    throw ArgumentError('BasisLZ needs at least one endpoint and selector');
  }
  if (endpointCount > maxEtc1sCodebookEntries ||
      selectorCount > maxEtc1sCodebookEntries) {
    throw ArgumentError(
      'BasisLZ codebooks hold at most $maxEtc1sCodebookEntries entries',
    );
  }

  final slices = <Etc1sSlice>[
    for (final image in images) ...[image.rgb, ?image.alpha],
  ];

  // Reorder both codebooks and remap every block.
  final endpointOrder = orderEndpoints(endpointCount, [
    for (final slice in slices) slice.endpoints,
  ]);
  final orderedEndpoints = Uint8List(endpoints.length);
  for (var i = 0; i < endpointCount; i++) {
    orderedEndpoints.setRange(
      endpointOrder[i] * 4,
      endpointOrder[i] * 4 + 4,
      endpoints,
      i * 4,
    );
  }
  final selectorRows = Uint32List(selectorCount);
  for (var i = 0; i < selectorCount; i++) {
    var packed = 0;
    for (var t = 0; t < 16; t++) {
      packed |= selectors[i * 16 + t] << (t * 2);
    }
    selectorRows[i] = packed;
  }
  final selectorOrder = orderSelectors(selectorRows);
  final orderedSelectors = Uint8List(selectors.length);
  for (var i = 0; i < selectorCount; i++) {
    orderedSelectors.setRange(
      selectorOrder[i] * 16,
      selectorOrder[i] * 16 + 16,
      selectors,
      i * 16,
    );
  }
  final remapped = [
    for (final slice in slices)
      Etc1sSlice(
        slice.blocksX,
        slice.blocksY,
        Int32List.fromList([for (final e in slice.endpoints) endpointOrder[e]]),
        Int32List.fromList([for (final s in slice.selectors) selectorOrder[s]]),
      ),
  ];

  final plans = [
    for (var i = 0; i < remapped.length; i++)
      _planSlice(remapped[i], i, orderedEndpoints, orderedSelectors, rdo),
  ];

  // Entropy models from the symbols every slice will write.
  final predFrequencies = List<int>.filled(257, 0);
  final deltaFrequencies = List<int>.filled(endpointCount, 0);
  final selectorFrequencies = List<int>.filled(
    selectorCount + selectorHistorySize + 1,
    0,
  );
  final rleFrequencies = List<int>.filled(_selectorRleSymbols, 0);
  for (final plan in plans) {
    for (final s in plan.predSymbols) {
      if (s >= 0) predFrequencies[s]++;
    }
    for (final d in plan.deltas) {
      deltaFrequencies[d]++;
    }
    for (final s in plan.selectorSymbols) {
      if (s >= 0) selectorFrequencies[s]++;
    }
    for (final r in plan.runs) {
      final symbol = r - _selectorRleMin;
      rleFrequencies[symbol < _selectorRleSymbols - 1
          ? symbol
          : _selectorRleSymbols - 1]++;
    }
  }
  final predModel = HuffmanCode.fromFrequencies(predFrequencies);
  final deltaModel = HuffmanCode.fromFrequencies(deltaFrequencies);
  final selectorModel = HuffmanCode.fromFrequencies(selectorFrequencies);
  final rleModel = HuffmanCode.fromFrequencies(rleFrequencies);

  final tables = BitWriter();
  writeHuffmanTable(tables, predModel);
  writeHuffmanTable(tables, deltaModel);
  writeHuffmanTable(tables, selectorModel);
  writeHuffmanTable(tables, rleModel);
  tables.writeBits(selectorHistorySize, 13);

  final sliceBytes = [
    for (final plan in plans)
      _writeSlice(plan, predModel, deltaModel, selectorModel, rleModel),
  ];

  final endpointBytes = _writeEndpoints(orderedEndpoints);
  final selectorBytes = _writeSelectors(orderedSelectors);
  final tableBytes = tables.takeBytes();

  // The global data holds a header, one descriptor per image, then the
  // sections.
  const headerSize = 20, descriptorSize = 20;
  final global = Uint8List(
    headerSize +
        descriptorSize * images.length +
        endpointBytes.length +
        selectorBytes.length +
        tableBytes.length,
  );
  final view = ByteData.sublistView(global);
  view
    ..setUint16(0, endpointCount, Endian.little)
    ..setUint16(2, selectorCount, Endian.little)
    ..setUint32(4, endpointBytes.length, Endian.little)
    ..setUint32(8, selectorBytes.length, Endian.little)
    ..setUint32(12, tableBytes.length, Endian.little)
    ..setUint32(16, 0, Endian.little); // no extended data
  final imageBytes = <Uint8List>[];
  var sliceIndex = 0;
  for (var i = 0; i < images.length; i++) {
    final rgb = sliceBytes[sliceIndex++];
    final alpha = images[i].alpha != null ? sliceBytes[sliceIndex++] : null;
    final o = headerSize + i * descriptorSize;
    view
      ..setUint32(o, 0, Endian.little) // An I-frame.
      ..setUint32(o + 4, 0, Endian.little)
      ..setUint32(o + 8, rgb.length, Endian.little)
      ..setUint32(o + 12, alpha == null ? 0 : rgb.length, Endian.little)
      ..setUint32(o + 16, alpha?.length ?? 0, Endian.little);
    imageBytes.add(
      alpha == null
          ? rgb
          : (BytesBuilder(copy: false)
                  ..add(rgb)
                  ..add(alpha))
                .takeBytes(),
    );
  }
  var o = headerSize + descriptorSize * images.length;
  global.setRange(o, o += endpointBytes.length, endpointBytes);
  global.setRange(o, o += selectorBytes.length, selectorBytes);
  global.setRange(o, o += tableBytes.length, tableBytes);
  return BasisLzPayload(global, imageBytes);
}

/// The symbols one slice writes, decided before any model exists.
class _SlicePlan {
  _SlicePlan(this.slice);

  final Etc1sSlice slice;

  /// Per quad (in decode order): its prediction symbol, or -1 for quads a
  /// preceding repeat symbol covers.
  final predSymbols = <int>[];

  /// For each repeat symbol in [predSymbols], the number of quads it covers.
  final predRepeats = <int>[];

  /// Endpoint deltas, in block order, for the blocks with no prediction.
  final deltas = <int>[];

  /// Per block: the selector symbol, or -1 for blocks a run covers.
  final selectorSymbols = <int>[];

  /// For each run symbol in [selectorSymbols], the blocks it covers.
  final runs = <int>[];
}

_SlicePlan _planSlice(
  Etc1sSlice slice,
  int sliceIndex,
  Uint8List endpoints,
  Uint8List selectors,
  Etc1sRdo? rdo,
) {
  final endpointCount = endpoints.length ~/ 4;
  final selectorCount = selectors.length ~/ 16;
  final bx = slice.blocksX, by = slice.blocksY;
  // The block indices this slice ends up coding; RDO may change them.
  final e = Int32List.fromList(slice.endpoints);
  final sel = Int32List.fromList(slice.selectors);
  final plan = _SlicePlan(Etc1sSlice(bx, by, e, sel));

  int predictorOf(int x, int y) {
    final i = y * bx + x;
    if (x > 0 && e[i - 1] == e[i]) return 0;
    if (y > 0 && e[i - bx] == e[i]) return 1;
    if (x > 0 && y > 0 && e[i - bx - 1] == e[i]) return 2;
    return _noEndpointPred;
  }

  // Blocks a later block predicts from keep their endpoint.
  final referenced = Uint8List(bx * by);
  for (var y = 0; y < by; y++) {
    for (var x = 0; x < bx; x++) {
      final i = y * bx + x;
      if ((x + 1 < bx && e[i + 1] == e[i]) ||
          (y + 1 < by && e[i + bx] == e[i]) ||
          (x + 1 < bx && y + 1 < by && e[i + bx + 1] == e[i])) {
        referenced[i] = 1;
      }
    }
  }

  final errors = rdo?.errors;
  final trialSelectors = Uint8List(16);
  double errorOf(int endpoint, int selector, {double limit = double.infinity}) {
    trialSelectors.setRange(0, 16, selectors, selector * 16);
    return errors!.error(
      endpoints[endpoint * 4],
      endpoints[endpoint * 4 + 1],
      endpoints[endpoint * 4 + 2],
      endpoints[endpoint * 4 + 3],
      trialSelectors,
      limit: limit,
    );
  }

  // Mirrors the decoder's state.
  final history = Int32List(selectorHistorySize);
  var rover = selectorHistorySize >> 1;
  var previousEndpoint = 0;
  var run = 0;
  void flushRun() {
    if (run == 0) return;
    if (run >= _selectorRleMin) {
      plan.selectorSymbols.add(selectorCount + selectorHistorySize);
      plan.runs.add(run);
      for (var k = 1; k < run; k++) {
        plan.selectorSymbols.add(-1);
      }
    } else {
      for (var k = 0; k < run; k++) {
        plan.selectorSymbols.add(selectorCount);
      }
    }
    run = 0;
  }

  for (var y = 0; y < by; y++) {
    for (var x = 0; x < bx; x++) {
      final i = y * bx + x;
      if (errors != null) errors.load(sliceIndex, i);
      if (errors != null &&
          rdo!.endpointThreshold > 1 &&
          predictorOf(x, y) == _noEndpointPred &&
          referenced[i] == 0) {
        final current = errorOf(e[i], sel[i]);
        if (current > 0) {
          final limit = current * rdo.endpointThreshold;
          // A neighbor's endpoint costs only its prediction bits.
          var best = -1;
          var bestError = double.infinity;
          for (final n in [
            if (x > 0) e[i - 1],
            if (y > 0) e[i - bx],
            if (x > 0 && y > 0) e[i - bx - 1],
          ]) {
            final error = errorOf(
              n,
              sel[i],
              limit: (bestError < limit ? bestError : limit) + 1e-9,
            );
            if (error <= limit && error < bestError) {
              bestError = error;
              best = n;
            }
          }
          // Or one a few index steps away, for a small delta.
          var delta = e[i] - previousEndpoint;
          if (delta < 0) delta = -delta;
          if (best < 0 && delta > 1) {
            final reach = delta - 1 < 16 ? delta - 1 : 16;
            for (var d = -reach; d < reach; d++) {
              var trial = previousEndpoint + d;
              if (trial < 0) trial += endpointCount;
              if (trial >= endpointCount) trial -= endpointCount;
              if (trial == e[i]) continue;
              final error = errorOf(
                trial,
                sel[i],
                limit: (bestError < limit ? bestError : limit) + 1e-9,
              );
              if (error <= limit && error < bestError) {
                bestError = error;
                best = trial;
              }
            }
          }
          if (best >= 0) e[i] = best;
        }
      }
      if (predictorOf(x, y) == _noEndpointPred) {
        var delta = e[i] - previousEndpoint;
        if (delta < 0) delta += endpointCount;
        plan.deltas.add(delta);
      }
      previousEndpoint = e[i];

      var slot = -1;
      for (var h = 0; h < selectorHistorySize; h++) {
        if (history[h] == sel[i]) {
          slot = h;
          break;
        }
      }
      if (slot < 0 && errors != null) {
        // A history selector costs less than a full index.
        errors.fixEndpoint(
          endpoints[e[i] * 4],
          endpoints[e[i] * 4 + 1],
          endpoints[e[i] * 4 + 2],
          endpoints[e[i] * 4 + 3],
        );
        double selectorErrorOf(int selector, double limit) {
          trialSelectors.setRange(0, 16, selectors, selector * 16);
          return errors.selectorError(trialSelectors, limit: limit);
        }

        final current = selectorErrorOf(sel[i], double.infinity);
        final threshold = rdo!.selectorThreshold;
        final limit = current * (threshold > 1 ? threshold : 1.0);
        var bestError = double.infinity;
        for (var h = 0; h < selectorHistorySize; h++) {
          final error = selectorErrorOf(
            history[h],
            (bestError < limit ? bestError : limit) + 1e-9,
          );
          if (error <= limit && error < bestError) {
            bestError = error;
            slot = h;
          }
        }
        if (slot >= 0) sel[i] = history[slot];
      }
      if (slot == 0) {
        run++;
        continue;
      }
      flushRun();
      if (slot > 0) {
        plan.selectorSymbols.add(selectorCount + slot);
        final half = slot >> 1;
        final t = history[half];
        history[half] = history[slot];
        history[slot] = t;
      } else {
        plan.selectorSymbols.add(sel[i]);
        history[rover++] = sel[i];
        if (rover == selectorHistorySize) rover = selectorHistorySize >> 1;
      }
    }
  }
  flushRun();

  // Quad prediction symbols, runs of equal ones collapsed.
  final quadSymbols = <int>[];
  for (var y = 0; y < by; y += 2) {
    for (var x = 0; x < bx; x += 2) {
      var symbol = 0;
      for (var qy = 0; qy < 2; qy++) {
        for (var qx = 0; qx < 2; qx++) {
          final pred = x + qx < bx && y + qy < by
              ? predictorOf(x + qx, y + qy)
              : _noEndpointPred;
          symbol |= pred << (qx * 2 + qy * 4);
        }
      }
      quadSymbols.add(symbol);
    }
  }
  var q = 0;
  while (q < quadSymbols.length) {
    final symbol = quadSymbols[q];
    plan.predSymbols.add(symbol);
    q++;
    var repeat = 0;
    while (q + repeat < quadSymbols.length &&
        quadSymbols[q + repeat] == symbol) {
      repeat++;
    }
    if (repeat > _endpointPredMinRepeat) {
      plan.predSymbols.add(_endpointPredRepeatSymbol);
      plan.predRepeats.add(repeat);
      for (var k = 1; k < repeat; k++) {
        plan.predSymbols.add(-1);
      }
      q += repeat;
    }
  }
  return plan;
}

Uint8List _writeSlice(
  _SlicePlan plan,
  HuffmanCode predModel,
  HuffmanCode deltaModel,
  HuffmanCode selectorModel,
  HuffmanCode rleModel,
) {
  final out = BitWriter();
  final slice = plan.slice;
  final selectorCount = selectorModel.sizes.length - selectorHistorySize - 1;
  var predIndex = 0, repeatIndex = 0;
  var deltaIndex = 0;
  var selectorIndex = 0, runIndex = 0;
  final e = slice.endpoints;
  final bx = slice.blocksX;
  for (var y = 0; y < slice.blocksY; y++) {
    for (var x = 0; x < bx; x++) {
      if ((x & 1) == 0 && (y & 1) == 0) {
        // Each quad holds a symbol, a repeat, or -1 when a repeat covers it.
        final symbol = plan.predSymbols[predIndex++];
        if (symbol >= 0) out.writeCode(symbol, predModel);
        if (symbol == _endpointPredRepeatSymbol) {
          out.writeVlc(
            plan.predRepeats[repeatIndex++] - _endpointPredMinRepeat,
            _endpointPredCountVlcBits,
          );
        }
      }
      final i = y * bx + x;
      final left = x > 0 && e[i - 1] == e[i];
      final up = y > 0 && e[i - bx] == e[i];
      final diagonal = x > 0 && y > 0 && e[i - bx - 1] == e[i];
      if (!left && !up && !diagonal) {
        out.writeCode(plan.deltas[deltaIndex++], deltaModel);
      }

      final symbol = plan.selectorSymbols[selectorIndex++];
      if (symbol < 0) continue;
      out.writeCode(symbol, selectorModel);
      if (symbol == selectorCount + selectorHistorySize) {
        final run = plan.runs[runIndex++];
        final code = run - _selectorRleMin;
        if (code < _selectorRleSymbols - 1) {
          out.writeCode(code, rleModel);
        } else {
          out.writeCode(_selectorRleSymbols - 1, rleModel);
          out.writeVlc(code, _selectorRleVlcBits);
        }
      }
    }
  }
  return out.takeBytes();
}

/// The endpoint codebook, delta coded entry to entry.
Uint8List _writeEndpoints(Uint8List endpoints) {
  final count = endpoints.length ~/ 4;
  var grayscale = true;
  for (var i = 0; i < count; i++) {
    if (endpoints[i * 4] != endpoints[i * 4 + 1] ||
        endpoints[i * 4] != endpoints[i * 4 + 2]) {
      grayscale = false;
      break;
    }
  }
  final channels = grayscale ? 1 : 3;
  int modelOf(int previous) => previous <= 9 ? 0 : (previous <= 21 ? 1 : 2);

  final colorFrequencies = List.generate(3, (_) => List<int>.filled(32, 0));
  final intenFrequencies = List<int>.filled(8, 0);
  var previous = [16, 16, 16];
  var previousInten = 0;
  for (var i = 0; i < count; i++) {
    intenFrequencies[(endpoints[i * 4 + 3] - previousInten) & 7]++;
    previousInten = endpoints[i * 4 + 3];
    for (var c = 0; c < channels; c++) {
      final v = endpoints[i * 4 + c];
      colorFrequencies[modelOf(previous[c])][(v - previous[c]) & 31]++;
      previous[c] = v;
    }
  }
  final colorModels = [
    for (final f in colorFrequencies) HuffmanCode.fromFrequencies(f),
  ];
  final intenModel = HuffmanCode.fromFrequencies(intenFrequencies);

  final out = BitWriter();
  for (final model in colorModels) {
    writeHuffmanTable(out, model);
  }
  writeHuffmanTable(out, intenModel);
  out.writeBits(grayscale ? 1 : 0, 1);
  previous = [16, 16, 16];
  previousInten = 0;
  for (var i = 0; i < count; i++) {
    out.writeCode((endpoints[i * 4 + 3] - previousInten) & 7, intenModel);
    previousInten = endpoints[i * 4 + 3];
    for (var c = 0; c < channels; c++) {
      final v = endpoints[i * 4 + c];
      out.writeCode((v - previous[c]) & 31, colorModels[modelOf(previous[c])]);
      previous[c] = v;
    }
  }
  return out.takeBytes();
}

/// The selector codebook, XOR coded entry to entry (or raw if smaller).
Uint8List _writeSelectors(Uint8List selectors) {
  final count = selectors.length ~/ 16;
  final rows = Uint8List(count * 4);
  for (var i = 0; i < count; i++) {
    for (var y = 0; y < 4; y++) {
      var row = 0;
      for (var x = 0; x < 4; x++) {
        row |= selectors[i * 16 + y * 4 + x] << (x * 2);
      }
      rows[i * 4 + y] = row;
    }
  }
  final frequencies = List<int>.filled(256, 0);
  for (var i = 4; i < rows.length; i++) {
    frequencies[rows[i] ^ rows[i - 4]]++;
  }
  final model = HuffmanCode.fromFrequencies(frequencies);
  final coded = BitWriter()
    ..writeBits(0, 1) // no global codebook
    ..writeBits(0, 1) // no hybrid codebook
    ..writeBits(0, 1); // not raw
  writeHuffmanTable(coded, model);
  for (var i = 0; i < rows.length; i++) {
    if (i < 4) {
      coded.writeBits(rows[i], 8);
    } else {
      coded.writeCode(rows[i] ^ rows[i - 4], model);
    }
  }
  final codedBytes = coded.takeBytes();
  if (codedBytes.length < rows.length) return codedBytes;
  final raw = BitWriter()
    ..writeBits(0, 1)
    ..writeBits(0, 1)
    ..writeBits(1, 1);
  for (final row in rows) {
    raw.writeBits(row, 8);
  }
  return raw.takeBytes();
}
