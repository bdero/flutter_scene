// Covers PunctualLightBuffer.packLights: the data-texture texel layout (which
// must match FetchPunctualTexel's column reads in material_lighting.glsl), the
// color-times-intensity premultiply, the inverse-range encoding, the spot cone
// scale/offset, and that the selected primary directional light is skipped.

import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene/src/render/punctual_lights.dart';
import 'package:flutter_scene/src/render/render_scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

// Floats per light row (8 RGBA32F texels). Kept local to the test so a change
// to the layout has to be reflected here on purpose.
const int _floatsPerLight = 32;

PointLightComponent _pointAt(Vector3 position, PointLight light) {
  final node = Node(localTransform: Matrix4.translation(position));
  final component = PointLightComponent(light);
  node.addComponent(component);
  return component;
}

SpotLightComponent _spotAt(Vector3 position, SpotLight light) {
  final node = Node(localTransform: Matrix4.translation(position));
  final component = SpotLightComponent(light);
  node.addComponent(component);
  return component;
}

DirectionalLightComponent _directional(DirectionalLight light) {
  final node = Node();
  final component = DirectionalLightComponent(light);
  node.addComponent(component);
  return component;
}

void main() {
  group('PunctualLightBuffer.packLights', () {
    test('aimed directional component normalizes its local direction', () {
      final node = Node();
      final component = DirectionalLightComponent.aimed(
        DirectionalLight(),
        Vector3(0, 0, 4),
      );
      node.addComponent(component);

      expect(component.worldDirection, Vector3(0, 0, 1));
    });

    test('default directional component rejects a custom light direction', () {
      expect(
        () => DirectionalLightComponent(
          DirectionalLight(direction: Vector3(1, 0, 0)),
        ),
        throwsAssertionError,
      );
    });

    test('cloning does not revalidate a mounted directional component', () {
      final light = DirectionalLight();
      final node = Node()..addComponent(DirectionalLightComponent(light));
      light.direction.setValues(-1, -1, 0);

      expect(() => node.clone(), returnsNormally);
    });

    test('packs a point light into row 0 with premultiplied color', () {
      final (floats, count) = PunctualLightBuffer.packLights(
        directionals: const [],
        points: [
          _pointAt(
            Vector3(1.0, 2.0, 3.0),
            PointLight(
              color: Vector3(0.5, 0.6, 0.7),
              intensity: 2.0,
              range: 10,
            ),
          ),
        ],
        spots: const [],
      );
      expect(count, 1);
      // Texel 0: position.xyz, type (1 = point).
      expect(floats[0], 1.0);
      expect(floats[1], 2.0);
      expect(floats[2], 3.0);
      expect(floats[3], 1.0);
      // Texel 1: color * intensity, inverse range.
      expect(floats[4], closeTo(1.0, 1e-6));
      expect(floats[5], closeTo(1.2, 1e-6));
      expect(floats[6], closeTo(1.4, 1e-6));
      expect(floats[7], closeTo(0.1, 1e-6));
      // Texel 3.z: the physical inverse-square exponent by default.
      expect(floats[14], closeTo(2.0, 1e-6));
    });

    test('packs the falloff exponent into texel 3.z, clamped positive', () {
      final (floats, _) = PunctualLightBuffer.packLights(
        directionals: const [],
        points: [_pointAt(Vector3.zero(), PointLight(falloffExponent: 1.3))],
        spots: [_spotAt(Vector3.zero(), SpotLight(falloffExponent: -1.0))],
      );
      expect(floats[14], closeTo(1.3, 1e-6));
      // The spot occupies row 1; a non-positive exponent clamps to 0.1.
      expect(floats[32 + 14], closeTo(0.1, 1e-6));
    });

    test('an infinite-range point light encodes inverse range 0', () {
      final (floats, _) = PunctualLightBuffer.packLights(
        directionals: const [],
        points: [_pointAt(Vector3.zero(), PointLight())],
        spots: const [],
      );
      expect(floats[7], 0.0);
    });

    test('packs a spot light with the precomputed cone scale and offset', () {
      final (floats, count) = PunctualLightBuffer.packLights(
        directionals: const [],
        points: const [],
        spots: [
          _spotAt(
            Vector3(4.0, 0.0, 0.0),
            SpotLight(
              direction: Vector3(0.0, -1.0, 0.0),
              innerConeAngle: 0.0,
              outerConeAngle: math.pi / 4.0,
            ),
          ),
        ],
      );
      expect(count, 1);
      // Texel 0: position + type (2 = spot).
      expect(floats[0], 4.0);
      expect(floats[3], 2.0);
      // Texel 2: direction + angular scale.
      expect(floats[8], closeTo(0.0, 1e-6));
      expect(floats[9], closeTo(-1.0, 1e-6));
      expect(floats[10], closeTo(0.0, 1e-6));
      final cosOuter = math.cos(math.pi / 4.0);
      final scale = 1.0 / (1.0 - cosOuter); // cos(inner=0) = 1
      expect(floats[11], closeTo(scale, 1e-6));
      // Texel 3: angular offset.
      expect(floats[12], closeTo(-cosOuter * scale, 1e-6));
    });

    test('skips the selected directional light and packs the rest', () {
      final first = _directional(DirectionalLight());
      final primary = _directional(
        DirectionalLight(color: Vector3(1.0, 1.0, 1.0), intensity: 3.0),
      );
      final (floats, count) = PunctualLightBuffer.packLights(
        directionals: [first, primary],
        primaryDirectional: primary,
        points: const [],
        spots: const [],
      );
      expect(count, 1);
      // The non-primary first light is retained as an additional directional.
      expect(floats[3], 0.0);
      expect(floats[4], closeTo(3.0, 1e-6));
      expect(floats[8], closeTo(0.0, 1e-6));
      expect(floats[10], closeTo(1.0, 1e-6));
    });

    test('a lone directional light packs nothing', () {
      final (_, count) = PunctualLightBuffer.packLights(
        directionals: [_directional(DirectionalLight())],
        points: const [],
        spots: const [],
      );
      expect(count, 0);
    });

    test('point and spot lights share the row order', () {
      final (floats, count) = PunctualLightBuffer.packLights(
        directionals: const [],
        points: [_pointAt(Vector3(1.0, 0.0, 0.0), PointLight())],
        spots: [_spotAt(Vector3(0.0, 5.0, 0.0), SpotLight())],
      );
      expect(count, 2);
      // Row 0 is the point light, row 1 the spot.
      expect(floats[3], 1.0);
      expect(floats[_floatsPerLight + 3], 2.0);
      expect(floats[_floatsPerLight + 1], 5.0);
    });
  });

  group('directional-light selection', () {
    test('priority wins over strength', () {
      final strong = _directional(DirectionalLight(intensity: 100));
      final preferred = _directional(
        DirectionalLight(intensity: 1, priority: 2),
      );
      final renderScene = RenderScene()
        ..addDirectionalLight(strong)
        ..addDirectionalLight(preferred);

      expect(renderScene.primaryDirectionalLight, same(preferred));
    });

    test('strength breaks equal-priority ties', () {
      final dim = _directional(DirectionalLight(intensity: 1));
      final bright = _directional(DirectionalLight(intensity: 3));
      final renderScene = RenderScene()
        ..addDirectionalLight(dim)
        ..addDirectionalLight(bright);

      expect(renderScene.primaryDirectionalLight, same(bright));
    });

    test('node rotation aims native local forward', () {
      final node = Node(localTransform: Matrix4.rotationY(math.pi / 2));
      final component = DirectionalLightComponent(DirectionalLight());
      node.addComponent(component);

      expect(component.worldDirection.x, closeTo(1, 1e-6));
      expect(component.worldDirection.y, closeTo(0, 1e-6));
      expect(component.worldDirection.z, closeTo(0, 1e-6));
    });
  });
}
