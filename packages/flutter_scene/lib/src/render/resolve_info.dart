import 'dart:typed_data';

import 'package:flutter_scene/src/post_process/post_process.dart';
import 'package:flutter_scene/src/tone_mapping.dart';

/// Number of floats in the `ResolveInfo` uniform block: six std140 rows
/// of four floats each.
const int kResolveInfoFloatCount = 24;

/// Packs the resolve pass's `ResolveInfo` uniform block.
///
/// The layout matches the std140 block in `flutter_scene_resolve.frag`.
/// `vec3` grading channels are stored as the first three floats of a
/// 16-byte row so the packing is straightforward. Kept as a pure function
/// so it can be unit tested without a GPU context.
Float32List packResolveInfo({
  required double exposure,
  required ToneMappingMode toneMappingMode,
  required bool flipY,
  required ColorGradingSettings grading,
}) {
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

  return info;
}
