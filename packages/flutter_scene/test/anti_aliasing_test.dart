// Covers the anti-aliasing mode API: the auto default, requested vs
// effective resolution, and the support query. GPU-gated like the other
// suites; resolving the effective mode reads backend capabilities, so the
// whole suite skips without a device.

import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';

bool _gpuAvailable() {
  try {
    Scene();
    return true;
  } catch (_) {
    return false;
  }
}

void main() {
  if (!_gpuAvailable()) {
    test(
      'anti-aliasing suite (skipped: no GPU device)',
      () {},
      skip: 'Requires a GPU device.',
    );
    return;
  }

  test('defaults to auto', () {
    final scene = Scene();
    expect(scene.antiAliasingMode, AntiAliasingMode.auto);
  });

  test('effective mode never reports auto', () {
    final scene = Scene();
    for (final mode in AntiAliasingMode.values) {
      scene.antiAliasingMode = mode;
      expect(scene.effectiveAntiAliasingMode, isNot(AntiAliasingMode.auto));
    }
  });

  test('requested mode is kept verbatim', () {
    final scene = Scene();
    for (final mode in AntiAliasingMode.values) {
      scene.antiAliasingMode = mode;
      expect(scene.antiAliasingMode, mode);
    }
  });

  test('smaa resolves to itself on every backend', () {
    final scene = Scene();
    scene.antiAliasingMode = AntiAliasingMode.smaa;
    expect(scene.effectiveAntiAliasingMode, AntiAliasingMode.smaa);
    expect(Scene.isAntiAliasingModeSupported(AntiAliasingMode.smaa), isTrue);
  });

  test('auto resolves to msaa exactly when msaa is supported', () {
    final scene = Scene();
    scene.antiAliasingMode = AntiAliasingMode.auto;
    final expected = Scene.isAntiAliasingModeSupported(AntiAliasingMode.msaa)
        ? AntiAliasingMode.msaa
        : AntiAliasingMode.fxaa;
    expect(scene.effectiveAntiAliasingMode, expected);
  });

  test('msaa request resolves like auto (fxaa fallback when unsupported)', () {
    final scene = Scene();
    scene.antiAliasingMode = AntiAliasingMode.msaa;
    final expected = Scene.isAntiAliasingModeSupported(AntiAliasingMode.msaa)
        ? AntiAliasingMode.msaa
        : AntiAliasingMode.fxaa;
    expect(scene.effectiveAntiAliasingMode, expected);
  });

  test('taa resolves to itself on every backend', () {
    final scene = Scene();
    scene.antiAliasingMode = AntiAliasingMode.taa;
    expect(scene.effectiveAntiAliasingMode, AntiAliasingMode.taa);
    expect(Scene.isAntiAliasingModeSupported(AntiAliasingMode.taa), isTrue);
  });

  test('none and fxaa resolve to themselves', () {
    final scene = Scene();
    scene.antiAliasingMode = AntiAliasingMode.none;
    expect(scene.effectiveAntiAliasingMode, AntiAliasingMode.none);
    scene.antiAliasingMode = AntiAliasingMode.fxaa;
    expect(scene.effectiveAntiAliasingMode, AntiAliasingMode.fxaa);
  });

  test('every mode except msaa is unconditionally supported', () {
    expect(Scene.isAntiAliasingModeSupported(AntiAliasingMode.none), isTrue);
    expect(Scene.isAntiAliasingModeSupported(AntiAliasingMode.fxaa), isTrue);
    expect(Scene.isAntiAliasingModeSupported(AntiAliasingMode.smaa), isTrue);
    expect(Scene.isAntiAliasingModeSupported(AntiAliasingMode.taa), isTrue);
    expect(Scene.isAntiAliasingModeSupported(AntiAliasingMode.auto), isTrue);
  });
}
