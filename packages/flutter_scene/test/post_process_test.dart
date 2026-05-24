import 'package:flutter_scene/src/post_process/post_process.dart';
import 'package:flutter_scene/src/render/resolve_info.dart';
import 'package:flutter_scene/src/tone_mapping.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  group('ColorGradingSettings', () {
    test('defaults are neutral', () {
      final grading = ColorGradingSettings();
      expect(grading.enabled, isFalse);
      expect(grading.brightness, 1.0);
      expect(grading.contrast, 1.0);
      expect(grading.saturation, 1.0);
      expect(grading.temperature, 0.0);
      expect(grading.tint, 0.0);
      expect(grading.lift.x, 0.0);
      expect(grading.lift.y, 0.0);
      expect(grading.lift.z, 0.0);
      expect(grading.gamma.x, 1.0);
      expect(grading.gamma.y, 1.0);
      expect(grading.gamma.z, 1.0);
      expect(grading.gain.x, 1.0);
      expect(grading.gain.y, 1.0);
      expect(grading.gain.z, 1.0);
    });
  });

  group('PostProcessSettings', () {
    test('color grading is off by default', () {
      expect(PostProcessSettings().colorGrading.enabled, isFalse);
    });
  });

  group('packResolveInfo', () {
    test('produces the std140 float count', () {
      final info = packResolveInfo(
        exposure: 1.0,
        toneMappingMode: ToneMappingMode.pbrNeutral,
        flipY: false,
        grading: ColorGradingSettings(),
      );
      expect(info.length, kResolveInfoFloatCount);
    });

    test('packs the resolve controls', () {
      final info = packResolveInfo(
        exposure: 2.5,
        toneMappingMode: ToneMappingMode.reinhard,
        flipY: true,
        grading: ColorGradingSettings(),
      );
      expect(info[0], 2.5);
      expect(info[1], ToneMappingMode.reinhard.index.toDouble());
      expect(info[2], 1.0);
      expect(info[3], 0.0);
    });

    test('flipY false packs zero', () {
      final info = packResolveInfo(
        exposure: 1.0,
        toneMappingMode: ToneMappingMode.pbrNeutral,
        flipY: false,
        grading: ColorGradingSettings(),
      );
      expect(info[2], 0.0);
    });

    test('packs grading fields at their std140 slots', () {
      final grading =
          ColorGradingSettings()
            ..enabled = true
            ..brightness = 1.1
            ..contrast = 1.2
            ..saturation = 0.9
            ..temperature = 0.3
            ..tint = -0.2
            ..lift = Vector3(0.01, 0.02, 0.03)
            ..gamma = Vector3(1.1, 1.2, 1.3)
            ..gain = Vector3(0.8, 0.9, 1.0);
      final info = packResolveInfo(
        exposure: 1.0,
        toneMappingMode: ToneMappingMode.pbrNeutral,
        flipY: false,
        grading: grading,
      );

      expect(info[3], 1.0);
      expect(info[4], closeTo(1.1, 1e-6));
      expect(info[5], closeTo(1.2, 1e-6));
      expect(info[6], closeTo(0.9, 1e-6));
      expect(info[7], closeTo(0.3, 1e-6));
      expect(info[8], closeTo(-0.2, 1e-6));

      // Padding floats stay zero.
      expect(info[9], 0.0);
      expect(info[10], 0.0);
      expect(info[11], 0.0);
      expect(info[15], 0.0);
      expect(info[19], 0.0);
      expect(info[23], 0.0);

      // lift / gamma / gain land at the start of their rows.
      expect(info[12], closeTo(0.01, 1e-6));
      expect(info[13], closeTo(0.02, 1e-6));
      expect(info[14], closeTo(0.03, 1e-6));
      expect(info[16], closeTo(1.1, 1e-6));
      expect(info[17], closeTo(1.2, 1e-6));
      expect(info[18], closeTo(1.3, 1e-6));
      expect(info[20], closeTo(0.8, 1e-6));
      expect(info[21], closeTo(0.9, 1e-6));
      expect(info[22], closeTo(1.0, 1e-6));
    });
  });
}
