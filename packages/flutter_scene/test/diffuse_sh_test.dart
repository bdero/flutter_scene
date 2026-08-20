import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// The coefficients a constant environment of radiance [radiance] projects to
/// under the engine's contract.
List<Vector3> _constantSh(Vector3 radiance) => <Vector3>[
  radiance / kShBand0Basis,
  for (var i = 1; i < kDiffuseShCoefficientCount; i++) Vector3.zero(),
];

void main() {
  group('evaluation', () {
    test('a constant environment evaluates to its radiance everywhere', () {
      final sh = _constantSh(Vector3(0.2, 0.4, 0.8));
      for (final direction in <Vector3>[
        Vector3(0, 1, 0),
        Vector3(0, -1, 0),
        Vector3(1, 0, 0),
        Vector3(0.3, -0.5, 0.81),
      ]) {
        final value = evaluateDiffuseSphericalHarmonics(sh, direction);
        expect(value.x, closeTo(0.2, 1e-6));
        expect(value.y, closeTo(0.4, 1e-6));
        expect(value.z, closeTo(0.8, 1e-6));
      }
    });

    test('a wrong coefficient count is rejected', () {
      expect(
        () => evaluateDiffuseSphericalHarmonics(<Vector3>[
          Vector3.zero(),
        ], Vector3(0, 1, 0)),
        throwsArgumentError,
      );
    });
  });

  group('verification helper', () {
    test('a constant environment reads back flat at its radiance', () {
      final summary = describeDiffuseSphericalHarmonics(
        _constantSh(Vector3.all(0.5)),
      );
      expect(summary.mean.x, closeTo(0.5, 1e-5));
      expect(summary.constantDeviation, lessThan(1e-5));
      expect(summary.negativeFraction, 0.0);
    });

    test(
      'coefficients missing the 1/pi fold read back pi times too bright',
      () {
        final correct = _constantSh(Vector3.all(1.0));
        final unfolded = [for (final c in correct) c * math.pi];
        final summary = describeDiffuseSphericalHarmonics(unfolded);
        expect(summary.mean.x, closeTo(math.pi, 1e-4));
      },
    );

    test('a directional lobe shows up as deviation and ringing', () {
      // Band 1 alone: a linear gradient along +Y, which dips negative below
      // the horizon.
      final sh = <Vector3>[
        Vector3.all(1.0 / kShBand0Basis),
        Vector3.all(1.0),
        for (var i = 2; i < kDiffuseShCoefficientCount; i++) Vector3.zero(),
      ];
      final summary = describeDiffuseSphericalHarmonics(sh);
      expect(summary.mean.x, closeTo(1.0, 1e-3));
      expect(summary.constantDeviation, greaterThan(0.4));
      expect(summary.maximum.y, greaterThan(summary.minimum.y));
    });

    test('the engine round-trips its own constant-diffuse environment', () {
      late EnvironmentMap environment;
      try {
        environment = EnvironmentMap.constantDiffuse(Vector3(0.25, 0.5, 1.0));
      } catch (_) {
        return; // Needs a GPU device for the coefficient texture.
      }
      final summary = describeDiffuseSphericalHarmonics(
        environment.diffuseSphericalHarmonics,
      );
      expect(summary.mean.x, closeTo(0.25, 1e-5));
      expect(summary.mean.z, closeTo(1.0, 1e-5));
      expect(summary.constantDeviation, lessThan(1e-5));
    });
  });

  group('sidecar', () {
    test('round-trips every coefficient', () {
      final sh = <Vector3>[
        for (var i = 0; i < kDiffuseShCoefficientCount; i++)
          Vector3(i * 0.5, -i * 0.25, i.toDouble()),
      ];
      final bytes = encodeDiffuseShSidecar(sh);
      expect(bytes.length, kDiffuseShSidecarByteLength);
      final read = parseDiffuseShSidecar(bytes);
      for (var i = 0; i < kDiffuseShCoefficientCount; i++) {
        expect(read[i].x, closeTo(sh[i].x, 1e-6));
        expect(read[i].y, closeTo(sh[i].y, 1e-6));
        expect(read[i].z, closeTo(sh[i].z, 1e-6));
      }
    });

    test('a wrong-sized payload is a FormatException', () {
      expect(
        () => parseDiffuseShSidecar(Uint8List(64)),
        throwsA(isA<FormatException>()),
      );
    });

    test('a non-finite coefficient is a FormatException', () {
      final bytes = encodeDiffuseShSidecar(
        List<Vector3>.generate(
          kDiffuseShCoefficientCount,
          (_) => Vector3.zero(),
        ),
      );
      ByteData.sublistView(bytes).setFloat32(0, double.nan, Endian.little);
      expect(
        () => parseDiffuseShSidecar(bytes),
        throwsA(isA<FormatException>()),
      );
    });

    test('encoding a wrong coefficient count is rejected', () {
      expect(
        () => encodeDiffuseShSidecar(<Vector3>[Vector3.zero()]),
        throwsArgumentError,
      );
    });
  });
}
