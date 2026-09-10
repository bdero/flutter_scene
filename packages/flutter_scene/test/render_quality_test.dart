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

  test('the scale bottoms out, then the tier steps down and scale resets', () {
    final c = controller(min: 0.8);
    feed(c, 1 / 30, window);
    expect(c.scale, closeTo(0.85, 1e-9));
    feed(c, 1 / 30, window);
    expect(c.scale, 0.8);
    feed(c, 1 / 30, window);
    expect(c.tierSteps, 1);
    expect(c.scale, 1.0);
    expect(c.effectiveTier(RenderQualityTier.high), RenderQualityTier.medium);
    // The scale has to bottom out again before the next tier step.
    feed(c, 1 / 30, window * 2);
    expect(c.tierSteps, 1);
    expect(c.scale, 0.8);
    feed(c, 1 / 30, window);
    expect(c.tierSteps, 2);
    feed(c, 1 / 30, window * 6);
    expect(c.tierSteps, 2, reason: 'never below the lowest tier');
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

  test('frames near the refresh period hold steady', () {
    // Vsync-capped frames sit at the target; that is neither slow nor fast.
    final c = controller();
    feed(c, 1 / 30, window);
    feed(c, 1 / 60, window * 20);
    expect(c.scale, closeTo(0.85, 1e-9));
  });
}
