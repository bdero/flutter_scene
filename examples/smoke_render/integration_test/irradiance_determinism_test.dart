// Renders each irradiance smoke scene several times, alternating a fast and
// a slow real frame cadence, and requires every capture to match the first
// byte for byte. The field converges over many frames, so anything that
// leaks wall-clock time or run-to-run state into it shows up here before it
// shows up as a flaky golden. Run on a device, for example
// `flutter test integration_test/irradiance_determinism_test.dart -d macos`.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_scene/scene.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
// ignore: implementation_imports
import 'package:flutter_scene/src/render/frame_transients.dart'
    show rendererSubmissions;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:smoke_render/smoke_scenes.dart';

// The first run only warms the process: the shared default environment
// refines its radiance over its first frames, so the comparison starts at
// the second run.
const _runs = [
  Duration.zero,
  Duration.zero,
  Duration(milliseconds: 40),
  Duration.zero,
];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  for (final id in const ['irradiance_field', 'irradiance_field_sh']) {
    testWidgets('$id renders identically at any frame cadence', (tester) async {
      await tester.pumpWidget(const SizedBox.expand());
      await tester.pump();
      final smoke = kSmokeScenes.firstWhere((s) => s.id == id);
      await tester.runAsync(() async {
        await Scene.preload(smaa: true);
        await smoke.preload?.call();
      });

      ByteData? first;
      for (var run = 0; run < _runs.length; run++) {
        await tester.pumpWidget(const SizedBox.expand());
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              backgroundColor: kSmokeClear,
              body: Center(child: SmokeSceneView(smoke)),
            ),
          ),
        );
        await _settle(tester, Duration.zero);
        final scene = tester
            .state<SmokeSceneViewState>(find.byType(SmokeSceneView))
            .scene;
        final boundary =
            smokeSceneKey.currentContext!.findRenderObject()
                as RenderRepaintBoundary;
        final pacedBefore = scene.pacedFrameCount;
        final clock = Stopwatch()..start();
        for (var i = 0; i < smoke.warmupFrames; i++) {
          boundary.markNeedsPaint();
          await tester.pump(const Duration(milliseconds: 16));
          await _settle(tester, _runs[run]);
        }
        final frameMs = clock.elapsedMicroseconds / 1000 / smoke.warmupFrames;
        expect(
          scene.pacedFrameCount,
          pacedBefore,
          reason: 'a paced frame skips a field update',
        );
        final rgba = (await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1.0);
          return image.toByteData(format: ui.ImageByteFormat.rawRgba);
        }))!;
        if (run == 0) continue;
        if (first == null) {
          first = rgba;
          continue;
        }
        final a = first.buffer.asUint8List();
        final b = rgba.buffer.asUint8List();
        var differing = 0;
        var maxDelta = 0;
        for (var p = 0; p < a.length; p++) {
          final d = (a[p] - b[p]).abs();
          if (d == 0) continue;
          differing++;
          if (d > maxDelta) maxDelta = d;
        }
        // ignore: avoid_print
        print(
          'determinism $id compute=${gpu.supportsCompute} run=$run '
          'wait=${_runs[run].inMilliseconds}ms '
          'frameMs=${frameMs.toStringAsFixed(1)} '
          'differing=$differing maxDelta=$maxDelta',
        );
        expect(differing, 0, reason: 'run $run differs from run 1');
      }
    });
  }
}

// Waits for the GPU to finish, then for [extra] of real time.
Future<void> _settle(WidgetTester tester, Duration extra) =>
    tester.runAsync(() async {
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (rendererSubmissions.framesInFlight > 0 &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      if (extra > Duration.zero) await Future<void>.delayed(extra);
    });
