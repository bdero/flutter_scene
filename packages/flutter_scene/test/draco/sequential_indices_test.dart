// Sequential connectivity's compressed index path (zigzag deltas through the
// symbol decoder), which the encoder fixtures never emit, exercised through a
// hand-built stream.

import 'dart:typed_data';

import 'package:flutter_scene/src/importer/src/gltf/draco/mesh_decoder.dart';
import 'package:flutter_test/flutter_test.dart';

import 'entropy_helpers.dart';

// The index delta coding, negative deltas set the low bit.
int _zigzag(int value) => value < 0 ? -2 * value + 1 : 2 * value;

Uint8List _buildStream(List<int> indices, int numPoints) {
  final out = BytesBuilder();
  out.add('DRACO'.codeUnits);
  out.addByte(2); // Version major.
  out.addByte(2); // Version minor.
  out.addByte(1); // TRIANGULAR_MESH.
  out.addByte(0); // MESH_SEQUENTIAL_ENCODING.
  out.addByte(0); // Flags, little endian.
  out.addByte(0);
  writeVarint(out, indices.length ~/ 3);
  writeVarint(out, numPoints);
  out.addByte(0); // Compressed (symbol coded) indices.

  // Zigzag coded deltas from the previous index.
  final symbols = <int>[];
  var last = 0;
  for (final index in indices) {
    symbols.add(_zigzag(index - last));
    last = index;
  }
  final maxSymbol = symbols.reduce((a, b) => a > b ? a : b);
  var maxBitLength = 1;
  while ((1 << maxBitLength) <= maxSymbol) {
    maxBitLength++;
  }
  // Flat probability table over the used symbol range.
  final numUnique = maxSymbol + 1;
  final precisionBits = (3 * maxBitLength) ~/ 2;
  final precision = 1 << (precisionBits < 12 ? 12 : precisionBits);
  final probs = List<int>.filled(numUnique, precision ~/ numUnique);
  probs[0] += precision - probs.reduce((a, b) => a + b);
  out.addByte(1); // SYMBOL_CODING_RAW.
  out.add(encodeRawSymbols(symbols, probs, maxBitLength));

  out.addByte(0); // No attribute decoders.
  return out.toBytes();
}

void main() {
  test('decodes compressed sequential indices', () {
    // A strip with forward and backward jumps to cover both zigzag signs.
    final indices = [0, 1, 2, 2, 1, 3, 3, 1, 0, 0, 2, 4];
    final stream = _buildStream(indices, 5);
    final decoded = decodeDracoMesh(stream);
    expect(decoded.numPoints, 5);
    expect(decoded.faces, indices);
    expect(decoded.attributes, isEmpty);
  });

  test('decodes wide uncompressed sequential indices', () {
    // Point counts at 2^16 and 2^21 select the varint and uint32 index
    // encodings; the fixtures only reach the narrower widths.
    Uint8List build(int numPoints, List<int> indices, List<int> indexBytes) {
      final out = BytesBuilder();
      out.add('DRACO'.codeUnits);
      out.add([2, 2, 1, 0, 0, 0]);
      writeVarint(out, indices.length ~/ 3);
      writeVarint(out, numPoints);
      out.addByte(1); // Uncompressed indices.
      out.add(indexBytes);
      out.addByte(0); // No attribute decoders.
      return out.toBytes();
    }

    final varintIndices = [0, 70000, 5];
    final varintBytes = BytesBuilder();
    for (final index in varintIndices) {
      writeVarint(varintBytes, index);
    }
    final varintDecoded = decodeDracoMesh(
      build(1 << 16, varintIndices, varintBytes.takeBytes()),
    );
    expect(varintDecoded.faces, varintIndices);

    final wideIndices = [1 << 20, 3, 2000000];
    final wideBytes = Uint32List.fromList(wideIndices);
    final wideDecoded = decodeDracoMesh(
      build(1 << 21, wideIndices, Uint8List.sublistView(wideBytes)),
    );
    expect(wideDecoded.faces, wideIndices);
  });

  test('rejects a negative running index', () {
    // First delta is -1, running index dips below zero.
    final out = BytesBuilder();
    out.add('DRACO'.codeUnits);
    out.add([2, 2, 1, 0, 0, 0]);
    writeVarint(out, 1);
    writeVarint(out, 3);
    out.addByte(0);
    final symbols = [_zigzag(-1), _zigzag(1), _zigzag(1)];
    final probs = [0, 0, 1 << 11, 1 << 11];
    out.addByte(1);
    out.add(encodeRawSymbols(symbols, probs, 2));
    out.addByte(0);
    expect(() => decodeDracoMesh(out.toBytes()), throwsFormatException);
  });
}
