/// Regression coverage for rigs with a joint named `root`. Both importers
/// synthesize an import root also named `root` (the runtime one carries the
/// glTF Z flip), and channels used to resolve to the bind root before its
/// descendants, so the joint's animation overwrote the import root instead.
/// Bind roots the engine did not name keep matching themselves first.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';
// The channel/resolver data model and importers are internal; tests reach
// them directly.
// ignore: implementation_imports
import 'package:flutter_scene/src/animation.dart'
    show AnimationChannel, BindKey, PropertyResolver;
// ignore: implementation_imports
import 'package:flutter_scene/src/fscene/realize/realize.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/importer/in_memory_import.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/runtime_importer/runtime_importer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

Matrix4 _zFlip() => Matrix4.identity()..setEntry(2, 2, -1.0);

/// A 1-second translation channel on [nodeName] from the origin to (1, 2, 3).
Animation _moveAnimation(String nodeName) => Animation(
  name: 'Move',
  channels: [
    AnimationChannel(
      bindTarget: BindKey(nodeName: nodeName),
      resolver: PropertyResolver.makeTranslationTimeline(
        [0.0, 1.0],
        [Vector3.zero(), Vector3(1, 2, 3)],
      ),
    ),
  ],
);

/// A glTF rig `Armature > root > hip` whose `Move` animation translates the
/// `root` joint from the origin to (1, 2, 3) over one second.
Uint8List _rootJointGltf() {
  final floats = Float32List.fromList([0, 1, 0, 0, 0, 1, 2, 3]);
  final buffer = floats.buffer.asUint8List();
  return Uint8List.fromList(
    utf8.encode(
      jsonEncode({
        'asset': {'version': '2.0'},
        'scene': 0,
        'scenes': [
          {
            'nodes': [0],
          },
        ],
        'nodes': [
          {
            'name': 'Armature',
            'children': [1],
          },
          {
            'name': 'root',
            'children': [2],
          },
          {'name': 'hip'},
        ],
        'buffers': [
          {
            'byteLength': buffer.length,
            'uri':
                'data:application/octet-stream;base64,${base64Encode(buffer)}',
          },
        ],
        'bufferViews': [
          {'buffer': 0, 'byteOffset': 0, 'byteLength': 8},
          {'buffer': 0, 'byteOffset': 8, 'byteLength': 24},
        ],
        'accessors': [
          {
            'bufferView': 0,
            'componentType': 5126,
            'count': 2,
            'type': 'SCALAR',
            'min': [0],
            'max': [1],
          },
          {'bufferView': 1, 'componentType': 5126, 'count': 2, 'type': 'VEC3'},
        ],
        'animations': [
          {
            'name': 'Move',
            'samplers': [
              {'input': 0, 'output': 1, 'interpolation': 'LINEAR'},
            ],
            'channels': [
              {
                'sampler': 0,
                'target': {'node': 1, 'path': 'translation'},
              },
            ],
          },
        ],
      }),
    ),
  );
}

Matcher _closeToVector(Vector3 expected) => predicate<Vector3>(
  (v) => (v - expected).length < 1e-6,
  'within 1e-6 of $expected',
);

/// Plays [importRoot]'s `Move` animation for half a second and checks the
/// `root` joint moved while [importRoot] kept its transform.
void _expectJointAnimates(Node importRoot) {
  expect(importRoot.name, 'root');
  final joint = importRoot.getChildByName('root')!;
  final importTransform = importRoot.localTransform.clone();

  importRoot
      .createAnimationClip(importRoot.findAnimationByName('Move')!)
      .play();
  importRoot.scenePrePass(0.5);

  expect(importRoot.localTransform, importTransform);
  final translation = joint.localTransform.getTranslation();
  expect(translation.x, closeTo(0.5, 1e-6));
  expect(translation.y, closeTo(1.0, 1e-6));
  // The offline path bakes the Z flip into the keyframes.
  expect(translation.z.abs(), closeTo(1.5, 1e-6));
}

void main() {
  test('a joint named root animates under a bind root named root', () {
    final joint = Node(name: 'root')..add(Node(name: 'hip'));
    final importRoot = Node(name: 'root', localTransform: _zFlip())
      ..isImportRoot = true
      ..add(Node(name: 'Armature')..add(joint));

    importRoot.createAnimationClip(_moveAnimation('root')).play();
    importRoot.scenePrePass(0.5);

    expect(importRoot.localTransform, _zFlip());
    expect(joint.globalTransform.determinant(), closeTo(-1, 1e-6));
    expect(
      joint.localTransform.getTranslation(),
      _closeToVector(Vector3(0.5, 1, 1.5)),
    );
  });

  test('an authored bind root still matches itself first', () async {
    final importRoot = await importGltf(
      _rootJointGltf(),
      resolveUri: (_) async => Uint8List(0),
    );
    final joint = importRoot.getChildByName('root')!;
    // An attached model's import root, also named root.
    final attachment = Node(name: 'root')..isImportRoot = true;
    joint.add(attachment);

    joint.createAnimationClip(importRoot.findAnimationByName('Move')!).play();
    joint.scenePrePass(0.5);

    expect(
      joint.localTransform.getTranslation(),
      _closeToVector(Vector3(0.5, 1, 1.5)),
    );
    expect(attachment.localTransform, Matrix4.identity());
  });

  test('a cloned import root still prefers the root joint', () async {
    final original = await importGltf(
      _rootJointGltf(),
      resolveUri: (_) async => Uint8List(0),
    );
    final importRoot = original.clone();
    expect(importRoot.isImportRoot, isTrue);
    _expectJointAnimates(importRoot);
  });

  test('a channel still binds the bind root when no descendant matches', () {
    final mover = Node(name: 'mover')..add(Node(name: 'child'));
    mover.createAnimationClip(_moveAnimation('mover')).play();
    mover.scenePrePass(0.5);
    expect(
      mover.localTransform.getTranslation(),
      _closeToVector(Vector3(0.5, 1, 1.5)),
    );
  });

  test(
    'runtime import keeps identity root transform and animates the root joint',
    () async {
      final importRoot = await importGltf(
        _rootJointGltf(),
        resolveUri: (_) async => Uint8List(0),
      );
      expect(importRoot.localTransform, Matrix4.identity());
      _expectJointAnimates(importRoot);
    },
  );

  test('offline realize animates the root joint', () {
    _expectJointAnimates(
      realizeScene(
        importGltfToSceneDocument(_rootJointGltf(), resolveUri: (_) => null),
      ),
    );
  });

  test('serialization targets the root joint, not the import root', () {
    final document = serializeScene(
      realizeScene(
        importGltfToSceneDocument(_rootJointGltf(), resolveUri: (_) => null),
      ),
    );
    final jointId = document.nodes.values
        .singleWhere((node) => node.name == 'root')
        .id;
    final channel = document.animations.values.single.channels.single;
    expect(channel.target, jointId);
  });

  test('hot reload rest poses skip the import root', () {
    final joint = Node(name: 'root');
    final importRoot = Node(name: 'root', localTransform: _zFlip())
      ..isImportRoot = true
      ..add(joint);
    final animation = _moveAnimation('root');
    importRoot.addParsedAnimation(animation);
    importRoot.createAnimationClip(animation);

    final posed = <Node>[];
    importRoot.reloadParsedAnimations(
      [animation],
      restPoseOf: (node) {
        posed.add(node);
        return Matrix4.identity();
      },
    );

    expect(posed, [same(joint)]);
    expect(importRoot.localTransform, _zFlip());
  });
}
