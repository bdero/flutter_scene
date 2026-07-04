// Covers PunctualLightBuffer.packLights: the data-texture texel layout (which
// must match FetchPunctualTexel's column reads in material_lighting.glsl), the
// color-times-intensity premultiply, the inverse-range encoding, the spot cone
// scale/offset, and that the first directional light is skipped (it is shaded
// with shadows by the FragInfo path, so only the extras are packed here).

import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene/src/render/punctual_lights.dart';
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

    test('skips the first directional light and packs the rest as type 0', () {
      final (floats, count) = PunctualLightBuffer.packLights(
        directionals: [
          _directional(DirectionalLight()), // shaded by the FragInfo path
          _directional(
            DirectionalLight(
              direction: Vector3(0.0, 0.0, -1.0),
              color: Vector3(1.0, 1.0, 1.0),
              intensity: 3.0,
            ),
          ),
        ],
        points: const [],
        spots: const [],
      );
      expect(count, 1);
      // Type 0 (directional), color premultiplied, travel direction in texel 2.
      expect(floats[3], 0.0);
      expect(floats[4], closeTo(3.0, 1e-6));
      expect(floats[8], closeTo(0.0, 1e-6));
      expect(floats[10], closeTo(-1.0, 1e-6));
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
}
