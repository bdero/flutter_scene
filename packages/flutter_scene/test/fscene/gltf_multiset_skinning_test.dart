// Multi-set joint/weight merging in the glTF packer.
//
// Assets rigged with more than four influences per vertex export several
// JOINTS_n/WEIGHTS_n sets. The packer must merge them into the engine's
// single four-slot layout, keep the strongest influences, and renormalize
// so every vertex blends exactly one unit of weight — otherwise skinned
// meshes sag toward the armature origin even in their rest pose.
//
// One triangle covers the three regimes: exactly-four influences (must be
// exact after normalization), more-than-four (merged + renormalized), and
// a degenerate all-zero vertex (pinned to a real bone).
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_scene/src/importer/gltf.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('packer merges multi-set influences to a full unit of weight', () {
    final glb = _multiJointGlb();
    final container = parseGlb(glb);
    final doc = parseGltfJson(container.json);

    final packed = packGltfPrimitive(
      primitive: doc.meshes[0].primitives[0],
      accessors: doc.accessors,
      bufferViews: doc.bufferViews,
      bufferData: container.binaryChunk,
      coordinatePolicy: GltfCoordinatePolicy.bakeNative,
    );

    expect(packed.isSkinned, isTrue);
    expect(packed.vertexCount, 3);

    // Skinned layout: 26 floats per vertex; joints at [18..22),
    // weights at [22..26).
    final floats = packed.vertexBytes.buffer.asFloat32List(
      packed.vertexBytes.offsetInBytes,
      packed.vertexBytes.lengthInBytes ~/ 4,
    );
    List<double> weights(int v) =>
        List.generate(4, (c) => floats[v * 26 + 22 + c]);
    List<double> joints(int v) =>
        List.generate(4, (c) => floats[v * 26 + 18 + c]);

        // v0: three influences across two sets totalling exactly 1 — merged
    // in descending-weight order, normalization is a no-op here.
    final w0 = weights(0);
    expect(w0[0], closeTo(0.5, 1e-6));
    expect(w0[1], closeTo(0.3, 1e-6));
    expect(w0[2], closeTo(0.2, 1e-6));
    expect(w0[3], 0.0);
    expect(joints(0)[0], 0.0);
    expect(joints(0)[1], 1.0);
    expect(joints(0)[2], 2.0);

    // v1: five influences across the two sets (j0 .5, j1 .3, j2 .2,
    // j3 .1, j4 .15) totalling 1.25. Only four slots exist, so j3's .1
    // is the weakest and drops; the survivors renormalize over their own
    // sum (1.15), keeping every vertex at a full unit of weight.
    final w1 = weights(1);
    expect(w1[0], closeTo(0.5 / 1.15, 1e-6)); // joint 0
    expect(w1[1], closeTo(0.3 / 1.15, 1e-6)); // joint 1
    expect(w1[2], closeTo(0.2 / 1.15, 1e-6)); // joint 2
    expect(w1[3], closeTo(0.15 / 1.15, 1e-6)); // joint 4
    expect(joints(1).take(4), orderedEquals([0.0, 1.0, 2.0, 4.0]));

    // v2: authored with all-zero weights — pinned to set 0's first joint
    // at weight 1 instead of collapsing toward the origin.
    final w2 = weights(2);
    expect(w2[0], 1.0);
    expect(w2[1], 0.0);
    expect(w2[2], 0.0);
    expect(w2[3], 0.0);
    expect(joints(2)[0], 5.0);

    // The core invariant: every vertex blends a full unit of weight.
    for (var v = 0; v < 3; v++) {
      final sum = weights(v).fold<double>(0, (a, b) => a + b);
      expect(sum, closeTo(1.0, 1e-6), reason: 'vertex $v weight sum');
    }
  });
}

/// A one-triangle GLB whose skinning spreads influence slots across
/// JOINTS_0/1 + WEIGHTS_0/1 (float32 joints keep the fixture simple).
///
/// Vertex data:
/// - v0: three live influences (j0 .5, j1 .3, j2 .2) totalling exactly 1.
/// - v1: five live influences (j0 .5, j1 .3, j2 .2, j3 .1, j4 .15)
///   totalling 1.25 — forces a drop + renormalize.
/// - v2: all-zero weights — exercises the degenerate-vertex fallback.
Uint8List _multiJointGlb() {
  // Layout chunks in order; bufferViews are derived from the real byte
  // cursor (with 4-byte inter-chunk padding) so JSON offsets always mirror
  // the binary chunk.
  final chunks = <Uint8List>[
    // 0: positions (3 verts)
    Float32List.fromList([0, 0, 0, 1, 0, 0, 0, 1, 0]).buffer.asUint8List(),
    // 1: indices
    Uint16List.fromList([0, 1, 2]).buffer.asUint8List(),
    // 2: JOINTS_0 — v0 (j0,j1,j2,-), v1 (j0,j1,j2,j3), v2 (j5,-,-,-)
    Uint16List.fromList([0, 1, 2, 0, 0, 1, 2, 3, 5, 0, 0, 0])
        .buffer
        .asUint8List(),
    // 3: WEIGHTS_0 — column-for-column with JOINTS_0
    Float32List.fromList([0.5, 0.3, 0.2, 0, 0.5, 0.3, 0.2, 0.1, 0, 0, 0, 0])
        .buffer
        .asUint8List(),
    // 4: JOINTS_1 — v1 carries one extra influence on j4
    Uint16List.fromList([0, 0, 0, 0, 4, 0, 0, 0, 0, 0, 0, 0])
        .buffer
        .asUint8List(),
    // 5: WEIGHTS_1
    Float32List.fromList([0, 0, 0, 0, 0.15, 0, 0, 0, 0, 0, 0, 0])
        .buffer
        .asUint8List(),
  ];

  final buffer = BytesBuilder();
  final offsets = <int>[];
  var cursor = 0;
  for (final chunk in chunks) {
    final pad = (4 - (cursor % 4)) % 4;
    if (pad > 0) {
      buffer.add(Uint8List(pad));
      cursor += pad;
    }
    offsets.add(cursor);
    buffer.add(chunk);
    cursor += chunk.length;
  }
  final binary = buffer.takeBytes();

  Map<String, Object?> view(int index) => {
    'buffer': 0,
    'byteOffset': offsets[index],
    'byteLength': chunks[index].length,
  };

  final json = {
    'asset': {'version': '2.0'},
    'scene': 0,
    'scenes': [
      {'nodes': [0]},
    ],
    'nodes': [
      {'mesh': 0},
    ],
    'meshes': [
      {
        'primitives': [
          {
            'attributes': {
              'POSITION': 0,
              'JOINTS_0': 2,
              'WEIGHTS_0': 3,
              'JOINTS_1': 4,
              'WEIGHTS_1': 5,
            },
            'indices': 1,
          },
        ],
      },
    ],
    'buffers': [
      {'byteLength': binary.length},
    ],
    'bufferViews': [
      view(0),
      view(1),
      view(2),
      view(3),
      view(4),
      view(5),
    ],
    'accessors': [
      {
        'bufferView': 0,
        'componentType': 5126,
        'count': 3,
        'type': 'VEC3',
        'min': [0, 0, 0],
        'max': [1, 1, 0],
      },
      {'bufferView': 1, 'componentType': 5123, 'count': 3, 'type': 'SCALAR'},
      {'bufferView': 2, 'componentType': 5123, 'count': 3, 'type': 'VEC4'},
      {'bufferView': 3, 'componentType': 5126, 'count': 3, 'type': 'VEC4'},
      {'bufferView': 4, 'componentType': 5123, 'count': 3, 'type': 'VEC4'},
      {'bufferView': 5, 'componentType': 5126, 'count': 3, 'type': 'VEC4'},
    ],
  };
  return _glb(json, binary);
}

Uint8List _glb(Map<String, Object?> json, Uint8List binary) {
  final jsonBytes = utf8.encode(jsonEncode(json));
  final jsonLength = (jsonBytes.length + 3) & ~3;
  final binaryLength = (binary.length + 3) & ~3;
  final output = BytesBuilder();
  void uint32(int value) => output.add(
    Uint8List(4)..buffer.asByteData().setUint32(0, value, Endian.little),
  );
  output.add(ascii.encode('glTF'));
  uint32(2);
  uint32(12 + 8 + jsonLength + 8 + binaryLength);
  uint32(jsonLength);
  output.add(ascii.encode('JSON'));
  output.add(jsonBytes);
  output.add(
    Uint8List(jsonLength - jsonBytes.length)
      ..fillRange(0, jsonLength - jsonBytes.length, 0x20),
  );
  uint32(binaryLength);
  output.add([0x42, 0x49, 0x4e, 0]);
  output.add(binary);
  output.add(Uint8List(binaryLength - binary.length));
  return output.takeBytes();
}
