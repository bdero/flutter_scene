// Tests IrradianceFieldBake and IrradianceFieldBakeStepper.

import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  group('IrradianceFieldBake', () {
    test('initializes and holds properties', () {
      final origin = Vector3(1, 2, 3);
      final spacing = Vector3(0.5, 0.5, 0.5);
      final resolution = Vector3(4, 4, 4);
      final bytes = Uint8List(128);

      final bake = IrradianceFieldBake(
        origin: origin,
        spacing: spacing,
        resolution: resolution,
        atlasBytes: bytes,
      );

      expect(bake.origin, origin);
      expect(bake.spacing, spacing);
      expect(bake.resolution, resolution);
      expect(bake.atlasBytes, bytes);
    });
  });

  group('IrradianceVolumeComponent bake property', () {
    test('attaches and retrieves bake data', () {
      final comp = IrradianceVolumeComponent();
      expect(comp.bake, isNull);

      final bake = IrradianceFieldBake(
        origin: Vector3.zero(),
        spacing: Vector3.all(1.0),
        resolution: Vector3(4, 4, 4),
        atlasBytes: Uint8List(64),
      );

      comp.bake = bake;
      expect(comp.bake, same(bake));
    });
  });
}
