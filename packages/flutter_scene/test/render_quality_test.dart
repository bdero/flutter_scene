// Covers the adaptive quality controller's state machine (pure Dart) and the
// tier ladder it steps through.

import 'package:flutter/foundation.dart';
import 'package:flutter_scene/src/global_illumination.dart';
import 'package:flutter_scene/src/render/render_quality.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const window = AdaptiveQualityController.windowFrames;

  AdaptiveQualityController controller({
    double target = 60,
    double min = 0.5,
    bool tiers = true,
    bool gi = true,
  }) => AdaptiveQualityController(
    RenderQualitySettings(
      adaptive: true,
      targetFrameRate: target,
      minRenderScale: min,
      adaptiveTiers: tiers,
      adaptiveGlobalIllumination: gi,
    ),
  )..reset();

  void feed(
    AdaptiveQualityController c,
    double seconds,
    int frames, {
    int giSteps = 0,
  }) {
    for (var i = 0; i < frames; i++) {
      c.update(seconds, globalIlluminationSteps: giSteps);
    }
  }

  test('frames within budget leave the scale alone', () {
    final c = controller();
    feed(c, 1 / 60, window * 3);
    expect(c.scale, 1.0);
    expect(c.tierSteps, 0);
  });

  test('overrunning frames step the scale down once per window', () {
    final c = controller();
    feed(c, 1 / 30, window - 1);
    expect(c.scale, 1.0);
    c.update(1 / 30);
    expect(c.scale, closeTo(0.85, 1e-9));
    feed(c, 1 / 30, window);
    expect(c.scale, closeTo(0.85 * 0.85, 1e-9));
  });

  test('the scale bottoms out, then the tier steps down at that scale', () {
    final c = controller(min: 0.8);
    feed(c, 1 / 30, window);
    expect(c.scale, closeTo(0.85, 1e-9));
    feed(c, 1 / 30, window);
    expect(c.scale, 0.8);
    feed(c, 1 / 30, window);
    expect(c.tierSteps, 1);
    expect(c.scale, 0.8, reason: 'a tier step keeps the output size');
    expect(c.effectiveTier(RenderQualityTier.high), RenderQualityTier.medium);
    feed(c, 1 / 30, window);
    expect(c.tierSteps, 2);
    feed(c, 1 / 30, window * 6);
    expect(c.tierSteps, 2, reason: 'never below the lowest tier');
    expect(c.scale, 0.8);
    expect(c.effectiveTier(RenderQualityTier.high), RenderQualityTier.low);
  });

  test('tier steps are clamped to the base tier', () {
    final c = controller(min: 1.0);
    feed(c, 1 / 30, window * 2);
    expect(c.tierSteps, 2);
    expect(c.effectiveTier(RenderQualityTier.medium), RenderQualityTier.low);
    expect(c.effectiveTier(RenderQualityTier.low), RenderQualityTier.low);
  });

  test('adaptiveTiers false keeps the tier and only scales', () {
    final c = controller(min: 0.9, tiers: false);
    feed(c, 1 / 30, window * 5);
    expect(c.scale, 0.9);
    expect(c.tierSteps, 0);
  });

  test(
    'recovery waits out the cooldown, then climbs while frames are fast',
    () {
      final c = controller();
      feed(c, 1 / 30, window);
      expect(c.scale, closeTo(0.85, 1e-9));
      // Fast frames during the cooldown do nothing.
      feed(c, 1 / 120, window * AdaptiveQualityController.cooldownWindows);
      expect(c.scale, closeTo(0.85, 1e-9));
      feed(c, 1 / 120, window);
      expect(c.scale, 1.0);
    },
  );

  test('a tier recovers after a run of fast windows at full scale', () {
    final c = controller(min: 1.0);
    feed(c, 1 / 30, window);
    expect(c.tierSteps, 1);
    feed(c, 1 / 120, window * AdaptiveQualityController.cooldownWindows);
    feed(
      c,
      1 / 120,
      window * (AdaptiveQualityController.tierRecoveryWindows - 1),
    );
    expect(c.tierSteps, 1);
    feed(c, 1 / 120, window);
    expect(c.tierSteps, 0);
  });

  test('a pause is not a slow frame', () {
    final c = controller();
    feed(c, 1 / 30, window - 1);
    c.update(2.0);
    feed(c, 1 / 60, window);
    expect(c.scale, 1.0);
  });

  test('frames at the refresh period recover', () {
    // Vsync caps frames at the target, so keeping it is the only headroom
    // signal there is.
    final c = controller();
    feed(c, 1 / 30, window);
    feed(c, 1 / 60, window * (AdaptiveQualityController.cooldownWindows + 1));
    expect(c.scale, 1.0);
  });

  test('frames between budget and overrun hold steady', () {
    final c = controller();
    feed(c, 1 / 30, window);
    feed(c, 1.08 / 60, window * 20);
    expect(c.scale, closeTo(0.85, 1e-9));
  });

  test('a step up that overruns at once backs off the next probe', () {
    // A load that fits 0.85 but overruns at full scale: every probe up fails.
    final c = controller();
    final stepUps = <int>[];
    for (var w = 0; w < 400; w++) {
      final before = c.scale;
      feed(c, c.scale > 0.9 ? 1 / 30 : 1 / 60, window);
      if (c.scale > before) stepUps.add(w);
    }
    final gaps = [
      for (var i = 1; i < stepUps.length; i++) stepUps[i] - stepUps[i - 1],
    ];
    expect(gaps.length, greaterThan(2));
    expect(gaps[1], greaterThan(gaps[0]));
    expect(gaps[2], greaterThan(gaps[1]));
    expect(
      gaps.last,
      lessThanOrEqualTo(AdaptiveQualityController.maxCooldownWindows + 2),
    );
    expect(stepUps.length, lessThan(10), reason: 'the size settles');
  });

  test('a step up that holds resets the backoff', () {
    final c = controller();
    // Two failed probes grow the backoff.
    for (var w = 0; w < 30; w++) {
      feed(c, c.scale > 0.9 ? 1 / 30 : 1 / 60, window);
    }
    // The load lifts; the next probe holds and recovery is prompt again.
    feed(c, 1 / 60, window * AdaptiveQualityController.maxCooldownWindows);
    expect(c.scale, 1.0);
    feed(c, 1 / 30, window);
    expect(c.scale, closeTo(0.85, 1e-9));
    feed(c, 1 / 60, window * (AdaptiveQualityController.cooldownWindows + 1));
    expect(c.scale, 1.0);
  });

  test('global illumination steps come before the scale', () {
    final c = controller();
    feed(c, 1 / 30, window, giSteps: 3);
    expect(c.globalIlluminationSteps, 1);
    expect(c.scale, 1.0);
    feed(c, 1 / 30, window * 2, giSteps: 3);
    expect(c.globalIlluminationSteps, 3);
    expect(c.scale, 1.0);
    feed(c, 1 / 30, window, giSteps: 3);
    expect(c.globalIlluminationSteps, 3);
    expect(c.scale, closeTo(0.85, 1e-9));
  });

  test('global illumination recovers after the scale and tier', () {
    final c = controller(min: 1.0);
    feed(c, 1 / 30, window * 2, giSteps: 1);
    expect(c.globalIlluminationSteps, 1);
    expect(c.tierSteps, 1);
    feed(
      c,
      1 / 120,
      window * AdaptiveQualityController.cooldownWindows,
      giSteps: 1,
    );
    feed(
      c,
      1 / 120,
      window * AdaptiveQualityController.tierRecoveryWindows,
      giSteps: 1,
    );
    expect(c.tierSteps, 0);
    expect(c.globalIlluminationSteps, 1);
    feed(
      c,
      1 / 120,
      window * AdaptiveQualityController.tierRecoveryWindows,
      giSteps: 1,
    );
    expect(c.globalIlluminationSteps, 0);
  });

  test('global illumination steps clamp to what the field offers', () {
    final c = controller();
    feed(c, 1 / 30, window * 2, giSteps: 2);
    expect(c.globalIlluminationSteps, 2);
    c.update(1 / 60);
    expect(c.globalIlluminationSteps, 0, reason: 'the field went away');
    final off = controller(gi: false);
    feed(off, 1 / 30, window, giSteps: 3);
    expect(off.globalIlluminationSteps, 0);
    expect(off.scale, closeTo(0.85, 1e-9));
  });

  group('resolveIrradianceFieldQuality', () {
    ({bool sphericalHarmonics, int probeUpdateBudget, int adaptiveSteps})
    resolve({
      IrradianceFieldReceiver receiver = IrradianceFieldReceiver.automatic,
      bool automaticSh = false,
      int budget = 0,
      bool solving = true,
      int steps = 0,
    }) => resolveIrradianceFieldQuality(
      settings: GlobalIlluminationSettings()
        ..receiver = receiver
        ..probeUpdateBudget = budget,
      automaticSh: automaticSh,
      probeCount: 1000,
      solving: solving,
      adaptiveSteps: steps,
    );

    test('explicit receivers ignore the tier', () {
      expect(
        resolve(
          receiver: IrradianceFieldReceiver.full,
          automaticSh: true,
        ).sphericalHarmonics,
        isFalse,
      );
      expect(
        resolve(
          receiver: IrradianceFieldReceiver.sphericalHarmonics,
        ).sphericalHarmonics,
        isTrue,
      );
    });

    test('an automatic receiver takes the first step', () {
      expect(resolve().adaptiveSteps, 3);
      expect(resolve().sphericalHarmonics, isFalse);
      final one = resolve(steps: 1);
      expect(one.sphericalHarmonics, isTrue);
      expect(one.probeUpdateBudget, 0);
      expect(resolve(automaticSh: true).adaptiveSteps, 2);
      expect(resolve(receiver: IrradianceFieldReceiver.full).adaptiveSteps, 2);
    });

    test('later steps halve the refresh', () {
      expect(resolve(steps: 2).probeUpdateBudget, 500);
      expect(resolve(steps: 3).probeUpdateBudget, 250);
      expect(resolve(steps: 9).probeUpdateBudget, 250);
      expect(
        resolve(budget: 300, automaticSh: true, steps: 1).probeUpdateBudget,
        150,
      );
      expect(resolve(budget: 5000).probeUpdateBudget, 0);
    });

    test('a field that is not refreshed offers only the receiver', () {
      expect(resolve(solving: false).adaptiveSteps, 1);
      expect(resolve(solving: false, automaticSh: true).adaptiveSteps, 0);
    });
  });

  test('the automatic receiver follows the tier', () {
    expect(
      automaticReceiverUsesSh(RenderQualityTier.low, platformDefault: false),
      isTrue,
    );
    expect(
      automaticReceiverUsesSh(RenderQualityTier.medium, platformDefault: false),
      isTrue,
    );
    expect(
      automaticReceiverUsesSh(RenderQualityTier.high, platformDefault: false),
      isFalse,
    );
  });

  // VM only, since a browser on an Android phone is not the native build this
  // targets.
  test('Android reads spherical harmonics only at its default tier', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    expect(
      automaticReceiverUsesSh(RenderQualityTier.high, platformDefault: true),
      isTrue,
    );
    expect(
      automaticReceiverUsesSh(RenderQualityTier.high, platformDefault: false),
      isFalse,
      reason: 'an explicit high tier keeps the full receiver',
    );
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(
      automaticReceiverUsesSh(RenderQualityTier.high, platformDefault: true),
      isFalse,
    );
  }, testOn: 'vm');
}
