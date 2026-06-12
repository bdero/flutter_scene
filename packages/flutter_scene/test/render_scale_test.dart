// Covers the render-scale and composite-filter settings: defaults, the
// scene-default/per-view-override pattern, and (GPU-gated) that the scale
// actually drives the screen view's swapchain resolution.

import 'dart:ui' as ui;

import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

bool _gpuAvailable() {
  try {
    Scene();
    return true;
  } catch (_) {
    return false;
  }
}

void main() {
  test('RenderView scale and filter default to inherit (null)', () {
    final view = RenderView(camera: PerspectiveCamera());
    expect(view.renderScale, isNull);
    expect(view.filterQuality, isNull);
  });

  test('RenderView rejects a non-positive renderScale', () {
    expect(
      () => RenderView(camera: PerspectiveCamera(), renderScale: 0.0),
      throwsAssertionError,
    );
  });

  if (!_gpuAvailable()) {
    test(
      'render scale suite (skipped: no GPU device)',
      () {},
      skip: 'Requires a GPU device.',
    );
    return;
  }

  test('scene defaults', () {
    final scene = Scene();
    expect(scene.renderScale, 1.0);
    expect(scene.filterQuality, ui.FilterQuality.medium);
    expect(() => scene.renderScale = 0.0, throwsAssertionError);
  });

  testWidgets('renderScale drives the swapchain resolution', (tester) async {
    await Scene.initializeStaticResources();

    final scene = Scene();
    scene.renderScale = 0.5;

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    scene.render(
      PerspectiveCamera(position: Vector3(0, 0, 5)),
      canvas,
      viewport: const ui.Rect.fromLTWH(0, 0, 32, 32),
      pixelRatio: 1.0,
    );
    recorder.endRecording();

    final swapchain = scene.surface.lastSwapchainColorTexture();
    expect(swapchain, isNotNull);
    expect(swapchain!.width, 16);
    expect(swapchain.height, 16);
  });

  testWidgets('per-view renderScale overrides the scene default', (
    tester,
  ) async {
    await Scene.initializeStaticResources();

    final scene = Scene();
    scene.renderScale = 0.5;

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    scene.renderViews(
      [
        RenderView(
          camera: PerspectiveCamera(position: Vector3(0, 0, 5)),
          renderScale: 2.0,
        ),
      ],
      canvas,
      region: const ui.Rect.fromLTWH(0, 0, 32, 32),
      pixelRatio: 1.0,
    );
    recorder.endRecording();

    final swapchain = scene.surface.lastSwapchainColorTexture();
    expect(swapchain, isNotNull);
    expect(swapchain!.width, 64);
    expect(swapchain.height, 64);
  });
}
