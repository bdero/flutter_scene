// Baked skinned pose bounds must cover the rest pose and the poses of each
// animation on its own. A runtime-imported skinned mesh must carry the same
// bounds, so it is culled.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene/src/importer/gltf.dart';
import 'package:flutter_scene/src/importer/in_memory_import.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/importer/src/gltf/bounds_baker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene/scene.dart' show GeometryResource;

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

    // A cubic spline can swing past its keyframes, so the bounds must follow
    // the curve between them.
    test('follow a cubic spline between its keyframes', () {
      final bounds = boundsOf(
        _skinnedGlb(
          animations: [
            [
              (
                node: 2,
                path: 'translation',
                interpolation: 'CUBICSPLINE',
                times: [0, 1],
                // Both keyframes sit at 0, but the child leaves the first
                // rising 8 per second and reaches the second falling 8 per
                // second, which lifts it 2 halfway through.
                output: [
                  0, 0, 0, 0, 0, 0, 0, 8, 0, //
                  0, -8, 0, 0, 0, 0, 0, 0, 0, //
                ],
              ),
            ],
          ],
        ),
      );
      expect(bounds.minY, 0);
      expect(bounds.maxY, closeTo(3, 1e-6));
    });

    // A step holds its keyframe until the next one while other channels keep
    // moving, so the bounds must cover the moment just before it jumps.
    test('cover the pose just before a step', () {
      final bounds = boundsOf(
        _skinnedGlb(
          animations: [
            [
              // The root joint jumps 10 along x at one second.
              (
                node: 1,
                path: 'translation',
                interpolation: 'STEP',
                times: [0, 1],
                output: [0, 0, 0, 10, 0, 0],
              ),
              // Its child slides 5 back along x over that second.
              (
                node: 2,
                path: 'translation',
                interpolation: 'LINEAR',
                times: [0, 1],
                output: [0, 0, 0, -5, 0, 0],
              ),
            ],
          ],
        ),
      );
      // Just before the jump, the child has slid back while the root has not
      // moved yet.
      expect(bounds.minX, -5);
      expect(bounds.maxX, 11);
    });
  });

  // The offline importer stores the bounds in the skinned node's space too, so
  // a node away from its skeleton is culled where its mesh draws.
  test('an offline-imported skinned mesh carries node-space bounds', () {
    final document = importGlbToSceneDocument(_skinnedGlb());
    final bounds = document.resources.values
        .whereType<GeometryResource>()
        .single
        .bounds!;
    expect([bounds.min.x, bounds.min.y, bounds.min.z], [-10, 0, 0]);
    expect([bounds.max.x, bounds.max.y, bounds.max.z], [-9, 6, 0]);
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

// One sampler driving a translation or scale of a joint: node 1, the root
// joint, or node 2, its child.
typedef _Track = ({
  int node,
  String path,
  String interpolation,
  List<double> times,
  List<double> output,
});

// A triangle skinned to two joints. The root joint moves the first two
// vertices and its child the third. The child rests [restY] up, and each of
// [clips] moves it up from 0 to its value over one second, unless
// [animations] gives each animation's tracks instead. The skinned node and the
// skeleton hang under a node 2 along z, and the skinned node sits 10 along x,
// which glTF ignores for a skinned mesh.
Uint8List _skinnedGlb({
  List<double> clips = const [5],
  double restY = 0,
  List<List<_Track>>? animations,
}) {
  final bin = BytesBuilder();
  final bufferViews = <Map<String, Object>>[];
  final accessors = <Map<String, Object>>[];
  // Appends [bytes] as a buffer view of their own, read by a new accessor
  // with [fields], and returns the accessor's index.
  int accessor(List<int> bytes, Map<String, Object> fields) {
    bufferViews.add({
      'buffer': 0,
      'byteOffset': bin.length,
      'byteLength': bytes.length,
    });
    bin.add(bytes);
    accessors.add({'bufferView': bufferViews.length - 1, ...fields});
    return accessors.length - 1;
  }

  List<int> floats(List<double> values) =>
      Float32List.fromList(values).buffer.asUint8List();
  accessor(floats([0, 0, 0, 1, 0, 0, 0, 1, 0]), {
    'componentType': 5126,
    'count': 3,
    'type': 'VEC3',
    'min': [0, 0, 0],
    'max': [1, 1, 0],
  });
  accessor(floats([0, 0, 1, 0, 0, 1, 0, 0, 1]), {
    'componentType': 5126,
    'count': 3,
    'type': 'VEC3',
  });
  accessor(
    [0, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0],
    {'componentType': 5121, 'count': 3, 'type': 'VEC4'},
  );
  accessor(floats([1, 0, 0, 0, 0.75, 0.25, 0, 0, 1, 0, 0, 0]), {
    'componentType': 5126,
    'count': 3,
    'type': 'VEC4',
  });

  final tracks =
      animations ??
      [
        for (final clip in clips)
          [
            (
              node: 2,
              path: 'translation',
              interpolation: 'LINEAR',
              times: const [0.0, 1.0],
              output: [0.0, 0, 0, 0, clip, 0],
            ),
          ],
      ];
  final gltfAnimations = [
    for (final animation in tracks)
      {
        'channels': [
          for (var i = 0; i < animation.length; i++)
            {
              'sampler': i,
              'target': {'node': animation[i].node, 'path': animation[i].path},
            },
        ],
        'samplers': [
          for (final track in animation)
            {
              'input': accessor(floats(track.times), {
                'componentType': 5126,
                'count': track.times.length,
                'type': 'SCALAR',
                'min': [track.times.first],
                'max': [track.times.last],
              }),
              'output': accessor(floats(track.output), {
                'componentType': 5126,
                'count': track.output.length ~/ 3,
                'type': 'VEC3',
              }),
              'interpolation': track.interpolation,
            },
        ],
      },
  ];
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
    'animations': gltfAnimations,
    'accessors': accessors,
    'bufferViews': bufferViews,
    'buffers': [
      {'byteLength': bin.length},
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
