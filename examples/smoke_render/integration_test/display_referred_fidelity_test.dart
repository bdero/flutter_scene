// Colour fidelity of a display-referred surface (issue #382). A flat sRGB
// texel on an unlit quad, rendered and read back under each tone mapping
// mode, scene-referred and display-referred.
//
// The scene-referred rows are the defect the issue reports; the
// display-referred rows must come back byte-exact under every operator.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_scene/scene.dart' hide Material;
// ignore: implementation_imports
import 'package:flutter_scene/src/render/frame_transients.dart'
    show rendererSubmissions;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

final GlobalKey _boundaryKey = GlobalKey();

Future<void> _settleGpu() async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (rendererSubmissions.framesInFlight > 0 &&
      DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  await Future<void>.delayed(const Duration(milliseconds: 30));
}

Texture2D _flat(int v) {
  final pixels = Uint8List(4 * 4 * 4);
  for (var i = 0; i < pixels.length; i += 4) {
    pixels[i] = v;
    pixels[i + 1] = v;
    pixels[i + 2] = v;
    pixels[i + 3] = 255;
  }
  return Texture2D.fromPixels(pixels, 4, 4);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a display-referred surface keeps its colours', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(backgroundColor: Colors.black, body: SizedBox.expand()),
      ),
    );
    await tester.pump();
    await Scene.initializeStaticResources();
    expect(Scene.isReadyToRender, isTrue);

    Future<int> through(
      int v,
      ToneMappingMode mode, {
      required bool displayReferred,
    }) async {
      final scene = Scene()
        ..toneMapping = mode
        ..environment = EnvironmentMap.empty();
      scene.add(
        Node(
          mesh: Mesh(
            CuboidGeometry(vm.Vector3(4, 4, 0.01)),
            UnlitMaterial(colorTexture: _flat(v))
              ..alphaMode = AlphaMode.opaque
              ..displayReferred = displayReferred,
          ),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            backgroundColor: Colors.black,
            body: Center(
              child: RepaintBoundary(
                key: _boundaryKey,
                child: SizedBox(
                  width: 200,
                  height: 200,
                  child: SceneView(
                    scene,
                    camera: PerspectiveCamera(
                      position: vm.Vector3(0, 0, 3),
                      target: vm.Vector3.zero(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      final boundary =
          _boundaryKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
      await _settleGpu();
      for (var i = 0; i < 10; i++) {
        boundary.markNeedsPaint();
        await tester.pump(const Duration(milliseconds: 50));
        await _settleGpu();
      }

      final image = await boundary.toImage(pixelRatio: 1.0);
      final data = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      image.dispose();

      final counts = <int, int>{};
      for (var i = 0; i < data.lengthInBytes; i += 4) {
        final c = data.getUint32(i);
        counts[c] = (counts[c] ?? 0) + 1;
      }
      final top = counts.entries.reduce((a, b) => a.value >= b.value ? a : b);
      return (top.key >> 24) & 0xFF;
    }

    const inputs = [255, 187, 128, 64, 27];
    final failures = <String>[];
    for (final mode in ToneMappingMode.values) {
      for (final displayReferred in [false, true]) {
        final row = <String>[];
        for (final v in inputs) {
          final out = await through(v, mode, displayReferred: displayReferred);
          row.add('$v->$out');
          if (displayReferred && out != v) {
            failures.add('${mode.name} $v came back $out');
          }
        }
        final label = displayReferred ? 'display' : 'scene  ';
        // ignore: avoid_print
        print('FIDELITY ${mode.name.padRight(11)} $label ${row.join('  ')}');
      }
    }
    expect(
      failures,
      isEmpty,
      reason:
          'a display-referred surface must reach the screen unchanged, '
          'whatever the scene tone curve is',
    );
  }, timeout: const Timeout(Duration(minutes: 10)));
}
