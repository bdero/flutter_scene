import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:smoke_render/smoke_scenes.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final captures = <String, String>{};

  for (final smoke in kSmokeScenes) {
    testWidgets('${smoke.id} renders a sane frame', (tester) async {
      // flutter_scene gates rendering on this future. Wait BEFORE building the
      // widget: a Geometry/Material ctor (run in SmokeSceneView.initState during
      // pumpWidget) touches baseShaderLibrary, which throws on web if touched
      // before initialization completes.
      await Scene.initializeStaticResources();
      await loadSmokeMaterials();

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            backgroundColor: kSmokeClear,
            body: Center(child: SmokeSceneView(smoke)),
          ),
        ),
      );

      // Let the post-ready repaint and GPU frames settle.
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }

      final boundary =
          smokeSceneKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
      final ui.Image image = await boundary.toImage(pixelRatio: 1.0);
      final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      final rgba = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;

      // Hand the PNG to the host driver (writes it outside the app sandbox).
      // Platform is distinguished by the Argos build-name, not the filename.
      captures['${smoke.id}.png'] = base64Encode(png.buffer.asUint8List());

      final stats = _frameStats(rgba, image.width, image.height);
      // ignore: avoid_print
      print(
        'SMOKE ${smoke.id}: ${image.width}x${image.height} '
        'cornersClear=${stats.cornersClear} '
        'centerCoverage=${stats.centerNonClearFraction.toStringAsFixed(3)} '
        'fgLuma=${stats.foregroundMeanLuma.toStringAsFixed(1)} '
        'colors=${stats.distinctColors}',
      );

      // Reference-free render-sanity checks (catch black screen / nothing /
      // unlit). The visual diff service catches subtler "renders, but changed".
      expect(
        stats.cornersClear,
        isTrue,
        reason: 'corners are not the clear color; the surface did not clear',
      );
      expect(
        stats.centerNonClearFraction,
        greaterThan(0.05),
        reason: 'little or no geometry drew in the center',
      );
      expect(
        stats.foregroundMeanLuma,
        greaterThan(20),
        reason: 'foreground is ~black; lighting or textures may have broken',
      );
      // A loose backstop against a flat/uniform fill; coverage and foreground
      // luma above are the primary blank detectors. Kept low because this
      // metric is noisy (dominated by the anti-aliased clear/geometry edge)
      // and software rasterizers (e.g. llvmpipe on the Linux CI) produce far
      // fewer distinct values than hardware, especially for a low-roughness
      // metallic surface reflecting a smooth environment.
      expect(
        stats.distinctColors,
        greaterThan(24),
        reason: 'frame looks uniform; possible blank render',
      );
    });
  }

  tearDownAll(() {
    binding.reportData = <String, dynamic>{...captures};
  });
}

({
  bool cornersClear,
  double centerNonClearFraction,
  double foregroundMeanLuma,
  int distinctColors,
})
_frameStats(ByteData rgba, int w, int h) {
  final bytes = rgba.buffer.asUint8List();
  int idx(int x, int y) => (y * w + x) * 4;
  bool isClear(int i) {
    final r = bytes[i], g = bytes[i + 1], b = bytes[i + 2];
    return (r - 0xFF).abs() < 24 && g < 24 && (b - 0xFF).abs() < 24;
  }

  final corners = <int>[
    idx(8, 8),
    idx(w - 9, 8),
    idx(8, h - 9),
    idx(w - 9, h - 9),
  ];
  final cornersClear = corners.every(isClear);

  final x0 = w ~/ 4, x1 = 3 * w ~/ 4, y0 = h ~/ 4, y1 = 3 * h ~/ 4;
  var centerTotal = 0, centerNonClear = 0, fgCount = 0;
  var fgLumaSum = 0.0;
  final colors = <int>{};
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = idx(x, y);
      final r = bytes[i], g = bytes[i + 1], b = bytes[i + 2], a = bytes[i + 3];
      colors.add((r << 24) | (g << 16) | (b << 8) | a);
      final clear = isClear(i);
      if (x >= x0 && x < x1 && y >= y0 && y < y1) {
        centerTotal++;
        if (!clear) centerNonClear++;
      }
      if (!clear) {
        fgLumaSum += 0.299 * r + 0.587 * g + 0.114 * b;
        fgCount++;
      }
    }
  }
  return (
    cornersClear: cornersClear,
    centerNonClearFraction: centerTotal == 0
        ? 0.0
        : centerNonClear / centerTotal,
    foregroundMeanLuma: fgCount == 0 ? 0.0 : fgLumaSum / fgCount,
    distinctColors: colors.length,
  );
}
