// Widget-level tests for SceneView. Scene.render() early-returns until static
// resources are ready (which never completes in a plain `flutter test`), so the
// widget's lifecycle, ticking, camera resolution, and SceneScope plumbing are
// what these exercise, not actual rendering.
//
// Constructing a Scene touches the Flutter GPU context (Impeller), which is not
// available under `flutter test`. These tests skip cleanly when it is absent
// (matching the rest of the suite) and run on a GPU-enabled harness.

import 'package:clock/clock.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// Builds a [Scene], or returns null when no GPU/Impeller context is available.
Scene? _tryScene() {
  try {
    return Scene();
  } catch (_) {
    return null;
  }
}

Widget _sized(Widget child) => Directionality(
  textDirection: TextDirection.ltr,
  child: Center(child: SizedBox(width: 200, height: 200, child: child)),
);

void main() {
  testWidgets('allows at most one of camera, cameraBuilder, or viewsBuilder', (
    tester,
  ) async {
    final scene = _tryScene();
    if (scene == null) {
      markTestSkipped('No Impeller GPU context');
      return;
    }
    // No camera argument falls back to the scene-owned camera.
    expect(() => SceneView(scene), returnsNormally);
    expect(
      () => SceneView(
        scene,
        camera: PerspectiveCamera(),
        cameraBuilder: (_) => PerspectiveCamera(),
      ),
      throwsAssertionError,
    );
  });

  testWidgets('exposes the scene through SceneScope', (tester) async {
    final scene = _tryScene();
    if (scene == null) {
      markTestSkipped('No Impeller GPU context');
      return;
    }
    await tester.pumpWidget(
      _sized(SceneView(scene, camera: PerspectiveCamera())),
    );

    final scope = tester.widget<SceneScope>(find.byType(SceneScope));
    expect(scope.scene, same(scene));
  });

  testWidgets('cameraBuilder receives advancing elapsed time while ticking', (
    tester,
  ) async {
    final scene = _tryScene();
    if (scene == null) {
      markTestSkipped('No Impeller GPU context');
      return;
    }
    final elapsedSamples = <Duration>[];
    await tester.pumpWidget(
      _sized(
        SceneView(
          scene,
          cameraBuilder: (elapsed) {
            elapsedSamples.add(elapsed);
            return PerspectiveCamera(
              position: Vector3(0, 0, 5),
              target: Vector3.zero(),
            );
          },
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));

    expect(elapsedSamples, isNotEmpty);
    expect(elapsedSamples.last, greaterThan(Duration.zero));
  });

  testWidgets('onTick fires with a positive delta after the first frame', (
    tester,
  ) async {
    final scene = _tryScene();
    if (scene == null) {
      markTestSkipped('No Impeller GPU context');
      return;
    }
    final deltas = <double>[];
    await tester.pumpWidget(
      _sized(
        SceneView(
          scene,
          camera: PerspectiveCamera(),
          onTick: (elapsed, deltaSeconds) => deltas.add(deltaSeconds),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));

    expect(deltas, isNotEmpty);
    expect(deltas.any((d) => d > 0), isTrue);
  });

  testWidgets('onTick deltas track the wall clock, not frame timestamps', (
    tester,
  ) async {
    final scene = _tryScene();
    if (scene == null) {
      markTestSkipped('No Impeller GPU context');
      return;
    }
    // A loaded GPU produces frame-begin timestamps that alternate between
    // tiny and double-length deltas while frames present at an even wall
    // cadence. Simulate that split, the injected wall clock advances a
    // steady 42ms per frame while the ticker is pumped 4ms/80ms.
    var now = DateTime(2026);
    final deltas = <double>[];
    await tester.pumpWidget(
      _sized(
        SceneView(
          scene,
          camera: PerspectiveCamera(),
          clock: Clock(() => now),
          onTick: (elapsed, deltaSeconds) => deltas.add(deltaSeconds),
        ),
      ),
    );
    // Prime one tick so a previous wall instant exists (the very first
    // delta falls back to the ticker's single-frame elapsed).
    await tester.pump(const Duration(milliseconds: 16));
    deltas.clear();
    for (var i = 0; i < 8; i++) {
      now = now.add(const Duration(milliseconds: 42));
      await tester.pump(Duration(milliseconds: i.isEven ? 4 : 80));
    }
    expect(deltas, hasLength(8));
    for (final delta in deltas) {
      expect(delta, closeTo(0.042, 0.001));
    }
  });

  testWidgets('maxFrameRate renders every other refresh at half rate', (
    tester,
  ) async {
    final scene = _tryScene();
    if (scene == null) {
      markTestSkipped('No Impeller GPU context');
      return;
    }
    final ticks = <Duration>[];
    await tester.pumpWidget(
      _sized(
        SceneView(
          scene,
          camera: PerspectiveCamera(),
          maxFrameRate: 60,
          onTick: (elapsed, _) => ticks.add(elapsed),
        ),
      ),
    );
    // A 120 Hz display, with a little timestamp jitter.
    for (var i = 0; i < 120; i++) {
      await tester.pump(Duration(microseconds: 8333 + (i % 3 - 1) * 400));
    }
    expect(ticks.length, inInclusiveRange(59, 61));
    for (var i = 2; i < ticks.length; i++) {
      final gap = (ticks[i] - ticks[i - 1]).inMicroseconds;
      expect(gap, inInclusiveRange(15800, 17600));
    }
  });

  testWidgets('maxFrameRate holds its average on a mismatched refresh', (
    tester,
  ) async {
    final scene = _tryScene();
    if (scene == null) {
      markTestSkipped('No Impeller GPU context');
      return;
    }
    var count = 0;
    await tester.pumpWidget(
      _sized(
        SceneView(
          scene,
          camera: PerspectiveCamera(),
          maxFrameRate: 60,
          onTick: (_, __) => count++,
        ),
      ),
    );
    // Two seconds of a 90 Hz display.
    for (var i = 0; i < 180; i++) {
      await tester.pump(const Duration(microseconds: 11111));
    }
    expect(count, inInclusiveRange(118, 122));
  });

  testWidgets('autoTick: false does not tick', (tester) async {
    final scene = _tryScene();
    if (scene == null) {
      markTestSkipped('No Impeller GPU context');
      return;
    }
    var tickCount = 0;
    await tester.pumpWidget(
      _sized(
        SceneView(
          scene,
          camera: PerspectiveCamera(),
          autoTick: false,
          onTick: (_, __) => tickCount++,
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));

    expect(tickCount, 0);
  });

  testWidgets('turning autoTick back on continues the clock', (tester) async {
    final scene = _tryScene();
    if (scene == null) {
      markTestSkipped('No Impeller GPU context');
      return;
    }
    var now = DateTime(2026);
    final ticks = <(Duration, double)>[];
    Widget view({required bool autoTick}) => _sized(
      SceneView(
        scene,
        camera: PerspectiveCamera(),
        autoTick: autoTick,
        clock: Clock(() => now),
        onTick: (elapsed, deltaSeconds) => ticks.add((elapsed, deltaSeconds)),
      ),
    );
    Future<void> frame() async {
      now = now.add(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
    }

    await tester.pumpWidget(view(autoTick: true));
    for (var i = 0; i < 4; i++) {
      await frame();
    }
    final elapsedAtPause = ticks.last.$1;
    expect(elapsedAtPause, greaterThan(Duration.zero));

    // Ten seconds with the ticker off, as when an app pauses a hidden view.
    await tester.pumpWidget(view(autoTick: false));
    ticks.clear();
    now = now.add(const Duration(seconds: 10));
    await tester.pump(const Duration(seconds: 10));
    expect(ticks, isEmpty);

    await tester.pumpWidget(view(autoTick: true));
    for (var i = 0; i < 3; i++) {
      await frame();
    }
    expect(tester.takeException(), isNull);
    expect(ticks, hasLength(3));
    // The first tick continues from where the clock stopped, and the time
    // spent off is not reported as one long step.
    expect(ticks.first.$1, elapsedAtPause);
    expect(ticks.first.$2, 0);
    expect(ticks[1].$1, elapsedAtPause + const Duration(milliseconds: 16));
    expect(ticks[1].$2, closeTo(0.016, 0.001));
    expect(ticks[2].$1, elapsedAtPause + const Duration(milliseconds: 32));
  });

  testWidgets('turning autoTick back on keeps maxFrameRate pacing', (
    tester,
  ) async {
    final scene = _tryScene();
    if (scene == null) {
      markTestSkipped('No Impeller GPU context');
      return;
    }
    var count = 0;
    Widget view({required bool autoTick}) => _sized(
      SceneView(
        scene,
        camera: PerspectiveCamera(),
        autoTick: autoTick,
        maxFrameRate: 60,
        onTick: (_, __) => count++,
      ),
    );

    // Two seconds on, so the next frame's deadline sits two seconds into the
    // ticker's time.
    await tester.pumpWidget(view(autoTick: true));
    for (var i = 0; i < 240; i++) {
      await tester.pump(const Duration(microseconds: 8333));
    }
    await tester.pumpWidget(view(autoTick: false));
    await tester.pump(const Duration(seconds: 1));

    // One second back on at 120 Hz renders about sixty frames.
    count = 0;
    await tester.pumpWidget(view(autoTick: true));
    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(microseconds: 8333));
    }
    expect(tester.takeException(), isNull);
    expect(count, inInclusiveRange(58, 62));
  });

  testWidgets('disposes cleanly (no ticker leak)', (tester) async {
    final scene = _tryScene();
    if (scene == null) {
      markTestSkipped('No Impeller GPU context');
      return;
    }
    await tester.pumpWidget(
      _sized(SceneView(scene, camera: PerspectiveCamera())),
    );
    await tester.pump(const Duration(milliseconds: 16));
    // Replacing the subtree disposes the SceneView's State; a leaked Ticker
    // would trip the test binding's debug assertions.
    await tester.pumpWidget(_sized(const SizedBox()));
  });

  testWidgets('disposes the scene it owns, not an app-owned one', (
    tester,
  ) async {
    final appScene = _tryScene();
    if (appScene == null) {
      markTestSkipped('No Impeller GPU context');
      return;
    }
    Scene scopeScene() =>
        tester.widget<SceneScope>(find.byType(SceneScope)).scene;

    await tester.pumpWidget(_sized(const SceneView.declarative()));
    final owned = scopeScene();
    await tester.pumpWidget(_sized(const SizedBox()));
    expect(owned.isDisposed, isTrue);

    // Switching to an app-owned scene drops the owned one.
    await tester.pumpWidget(_sized(const SceneView.declarative()));
    final replaced = scopeScene();
    await tester.pumpWidget(_sized(SceneView(appScene)));
    expect(replaced.isDisposed, isTrue);
    expect(appScene.isDisposed, isFalse);

    await tester.pumpWidget(_sized(const SizedBox()));
    expect(appScene.isDisposed, isFalse);
  });
}
