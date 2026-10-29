// Baked skinned pose bounds must cover the rest pose and the poses of each
// animation on its own. A runtime-imported skinned mesh must carry the same
// bounds, so it is culled.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene/src/importer/gltf.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/importer/src/gltf/bounds_baker.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/gpu_available.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final noGpu = gpuAvailable()
      ? null
      : 'Requires a GPU device: --enable-impeller --enable-flutter-gpu.';

  group('baked skinned pose bounds', () {
    AabbBounds boundsOf(Uint8List glb) {
      final container = parseGlb(glb);
      return bakeSkinnedPoseUnionAabbs(
        parseGltfJson(container.json),
        container.binaryChunk,
      )[0]!.single!;
    }

    // Two clips that drive the same joint must each be posed, not only the
    // last one.
    test('cover the poses of every clip', () {
      final bounds = boundsOf(_skinnedGlb(clips: [5, 0]));
      expect(bounds.minY, 0);
      expect(bounds.maxY, 6);
    });

    // A model shows its rest pose while no clip plays, so the bounds must
    // cover it even where every clip starts elsewhere.
    test('cover the rest pose', () {
      final bounds = boundsOf(_skinnedGlb(clips: [0], restY: 3));
      expect(bounds.minY, 0);
      expect(bounds.maxY, 4);
    });
  });

  // A skinned mesh imported at runtime must carry the bounds of its poses, in
  // the space of its node, so it is culled like one the offline importer
  // bakes.
  test('a runtime-imported skinned mesh carries its pose bounds', () async {
    final root = await Node.fromGlbBytes(_skinnedGlb());
    final geometry =
        root.children.single.children.first.mesh!.primitives.single.geometry;
    expect(geometry, isA<SkinnedGeometry>());
    final bounds = geometry.localBounds;
    expect(bounds, isNotNull);
    expect(bounds!.min.x, -10);
    expect(bounds.max.x, -9);
    expect(bounds.min.y, 0);
    expect(bounds.max.y, 6);
    expect(bounds.min.z, 0);
    expect(bounds.max.z, 0);
    expect(geometry.localBoundingSphere, isNotNull);
  }, skip: noGpu);
}

// A triangle skinned to two joints. The root joint moves the first two
// vertices and its child the third. The child rests [restY] up, and each of
// [clips] moves it up from 0 to its value over one second. The skinned node
// and the skeleton hang under a node 2 along z, and the skinned node sits 10
// along x, which glTF ignores for a skinned mesh.
Uint8List _skinnedGlb({List<double> clips = const [5], double restY = 0}) {
  final bin = BytesBuilder();
  void floats(List<double> values) =>
      bin.add(Float32List.fromList(values).buffer.asUint8List());
  floats([0, 0, 0, 1, 0, 0, 0, 1, 0]);
  floats([0, 0, 1, 0, 0, 1, 0, 0, 1]);
  bin.add([0, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0]);
  floats([1, 0, 0, 0, 0.75, 0.25, 0, 0, 1, 0, 0, 0]);
  floats([0, 1]);
  for (final clip in clips) {
    floats([0, 0, 0, 0, clip, 0]);
  }
  final json = {
    'asset': {'version': '2.0'},
    'scene': 0,
    'scenes': [
      {
        'nodes': [3],
      },
    ],
    'nodes': [
      {
        'mesh': 0,
        'skin': 0,
        'translation': [10, 0, 0],
      },
      {
        'children': [2],
      },
      {
        'translation': [0, restY, 0],
      },
      {
        'translation': [0, 0, 2],
        'children': [0, 1],
      },
    ],
    'skins': [
      {
        'joints': [1, 2],
      },
    ],
    'meshes': [
      {
        'primitives': [
          {
            'attributes': {
              'POSITION': 0,
              'NORMAL': 1,
              'JOINTS_0': 2,
              'WEIGHTS_0': 3,
            },
          },
        ],
      },
    ],
    'animations': [
      for (var clip = 0; clip < clips.length; clip++)
        {
          'channels': [
            {
              'sampler': 0,
              'target': {'node': 2, 'path': 'translation'},
            },
          ],
          'samplers': [
            {'input': 4, 'output': 5 + clip},
          ],
        },
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
      {'bufferView': 1, 'componentType': 5126, 'count': 3, 'type': 'VEC3'},
      {'bufferView': 2, 'componentType': 5121, 'count': 3, 'type': 'VEC4'},
      {'bufferView': 3, 'componentType': 5126, 'count': 3, 'type': 'VEC4'},
      {
        'bufferView': 4,
        'componentType': 5126,
        'count': 2,
        'type': 'SCALAR',
        'min': [0],
        'max': [1],
      },
      for (var clip = 0; clip < clips.length; clip++)
        {
          'bufferView': 5 + clip,
          'componentType': 5126,
          'count': 2,
          'type': 'VEC3',
        },
    ],
    'bufferViews': [
      {'buffer': 0, 'byteOffset': 0, 'byteLength': 36},
      {'buffer': 0, 'byteOffset': 36, 'byteLength': 36},
      {'buffer': 0, 'byteOffset': 72, 'byteLength': 12},
      {'buffer': 0, 'byteOffset': 84, 'byteLength': 48},
      {'buffer': 0, 'byteOffset': 132, 'byteLength': 8},
      for (var clip = 0; clip < clips.length; clip++)
        {'buffer': 0, 'byteOffset': 140 + 24 * clip, 'byteLength': 24},
    ],
    'buffers': [
      {'byteLength': 140 + 24 * clips.length},
    ],
  };
  return _glb(utf8.encode(jsonEncode(json)), bin.takeBytes());
}

Uint8List _glb(List<int> json, List<int> bin) {
  List<int> padded(List<int> bytes, int fill) => [
    ...bytes,
    for (var at = bytes.length; at % 4 != 0; at++) fill,
  ];
  final jsonChunk = padded(json, 0x20);
  final binChunk = padded(bin, 0);
  final out = ByteData(28 + jsonChunk.length + binChunk.length);
  out
    ..setUint32(0, 0x46546C67, Endian.little)
    ..setUint32(4, 2, Endian.little)
    ..setUint32(8, out.lengthInBytes, Endian.little)
    ..setUint32(12, jsonChunk.length, Endian.little)
    ..setUint32(16, 0x4E4F534A, Endian.little);
  final bytes = out.buffer.asUint8List()..setAll(20, jsonChunk);
  out
    ..setUint32(20 + jsonChunk.length, binChunk.length, Endian.little)
    ..setUint32(24 + jsonChunk.length, 0x004E4942, Endian.little);
  bytes.setAll(28 + jsonChunk.length, binChunk);
  return bytes;
}
