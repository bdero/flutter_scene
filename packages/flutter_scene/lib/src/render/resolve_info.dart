import 'dart:typed_data';
import 'dart:math' as math;

import 'package:flutter_scene/src/post_process/post_process.dart';
import 'package:flutter_scene/src/tone_mapping.dart';

/// Number of floats in the `ResolveInfo` uniform block: eleven std140 rows
/// of four floats each.
const int kResolveInfoFloatCount = 48;

/// Packs the resolve pass's `ResolveInfo` uniform block.
///
/// The layout matches the std140 block in `flutter_scene_resolve.frag`.
/// `vec3` grading channels are stored as the first three floats of a
/// 16-byte row so the packing is straightforward. Kept as a pure function
/// so it can be unit tested without a GPU context.
///
/// [time] is a wall-clock seconds value used to animate film grain.
Float32List packResolveInfo({
  required double exposure,
  required ToneMappingMode toneMappingMode,
  double agxWhite = 16.29,
  double agxContrast = 1.25,
  required bool flipY,
  required double time,
  required PostProcessSettings settings,
}) {
  final grading = settings.colorGrading;
  final aberration = settings.chromaticAberration;
  final vignette = settings.vignette;
  final grain = settings.filmGrain;
  final bloom = settings.bloom;

  final info = Float32List(kResolveInfoFloatCount);

  // Row 0: resolve controls.
  info[0] = exposure;
  info[1] = toneMappingMode.index.toDouble();
  info[2] = flipY ? 1.0 : 0.0;
  info[3] = grading.enabled ? 1.0 : 0.0;

  // Row 1: scalar grading controls.
  info[4] = grading.brightness;
  info[5] = grading.contrast;
  info[6] = grading.saturation;
  info[7] = grading.temperature;

  // Row 2: tint, then padding.
  info[8] = grading.tint;

  // Row 3: lift (xyz), then padding.
  info[12] = grading.lift.x;
  info[13] = grading.lift.y;
  info[14] = grading.lift.z;

  // Row 4: gamma (xyz), then padding.
  info[16] = grading.gamma.x;
  info[17] = grading.gamma.y;
  info[18] = grading.gamma.z;

  // Row 5: gain (xyz), then padding.
  info[20] = grading.gain.x;
  info[21] = grading.gain.y;
  info[22] = grading.gain.z;

  // Row 6: chromatic aberration, then time.
  info[24] = aberration.enabled ? 1.0 : 0.0;
  info[25] = aberration.intensity;
  info[26] = time;

  // Row 7: vignette.
  info[28] = vignette.enabled ? 1.0 : 0.0;
  info[29] = vignette.intensity;
  info[30] = vignette.radius;
  info[31] = vignette.smoothness;

  // Row 8: film grain, then padding.
  info[32] = grain.enabled ? 1.0 : 0.0;
  info[33] = grain.intensity;

  // Row 9: bloom, then padding.
  info[36] = bloom.enabled ? 1.0 : 0.0;
  info[37] = bloom.intensity;

  // Row 10: AgX curve parameters.
  const crossover = 0.18;
  const shoulderMax = 1.0 - crossover;
  final contrast = math.max(agxContrast, 0.01);
  final white = math.max(agxWhite, 2.0);
  final crossoverPower = math.pow(crossover, contrast).toDouble();
  final toeA = (1.0 / crossover - 1.0) * crossoverPower;
  final slopeDenominator = crossoverPower + toeA;
  final slope =
      contrast *
      math.pow(crossover, contrast - 1.0) *
      toeA /
      (slopeDenominator * slopeDenominator);
  final shoulderWidth = white - crossover;
  info[40] = contrast;
  info[41] = toeA;
  info[42] = slope;
  info[43] = shoulderWidth * shoulderWidth / shoulderMax * slope;

  // Row 11: the grading LUT. x is the blend (0 disables), y the cube edge
  // length.
  final lut = grading.lut;
  info[44] = lut != null ? grading.lutBlend.clamp(0.0, 1.0) : 0.0;
  info[45] = lut?.size.toDouble() ?? 0.0;

  return info;
}
