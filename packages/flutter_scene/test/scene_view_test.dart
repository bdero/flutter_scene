// Widget-level tests for SceneView. Scene.render() early-returns until static
// resources are ready (which never completes in a plain `flutter test`), so the
// widget's lifecycle, ticking, camera resolution, and SceneScope plumbing are
// what these exercise, not actual rendering.
//
// Constructing a Scene touches the Flutter GPU context (Impeller), which is not
// available under `flutter test`. These tests skip cleanly when it is absent
// (matching the rest of the suite) and run on a GPU-enabled harness.

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:flutter_scene/scene.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/scene.dart' show notifySceneRepaintForTesting;
// ignore: implementation_imports
import 'package:flutter_scene/src/widgets/scene_view_pacing.dart'
    show computePacedTickerSleep;
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

import 'support/gpu_available.dart';

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

  testWidgets(
    'repaintRequested under an active rate-limited ticker clears the deadline without dirtying out of band',
    (tester) async {
      final scene = _tryScene();
      if (scene == null) {
        markTestSkipped('No Impeller GPU context');
        return;
      }
      var ticks = 0;
      var paints = 0;
      await tester.pumpWidget(
        _sized(
          SceneView(
            scene,
            maxFrameRate: 10, // 100 ms period; 75 ms earliest due threshold.
            cameraBuilder: (_) {
              paints++;
              return PerspectiveCamera();
            },
            onTick: (_, _) => ticks++,
          ),
        ),
      );
      // First ticker callback sets the 100 ms deadline.
      await tester.pump(const Duration(milliseconds: 10));
      expect(ticks, 1);

      // 16 ms into the period is rate-limited; neither tick nor paint runs.
      await tester.pump(const Duration(milliseconds: 16));
      final ticksBefore = ticks;
      final paintsBefore = paints;
      final paintBox = tester.renderObject(find.bySubtype<CustomPaint>());
      expect(paintBox.debugNeedsPaint, isFalse);

      // Firing repaintRequested must NOT dirty CustomPaint immediately, and
      // must clear _frameDue so the very next vsync advances onTick early.
      notifySceneRepaintForTesting(scene);
      expect(paintBox.debugNeedsPaint, isFalse);

      await tester.pump(const Duration(milliseconds: 16));
      expect(ticks, ticksBefore + 1);
      expect(paints, paintsBefore + 1);
    },
  );

  testWidgets(
    'repaintRequested marks CustomPaint dirty when autoTick is false',
    (tester) async {
      final scene = _tryScene();
      if (scene == null) {
        markTestSkipped('No Impeller GPU context');
        return;
      }
      var ticks = 0;
      var paints = 0;
      await tester.pumpWidget(
        _sized(
          SceneView(
            scene,
            autoTick: false,
            cameraBuilder: (_) {
              paints++;
              return PerspectiveCamera();
            },
            onTick: (_, _) => ticks++,
          ),
        ),
      );
      final paintsBefore = paints;
      final paintBox = tester.renderObject(find.bySubtype<CustomPaint>());
      expect(paintBox.debugNeedsPaint, isFalse);

      notifySceneRepaintForTesting(scene);
      expect(paintBox.debugNeedsPaint, isTrue);

      await tester.pump();
      expect(paints, paintsBefore + 1);
      expect(ticks, 0);
    },
  );

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

  testWidgets('a view that starts with autoTick off ticks once it is on', (
    tester,
  ) async {
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

    await tester.pumpWidget(view(autoTick: false));
    now = now.add(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 5));
    expect(ticks, isEmpty);

    await tester.pumpWidget(view(autoTick: true));
    for (var i = 0; i < 3; i++) {
      now = now.add(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(tester.takeException(), isNull);
    // The clock starts at zero, whatever time passed before the first tick.
    expect(ticks, hasLength(3));
    expect(ticks.first, (Duration.zero, 0.0));
    expect(ticks[1].$1, const Duration(milliseconds: 16));
    expect(ticks[1].$2, closeTo(0.016, 0.001));
    expect(ticks[2].$1, const Duration(milliseconds: 32));
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

  testWidgets('errorBuilder shows a failed static load and retry recovers', (
    tester,
  ) async {
    // Static resources never finish loading under a web `flutter test`.
    if (!gpuAvailable()) {
      markTestSkipped('No GPU rendering');
      return;
    }
    final scene = Scene();
    await tester.runAsync(Scene.initializeStaticResources);
    Scene.debugFailNextStaticResourcesLoad(StateError('offline'));

    VoidCallback? retry;
    await tester.pumpWidget(
      _sized(
        SceneView(
          scene,
          camera: PerspectiveCamera(),
          loadingBuilder: (_, _) => const Text('loading'),
          errorBuilder: (context, error, onRetry) {
            retry = onRetry;
            return Text('failed: $error');
          },
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('offline'), findsOneWidget);
    // Handed to the builder, not reported.
    expect(tester.takeException(), isNull);

    retry!();
    await tester.pump();
    expect(find.text('loading'), findsOneWidget);
    await tester.runAsync(Scene.initializeStaticResources);
    for (var i = 0; i < 10 && !_revealed(tester); i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(Scene.isReadyToRender, isTrue);
    expect(_revealed(tester), isTrue);
    expect(find.textContaining('offline'), findsNothing);
  });

  testWidgets('without errorBuilder a failed static load is reported', (
    tester,
  ) async {
    // Static resources never finish loading under a web `flutter test`.
    if (!gpuAvailable()) {
      markTestSkipped('No GPU rendering');
      return;
    }
    final scene = Scene();
    await tester.runAsync(Scene.initializeStaticResources);
    Scene.debugFailNextStaticResourcesLoad(StateError('offline'));
    addTearDown(() => tester.runAsync(Scene.initializeStaticResources));

    await tester.pumpWidget(
      _sized(
        SceneView(
          scene,
          camera: PerspectiveCamera(),
          loadingBuilder: (_, _) => const Text('loading'),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isA<StateError>());
    expect(find.text('loading'), findsOneWidget);
  });

  group('computePacedTickerSleep', () {
    test('returns null on 60 Hz display when running at 60 fps', () {
      expect(
        computePacedTickerSleep(
          targetPeriod: const Duration(microseconds: 16667),
          measuredVsyncInterval: const Duration(microseconds: 16667),
          sawSkippedVsync: true,
        ),
        isNull,
      );
    });

    test('returns null before any VSync skip is observed for 60 fps', () {
      expect(
        computePacedTickerSleep(
          targetPeriod: const Duration(microseconds: 16667),
          measuredVsyncInterval: const Duration(microseconds: 4167),
          sawSkippedVsync: false,
        ),
        isNull,
      );
    });

    test(
      'returns null on 2:1 ratios where 1.25x wakeup margin cannot skip a VSync',
      () {
        // 120 Hz @ 60 fps: 16.67 - 1.25 * 8.33 = 6.25 ms < 8.33 ms (wakes
        // before the very next VSync, so sleeping would save zero frames).
        expect(
          computePacedTickerSleep(
            targetPeriod: const Duration(microseconds: 16667),
            measuredVsyncInterval: const Duration(microseconds: 8333),
            sawSkippedVsync: true,
          ),
          isNull,
        );
        // 60 Hz @ 30 fps: 33.33 - 1.25 * 16.67 = 12.50 ms < 16.67 ms.
        expect(
          computePacedTickerSleep(
            targetPeriod: const Duration(microseconds: 33333),
            measuredVsyncInterval: const Duration(microseconds: 16667),
            sawSkippedVsync: true,
          ),
          isNull,
        );
      },
    );

    test('computes bounded sleep for 60 fps on 144 and 240 Hz displays', () {
      final sleep144 = computePacedTickerSleep(
        targetPeriod: const Duration(microseconds: 16667),
        measuredVsyncInterval: const Duration(microseconds: 6944),
        sawSkippedVsync: true,
      );
      expect(sleep144!.inMicroseconds, inInclusiveRange(7000, 10000));

      final sleep240 = computePacedTickerSleep(
        targetPeriod: const Duration(microseconds: 16667),
        measuredVsyncInterval: const Duration(microseconds: 4167),
        sawSkippedVsync: true,
      );
      expect(sleep240!.inMicroseconds, inInclusiveRange(10000, 13000));
    });

    test('computes long sleep for low-rate pacing on 60, 120, and 240 Hz', () {
      final sleep240 = computePacedTickerSleep(
        targetPeriod: const Duration(milliseconds: 50),
        measuredVsyncInterval: const Duration(microseconds: 4167),
        sawSkippedVsync: false,
      );
      expect(sleep240!.inMilliseconds, inInclusiveRange(42, 46));

      final sleep120 = computePacedTickerSleep(
        targetPeriod: const Duration(microseconds: 33333),
        measuredVsyncInterval: const Duration(microseconds: 8333),
        sawSkippedVsync: true,
      );
      expect(sleep120!.inMilliseconds, inInclusiveRange(21, 24));

      final sleep60 = computePacedTickerSleep(
        targetPeriod: const Duration(milliseconds: 50),
        measuredVsyncInterval: const Duration(microseconds: 16667),
        sawSkippedVsync: true,
      );
      expect(sleep60!.inMilliseconds, inInclusiveRange(26, 32));
    });

    test('respects remaining deadline budget and skips sleep when tight', () {
      final sleep = computePacedTickerSleep(
        targetPeriod: const Duration(microseconds: 16667),
        measuredVsyncInterval: const Duration(microseconds: 4167),
        sawSkippedVsync: true,
        remaining: const Duration(microseconds: 11067),
      );
      // The 6 ms wake margin floor applies at 240 Hz (1.25 * 4.17 ms is less).
      expect(sleep!.inMicroseconds, inInclusiveRange(5000, 5100));

      expect(
        computePacedTickerSleep(
          targetPeriod: const Duration(microseconds: 16667),
          measuredVsyncInterval: const Duration(microseconds: 4167),
          sawSkippedVsync: true,
          remaining: const Duration(microseconds: 5667),
        ),
        isNull,
      );
    });

    test('rejects out-of-range VSync intervals cleanly', () {
      expect(
        computePacedTickerSleep(
          targetPeriod: const Duration(milliseconds: 50),
          measuredVsyncInterval: const Duration(microseconds: 500),
          sawSkippedVsync: true,
        ),
        isNull,
      );
      expect(
        computePacedTickerSleep(
          targetPeriod: const Duration(milliseconds: 50),
          measuredVsyncInterval: const Duration(milliseconds: 40),
          sawSkippedVsync: true,
        ),
        isNull,
      );
    });
  });

  testWidgets(
    'low maxFrameRate on 240 Hz preserves continuous elapsed and wall-clock deltas across paced sleeps',
    (tester) async {
      final scene = _tryScene();
      if (scene == null) {
        markTestSkipped('No Impeller GPU context');
        return;
      }
      final elapsedSamples = <Duration>[];
      final deltas = <double>[];
      await tester.pumpWidget(
        _sized(
          SceneView(
            scene,
            cameraBuilder: (elapsed) {
              elapsedSamples.add(elapsed);
              return PerspectiveCamera();
            },
            maxFrameRate: 20, // 50 ms period on a 240 Hz display.
            onTick: (_, delta) => deltas.add(delta),
          ),
        ),
      );
      // Half a second at 240 Hz (~4.167 ms per VSync).
      var sleepingPumps = 0;
      for (var i = 0; i < 120; i++) {
        await tester.pump(const Duration(microseconds: 4167));
        if (!tester.binding.hasScheduledFrame) sleepingPumps++;
      }
      if (kIsWeb) {
        expect(sleepingPumps, greaterThan(50));
      }
      expect(deltas.length, inInclusiveRange(9, 12));
      for (var i = 1; i < elapsedSamples.length; i++) {
        expect(elapsedSamples[i], greaterThanOrEqualTo(elapsedSamples[i - 1]));
      }
      expect(elapsedSamples.last.inMilliseconds, greaterThanOrEqualTo(400));
      for (var i = 2; i < deltas.length; i++) {
        expect(deltas[i], inInclusiveRange(0.035, 0.065));
      }
    },
  );

  testWidgets(
    'repaintRequested, scene swap, maxFrameRate, and re-gating wake a sleeping paced ticker without leaking timers',
    (tester) async {
      final scene = _tryScene();
      if (scene == null) {
        markTestSkipped('No Impeller GPU context');
        return;
      }
      var ticks = 0;
      Future<void> pumpUntilSleeping() async {
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(microseconds: 4167));
          if (kIsWeb && !tester.binding.hasScheduledFrame) return;
        }
      }

      await tester.pumpWidget(
        _sized(
          SceneView(
            scene,
            camera: PerspectiveCamera(),
            maxFrameRate: 20,
            onTick: (_, _) => ticks++,
          ),
        ),
      );
      // Measure 240 Hz VSync and let paced sleep engage.
      await pumpUntilSleeping();
      if (kIsWeb) {
        expect(tester.binding.hasScheduledFrame, isFalse);
      }
      final ticksBeforeRepaint = ticks;

      // repaintRequested wakes a sleeping ticker for the next VSync.
      notifySceneRepaintForTesting(scene);
      if (kIsWeb) {
        expect(tester.binding.hasScheduledFrame, isTrue);
      }
      await tester.pump(const Duration(microseconds: 4167));
      expect(ticks, greaterThan(ticksBeforeRepaint));

      // Switching to a new scene while sleeping (with maxFrameRate unchanged)
      // wakes the ticker promptly.
      if (kIsWeb) {
        expect(tester.binding.hasScheduledFrame, isFalse);
      }
      final scene2 = _tryScene()!;
      addTearDown(scene2.dispose);
      await tester.pumpWidget(
        _sized(
          SceneView(
            scene2,
            camera: PerspectiveCamera(),
            maxFrameRate: 20,
            onTick: (_, _) => ticks++,
          ),
        ),
      );
      if (kIsWeb) {
        expect(tester.binding.hasScheduledFrame, isTrue);
      }
      final ticksBeforeSwitch = ticks;
      await tester.pump(const Duration(microseconds: 4167));
      expect(ticks, greaterThan(ticksBeforeSwitch));

      // Raising maxFrameRate while sleeping resumes ticking promptly.
      if (kIsWeb) {
        expect(tester.binding.hasScheduledFrame, isFalse);
      }
      await tester.pumpWidget(
        _sized(
          SceneView(
            scene2,
            camera: PerspectiveCamera(),
            maxFrameRate: 60,
            onTick: (_, _) => ticks++,
          ),
        ),
      );
      final ticksBeforeBoost = ticks;
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(microseconds: 4167));
      }
      expect(ticks, greaterThanOrEqualTo(ticksBeforeBoost + 2));

      // Re-entering a gated loading phase while sleeping restarts the ticker
      // so the reveal-origin watch keeps tracking frames, and unhiding resumes.
      await tester.pumpWidget(
        _sized(
          SceneView(
            scene2,
            camera: PerspectiveCamera(),
            maxFrameRate: 20,
            onTick: (_, _) => ticks++,
          ),
        ),
      );
      await pumpUntilSleeping();
      if (kIsWeb) {
        expect(tester.binding.hasScheduledFrame, isFalse);
      }
      final group = ResourceGroup();
      await tester.pumpWidget(
        _sized(
          SceneView(
            scene2,
            camera: PerspectiveCamera(),
            maxFrameRate: 20,
            loading: group,
            onTick: (_, _) => ticks++,
          ),
        ),
      );
      if (kIsWeb) {
        expect(tester.binding.hasScheduledFrame, isTrue);
      }
      await tester.pump(const Duration(microseconds: 4167));
      // Returning to ungated resumes ticking cleanly and lets sleep re-engage.
      await tester.pumpWidget(
        _sized(
          SceneView(
            scene2,
            camera: PerspectiveCamera(),
            maxFrameRate: 20,
            onTick: (_, _) => ticks++,
          ),
        ),
      );
      final ticksAfterUngate = ticks;
      await pumpUntilSleeping();
      expect(ticks, greaterThan(ticksAfterUngate));

      // Disposing while sleeping cancels any pending wakeup timer.
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'custom SceneView.clock with maxFrameRate does not stall under paced sleep',
    (tester) async {
      final scene = _tryScene();
      if (scene == null) {
        markTestSkipped('No Impeller GPU context');
        return;
      }
      // A driver-owned clock that stays paused between externally driven steps.
      final driverClock = Clock.fixed(DateTime(2026));
      var ticks = 0;
      await tester.pumpWidget(
        _sized(
          SceneView(
            scene,
            camera: PerspectiveCamera(),
            maxFrameRate: 20,
            clock: driverClock,
            onTick: (_, _) => ticks++,
          ),
        ),
      );
      for (var i = 0; i < 120; i++) {
        await tester.pump(const Duration(microseconds: 4167));
      }
      expect(ticks, inInclusiveRange(9, 12));
    },
  );

  testWidgets(
    'system clock jumps during paced sleep keep ticking and monotonic elapsed',
    (tester) async {
      final scene = _tryScene();
      if (scene == null) {
        markTestSkipped('No Impeller GPU context');
        return;
      }
      var wallNow = DateTime(2026, 11, 24, 12, 0, 0);
      final elapsedSamples = <Duration>[];
      Future<void> pumpUntilSleeping() async {
        for (var i = 0; i < 20; i++) {
          wallNow = wallNow.add(const Duration(microseconds: 4167));
          await tester.pump(const Duration(microseconds: 4167));
          if (kIsWeb && !tester.binding.hasScheduledFrame) break;
        }
        if (kIsWeb) {
          expect(tester.binding.hasScheduledFrame, isFalse);
        }
      }

      await withClock(Clock(() => wallNow), () async {
        await tester.pumpWidget(
          _sized(
            SceneView(
              scene,
              cameraBuilder: (elapsed) {
                elapsedSamples.add(elapsed);
                return PerspectiveCamera();
              },
              maxFrameRate: 20,
            ),
          ),
        );
        // Simulate a 60-second backward NTP step while sleeping.
        await pumpUntilSleeping();
        var samplesBefore = elapsedSamples.length;
        var elapsedBefore = elapsedSamples.last;
        wallNow = wallNow.subtract(const Duration(seconds: 60));
        for (var i = 0; i < 60; i++) {
          wallNow = wallNow.add(const Duration(microseconds: 4167));
          await tester.pump(const Duration(microseconds: 4167));
        }
        expect(elapsedSamples.length, greaterThanOrEqualTo(samplesBefore + 3));
        expect(
          (elapsedSamples.last - elapsedBefore).inMilliseconds,
          inInclusiveRange(150, 320),
        );

        // Simulate a 60-second forward NTP step while sleeping.
        await pumpUntilSleeping();
        samplesBefore = elapsedSamples.length;
        elapsedBefore = elapsedSamples.last;
        wallNow = wallNow.add(const Duration(seconds: 60));
        for (var i = 0; i < 24; i++) {
          wallNow = wallNow.add(const Duration(microseconds: 4167));
          await tester.pump(const Duration(microseconds: 4167));
        }
        expect(elapsedSamples.length, greaterThan(samplesBefore));
        expect(
          (elapsedSamples.last - elapsedBefore).inMilliseconds,
          inInclusiveRange(30, 200),
        );
        await tester.pumpWidget(const SizedBox.shrink());
      });
    },
  );

  testWidgets(
    'repaintRequested while sleeping under TickerMode(enabled: false) still repaints and resumes on unmute',
    (tester) async {
      final scene = _tryScene();
      if (scene == null) {
        markTestSkipped('No Impeller GPU context');
        return;
      }
      var ticks = 0;
      var paints = 0;
      Widget buildView({required bool tickerEnabled}) => TickerMode(
        enabled: tickerEnabled,
        child: _sized(
          SceneView(
            scene,
            maxFrameRate: 20,
            cameraBuilder: (_) {
              paints++;
              return PerspectiveCamera();
            },
            onTick: (_, _) => ticks++,
          ),
        ),
      );
      await tester.pumpWidget(buildView(tickerEnabled: true));
      for (var i = 0; i < 16; i++) {
        await tester.pump(const Duration(microseconds: 4167));
        if (kIsWeb && !tester.binding.hasScheduledFrame) break;
      }
      // Mute the ticker while paced sleep is active.
      await tester.pumpWidget(buildView(tickerEnabled: false));
      final paintsBefore = paints;
      final paintBox = tester.renderObject(find.bySubtype<CustomPaint>());
      expect(paintBox.debugNeedsPaint, isFalse);

      notifySceneRepaintForTesting(scene);
      expect(paintBox.debugNeedsPaint, isTrue);
      await tester.pump();
      expect(paints, paintsBefore + 1);

      // Re-enabling TickerMode resumes ticking without staying stuck stopped.
      final ticksBeforeUnmute = ticks;
      await tester.pumpWidget(buildView(tickerEnabled: true));
      for (var i = 0; i < 16; i++) {
        await tester.pump(const Duration(microseconds: 4167));
      }
      expect(ticks, greaterThan(ticksBeforeUnmute));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

// Whether the view has swapped its loading or error widget for the scene.
bool _revealed(WidgetTester tester) =>
    find.text('loading').evaluate().isEmpty &&
    find.textContaining('failed').evaluate().isEmpty;
