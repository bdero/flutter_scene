// Covers the adaptive quality controller's state machine (pure Dart) and the
// tier ladder it steps through.

import 'package:flutter_scene/src/render/render_quality.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const window = AdaptiveQualityController.windowFrames;

  AdaptiveQualityController controller({
    double target = 60,
    double min = 0.5,
    bool tiers = true,
  }) => AdaptiveQualityController(
    RenderQualitySettings(
      adaptive: true,
      targetFrameRate: target,
      minRenderScale: min,
      adaptiveTiers: tiers,
    ),
  )..reset();

  void feed(AdaptiveQualityController c, double seconds, int frames) {
    for (var i = 0; i < frames; i++) {
      c.update(seconds);
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
}
