import 'dart:math' as math;
import 'dart:ui' show Color, ColorSpace;

import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

double _eotf(double v) =>
    v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();

// Vectors store float32, so expectations allow 1e-6.
void main() {
  group('ColorToLinear', () {
    test('decodes sRGB channels with the sRGB EOTF', () {
      for (final byte in [0, 1, 10, 27, 64, 128, 187, 254, 255]) {
        final linear = Color.fromARGB(255, byte, byte, byte).toLinearRgb();
        final expected = _eotf(byte / 255);
        expect(linear.r, closeTo(expected, 1e-6), reason: 'byte $byte');
        expect(linear.g, closeTo(expected, 1e-6), reason: 'byte $byte');
        expect(linear.b, closeTo(expected, 1e-6), reason: 'byte $byte');
      }
      final mid = const Color(0xFF808080).toLinearRgb();
      expect(mid.r, closeTo(0.2158605, 1e-6));
    });

    test('keeps channels independent and alpha unchanged', () {
      final rgba = const Color(0x80FF4000).toLinearRgba();
      expect(rgba.r, 1.0);
      expect(rgba.g, closeTo(_eotf(0x40 / 255), 1e-6));
      expect(rgba.b, 0.0);
      expect(rgba.a, closeTo(0x80 / 255, 1e-6));
    });

    test('converts Display P3 into sRGB primaries', () {
      final white = Color.from(
        alpha: 1,
        red: 1,
        green: 1,
        blue: 1,
        colorSpace: ColorSpace.displayP3,
      ).toLinearRgb();
      expect(white.r, closeTo(1.0, 1e-3));
      expect(white.g, closeTo(1.0, 1e-3));
      expect(white.b, closeTo(1.0, 1e-3));

      // P3 red lies outside sRGB: its red runs past 1 and the negative green
      // and blue clip to 0.
      final red = Color.from(
        alpha: 1,
        red: 1,
        green: 0,
        blue: 0,
        colorSpace: ColorSpace.displayP3,
      ).toLinearRgb();
      expect(red.r, greaterThan(1.0));
      expect(red.g, 0.0);
      expect(red.b, 0.0);
    });

    test('keeps extended sRGB values above 1', () {
      final bright = Color.from(
        alpha: 1,
        red: 1.5,
        green: 1,
        blue: -0.25,
        colorSpace: ColorSpace.extendedSRGB,
      ).toLinearRgb();
      expect(bright.r, closeTo(_eotf(1.5), 1e-6));
      expect(bright.g, 1.0);
      expect(bright.b, 0.0);
    });
  });

  group('Color setters', () {
    const color = Color(0xFF3366CC);
    final linear = color.toLinearRgba();

    void expectVector4(vm.Vector4 actual) {
      for (var i = 0; i < 4; i++) {
        expect(actual[i], closeTo(linear[i], 1e-6));
      }
    }

    void expectVector3(vm.Vector3 actual) {
      for (var i = 0; i < 3; i++) {
        expect(actual[i], closeTo(linear[i], 1e-6));
      }
    }

    test('UnlitMaterial.setBaseColor', () {
      expectVector4((UnlitMaterial()..setBaseColor(color)).baseColorFactor);
    });

    test('PhysicallyBasedMaterial.setBaseColor and setEmissiveColor', () {
      final material = PhysicallyBasedMaterial()
        ..setBaseColor(color)
        ..setEmissiveColor(color);
      expectVector4(material.baseColorFactor);
      expectVector4(material.emissiveFactor);
    });

    test('light and fog setColor', () {
      expectVector3((DirectionalLight()..setColor(color)).color);
      expectVector3((PointLight()..setColor(color)).color);
      expectVector3((SpotLight()..setColor(color)).color);
      expectVector3((RectAreaLight()..setColor(color)).color);
      expectVector3((Fog()..setColor(color)).color);
    });
  });
}
