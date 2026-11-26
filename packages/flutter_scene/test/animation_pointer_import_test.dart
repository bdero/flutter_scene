// Covers KHR_animation_pointer import, pointer resolution and each target
// class (node visibility, node transform, light, material factor, texture
// transform) animating through both the runtime and the offline importer.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/animation.dart'
    show AnimationChannel, AnimationProperty, BindKey, PropertyResolver;
// ignore: implementation_imports
import 'package:flutter_scene/src/fscene/realize/realize.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
// ignore: implementation_imports
import 'package:flutter_scene/src/importer/gltf.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/importer/gltf_light_units.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/importer/in_memory_import.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/runtime_importer/runtime_importer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene/scene.dart' show SceneDocument, readFsceneb, writeFsceneb;
import 'package:vector_math/vector_math.dart';

import 'support/gpu_available.dart';

// Accessors packed into one data URI buffer, each as (type, values), with
// unsigned byte values for the boolean visibility track.
const _accessors = <(String, List<num>)>[
  ('VEC3', [0, 0, 0, 1, 0, 0, 0, 1, 0]), // 0 triangle positions
  ('SCALAR', [0, 1]), // 1 times
  ('VEC4', [1, 0, 0, 1, 0, 0, 1, 0.5]), // 2 baseColorFactor
  ('VEC3', [0, 0, 0, 2, 4, 6]), // 3 emissiveFactor
  ('VEC2', [0, 0, 1, 0.5]), // 4 texture offset
  ('SCALAR', [0, 1]), // 5 texture rotation, cone angle
  ('SCALAR', [1, 0]), // 6 visibility (unsigned byte)
  ('SCALAR', [5, 10]), // 7 light intensity
  ('VEC3', [1, 0, 0, 0, 0, 1]), // 8 light color
  ('VEC3', [0, 0, 0, 0, 2, 0]), // 9 translation
];

// Without [mesh] the fixture uploads no geometry, so it imports without a GPU
// and its material pointers resolve to no targets.
Map<String, Object?> _gltf({bool mesh = true}) {
  final bytes = BytesBuilder();
  final views = <Map<String, Object?>>[];
  final accessors = <Map<String, Object?>>[];
  for (final (i, (type, values)) in _accessors.indexed) {
    final unsignedByte = i == 6;
    final offset = bytes.length;
    if (unsignedByte) {
      bytes.add([for (final v in values) v.toInt()]);
      while (bytes.length % 4 != 0) {
        bytes.addByte(0);
      }
    } else {
      final floats = Float32List.fromList([
        for (final v in values) v.toDouble(),
      ]);
      bytes.add(floats.buffer.asUint8List());
    }
    views.add({
      'buffer': 0,
      'byteOffset': offset,
      'byteLength': unsignedByte ? values.length : values.length * 4,
    });
    final components = switch (type) {
      'VEC4' => 4,
      'VEC3' => 3,
      'VEC2' => 2,
      _ => 1,
    };
    accessors.add({
      'bufferView': i,
      'componentType': unsignedByte ? 5121 : 5126,
      'count': values.length ~/ components,
      'type': type,
      if (i == 0) 'min': [0, 0, 0],
      if (i == 0) 'max': [1, 1, 0],
      if (i == 1) 'min': [0],
      if (i == 1) 'max': [1],
    });
  }
  final data = bytes.takeBytes();

  Map<String, Object?> channel(int sampler, String pointer) => {
    'sampler': sampler,
    'target': {
      'path': 'pointer',
      'extensions': {
        'KHR_animation_pointer': {'pointer': pointer},
      },
    },
  };
  Map<String, Object?> sampler(int output, [String? interpolation]) => {
    'input': 1,
    'output': output,
    if (interpolation != null) 'interpolation': interpolation,
  };

  return {
    'asset': {'version': '2.0'},
    'extensionsUsed': [
      'KHR_animation_pointer',
      'KHR_lights_punctual',
      'KHR_node_visibility',
    ],
    'extensions': {
      'KHR_lights_punctual': {
        'lights': [
          {
            'type': 'spot',
            'color': [0.0, 1.0, 0.0],
            'intensity': 5.0,
            'spot': {'innerConeAngle': 0.1, 'outerConeAngle': 0.5},
          },
        ],
      },
    },
    'buffers': [
      {
        'byteLength': data.length,
        'uri': 'data:application/octet-stream;base64,${base64Encode(data)}',
      },
    ],
    'bufferViews': views,
    'accessors': accessors,
    'materials': [
      {'name': 'Animated'},
      {'name': 'Unused'},
    ],
    'meshes': [
      {
        'primitives': [
          {
            'attributes': {'POSITION': 0},
            'material': 0,
          },
        ],
      },
    ],
    'scene': 0,
    'scenes': [
      {
        'nodes': [0, 1, 2],
      },
    ],
    'nodes': [
      {'name': 'Mesh', if (mesh) 'mesh': 0},
      {
        'name': 'Spot',
        'extensions': {
          'KHR_lights_punctual': {'light': 0},
        },
      },
      {'name': 'Toggled'},
    ],
    'animations': [
      {
        'name': 'Pointers',
        'samplers': [
          sampler(2), // 0
          sampler(3), // 1
          sampler(4), // 2
          sampler(5), // 3
          sampler(6, 'STEP'), // 4
          sampler(7), // 5
          sampler(8), // 6
          sampler(9), // 7
        ],
        'channels': [
          channel(0, '/materials/0/pbrMetallicRoughness/baseColorFactor'),
          channel(1, '/materials/0/emissiveFactor'),
          channel(
            2,
            '/materials/0/pbrMetallicRoughness/baseColorTexture/extensions/'
            'KHR_texture_transform/offset',
          ),
          channel(
            3,
            '/materials/0/pbrMetallicRoughness/baseColorTexture/extensions/'
            'KHR_texture_transform/rotation',
          ),
          channel(4, '/nodes/2/extensions/KHR_node_visibility/visible'),
          channel(5, '/extensions/KHR_lights_punctual/lights/0/intensity'),
          channel(6, '/extensions/KHR_lights_punctual/lights/0/color'),
          channel(
            3,
            '/extensions/KHR_lights_punctual/lights/0/spot/outerConeAngle',
          ),
          channel(7, '/nodes/0/translation'),
          channel(3, '/materials/1/pbrMetallicRoughness/metallicFactor'),
          channel(3, '/cameras/0/perspective/yfov'),
        ],
      },
    ],
  };
}

Uint8List _bytes({required bool mesh}) =>
    Uint8List.fromList(utf8.encode(jsonEncode(_gltf(mesh: mesh))));

Future<Node> _runtimeImport({required bool mesh}) => importGltf(
  _bytes(mesh: mesh),
  resolveUri: (uri) async => fail('fetched $uri'),
);

// Through the binary codec, so the path channels survive a save and load.
SceneDocument _offlineDocument({required bool mesh}) => readFsceneb(
  writeFsceneb(
    importGltfToSceneDocument(
      _bytes(mesh: mesh),
      resolveUri: (uri) => fail('fetched $uri'),
    ),
  ),
);

Future<Node> _offlineImport({required bool mesh}) async =>
    realizeScene(_offlineDocument(mesh: mesh));

class _StubGeometry extends Geometry {
  @override
  void bind(
    gpu.RenderPass pass,
    TransientWriter transientsBuffer,
    Matrix4 modelTransform,
    Matrix4 cameraTransform,
    Vector3 cameraPosition, {
    gpu.Shader? shaderOverride,
    double depthBias = 0.0,
  }) => throw UnsupportedError('stub');
}

// An animation driving [path] on a node named `Target` from [from] to [to]
// over one second.
Animation _pathAnimation(String path, List<double> from, List<double> to) =>
    Animation(
      channels: [
        AnimationChannel(
          bindTarget: BindKey(
            nodeName: 'Target',
            property: AnimationProperty.path,
            path: path,
          ),
          resolver: PropertyResolver.makePathTimeline(
            path,
            [0, 1],
            Float32List.fromList([...from, ...to]),
            componentCount: from.length,
          ),
        ),
      ],
    );

// Evaluates [animation] (the import's, by default) at [time] seconds.
void _poseAt(Node root, double time, [Animation? animation]) {
  final player = AnimationPlayer();
  player
      .createAnimationClip(animation ?? root.parsedAnimations.single, root)
      .seek(time);
  player.update(0);
}

PhysicallyBasedMaterial _material(Node root) =>
    root.getChildByName('Mesh')!.mesh!.primitives.single.material
        as PhysicallyBasedMaterial;

void main() {
  group('pointer resolution', () {
    final doc = parseGltfJson(_gltf());
    final channels = doc.animations.single.channels;

    test('node transform pointers become plain channels', () {
      expect(channels[8].targetNode, 0);
      expect(channels[8].targetPath, 'translation');
      expect(channels[8].pathTargets, isEmpty);
    });

    test('other pointers resolve to engine paths on their nodes', () {
      String describe(GltfAnimationChannel c) =>
          [for (final t in c.pathTargets) '${t.node}:${t.path}'].join(',');

      expect(describe(channels[0]), '0:primitives/0/material/baseColorFactor');
      expect(channels[0].pathComponentCount, 4);
      expect(describe(channels[1]), '0:primitives/0/material/emissiveFactor');
      expect(channels[1].pathComponentCount, 3);
      expect(
        describe(channels[2]),
        '0:primitives/0/material/baseColorTexture/offset',
      );
      expect(describe(channels[4]), '2:visible');
      expect(describe(channels[5]), '1:light/intensity');
      expect(channels[5].pointerLight, 0);
      expect(describe(channels[7]), '1:light/outerConeAngle');
    });

    test('a material no mesh uses has no targets and no warning', () {
      expect(channels[9].pathTargets, isEmpty);
      expect(channels[9].targetNode, isNull);
    });

    test('an unsupported pointer warns and is skipped', () {
      expect(channels[10].pathTargets, isEmpty);
      expect(channels[10].targetNode, isNull);
      expect(doc.warnings.map((w) => w.message), [
        contains('/cameras/0/perspective/yfov'),
      ]);
    });

    test('pointers the engine has no property for warn', () {
      for (final pointer in [
        '/nodes/0/weights/0',
        '/materials/0/pbrMetallicRoughness/baseColorTexture/texCoord',
        '/extensions/KHR_lights_punctual/lights/0/spot/unknownAngle',
        '/materials/9/alphaCutoff',
        'nodes/0/translation',
      ]) {
        final json = _gltf();
        final animation = (json['animations'] as List).single as Map;
        animation['channels'] = [
          {
            'sampler': 3,
            'target': {
              'path': 'pointer',
              'extensions': {
                'KHR_animation_pointer': {'pointer': pointer},
              },
            },
          },
        ];
        final warnings = parseGltfJson(json).warnings;
        expect(warnings, hasLength(1), reason: pointer);
      }
    });
  });

  for (final (name, import) in [
    ('runtime importer', _runtimeImport),
    ('offline importer', _offlineImport),
  ]) {
    group(name, () {
      test('animates node visibility, holding each step', () async {
        final root = await import(mesh: false);
        final node = root.getChildByName('Toggled')!;
        expect(node.visible, isTrue);

        _poseAt(root, 0.0);
        expect(node.visible, isTrue);
        _poseAt(root, 0.99);
        expect(node.visible, isTrue);
        _poseAt(root, 1.0);
        expect(node.visible, isFalse);
      });

      test('animates a node transform through a pointer', () async {
        final root = await import(mesh: false);
        _poseAt(root, 0.5);
        final translation = root
            .getChildByName('Mesh')!
            .localTransform
            .getTranslation();
        expect(translation.y, closeTo(1.0, 1e-5));
      });

      test('animates light color, intensity, and cone angle', () async {
        final root = await import(mesh: false);
        final light = root
            .getChildByName('Spot')!
            .getComponent<SpotLightComponent>()!
            .light;

        // Each keyframe pair lights the scene as a static light of that
        // color and photometric intensity would.
        void expectLight(Vector3 color, double intensity) {
          final expected =
              color *
              gltfLightIntensity(
                GltfPunctualLight(
                  type: 'spot',
                  color: color,
                  intensity: intensity,
                ),
              );
          final actual = light.color * light.intensity;
          for (var i = 0; i < 3; i++) {
            expect(actual[i], closeTo(expected[i], 1e-6));
          }
        }

        _poseAt(root, 0.0);
        expectLight(Vector3(1, 0, 0), 5);
        expect(light.outerConeAngle, closeTo(0.0, 1e-6));

        _poseAt(root, 1.0);
        expectLight(Vector3(0, 0, 1), 10);
        expect(light.outerConeAngle, closeTo(1.0, 1e-6));
      });
    });

    group('$name with a mesh', skip: !gpuAvailable(), () {
      test('animates material factors', () async {
        final root = await import(mesh: true);
        final material = _material(root);

        _poseAt(root, 0.5);
        final base = material.baseColorFactor;
        expect(base.x, closeTo(0.5, 1e-6));
        expect(base.z, closeTo(0.5, 1e-6));
        expect(base.w, closeTo(0.75, 1e-6));
        final emissive = material.emissiveFactor;
        expect(emissive.xyz, Vector3(1, 2, 3));
        expect(emissive.w, 1.0);
      });

      test('animates a texture transform', () async {
        final root = await import(mesh: true);
        final material = _material(root);

        _poseAt(root, 0.5);
        final transform = material.baseColorTextureTransform;
        expect(transform.offset, Vector2(0.5, 0.25));
        expect(transform.rotation, closeTo(0.5, 1e-6));
        expect(transform.scale, Vector2(1, 1));
      });
    });
  }

  test('the offline importer emits a path channel per pointer target', () {
    final document = _offlineDocument(mesh: true);
    final animation = document.animations.values.single;
    final names = {
      for (final node in document.nodes.values) node.id: node.name,
    };

    expect(
      [
        for (final c in animation.pathChannels)
          '${names[c.target]}:${c.path}${c.step ? ' (step)' : ''}',
      ],
      [
        'Mesh:primitives/0/material/baseColorFactor',
        'Mesh:primitives/0/material/emissiveFactor',
        'Mesh:primitives/0/material/baseColorTexture/offset',
        'Mesh:primitives/0/material/baseColorTexture/rotation',
        'Toggled:visible (step)',
        'Spot:light/intensity',
        'Spot:light/color',
        'Spot:light/outerConeAngle',
      ],
    );
    expect(
      [
        for (final c in animation.channels)
          '${names[c.target]}:${c.property.name}',
      ],
      ['Mesh:translation'],
    );
  });

  group('material paths', () {
    late PhysicallyBasedMaterial material;
    late Node root;

    setUp(() {
      material = PhysicallyBasedMaterial();
      root = Node(name: 'root')
        ..add(
          Node(
            name: 'Target',
            mesh: Mesh.primitives(
              primitives: [MeshPrimitive(_StubGeometry(), material)],
            ),
          ),
        );
    });

    test('animate factors', () {
      _poseAt(
        root,
        0.5,
        _pathAnimation(
          'primitives/0/material/emissiveFactor',
          [0, 0, 0],
          [2, 4, 6],
        ),
      );
      expect(material.emissiveFactor, Vector4(1, 2, 3, 0));

      _poseAt(
        root,
        0.5,
        _pathAnimation('primitives/0/material/roughnessFactor', [0], [0.5]),
      );
      expect(material.roughnessFactor, closeTo(0.25, 1e-6));
    });

    test('animate extension texture transforms', () {
      _poseAt(
        root,
        1.0,
        _pathAnimation(
          'primitives/0/material/clearcoatNormalTexture/scale',
          [1, 1],
          [2, 3],
        ),
      );
      expect(material.clearcoatNormalTextureTransform.scale, Vector2(2, 3));
      expect(material.clearcoatNormalTextureTransform.offset, Vector2.zero());
    });

    test('animate an unlit material\'s base color', () {
      final unlit = UnlitMaterial();
      root.getChildByName('Target')!.mesh!.primitives.single.material = unlit;
      _poseAt(
        root,
        1.0,
        _pathAnimation(
          'primitives/0/material/baseColorFactor',
          [1, 1, 1, 1],
          [0, 0.5, 1, 1],
        ),
      );
      expect(unlit.baseColorFactor, Vector4(0, 0.5, 1, 1));
    });

    test('skip a path the material lacks', () {
      _poseAt(
        root,
        1.0,
        _pathAnimation('primitives/3/material/roughnessFactor', [0], [0.5]),
      );
      _poseAt(
        root,
        1.0,
        _pathAnimation('primitives/0/material/sparkle', [0], [0.5]),
      );
      expect(material.roughnessFactor, 1.0);
    });

    test('leave a held value alone', () {
      final player = AnimationPlayer();
      player
          .createAnimationClip(
            _pathAnimation('primitives/0/material/metallicFactor', [0], [0.5]),
            root,
          )
          .seek(0.5);
      player.update(0);
      expect(material.metallicFactor, closeTo(0.25, 1e-6));
      material.metallicFactor = 0.9;

      player.update(0);
      expect(material.metallicFactor, 0.9);
    });
  });
}
