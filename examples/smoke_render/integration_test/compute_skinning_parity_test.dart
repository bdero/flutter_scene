// Proves compute skinning renders like vertex shader skinning. Renders a posed
// dash.glb with a shadow-casting light, skinned in the vertex shader, then by
// the compute pass, then in the vertex shader again (the frame-to-frame noise
// the compute frame is held to), and compares the frames. Then checks a scene
// that needs no compute skinning leaves it off.
//
// Not part of the smoke matrix. Needs compute (Flutter 3.53 or newer on Metal
// or Vulkan) and skips elsewhere. Run on macOS:
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/compute_skinning_parity_test.dart \
//     -d macos --enable-impeller --enable-flutter-gpu

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_scene/scene.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
// ignore: implementation_imports
import 'package:flutter_scene/src/render/compute_skinning.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/render/frame_transients.dart'
    show rendererSubmissions;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

const _width = 512.0;
const _height = 512.0;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('compute skinning renders like vertex shader skinning', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox.expand());
    await tester.pump();
    await Scene.preload(smaa: true);
    if (!gpu.supportsCompute) {
      _report(binding, {'skipped': 'no compute'});
      markTestSkipped('No compute on this engine or backend.');
      return;
    }
    await tester.runAsync(ComputeSkinning.instance.debugWaitUntilReady);
    expect(ComputeSkinning.instance.debugReady, isTrue);

    final model = await tester.runAsync(
      () => Node.fromGlbAsset('assets_src/dash.glb'),
    );
    final scene = Scene()
      ..add(model!)
      ..directionalLight = DirectionalLight(
        direction: vm.Vector3(-0.4, -1, -0.3),
        castsShadow: true,
      );
    // Bend every joint, so a wrong skinning matrix moves pixels, and frame the
    // joints, since skinned geometry carries no bounds until it is drawn.
    final bounds = vm.Aabb3.minMax(
      vm.Vector3.all(double.infinity),
      vm.Vector3.all(double.negativeInfinity),
    );
    void bend(Node node) {
      if (node.skin case final skin?) {
        for (final (index, joint) in skin.joints.indexed) {
          if (joint == null) continue;
          joint.localTransform.rotateZ(0.2 * math.sin(index.toDouble()));
          bounds.hullPoint(joint.globalTransform.getTranslation());
        }
      }
      node.children.forEach(bend);
    }

    bend(model);

    final center = bounds.center;
    final radius = (bounds.max - bounds.min).length * 0.5;
    expect(radius, greaterThan(0));
    final camera = PerspectiveCamera(
      position: center + vm.Vector3(radius * 0.4, radius * 0.4, radius * 1.8),
      target: center,
    );

    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Center(
          child: RepaintBoundary(
            key: boundaryKey,
            child: SizedBox(
              width: _width,
              height: _height,
              child: CustomPaint(
                size: Size.infinite,
                painter: _Painter(scene, camera),
              ),
            ),
          ),
        ),
      ),
    );
    await _settleGpu(tester);
    final boundary =
        boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;

    Future<Uint8List> render({required bool compute}) async {
      computeSkinningEnabled = compute;
      debugForceComputeSkinning = compute;
      for (var i = 0; i < 3; i++) {
        boundary.markNeedsPaint();
        await tester.pump(const Duration(milliseconds: 16));
        await _settleGpu(tester);
      }
      final skinned = scene.renderScene.items.where(
        (item) => item.preSkinnedVertices != null,
      );
      expect(skinned.isNotEmpty, compute, reason: 'compute=$compute');
      final image = await tester.runAsync(
        () => boundary.toImage(pixelRatio: 1.0),
      );
      final bytes = await tester.runAsync(
        () => image!.toByteData(format: ui.ImageByteFormat.rawRgba),
      );
      return bytes!.buffer.asUint8List();
    }

    final before = await render(compute: false);
    final computed = await render(compute: true);
    final after = await render(compute: false);

    // Allowed but not needed (no traced irradiance feed), it stays off.
    computeSkinningEnabled = true;
    debugForceComputeSkinning = false;
    for (var i = 0; i < 3; i++) {
      boundary.markNeedsPaint();
      await tester.pump(const Duration(milliseconds: 16));
      await _settleGpu(tester);
    }
    expect(
      scene.renderScene.items.where((item) => item.preSkinnedVertices != null),
      isEmpty,
      reason: 'nothing in the scene needs compute skinning',
    );
    computeSkinningEnabled = true;
    debugForceComputeSkinning = false;

    ({int differing, int maxDelta}) compare(Uint8List a, Uint8List b) {
      var differing = 0;
      var maxDelta = 0;
      for (var p = 0; p < a.length; p += 4) {
        var delta = 0;
        for (var c = 0; c < 3; c++) {
          delta = math.max(delta, (a[p + c] - b[p + c]).abs());
        }
        if (delta > 0) differing++;
        maxDelta = math.max(maxDelta, delta);
      }
      return (differing: differing, maxDelta: maxDelta);
    }

    // Pixels the model changes from the clear color, so a frame that drew
    // nothing on both paths cannot pass.
    var covered = 0;
    for (var p = 0; p < before.length; p += 4) {
      if (before[p] != before[0] ||
          before[p + 1] != before[1] ||
          before[p + 2] != before[2]) {
        covered++;
      }
    }
    final determinism = compare(before, after);
    final parity = compare(before, computed);
    final pixels = before.length ~/ 4;
    _report(binding, {
      'coveredPixels': covered,
      'determinism': {
        'differing': determinism.differing,
        'maxDelta': determinism.maxDelta,
      },
      'parity': {'differing': parity.differing, 'maxDelta': parity.maxDelta},
    });
    // ignore: avoid_print
    print(
      'compute skinning parity: covered $covered of $pixels, '
      'vertex rerun differs at ${determinism.differing} '
      '(max ${determinism.maxDelta}), compute differs at '
      '${parity.differing} (max ${parity.maxDelta})',
    );
    expect(covered, greaterThan(pixels ~/ 20));
    // Consecutive frames are not bit-identical (temporal effects), so the
    // compute frame must stay within the vertex path's own frame-to-frame
    // noise rather than match exactly.
    expect(
      parity.maxDelta,
      lessThanOrEqualTo(math.max(2, determinism.maxDelta)),
    );
    expect(
      parity.differing,
      lessThanOrEqualTo(math.max(pixels ~/ 1000, determinism.differing)),
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

// Saved by the driver as build/smoke/compute_skinning_parity.json, since a web
// run's prints reach only the browser console.
void _report(
  IntegrationTestWidgetsFlutterBinding binding,
  Map<String, Object?> data,
) {
  binding.reportData = {
    'compute_skinning_parity.json': base64Encode(utf8.encode(jsonEncode(data))),
  };
}
