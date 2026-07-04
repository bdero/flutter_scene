// Covers collectSpotShadows: only shadow-casting spots are selected, the count
// is capped at kMaxSpotShadows, a matrix is computed per caster, and slotOf
// reports each caster's slot (or -1 for a non-caster).

import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene/src/render/spot_shadow.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

SpotLightComponent _spot({required bool castsShadow, Vector3? at}) {
  final node = Node(localTransform: Matrix4.translation(at ?? Vector3.zero()));
  final component = SpotLightComponent(
    SpotLight(range: 10.0, castsShadow: castsShadow),
  );
  node.addComponent(component);
  return component;
}

void main() {
  test('no shadow casters yields null', () {
    final frame = collectSpotShadows([
      _spot(castsShadow: false),
      _spot(castsShadow: false),
    ]);
    expect(frame, isNull);
  });

  test('selects only casters and computes a matrix each', () {
    final a = _spot(castsShadow: true, at: Vector3(0, 5, 0));
    final b = _spot(castsShadow: false);
    final c = _spot(castsShadow: true, at: Vector3(3, 5, 0));
    final frame = collectSpotShadows([a, b, c])!;

    expect(frame.casters, [a, c]);
    expect(frame.matrices, hasLength(2));
    expect(frame.slotOf(a), 0);
    expect(frame.slotOf(c), 1);
    expect(frame.slotOf(b), -1);
  });

  test('caps the number of shadow casters at kMaxSpotShadows', () {
    final spots = [
      for (var i = 0; i < kMaxSpotShadows + 3; i++)
        _spot(castsShadow: true, at: Vector3(i.toDouble(), 5, 0)),
    ];
    final frame = collectSpotShadows(spots)!;
    expect(frame.casters, hasLength(kMaxSpotShadows));
    expect(frame.matrices, hasLength(kMaxSpotShadows));
    // The spots past the budget are not casters this frame.
    expect(frame.slotOf(spots.last), -1);
  });

  test('shares tile resolution and bias from the first caster', () {
    final node = Node();
    final component = SpotLightComponent(
      SpotLight(
        castsShadow: true,
        range: 10,
        shadowMapResolution: 512,
        shadowDepthBias: 0.007,
      ),
    );
    node.addComponent(component);
    final frame = collectSpotShadows([component])!;
    expect(frame.tileResolution, 512);
    expect(frame.depthBias, closeTo(0.007, 1e-9));
  });
}
