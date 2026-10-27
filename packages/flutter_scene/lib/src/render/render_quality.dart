import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;

/// A coarse rendering budget the scene resolves its automatic settings
/// against: which anti-aliasing `auto` picks and how many scene color
/// captures a frame may open. Settings given explicitly are never changed by
/// the tier.
/// {@category Rendering}
enum RenderQualityTier {
  /// No anti-aliasing and one shared scene color capture. The cheapest frame
  /// the renderer can produce for the same content.
  low,

  /// FXAA and two scene color captures, for GLES-class and integrated GPUs.
  medium,

  /// MSAA where the backend supports it and the full capture budget.
  high,
}

/// Where the scene's automatic settings sit on the quality ladder, and
/// whether the renderer may move them itself when frames run long.
///
/// [tier] left null resolves by platform (web and Linux desktop render
/// through OpenGL ES class backends and start at [RenderQualityTier.medium],
/// everything else at [RenderQualityTier.high]). With [adaptive] on, the
/// scene measures its own frame period and, when frames overrun
/// [targetFrameRate], lowers the render scale toward [minRenderScale] and
/// then, if [adaptiveTiers] allows, steps the tier down at that scale; both
/// recover while frames keep their budget. The adaptive scale multiplies
/// `Scene.renderScale`, so an explicit scale stays the ceiling. Each scale
/// change reallocates the render targets, so the controller steps sparingly.
///
/// Frame period is measured on the UI thread, which a GPU-bound frame stalls
/// the same way, so no GPU timer is needed; it cannot see headroom below the
/// display refresh, so recovery only climbs while frames keep their budget.
/// {@category Rendering}
class RenderQualitySettings {
  RenderQualitySettings({
    this.tier,
    this.adaptive = false,
    this.targetFrameRate = 60.0,
    this.minRenderScale = 0.5,
    this.maxRenderScale = 1.0,
    this.adaptiveTiers = true,
  });

  /// The tier automatic settings resolve against, or null for the platform
  /// default (see the class docs).
  RenderQualityTier? tier;

  /// Whether the renderer adjusts the render scale (and tier) from measured
  /// frame periods.
  bool adaptive;

  /// Frames per second the adaptive controller tries to hold.
  double targetFrameRate;

  /// Lowest render scale the adaptive controller may apply.
  double minRenderScale;

  /// Highest render scale the adaptive controller may apply (its resting
  /// value while frames keep their budget).
  double maxRenderScale;

  /// Whether the adaptive controller may step the tier below the resolved
  /// [tier] once the render scale has bottomed out.
  bool adaptiveTiers;

  /// The tier the platform starts at when [tier] is null.
  static RenderQualityTier get platformDefaultTier {
    if (kIsWeb) return RenderQualityTier.medium;
    return defaultTargetPlatform == TargetPlatform.linux
        ? RenderQualityTier.medium
        : RenderQualityTier.high;
  }
}

/// Frame-period feedback for [RenderQualitySettings.adaptive]: a windowed
/// mean of frame periods steps the render scale down when frames overrun the
/// target and back up when they keep it. A cooldown follows every step down,
/// and doubles each time a step up overruns at once, so a load that sits
/// between two sizes settles instead of alternating.
///
/// Public for tests; not exported.
class AdaptiveQualityController {
  AdaptiveQualityController(this.settings);

  final RenderQualitySettings settings;

  /// Frames per evaluation window.
  static const int windowFrames = 30;

  /// Windows to wait after a step down before stepping up again.
  static const int cooldownWindows = 4;

  /// The longest wait the cooldown backs off to.
  static const int maxCooldownWindows = 64;

  /// Windows a step up must hold before its headroom counts as real. One
  /// that overruns sooner doubles the cooldown, up to [maxCooldownWindows].
  static const int probeWindows = 2;

  /// Consecutive fast windows at the top scale before a tier steps back up.
  static const int tierRecoveryWindows = 6;

  /// A frame period this long means the app paused, not that it is slow.
  static const double pauseSeconds = 0.5;

  static const double _stepDown = 0.85;

  double _scale = 1.0;
  int _tierSteps = 0;
  double _windowSeconds = 0;
  int _windowFrames = 0;
  int _cooldown = 0;
  int _fastStreak = 0;
  int _backoff = cooldownWindows;

  /// Windows since the last step up, or -1 once it has held.
  int _sinceStepUp = -1;

  /// The render scale multiplier currently applied.
  double get scale => _scale;

  /// How many tiers below the resolved tier the controller has stepped.
  int get tierSteps => _tierSteps;

  /// The tier to render with, [base] lowered by [tierSteps].
  RenderQualityTier effectiveTier(RenderQualityTier base) {
    final index = (base.index - _tierSteps).clamp(0, base.index);
    return RenderQualityTier.values[index];
  }

  /// Forgets every adjustment and measurement.
  void reset() {
    _scale = settings.maxRenderScale;
    _tierSteps = 0;
    _windowSeconds = 0;
    _windowFrames = 0;
    _cooldown = 0;
    _fastStreak = 0;
    _backoff = cooldownWindows;
    _sinceStepUp = -1;
  }

  /// Feeds one frame period. Returns true when the scale or tier changed.
  bool update(double frameSeconds) {
    if (frameSeconds <= 0 || frameSeconds >= pauseSeconds) {
      _windowSeconds = 0;
      _windowFrames = 0;
      return false;
    }
    _windowSeconds += frameSeconds;
    _windowFrames++;
    if (_windowFrames < windowFrames) return false;
    final mean = _windowSeconds / _windowFrames;
    _windowSeconds = 0;
    _windowFrames = 0;
    final target = 1.0 / settings.targetFrameRate;
    if (_sinceStepUp >= 0 && ++_sinceStepUp > probeWindows) {
      // The last step up held, so the headroom was real.
      _sinceStepUp = -1;
      _backoff = cooldownWindows;
    }
    if (mean > target * 1.1) {
      _fastStreak = 0;
      if (_sinceStepUp >= 0) {
        // A step up that overran at once found no headroom; probe less often.
        _backoff = math.min(_backoff * 2, maxCooldownWindows);
        _sinceStepUp = -1;
      }
      _cooldown = _backoff;
      if (_scale > settings.minRenderScale) {
        _scale = (_scale * _stepDown).clamp(
          settings.minRenderScale,
          settings.maxRenderScale,
        );
        return true;
      }
      if (settings.adaptiveTiers &&
          _tierSteps < RenderQualityTier.values.length - 1) {
        // The scale stays at its floor, so the output size does not change.
        _tierSteps++;
        return true;
      }
      return false;
    }
    if (_cooldown > 0) {
      _cooldown--;
      return false;
    }
    // A UI-thread period cannot drop below the display refresh, so keeping
    // the budget is the only sign of headroom; a step up is a probe.
    if (mean > target * 1.05) {
      _fastStreak = 0;
      return false;
    }
    if (_scale < settings.maxRenderScale) {
      _scale = (_scale / _stepDown).clamp(
        settings.minRenderScale,
        settings.maxRenderScale,
      );
      _sinceStepUp = 0;
      return true;
    }
    if (_tierSteps > 0 && ++_fastStreak >= tierRecoveryWindows) {
      _fastStreak = 0;
      _tierSteps--;
      _sinceStepUp = 0;
      return true;
    }
    return false;
  }
}
