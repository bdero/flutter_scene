// Covers STEP and CUBICSPLINE keyframe interpolation: the timeline resolvers'
// modes, and the runtime importer carrying each glTF sampler's interpolation
// and tangents through, pointer channels included.

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';
// The channel/resolver data model is internal; tests reach it directly.
// ignore: implementation_imports
import 'package:flutter_scene/src/animation.dart'
    show
        AnimationInterpolation,
        AnimationTransforms,
        DecomposedTransform,
        PropertyResolver;
// ignore: implementation_imports
import 'package:flutter_scene/src/importer/gltf.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/importer/gltf_light_units.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/runtime_importer/runtime_importer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

// A node's animation state at rest, with its rotation fully covered as an
// AnimationPlayer leaves it for a single clip.
AnimationTransforms _rest() {
  final transforms = AnimationTransforms(
    bindPose: DecomposedTransform(
      translation: Vector3.zero(),
      rotation: Quaternion.identity(),
      scale: Vector3.all(1),
    ),
  );
  transforms.rotationBlendWeight = 0;
  return transforms;
}

Vector3 _translationAt(PropertyResolver resolver, double time) {
  final transforms = _rest();
  resolver.apply(transforms, time, 1);
  return transforms.animatedPose.translation;
}

const _flat = <double>[0, 0, 0, 0];
const _identity = <double>[0, 0, 0, 1];
// A quarter turn about Y.
const _turnY = <double>[0, 0.70710678, 0, 0.70710678];

// Accessors packed into one data URI buffer, each as (type, values). A
// cubic spline's output is (in-tangent, value, out-tangent) per keyframe.
const _accessors = <(String, List<double>)>[
  ('SCALAR', [0, 2]), // 0 times
  ('VEC3', [0, 0, 0, 0, 2, 0]), // 1 step and linear translations
  // 2 cubic translations, leaving the first keyframe at 1 per second.
  ('VEC3', [0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 2, 0, 0, 0, 0]),
  // 3 cubic rotations with flat tangents.
  ('VEC4', [..._flat, ..._identity, ..._flat, ..._flat, ..._turnY, ..._flat]),
  ('SCALAR', [0, 5, 10, 0, 10, 0]), // 4 cubic light intensities
];

Map<String, Object?> _gltf() {
  final bytes = BytesBuilder();
  final views = <Map<String, Object?>>[];
  final accessors = <Map<String, Object?>>[];
  for (final (i, (type, values)) in _accessors.indexed) {
    final offset = bytes.length;
    bytes.add(Float32List.fromList(values).buffer.asUint8List());
    views.add({
      'buffer': 0,
      'byteOffset': offset,
      'byteLength': values.length * 4,
    });
    final components = switch (type) {
      'VEC4' => 4,
      'VEC3' => 3,
      _ => 1,
    };
    accessors.add({
      'bufferView': i,
      'componentType': 5126,
      'count': values.length ~/ components,
      'type': type,
      if (i == 0) 'min': [0],
      if (i == 0) 'max': [2],
    });
  }
  final data = bytes.takeBytes();

  Map<String, Object?> sampler(int output, String interpolation) => {
    'input': 0,
    'output': output,
    'interpolation': interpolation,
  };
  Map<String, Object?> channel(int sampler, int node, String path) => {
    'sampler': sampler,
    'target': {'node': node, 'path': path},
  };
  const intensity = '/extensions/KHR_lights_punctual/lights/0/intensity';

  return {
    'asset': {'version': '2.0'},
    'extensionsUsed': ['KHR_animation_pointer', 'KHR_lights_punctual'],
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
    'scene': 0,
    'scenes': [
      {
        'nodes': [0, 1, 2, 3, 4],
      },
    ],
    'nodes': [
      {'name': 'Stepped'},
      {'name': 'Linear'},
      {'name': 'Cubic'},
      {'name': 'Spun'},
      {
        'name': 'Spot',
        'extensions': {
          'KHR_lights_punctual': {'light': 0},
        },
      },
    ],
    'animations': [
      {
        'name': 'Interpolations',
        'samplers': [
          sampler(1, 'STEP'),
          sampler(1, 'LINEAR'),
          sampler(2, 'CUBICSPLINE'),
          sampler(3, 'CUBICSPLINE'),
          sampler(4, 'CUBICSPLINE'),
        ],
        'channels': [
          channel(0, 0, 'translation'),
          channel(1, 1, 'translation'),
          channel(2, 2, 'translation'),
          channel(3, 3, 'rotation'),
          {
            'sampler': 4,
            'target': {
              'path': 'pointer',
              'extensions': {
                'KHR_animation_pointer': {'pointer': intensity},
              },
            },
          },
        ],
      },
    ],
  };
}

Future<Node> _import() => importGltf(
  Uint8List.fromList(utf8.encode(jsonEncode(_gltf()))),
  resolveUri: (uri) async => fail('fetched $uri'),
);

// Evaluates the import's animation at [time] seconds.
void _poseAt(Node root, double time) {
  final player = AnimationPlayer();
  player.createAnimationClip(root.parsedAnimations.single, root).seek(time);
  player.update(0);
}

void main() {
  group('timeline resolvers', () {
    test('step holds each keyframe until the next', () {
      final resolver = PropertyResolver.makeTranslationTimeline(
        [0, 1, 2],
        [Vector3.zero(), Vector3(1, 0, 0), Vector3(3, 0, 0)],
        interpolation: AnimationInterpolation.step,
      );
      const samples = [
        (0.0, 0.0),
        (0.5, 0.0),
        (0.99, 0.0),
        (1.0, 1.0),
        (1.5, 1.0),
        (2.0, 3.0),
      ];
      for (final (time, x) in samples) {
        expect(_translationAt(resolver, time).x, x, reason: 'at $time s');
      }
    });

    test('a cubic spline scales its tangents by the keyframe interval', () {
      // Over two seconds, an out-tangent of 1 per second adds
      // h10(0.5) * 2 = 0.25 at the midpoint, on top of the values' 0.5.
      final resolver = PropertyResolver.makeTranslationTimeline(
        [0, 2],
        [Vector3.zero(), Vector3(1, 0, 0)],
        interpolation: AnimationInterpolation.cubicSpline,
        inTangents: [Vector3.zero(), Vector3.zero()],
        outTangents: [Vector3(1, 0, 0), Vector3.zero()],
      );
      expect(_translationAt(resolver, 0).x, 0);
      expect(_translationAt(resolver, 1).x, closeTo(0.75, 1e-6));
      expect(_translationAt(resolver, 2).x, 1);
    });

    test('a cubic spline passes beyond its keyframes along its tangents', () {
      final resolver = PropertyResolver.makeTranslationTimeline(
        [0, 1],
        [Vector3.zero(), Vector3.zero()],
        interpolation: AnimationInterpolation.cubicSpline,
        inTangents: [Vector3.zero(), Vector3(-4, 0, 0)],
        outTangents: [Vector3(4, 0, 0), Vector3.zero()],
      );
      // h10(0.5) * 4 + h11(0.5) * -4 = 0.5 + 0.5, where linear stays at 0.
      expect(_translationAt(resolver, 0.5).x, closeTo(1, 1e-6));
    });

    test('a cubic spline rotation comes out normalized', () {
      final flat = Quaternion(0, 0, 0, 0);
      final resolver = PropertyResolver.makeRotationTimeline(
        [0, 1],
        [Quaternion.identity(), Quaternion.axisAngle(Vector3(0, 1, 0), pi / 2)],
        interpolation: AnimationInterpolation.cubicSpline,
        inTangents: [flat, flat],
        outTangents: [flat, flat],
      );
      final transforms = _rest();
      resolver.apply(transforms, 0.5, 1);

      // Flat tangents meet the two keyframes halfway, an eighth turn.
      final rotation = transforms.animatedPose.rotation;
      final eighthTurn = Quaternion.axisAngle(Vector3(0, 1, 0), pi / 4);
      expect(rotation.length, closeTo(1, 1e-6));
      expect(rotation.y, closeTo(eighthTurn.y, 1e-6));
      expect(rotation.w, closeTo(eighthTurn.w, 1e-6));
    });

    test('morph weights hold a step and follow a cubic spline', () {
      Float32List weightsAt(PropertyResolver resolver, double time) {
        final transforms = _rest()
          ..bindMorphWeights = Float32List(2)
          ..animatedMorphWeights = Float32List(2);
        resolver.apply(transforms, time, 1);
        return transforms.animatedMorphWeights!;
      }

      final values = Float32List.fromList([0, 1, 1, 0]);
      final step = PropertyResolver.makeMorphWeightsTimeline(
        [0, 1],
        values,
        targetCount: 2,
        interpolation: AnimationInterpolation.step,
      );
      expect(weightsAt(step, 0.5), [0.0, 1.0]);

      final cubic = PropertyResolver.makeMorphWeightsTimeline(
        [0, 1],
        values,
        targetCount: 2,
        interpolation: AnimationInterpolation.cubicSpline,
        inTangents: Float32List(4),
        outTangents: Float32List(4),
      );
      // Flat tangents ease in and out, h01(0.25) = 0.15625.
      final weights = weightsAt(cubic, 0.25);
      expect(weights[0], closeTo(0.15625, 1e-6));
      expect(weights[1], closeTo(0.84375, 1e-6));
    });
  });

  group('the runtime importer', () {
    test('keeps each sampler\'s interpolation', () async {
      final root = await _import();
      _poseAt(root, 1);
      double heightOf(String name) =>
          root.getChildByName(name)!.localTransform.getTranslation().y;

      // Halfway between keyframes at y = 0 and y = 2.
      expect(heightOf('Stepped'), 0);
      expect(heightOf('Linear'), closeTo(1, 1e-6));
      // The out-tangent of 1 per second, over two seconds, adds 0.25.
      expect(heightOf('Cubic'), closeTo(1.25, 1e-6));

      // Halfway through a quarter turn about Y.
      final spun = root.getChildByName('Spun')!.localTransform;
      final right = spun.rotated3(Vector3(1, 0, 0));
      expect(right.x, closeTo(cos(pi / 4), 1e-6));
      expect(right.z, closeTo(-sin(pi / 4), 1e-6));
    });

    test('converts a cubic pointer channel\'s tangents', () async {
      final root = await _import();
      final light = root
          .getChildByName('Spot')!
          .getComponent<SpotLightComponent>()!
          .light;
      _poseAt(root, 1);

      // The glTF spline reaches an intensity of 10 at the midpoint, where
      // linear interpolation would give 7.5.
      final color = Vector3(0, 1, 0);
      final expected =
          color *
          gltfLightIntensity(
            GltfPunctualLight(type: 'spot', color: color, intensity: 10),
          );
      final actual = light.color * light.intensity;
      for (var i = 0; i < 3; i++) {
        expect(actual[i], closeTo(expected[i], 1e-6));
      }
    });

    test('converts a light color tangent as its keyframe converts', () {
      final channel = GltfAnimationChannel(
        sampler: 0,
        targetNode: null,
        targetPath: 'pointer',
        pathTargets: const [GltfAnimationPathTarget(0, 'light/color')],
        pathComponentCount: 3,
        pointerLight: 0,
      );
      final lights = [
        GltfPunctualLight(type: 'point', color: Vector3(0, 1, 0)),
      ];
      final color = [1.0, 0.5, 0.25];
      final tangent = [0.2, -0.4, 1.0];
      const h = 1e-2;
      Float32List convert(double offset) => convertGltfPathKeyframes(
        channel,
        lights,
        Float32List.fromList([
          for (var c = 0; c < 3; c++) color[c] + tangent[c] * offset,
        ]),
      );

      // A central difference of the keyframe conversion.
      final above = convert(h);
      final below = convert(-h);
      final converted = convertGltfPathTangents(
        channel,
        lights,
        Float32List.fromList(tangent),
        Float32List.fromList(color),
      );
      for (var c = 0; c < 3; c++) {
        expect(
          converted[c],
          closeTo((above[c] - below[c]) / (2 * h), 1e-3),
          reason: 'component $c',
        );
      }
    });
  });
}
