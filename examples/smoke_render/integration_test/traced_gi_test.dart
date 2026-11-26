// Renders the irradiance_field room (an emissive green wall on the left of
// the frame, an emissive red wall on the right, a sun) with the field off, fed by the
// screen-space scatter, and fed by the compute trace, saving each frame and
// the colour bleed each one measures to build/smoke/.
//
// Not part of the smoke matrix. Needs compute for the traced frame (Flutter
// 3.53 or newer on Metal or Vulkan, or WebGPU). Run on macOS:
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/traced_gi_test.dart \
//     -d macos --enable-impeller --enable-flutter-gpu

import 'dart:convert';
import 'dart:math' as math;
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

const _size = 512.0;
const _frames = 60;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the traced feed lights the room from its walls', (tester) async {
    await tester.pumpWidget(const SizedBox.expand());
    await tester.pump();
    await tester.runAsync(() => Scene.preload(smaa: true, compute: true));
    final room = kSmokeScenes.firstWhere((s) => s.id == 'irradiance_field');

    final report = <String, Object?>{'compute': gpu.supportsCompute};
    final captures = <String, String>{};

    Future<Map<String, Object?>> render(
      String name, {
      required bool gi,
      required bool traced,
    }) async {
      final setup = room.setup();
      final scene = setup.scene
        ..globalIllumination.enabled = gi
        ..globalIllumination.feed = traced
            ? IrradianceFeed.rayTraced
            : IrradianceFeed.screenSpace;
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Center(
            child: RepaintBoundary(
              key: key,
              child: SizedBox(
                width: _size,
                height: _size,
                child: CustomPaint(
                  size: Size.infinite,
                  painter: _Painter(scene, setup.camera),
                ),
              ),
            ),
          ),
        ),
      );
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      for (var i = 0; i < _frames; i++) {
        boundary.markNeedsPaint();
        await tester.pump(const Duration(milliseconds: 16));
        await _settleGpu(tester);
      }
      final passes = [
        for (final pass in scene.renderStats.latest!.views.first.passes)
          pass.name,
      ];
      final image = (await tester.runAsync(
        () => boundary.toImage(pixelRatio: 1.0),
      ))!;
      final rgba = (await tester.runAsync(
        () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
      ))!.buffer.asUint8List();
      final png = (await tester.runAsync(
        () => image.toByteData(format: ui.ImageByteFormat.png),
      ))!;
      captures['traced_gi_$name.png'] = base64Encode(png.buffer.asUint8List());
      scene.dispose();
      final width = image.width;
      final height = image.height;
      // The back wall and floor between the side walls, split down the
      // middle. Bleed shows as the right half redder and the left greener.
      List<double> mean(int x0, int x1) {
        final sum = [0.0, 0.0, 0.0];
        var count = 0;
        for (var y = height * 2 ~/ 5; y < height * 4 ~/ 5; y++) {
          for (var x = x0; x < x1; x++) {
            final p = (y * width + x) * 4;
            for (var c = 0; c < 3; c++) {
              sum[c] += rgba[p + c];
            }
            count++;
          }
        }
        return [for (final s in sum) s / count];
      }

      final left = mean(width * 3 ~/ 10, width ~/ 2);
      final right = mean(width ~/ 2, width * 7 ~/ 10);
      return {
        'traced': passes.contains('IrradianceTracePass'),
        'injected': passes.contains('IrradianceInjectPass'),
        'left': left,
        'right': right,
        // Positive when the right half leans red against green more than the
        // left half does.
        'bleed': (right[0] - right[1]) - (left[0] - left[1]),
      };
    }

    report['off'] = await render('off', gi: false, traced: false);
    report['screen_space'] = await render(
      'screen_space',
      gi: true,
      traced: false,
    );
    if (gpu.supportsCompute) {
      report['traced'] = await render('traced', gi: true, traced: true);
    }

    binding.reportData = {
      ...captures,
      'traced_gi.json': base64Encode(utf8.encode(jsonEncode(report))),
    };
    // ignore: avoid_print
    print('traced gi: ${jsonEncode(report)}');

    final off = report['off']! as Map<String, Object?>;
    final screenSpace = report['screen_space']! as Map<String, Object?>;
    expect(screenSpace['injected'], isTrue);
    if (!gpu.supportsCompute) return;
    final traced = report['traced']! as Map<String, Object?>;
    expect(traced['traced'], isTrue, reason: 'the trace pass ran');
    expect(traced['injected'], isFalse);
    // The walls bleed onto the room, more than with the field off.
    expect(
      (traced['bleed']! as double),
      greaterThan(math.max(2.0, (off['bleed']! as double) + 2.0)),
    );
  });
}

class _Painter extends CustomPainter {
  _Painter(this.scene, this.camera);
  final Scene scene;
  final Camera camera;

  @override
  void paint(Canvas canvas, Size size) {
    scene.render(camera, canvas, viewport: Offset.zero & size);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

Future<void> _settleGpu(WidgetTester tester) => tester.runAsync(() async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (rendererSubmissions.framesInFlight > 0 &&
      DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  await Future<void>.delayed(const Duration(milliseconds: 20));
});
