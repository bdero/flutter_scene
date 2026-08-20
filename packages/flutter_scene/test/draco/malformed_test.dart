// Malformed and truncated Draco streams must fail with a clean
// FormatException, never an index error or a wrong-type crash.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_scene/src/importer/gltf.dart';
import 'package:flutter_scene/src/importer/src/gltf/draco/mesh_decoder.dart';
import 'package:flutter_test/flutter_test.dart';

const _fixtureDir = 'test/fixtures/draco';

Uint8List _payload(String name) {
  final contents = parseGlb(File('$_fixtureDir/$name.glb').readAsBytesSync());
  final doc = parseGltfJson(contents.json);
  final meshes = contents.json['meshes'] as List;
  final primitives = (meshes[0] as Map)['primitives'] as List;
  final extensions = (primitives[0] as Map)['extensions'] as Map;
  final draco = extensions['KHR_draco_mesh_compression'] as Map;
  final view = doc.bufferViews[draco['bufferView'] as int];
  return Uint8List.sublistView(
    contents.binaryChunk,
    view.byteOffset,
    view.byteOffset + view.byteLength,
  );
}

/// Decoding must either succeed or throw a FormatException.
void _decodeOrFormatException(Uint8List data) {
  try {
    decodeDracoMesh(data);
  } on FormatException {
    // Expected for malformed input.
  }
}

void main() {
  final payloads = {
    'sequential': _payload('synthetic_draco_seq'),
    'edgebreaker': _payload('synthetic_draco_eb'),
    'edgebreaker seams': _payload('cube_draco_eb'),
    'edgebreaker valence': _payload('synthetic_draco_eb_valence'),
  };

  test('empty and undersized streams throw', () {
    expect(() => decodeDracoMesh(Uint8List(0)), throwsFormatException);
    expect(() => decodeDracoMesh(Uint8List(5)), throwsFormatException);
  });

  test('bad magic throws', () {
    final data = Uint8List.fromList(payloads['edgebreaker']!);
    data[0] = 0x58;
    expect(() => decodeDracoMesh(data), throwsFormatException);
  });

  test('unsupported bitstream versions throw', () {
    for (final version in [(1, 2), (2, 1), (2, 3), (3, 0)]) {
      final data = Uint8List.fromList(payloads['edgebreaker']!);
      data[5] = version.$1;
      data[6] = version.$2;
      expect(
        () => decodeDracoMesh(data),
        throwsFormatException,
        reason: 'version ${version.$1}.${version.$2}',
      );
    }
  });

  test('point cloud geometry throws', () {
    final data = Uint8List.fromList(payloads['edgebreaker']!);
    data[7] = 0; // POINT_CLOUD
    expect(() => decodeDracoMesh(data), throwsFormatException);
  });

  test('unknown encoder method throws', () {
    final data = Uint8List.fromList(payloads['edgebreaker']!);
    data[8] = 2;
    expect(() => decodeDracoMesh(data), throwsFormatException);
  });

  test('metadata flag throws', () {
    final data = Uint8List.fromList(payloads['edgebreaker']!);
    data[10] |= 0x80; // High byte of the little-endian flags.
    expect(() => decodeDracoMesh(data), throwsFormatException);
  });

  test('every truncation point fails cleanly', () {
    for (final entry in payloads.entries) {
      final payload = entry.value;
      for (var length = 0; length < payload.length; length++) {
        final truncated = Uint8List.sublistView(payload, 0, length);
        try {
          _decodeOrFormatException(truncated);
        } catch (e) {
          fail('${entry.key} truncated to $length threw $e');
        }
      }
    }
  });

  test('single byte corruption fails cleanly', () {
    // Every position on the smaller payloads, a stride on the larger ones,
    // keeping the sweep fast without losing section coverage.
    for (final entry in payloads.entries) {
      final payload = entry.value;
      final stride = payload.length > 1500 ? 5 : 1;
      for (var i = 0; i < payload.length; i += stride) {
        for (final value in [0x00, 0xFF]) {
          if (payload[i] == value) continue;
          final corrupted = Uint8List.fromList(payload);
          corrupted[i] = value;
          try {
            _decodeOrFormatException(corrupted);
          } catch (e) {
            fail('${entry.key} byte $i set to $value threw $e');
          }
        }
      }
    }
  });
}
