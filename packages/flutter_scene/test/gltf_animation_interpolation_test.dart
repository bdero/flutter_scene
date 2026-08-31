// Covers the glTF importer carrying a sampler's interpolation through to the
// engine timeline. A STEP sampler used to be read as LINEAR, so a value that
// was authored to snap eased instead; a CUBICSPLINE sampler was flattened to
// its keyframe values with the tangents discarded, so an arc that overshot
// its endpoints came back as a straight line between them.

import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene/src/animation.dart' as engine;
import 'package:flutter_scene/src/importer/gltf.dart';
import 'package:flutter_scene/src/runtime_importer/animation_builder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// Builds a one-node animation whose single translation channel runs from the
/// origin to x = 10 over one second, sampled with [interpolation].
///
/// [output] is the sampler's raw output stream: three floats per keyframe for
/// LINEAR and STEP, nine for CUBICSPLINE (in-tangent, value, out-tangent).
engine.Animation _import(
  String interpolation,
  List<double> output, {
  GltfCoordinatePolicy policy = GltfCoordinatePolicy.runtimeBoundary,
}) {
  final times = Float32List.fromList([0.0, 1.0]);
  final values = Float32List.fromList(output);
  final buffer = BytesBuilder()
    ..add(times.buffer.asUint8List())
    ..add(values.buffer.asUint8List());

  final accessors = [
    GltfAccessor(
      componentType: GltfComponentType.float,
      count: times.length,
      type: GltfAccessorType.scalar,
      bufferView: 0,
    ),
    GltfAccessor(
      componentType: GltfComponentType.float,
      count: values.length ~/ 3,
      type: GltfAccessorType.vec3,
      bufferView: 1,
    ),
  ];
  final bufferViews = [
    GltfBufferView(buffer: 0, byteOffset: 0, byteLength: times.lengthInBytes),
    GltfBufferView(
      buffer: 0,
      byteOffset: times.lengthInBytes,
      byteLength: values.lengthInBytes,
    ),
  ];

  return buildAnimation(
    gltfAnimation: GltfAnimation(
      name: 'Slide',
      samplers: [
        GltfAnimationSampler(input: 0, output: 1, interpolation: interpolation),
      ],
      channels: [
        GltfAnimationChannel(
          sampler: 0,
          targetNode: 0,
          targetPath: 'translation',
        ),
      ],
    ),
    accessors: accessors,
    bufferViews: bufferViews,
    bufferData: buffer.takeBytes(),
    engineNodes: [Node()..name = 'Bone'],
    coordinatePolicy: policy,
  );
}

/// The x the animation's only channel resolves to at [time].
double _xAt(engine.Animation animation, double time) {
  final target = engine.AnimationTransforms(
    bindPose: engine.DecomposedTransform(
      translation: Vector3.zero(),
      rotation: Quaternion.identity(),
      scale: Vector3.all(1.0),
    ),
  );
  animation.channels.single.resolver.apply(target, time, 1.0);
  return target.animatedPose.translation.x;
}

/// The straight run 0 to 10 as a LINEAR/STEP output stream.
const List<double> _straight = [0.0, 0, 0, 10.0, 0, 0];

void main() {
  test('LINEAR still interpolates', () {
    expect(_xAt(_import('LINEAR', _straight), 0.5), closeTo(5.0, 1e-5));
  });

  test('STEP holds the previous keyframe', () {
    final animation = _import('STEP', _straight);

    expect(_xAt(animation, 0.25), 0.0);
    expect(_xAt(animation, 0.99), 0.0);
    expect(_xAt(animation, 1.0), 10.0);
  });

  test('CUBICSPLINE keeps its tangents instead of flattening to the keys', () {
    // Key 0: in-tangent 0, value 0, out-tangent 60 per second.
    // Key 1: in-tangent 0, value 10, out-tangent 0.
    // That out-tangent throws the curve well past x = 10 mid-segment, which
    // is exactly the shape that discarding tangents cannot produce.
    final animation = _import('CUBICSPLINE', const [
      0.0, 0, 0, /* value */ 0.0, 0, 0, /* out */ 60.0, 0, 0, //
      0.0, 0, 0, /* value */ 10.0, 0, 0, /* out */ 0.0, 0, 0,
    ]);

    expect(_xAt(animation, 0.0), closeTo(0.0, 1e-5));
    expect(_xAt(animation, 1.0), closeTo(10.0, 1e-5));
    expect(
      _xAt(animation, 0.5),
      greaterThan(10.0),
      reason: 'the out-tangent must bend the segment past its endpoints',
    );
  });

  test('CUBICSPLINE takes the middle of each triplet as the keyframe', () {
    // Tangents set to values that would be obvious if a slot were misread:
    // reading slot 0 or 2 as the value would put the curve nowhere near the
    // authored 0 and 10 at the keyframe times.
    final animation = _import('CUBICSPLINE', const [
      -99.0, 0, 0, 0.0, 0, 0, 0.0, 0, 0, //
      0.0, 0, 0, 10.0, 0, 0, 99.0, 0, 0,
    ]);

    expect(_xAt(animation, 0.0), closeTo(0.0, 1e-5));
    expect(_xAt(animation, 1.0), closeTo(10.0, 1e-5));
    // Flat tangents on the interior of the segment: smoothstep.
    expect(_xAt(animation, 0.25), closeTo(1.5625, 1e-5));
  });

  test('a baking policy converts the tangents with the values', () {
    // bakeNative negates Z on translation. A tangent is a difference of two
    // translations, so it has to be negated too; leaving it alone would send
    // the curve off the Z axis the keyframes sit on.
    final animation = _import('CUBICSPLINE', const [
      0.0, 0, 0.0, 0.0, 0, 0.0, 0.0, 0, 4.0, //
      0.0, 0, 0.0, 0.0, 0, 2.0, 0.0, 0, 0.0,
    ], policy: GltfCoordinatePolicy.bakeNative);

    final resolver =
        animation.channels.single.resolver
            as engine.TranslationTimelineResolver;

    expect(resolver.values.first.z, 0.0);
    expect(resolver.values.last.z, -2.0);
    expect(resolver.outTangents!.first.z, -4.0);
  });

  test('an unknown interpolation name falls back to linear', () {
    // The spec default, and the only reading that produces motion at all.
    expect(_xAt(_import('BOGUS', _straight), 0.5), closeTo(5.0, 1e-5));
  });
}
