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

  group('overlay settings defaults', () {
    test('chromatic aberration', () {
      final aberration = ChromaticAberrationSettings();
      expect(aberration.enabled, isFalse);
      expect(aberration.intensity, 0.5);
    });

    test('vignette', () {
      final vignette = VignetteSettings();
      expect(vignette.enabled, isFalse);
      expect(vignette.intensity, 0.5);
      expect(vignette.radius, 0.75);
      expect(vignette.smoothness, 0.5);
    });

    test('film grain', () {
      final grain = FilmGrainSettings();
      expect(grain.enabled, isFalse);
      expect(grain.intensity, 0.3);
    });

    test('bloom', () {
      final bloom = BloomSettings();
      expect(bloom.enabled, isFalse);
      expect(bloom.threshold, 1.0);
      expect(bloom.intensity, 0.5);
      expect(bloom.scatter, 0.7);
    });
  });

  group('PostProcessSettings', () {
    test('every effect is off by default', () {
      final settings = PostProcessSettings();
      expect(settings.colorGrading.enabled, isFalse);
      expect(settings.chromaticAberration.enabled, isFalse);
      expect(settings.vignette.enabled, isFalse);
      expect(settings.filmGrain.enabled, isFalse);
      expect(settings.bloom.enabled, isFalse);
    });
  });

  group('packResolveInfo', () {
    test('produces the std140 float count', () {
      final info = packResolveInfo(
        exposure: 1.0,
        toneMappingMode: ToneMappingMode.pbrNeutral,
        flipY: false,
        time: 0.0,
        settings: PostProcessSettings(),
      );
      expect(info.length, kResolveInfoFloatCount);
      expect(info.length, 40);
    });

    test('packs the resolve controls', () {
      final info = packResolveInfo(
        exposure: 2.5,
        toneMappingMode: ToneMappingMode.reinhard,
        flipY: true,
        time: 0.0,
        settings: PostProcessSettings(),
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
        time: 0.0,
        settings: PostProcessSettings(),
      );
      expect(info[2], 0.0);
    });

    test('packs grading fields at their std140 slots', () {
      final settings = PostProcessSettings();
      settings.colorGrading
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
        time: 0.0,
        settings: settings,
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

    test('packs overlay fields and time at their std140 slots', () {
      final settings = PostProcessSettings();
      settings.chromaticAberration
        ..enabled = true
        ..intensity = 0.7;
      settings.vignette
        ..enabled = true
        ..intensity = 0.6
        ..radius = 0.8
        ..smoothness = 0.3;
      settings.filmGrain
        ..enabled = true
        ..intensity = 0.25;
      settings.bloom
        ..enabled = true
        ..intensity = 0.8;
      final info = packResolveInfo(
        exposure: 1.0,
        toneMappingMode: ToneMappingMode.pbrNeutral,
        flipY: false,
        time: 2.0,
        settings: settings,
      );

      expect(info[24], 1.0);
      expect(info[25], closeTo(0.7, 1e-6));
      expect(info[26], closeTo(2.0, 1e-6));
      expect(info[27], 0.0);
      expect(info[28], 1.0);
      expect(info[29], closeTo(0.6, 1e-6));
      expect(info[30], closeTo(0.8, 1e-6));
      expect(info[31], closeTo(0.3, 1e-6));
      expect(info[32], 1.0);
      expect(info[33], closeTo(0.25, 1e-6));
      expect(info[34], 0.0);
      expect(info[35], 0.0);
      expect(info[36], 1.0);
      expect(info[37], closeTo(0.8, 1e-6));
      expect(info[38], 0.0);
      expect(info[39], 0.0);
    });
  });
}
