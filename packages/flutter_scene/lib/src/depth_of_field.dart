import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show internal;

/// Depth-of-field quality tiers, trading gather taps and cleanup passes for
/// frame time. See [DepthOfField.quality].
/// {@category Rendering}
enum DepthOfFieldQuality {
  /// 16 gather taps and no postfilter. The web/mobile tier.
  low,

  /// 32 gather taps plus the noise-smoothing postfilter. The default.
  medium,

  /// 48 gather taps plus the postfilter.
  high,
}

/// Depth-of-field settings for a `Scene` (`scene.depthOfField`), disabled by
/// default.
///
/// When enabled, out-of-focus geometry blurs with a bokeh look, driven by a
/// thin-lens camera model. Focus is always [focusDistance] (world units,
/// treated as meters by the lens math); the blur amount comes from the
/// physical lens parameters ([fStop], [focalLength], [sensorHeight]) times
/// the artistic [blurScale]. The bokeh's aperture shape is controlled with
/// [bladeCount], [bladeRotation], and [bladeCurvature].
///
/// The effect renders as half-resolution fragment passes on the linear HDR
/// scene color before bloom, and forces the camera depth prepass while
/// enabled. Translucent surfaces blur by the opaque depth behind them (the
/// standard post-process depth-of-field caveat). Requires a perspective
/// camera.
/// {@category Rendering}
class DepthOfField {
  /// Whether depth of field renders. Off by default; when off, the engine
  /// adds no passes and the feature costs nothing.
  bool enabled = false;

  /// Distance to the focus plane in world units.
  double focusDistance = 10.0;

  /// The aperture f-number. Smaller stops (1.4, 2.8) give a shallower depth
  /// of field and larger bokeh; the aperture diameter is
  /// [focalLength] / [fStop]. Uses the same vocabulary as
  /// `Scene.physicalCameraExposure` so one set of camera numbers can drive
  /// exposure and blur.
  double fStop = 2.8;

  /// Lens focal length in meters (0.05 is a classic 50 mm). 0 (the default)
  /// derives it from the camera's vertical field of view and [sensorHeight],
  /// so zooming the camera changes the blur physically.
  double focalLength = 0.0;

  /// Simulated sensor height in meters. The default 0.024 is a full-frame
  /// 24 mm sensor.
  double sensorHeight = 0.024;

  /// Artistic multiplier on the physically computed blur. 1 is physical.
  double blurScale = 1.0;

  /// Clamps on the blur radius, in half-resolution pixels, for the near and
  /// far fields. Larger values blur more but cost more and undersample
  /// sooner.
  double maxForegroundBlur = 24.0;
  double maxBackgroundBlur = 32.0;

  /// Aperture blade count shaping the bokeh. 0 (or anything below 3) keeps a
  /// perfect circle; 5..9 give the classic polygonal irises.
  int bladeCount = 0;

  /// Rotation of the aperture polygon in radians.
  double bladeRotation = 0.0;

  /// How rounded the aperture polygon is. 1 is fully circular (the blade
  /// count stops mattering), 0 is a hard polygon.
  double bladeCurvature = 0.0;

  /// Gather quality tier; see [DepthOfFieldQuality].
  DepthOfFieldQuality quality = DepthOfFieldQuality.medium;

  /// The lens focal length in meters for a camera with [fovRadiansY],
  /// honoring an explicit [focalLength] override.
  @internal
  double resolveFocalLength(double fovRadiansY) => focalLength > 0
      ? focalLength
      : 0.5 * sensorHeight / math.tan(0.5 * fovRadiansY);

  /// The CoC scale K, in target pixels of radius per unit of `(1 - S/d)`,
  /// for a target [heightPixels] tall. The shader evaluates
  /// `coc = K * (1 - S / depth)`, the thin-lens circle of confusion with the
  /// constant part folded in (`c = (A*f/(S-f)) * |d-S|/d` sensor-space
  /// diameter, halved for radius, scaled to pixels).
  @internal
  double cocScale(double fovRadiansY, double heightPixels) {
    final f = resolveFocalLength(fovRadiansY);
    final s = math.max(focusDistance, f * 1.01);
    final aperture = f / math.max(fStop, 0.1);
    final sensorDiameter = aperture * f / (s - f);
    return sensorDiameter / sensorHeight * heightPixels * 0.5 * blurScale;
  }

  /// The number of gather taps for [quality] (a multiple of 2; the shader
  /// consumes them as vec4 pairs).
  @internal
  int get tapCount => switch (quality) {
    DepthOfFieldQuality.low => 16,
    DepthOfFieldQuality.medium => 32,
    DepthOfFieldQuality.high => 48,
  };

  /// Whether the noise-smoothing postfilter pass runs.
  @internal
  bool get usePostFilter => quality != DepthOfFieldQuality.low;

  /// The packed `GatherInfo` uniform block for a half-res target of the given
  /// size, memoized against the kernel-shaping parameters so steady-state
  /// frames reuse one buffer (the render pass is rebuilt every frame; this
  /// object persists).
  @internal
  Float32List gatherInfoBlock(int halfWidth, int halfHeight) {
    final key = (
      bladeCount,
      bladeRotation,
      bladeCurvature,
      tapCount,
      halfWidth,
      halfHeight,
    );
    final cached = _gatherInfoCache;
    if (cached != null && _gatherInfoKey == key) return cached;
    final taps = buildKernel();
    final info = Float32List(4 + 24 * 4);
    info[0] = (tapCount / 2).floorToDouble();
    info[1] = 1.0 / halfWidth;
    info[2] = 1.0 / halfHeight;
    for (var i = 0; i < taps.length && i < 24 * 4; i++) {
      info[4 + i] = taps[i];
    }
    _gatherInfoCache = info;
    _gatherInfoKey = key;
    return info;
  }

  Float32List? _gatherInfoCache;
  (int, double, double, int, int, int)? _gatherInfoKey;

  /// Builds the unit-disc gather kernel, a Vogel spiral warped to the
  /// aperture polygon ([bladeCount]/[bladeRotation]/[bladeCurvature]), packed
  /// as consecutive (x, y) pairs.
  @internal
  Float32List buildKernel() {
    const goldenAngle = 2.399963229728653;
    final count = tapCount;
    final taps = Float32List(count * 2);
    final blades = bladeCount;
    for (var i = 0; i < count; i++) {
      var r = math.sqrt((i + 0.5) / count);
      final theta = i * goldenAngle + bladeRotation;
      if (blades >= 3 && bladeCurvature < 1.0) {
        // Polygon SDF warp: the radius of an N-gon (relative to its
        // circumcircle) in this tap's direction, faded by the curvature.
        final sector = 2.0 * math.pi / blades;
        final local = (theta - bladeRotation) % sector;
        final polygon =
            math.cos(math.pi / blades) / math.cos(local - sector / 2.0);
        r *= math.pow(polygon, 1.0 - bladeCurvature).toDouble();
      }
      taps[i * 2] = r * math.cos(theta);
      taps[i * 2 + 1] = r * math.sin(theta);
    }
    return taps;
  }
}
