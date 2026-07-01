// Covers RenderTexture: update-policy resolution (everyFrame/interval/
// manual + requestUpdate + resize forcing), the texture lifecycle, and the
// scene integration (a Scene.views entry targeting a texture renders when
// the scene renders). Policy logic is pure Dart; the render integration is
// GPU-gated like the other suites.

import 'dart:ui' as ui;

import 'package:flutter/widgets.dart' show SizedBox;
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
  group('update policy', () {
    final t0 = DateTime(2026, 1, 1);

    test('everyFrame updates every check', () {
      final target = RenderTexture(width: 8, height: 8);
      expect(target.shouldUpdate(t0), isTrue);
      target.markUpdated(t0);
      expect(target.shouldUpdate(t0), isTrue);
    });

    test('interval waits out the duration', () {
      final target = RenderTexture(
        width: 8,
        height: 8,
        update: const RenderTextureUpdate.interval(Duration(seconds: 1)),
      );
      expect(target.shouldUpdate(t0), isTrue);
      target.markUpdated(t0);
      expect(
        target.shouldUpdate(t0.add(const Duration(milliseconds: 500))),
        isFalse,
      );
      expect(target.shouldUpdate(t0.add(const Duration(seconds: 1))), isTrue);
    });

    test('manual renders once, then only on request', () {
      final target = RenderTexture(
        width: 8,
        height: 8,
        update: RenderTextureUpdate.manual,
      );
      expect(target.shouldUpdate(t0), isTrue);
      target.markUpdated(t0);
      expect(target.shouldUpdate(t0), isFalse);
      target.requestUpdate();
      expect(target.shouldUpdate(t0), isTrue);
      expect(target.shouldUpdate(t0), isFalse);
    });

    test('resize forces the next update regardless of policy', () {
      final target = RenderTexture(
        width: 8,
        height: 8,
        update: RenderTextureUpdate.manual,
      );
      target.markUpdated(t0);
      expect(target.shouldUpdate(t0), isFalse);
      target.resize(16, 16);
      expect(target.width, 16);
      expect(target.shouldUpdate(t0), isTrue);
    });

    test('resize to the same size is a no-op', () {
      final target = RenderTexture(
        width: 8,
        height: 8,
        update: RenderTextureUpdate.manual,
      );
      target.markUpdated(t0);
      target.resize(8, 8);
      expect(target.shouldUpdate(t0), isFalse);
    });

    test('markUpdated notifies listeners', () {
      final target = RenderTexture(width: 8, height: 8);
      var notified = 0;
      target.addListener(() => notified++);
      target.markUpdated(t0);
      expect(notified, 1);
    });
  });

  test('texture is null before the first render', () {
    final target = RenderTexture(width: 8, height: 8);
    expect(target.texture, isNull);
  });

  testWidgets('RenderTextureView shows nothing before the first render', (
    tester,
  ) async {
    final target = RenderTexture(width: 8, height: 8);
    await tester.pumpWidget(
      SizedBox(width: 32, height: 32, child: RenderTextureView(target)),
    );
    expect(find.byType(RenderTextureView), findsOneWidget);
  });

  if (!_gpuAvailable()) {
    test(
      'render integration (skipped: no GPU device)',
      () {},
      skip: 'Requires a GPU device.',
    );
    return;
  }

  test('material texture slots accept texture sources', () async {
    await Scene.initializeStaticResources();

    final target = RenderTexture(width: 8, height: 8);
    final pbr = PhysicallyBasedMaterial();

    // The slot holds the source; a render texture with no completed frame
    // yet resolves (internally) to null so the placeholder applies at draw.
    pbr.baseColorTexture = target;
    expect(pbr.baseColorTexture, same(target));
    expect(target.sampledTexture, isNull);

    // A raw GPU texture can be bound via GpuTextureSource.
    final white = GpuTextureSource(Material.getWhitePlaceholderTexture());
    pbr.baseColorTexture = white;
    expect(pbr.baseColorTexture, same(white));

    final unlit = UnlitMaterial();
    unlit.baseColorTexture = target;
    expect(unlit.baseColorTexture, same(target));
  });

  test('texture publishes on markUpdated, not on acquire', () async {
    await Scene.initializeStaticResources();

    final target = RenderTexture(width: 8, height: 8);
    final first = target.acquireNextTexture();
    // Mid-render (acquired but not published), consumers still see the
    // previous frame, which is null before the first completes.
    expect(target.texture, isNull);
    target.markUpdated(DateTime(2026));
    expect(target.texture, same(first));

    final second = target.acquireNextTexture();
    expect(second, isNot(same(first)));
    // The ring's previous frame stays visible while the next is written.
    expect(target.texture, same(first));
    target.markUpdated(DateTime(2026));
    expect(target.texture, same(second));
  });

  testWidgets('a scene-owned texture view renders into its target', (
    tester,
  ) async {
    await Scene.initializeStaticResources();

    final scene = Scene();
    final target = RenderTexture(width: 16, height: 16);
    scene.views.add(
      RenderView(
        camera: PerspectiveCamera(position: Vector3(0, 0, 5)),
        target: target,
        antiAliasingMode: AntiAliasingMode.fxaa,
      ),
    );

    var notified = 0;
    target.addListener(() => notified++);

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    scene.render(
      PerspectiveCamera(position: Vector3(0, 0, 5)),
      canvas,
      viewport: const ui.Rect.fromLTWH(0, 0, 32, 32),
      pixelRatio: 1.0,
    );
    recorder.endRecording();

    expect(target.texture, isNotNull);
    expect(target.texture!.width, 16);
    expect(notified, 1);
  });
}
