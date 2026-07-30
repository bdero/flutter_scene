import 'dart:math' as math;

import 'package:flutter/foundation.dart' show internal;

/// The mid-gray scene luminance the meter drives the image toward, before
/// the scene's base exposure is applied.
const double kAutoExposureReferenceLuminance = 0.18;

/// Automatic exposure (eye adaptation) settings for a [Scene].
///
/// Reachable through `Scene.autoExposure`. When enabled, the engine meters
/// the average luminance of the rendered HDR image each frame and eases a
/// correction factor toward it, so the image brightens in dark surroundings
/// and darkens in bright ones, like eyes adjusting. The factor multiplies on
/// top of `Scene.exposure`, which stays the artistic base (a value derived
/// from `Scene.physicalCameraExposure` keeps working unchanged); the final
/// multiplier applied to the HDR color is `exposure * factor`.
///
/// Metering runs entirely on the GPU (a luminance downsample chain feeding a
/// one-pixel adaptation state), so enabling it adds no readback and works on
/// every backend.
///
/// Disabled by default; a fresh scene meters nothing and renders with
/// [Scene.exposure] alone.
/// {@category Rendering}
class AutoExposureSettings {
  /// Whether auto exposure runs. Off by default. When false the scene adds
  /// no metering passes and the image is unaffected.
  bool enabled = false;

  /// How strongly the metered error is corrected, from `0` (no correction)
  /// to `1` (full correction to the metering target). Partial correction
  /// preserves some of the scene's natural brightness variation, which
  /// usually reads better than a fully flattened image.
  double strength = 0.55;

  /// Exposure compensation in EV stops, applied to the metering target.
  /// `0` is neutral; `+1` doubles the target brightness, `-1` halves it.
  double compensation = 0.0;

  /// The lowest the correction may go, in EV stops relative to the base
  /// exposure. `-1` (the default) lets bright scenes be darkened to half.
  double minEv = -1.0;

  /// The highest the correction may go, in EV stops relative to the base
  /// exposure. `1.3` (the default) lets dark scenes be brightened to about
  /// 2.5x.
  double maxEv = 1.3;

  /// Adaptation rate while the scene gets brighter (the correction falls),
  /// in blends per second. Adapting to brightness is faster than adapting
  /// to darkness by default, matching how eyes behave.
  double speedUp = 3.0;

  /// Adaptation rate while the scene gets darker (the correction rises),
  /// in blends per second.
  double speedDown = 1.0;

  /// Snaps the adaptation to the metered target on the next frame, skipping
  /// the eased transition. Call on camera cuts and teleports so the new shot
  /// does not visibly ramp from the previous shot's adaptation.
  void reset() => _resetPending = true;

  bool _resetPending = false;

  /// Consumes a pending [reset] request. Called once per metered frame by
  /// the auto exposure render pass.
  @internal
  bool takeResetRequest() {
    final pending = _resetPending;
    _resetPending = false;
    return pending;
  }
}

/// The correction factor auto exposure eases toward for a metered mean
/// log-luminance, mirroring the adaptation shader's curve so it can be unit
/// tested without a GPU.
double autoExposureTargetFactor({
  required double meanLogLuminance,
  required AutoExposureSettings settings,
}) {
  final meanLuminance = math.max(math.exp(meanLogLuminance), 1e-6);
  final target =
      math.pow(
        kAutoExposureReferenceLuminance / meanLuminance,
        settings.strength,
      ) *
      _exp2(settings.compensation);
  return target.clamp(_exp2(settings.minEv), _exp2(settings.maxEv));
}

/// The blend weight toward the target after [deltaSeconds] at [speed] blends
/// per second, the exponential-ease step mirrored from the adaptation
/// shader. `0` holds the previous value, `1` lands on the target.
double autoExposureBlend({
  required double deltaSeconds,
  required double speed,
}) => 1.0 - math.exp(-deltaSeconds * speed);

double _exp2(double ev) => math.pow(2.0, ev).toDouble();
