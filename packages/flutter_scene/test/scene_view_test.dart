// Widget-level tests for SceneView. Scene.render() early-returns until static
// resources are ready (which never completes in a plain `flutter test`), so the
// widget's lifecycle, ticking, camera resolution, and SceneScope plumbing are
// what these exercise, not actual rendering.
//
// Constructing a Scene touches the Flutter GPU context (Impeller), which is not
// available under `flutter test`. These tests skip cleanly when it is absent
// (matching the rest of the suite) and run on a GPU-enabled harness.

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

Widget _sized(Widget child) =>
    Center(child: SizedBox(width: 200, height: 200, child: child));

void main() {
  testWidgets('requires exactly one of camera or cameraBuilder', (
    tester,
  ) async {
    final scene = _tryScene();
    if (scene == null) {
      markTestSkipped('No Impeller GPU context');
      return;
    }
    expect(() => SceneView(scene), throwsAssertionError);
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
}
