import 'dart:math' as math;

import 'package:flutter_scene/src/auto_exposure.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AutoExposureSettings', () {
    test('defaults', () {
      final settings = AutoExposureSettings();
      expect(settings.enabled, isFalse);
      expect(settings.strength, 0.55);
      expect(settings.compensation, 0.0);
      expect(settings.minEv, -1.0);
      expect(settings.maxEv, 1.3);
      expect(settings.speedUp, 3.0);
      expect(settings.speedDown, 1.0);
    });

    test('reset is a one-shot request', () {
      final settings = AutoExposureSettings();
      expect(settings.takeResetRequest(), isFalse);
      settings.reset();
      expect(settings.takeResetRequest(), isTrue);
      expect(settings.takeResetRequest(), isFalse);
    });
  });

  group('autoExposureTargetFactor', () {
    test('a scene metering at the reference needs no correction', () {
      final factor = autoExposureTargetFactor(
        meanLogLuminance: math.log(kAutoExposureReferenceLuminance),
        settings: AutoExposureSettings(),
      );
      expect(factor, closeTo(1.0, 1e-9));
    });

    test('full strength fully corrects to the reference', () {
      final settings = AutoExposureSettings()..strength = 1.0;
      const luminance = 0.09;
      final factor = autoExposureTargetFactor(
        meanLogLuminance: math.log(luminance),
        settings: settings,
      );
      expect(
        factor,
        closeTo(kAutoExposureReferenceLuminance / luminance, 1e-9),
      );
    });

    test('partial strength corrects partially', () {
      final settings = AutoExposureSettings()..strength = 0.5;
      const luminance = 0.045; // Two stops under the reference.
      final factor = autoExposureTargetFactor(
        meanLogLuminance: math.log(luminance),
        settings: settings,
      );
      // Half of a 4x correction in log space is 2x.
      expect(factor, closeTo(2.0, 1e-9));
    });

    test('compensation shifts the target in stops', () {
      final base = AutoExposureSettings()..maxEv = 10.0;
      final compensated = AutoExposureSettings()
        ..maxEv = 10.0
        ..compensation = 1.0;
      final logLuminance = math.log(0.09);
      expect(
        autoExposureTargetFactor(
          meanLogLuminance: logLuminance,
          settings: compensated,
        ),
        closeTo(
          2.0 *
              autoExposureTargetFactor(
                meanLogLuminance: logLuminance,
                settings: base,
              ),
          1e-9,
        ),
      );
    });

    test('a dark scene clamps to maxEv', () {
      final factor = autoExposureTargetFactor(
        meanLogLuminance: math.log(1e-4),
        settings: AutoExposureSettings(),
      );
      expect(factor, closeTo(math.pow(2.0, 1.3), 1e-9));
    });

    test('a bright scene clamps to minEv', () {
      final factor = autoExposureTargetFactor(
        meanLogLuminance: math.log(50.0),
        settings: AutoExposureSettings(),
      );
      expect(factor, closeTo(0.5, 1e-9));
    });
  });

  group('autoExposureBlend', () {
    test('zero dt holds the previous value', () {
      expect(autoExposureBlend(deltaSeconds: 0.0, speed: 3.0), 0.0);
    });

    test('a long step converges on the target', () {
      expect(
        autoExposureBlend(deltaSeconds: 10.0, speed: 3.0),
        closeTo(1.0, 1e-9),
      );
    });

    test('matches the exponential ease', () {
      expect(
        autoExposureBlend(deltaSeconds: 1 / 60, speed: 3.0),
        closeTo(1.0 - math.exp(-3.0 / 60), 1e-12),
      );
    });

    test('a faster speed blends further per step', () {
      final up = autoExposureBlend(deltaSeconds: 1 / 60, speed: 3.0);
      final down = autoExposureBlend(deltaSeconds: 1 / 60, speed: 1.0);
      expect(up, greaterThan(down));
    });
  });
}
