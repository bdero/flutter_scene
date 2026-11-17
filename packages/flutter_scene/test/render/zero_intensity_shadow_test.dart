import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene/src/render/point_shadow.dart';
import 'package:flutter_scene/src/render/shadow_cache.dart';
import 'package:flutter_scene/src/render/spot_shadow.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

SpotLightComponent _spot({
  bool castsShadow = true,
  double intensity = 1.0,
  Vector3? position,
}) {
  final node = Node(
    localTransform: Matrix4.translation(position ?? Vector3(0, 5, 0)),
  );
  final component = SpotLightComponent(
    SpotLight(
      castsShadow: castsShadow,
      intensity: intensity,
      range: 20.0,
      direction: Vector3(0, -1, 0),
    ),
  );
  node.addComponent(component);
  return component;
}

PointLightComponent _point({
  bool castsShadow = true,
  double intensity = 1.0,
  Vector3? position,
}) {
  final node = Node(
    localTransform: Matrix4.translation(position ?? Vector3(0, 3, 0)),
  );
  final component = PointLightComponent(
    PointLight(castsShadow: castsShadow, intensity: intensity, range: 20.0),
  );
  node.addComponent(component);
  return component;
}

void main() {
  group('zero-intensity shadow short-circuit', () {
    test('collectSpotShadows skips spots with intensity <= 1e-4', () {
      final zero = _spot(intensity: 0.0);
      final negative = _spot(intensity: -1.0);
      final atThreshold = _spot(intensity: kMinShadowLightIntensity);
      expect(collectSpotShadows([zero, negative, atThreshold]), isNull);

      final aboveThreshold = _spot(intensity: 1.01e-4);
      final frame = collectSpotShadows([zero, atThreshold, aboveThreshold])!;
      expect(frame.casters, [aboveThreshold]);
      expect(frame.slotOf(zero), -1);
      expect(frame.slotOf(aboveThreshold), 0);
    });

    test('zero-intensity spots do not consume kMaxSpotShadows budget', () {
      final inactive = [for (var i = 0; i < 3; i++) _spot(intensity: 0.0)];
      final active = [
        for (var i = 0; i < kMaxSpotShadows; i++)
          _spot(intensity: 2.0, position: Vector3(i.toDouble(), 5, 0)),
      ];
      final frame = collectSpotShadows([...inactive, ...active])!;
      expect(frame.casters, active);
    });

    test('spotLightCastsShadow and directionalLightCastsShadow helpers', () {
      expect(
        spotLightCastsShadow(SpotLight(castsShadow: false, intensity: 5.0)),
        isFalse,
      );
      expect(
        spotLightCastsShadow(SpotLight(castsShadow: true, intensity: 0.0)),
        isFalse,
      );
      expect(
        spotLightCastsShadow(SpotLight(castsShadow: true, intensity: 1e-4)),
        isFalse,
      );
      expect(
        spotLightCastsShadow(SpotLight(castsShadow: true, intensity: 2e-4)),
        isTrue,
      );

      expect(directionalLightCastsShadow(null), isFalse);
      expect(
        directionalLightCastsShadow(
          DirectionalLight(castsShadow: false, intensity: 3.0),
        ),
        isFalse,
      );
      expect(
        directionalLightCastsShadow(
          DirectionalLight(castsShadow: true, intensity: 0.0),
        ),
        isFalse,
      );
      expect(
        directionalLightCastsShadow(
          DirectionalLight(castsShadow: true, intensity: 1e-4),
        ),
        isFalse,
      );
      expect(
        directionalLightCastsShadow(
          DirectionalLight(castsShadow: true, intensity: 2e-4),
        ),
        isTrue,
      );

      expect(
        pointLightCastsShadow(PointLight(castsShadow: false, intensity: 5.0)),
        isFalse,
      );
      expect(
        pointLightCastsShadow(PointLight(castsShadow: true, intensity: 0.0)),
        isFalse,
      );
      expect(
        pointLightCastsShadow(PointLight(castsShadow: true, intensity: 1e-4)),
        isFalse,
      );
      expect(
        pointLightCastsShadow(PointLight(castsShadow: true, intensity: 2e-4)),
        isTrue,
      );
    });

    test(
      'collectPointShadows skips points with intensity <= 1e-4 and preserves kMaxPointShadows budget',
      () {
        final zero = _point(intensity: 0.0);
        final negative = _point(intensity: -0.5);
        final atThreshold = _point(intensity: kMinShadowLightIntensity);
        expect(collectPointShadows([zero, negative, atThreshold]), isNull);

        final active = [
          for (var i = 0; i < kMaxPointShadows; i++)
            _point(intensity: 2.0, position: Vector3(i.toDouble(), 3, 0)),
        ];
        final frame = collectPointShadows([zero, atThreshold, ...active])!;
        expect(frame.casters, active);
        expect(frame.slotOf(zero), -1);
      },
    );
  });
}
