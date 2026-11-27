// Frame time of the irradiance_field room with the field off, read through
// the full receiver, read through the spherical-harmonic receiver, with the
// receiver the platform picks, and with the adaptive controller cheapening a
// full receiver at 30 fps, all on the screen-space feed. One frame is encode
// start to the last GPU completion. Run on a device, for example
// `flutter test integration_test/irradiance_receiver_cost_test.dart -d <id>`
// (add `--flavor vulkan` on Android).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_scene/scene.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/render/frame_transients.dart'
    show rendererSubmissions;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:smoke_render/smoke_scenes.dart';

const _warmup = 40;
const _frames = 60;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('irradiance receiver cost', (tester) async {
    await tester.pumpWidget(const SizedBox.expand());
    await tester.pump();
    await tester.runAsync(() => Scene.preload(smaa: true));
    final room = kSmokeScenes.firstWhere((s) => s.id == 'irradiance_field');
    final report = <String, Object?>{};
    for (var round = 0; round < 3; round++) {
      for (final mode in const [
        'gi_off',
        'full',
        'sh',
        'automatic',
        'adaptive',
      ]) {
        final setup = room.setup();
        final scene = setup.scene
          ..globalIllumination.enabled = mode != 'gi_off'
          ..globalIllumination.receiver = switch (mode) {
            'sh' => IrradianceFieldReceiver.sphericalHarmonics,
            'automatic' || 'adaptive' => IrradianceFieldReceiver.automatic,
            _ => IrradianceFieldReceiver.full,
          };
        if (mode == 'adaptive') {
          scene.renderQuality
            ..tier = RenderQualityTier.high
            ..adaptive = true
            ..targetFrameRate = 30;
        }
        final frames = mode == 'adaptive' ? _frames * 3 : _frames;
        final watch = Stopwatch()..start();
        var encodeStart = 0;
        var completed = -1;
        void onCompleted() {
          if (rendererSubmissions.framesInFlight == 0) {
            completed = watch.elapsedMicroseconds;
          }
        }

        final key = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            home: RepaintBoundary(
              key: key,
              child: SizedBox.expand(
                child: CustomPaint(
                  size: Size.infinite,
                  painter: _Painter(scene, setup.camera, () {
                    encodeStart = watch.elapsedMicroseconds;
                  }),
                ),
              ),
            ),
          ),
        );
        final boundary =
            key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        rendererSubmissions.addCompletionListener(onCompleted);
        final ms = <double>[];
        for (var i = 0; i < _warmup + frames; i++) {
          completed = -1;
          boundary.markNeedsPaint();
          await tester.pump(const Duration(milliseconds: 16));
          await _settleGpu(tester);
          if (i < _warmup || completed < 0) continue;
          ms.add((completed - encodeStart) / 1000.0);
        }
        // The adaptive run settles first, so its median is the last window.
        if (mode == 'adaptive') ms.removeRange(0, ms.length - 30);
        rendererSubmissions.removeCompletionListener(onCompleted);
        final passes = [
          for (final pass in scene.renderStats.latest!.views.first.passes)
            pass.name,
        ];
        scene.dispose();
        ms.sort();
        final runs = (report[mode] ??= <Object?>[]) as List<Object?>;
        runs.add({'median_ms': ms[ms.length ~/ 2], 'passes': passes.length});
        // ignore: avoid_print
        print(
          'receiver run $mode round=$round median_ms=${ms[ms.length ~/ 2]} '
          'sh=${passes.contains('IrradianceShPass')} '
          'scale=${scene.adaptiveRenderScale.toStringAsFixed(2)}',
        );
      }
    }
    // ignore: avoid_print
    print('receiver cost: ${jsonEncode(report)}');
    binding.reportData = {
      'receiver_cost.json': base64Encode(utf8.encode(jsonEncode(report))),
    };
  });
}

class _Painter extends CustomPainter {
  _Painter(this.scene, this.camera, this.onPaint);
  final Scene scene;
  final Camera camera;
  final VoidCallback onPaint;

  @override
  void paint(Canvas canvas, Size size) {
    onPaint();
    scene.render(camera, canvas, viewport: Offset.zero & size);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

Future<void> _settleGpu(WidgetTester tester) => tester.runAsync(() async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (rendererSubmissions.framesInFlight > 0 &&
      DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  await Future<void>.delayed(const Duration(milliseconds: 5));
});
