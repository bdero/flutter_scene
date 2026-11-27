// Compares compute skinning against vertex shader skinning on crowds of
// animated dash.glb, with and without a shadow-casting sun, saving
// compute_skinning_cost.json to build/smoke/.
//
// Each frame waits for the GPU before the next, so the time from encoding to
// the frame's last completion is the frame's GPU time plus a fixed delivery
// delay that cancels between the two paths.
//
// Not part of the smoke matrix. Needs compute (Flutter 3.53 or newer on Metal
// or Vulkan). Run on macOS, or on Android with `--flavor vulkan`:
//
//   flutter drive --profile --driver=test_driver/integration_test.dart \
//     --target=integration_test/compute_skinning_cost_test.dart \
//     -d macos --enable-impeller --enable-flutter-gpu

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_scene/scene.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
// ignore: implementation_imports
import 'package:flutter_scene/src/render/compute_skinning.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/render/frame_transients.dart'
    show rendererSubmissions;
// ignore: implementation_imports
import 'package:flutter_scene/src/importer/constants.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

const _size = 512.0;
const _warmup = 20;
const _frames = 40;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('compute skinning costs', (tester) async {
    await tester.pumpWidget(const SizedBox.expand());
    await tester.pump();
    await tester.runAsync(() => Scene.preload(smaa: true, compute: true));
    final report = <String, Object?>{'compute': gpu.supportsCompute};
    if (!gpu.supportsCompute) {
      _report(binding, report);
      markTestSkipped('No compute on this engine or backend.');
      return;
    }
    await tester.runAsync(ComputeSkinning.instance.debugWaitUntilReady);
    final glb = (await tester.runAsync(
      () => rootBundle.load('assets_src/dash.glb'),
    ))!.buffer.asUint8List();

    for (final count in const [1, 5, 10]) {
      for (final shadows in const [false, true]) {
        final name = 'dash_x${count}_${shadows ? 'shadows' : 'no_shadows'}';
        final result = <String, Object?>{};
        // Alternate the modes so drift (thermal throttling) hits each.
        for (var round = 0; round < 2; round++) {
          for (final mode in _Mode.values) {
            final run = await _measure(
              tester,
              glb,
              count: count,
              shadows: shadows,
              mode: mode,
            );
            final runs =
                (result[mode.name] ??= <Map<String, Object?>>[]) as List;
            runs.add(run);
            // One short line per run, since logcat truncates long ones.
            // ignore: avoid_print
            print(
              'skin run $name ${mode.name} '
              'gpu=${run['frame_to_completion_ms']} '
              'cpu=${run['encode_cpu_ms']} pre=${run['pre_skinned_items']} '
              'rss_mb=${_rssMb()}',
            );
          }
        }
        report[name] = result;
      }
    }
    computeSkinningEnabled = true;
    debugForceComputeSkinning = false;
    _report(binding, report);
  });
}

Future<Map<String, Object?>> _measure(
  WidgetTester tester,
  Uint8List glb, {
  required int count,
  required bool shadows,
  required _Mode mode,
}) async {
  final compute = mode == _Mode.compute;
  computeSkinningEnabled = compute;
  debugForceComputeSkinning = compute;
  final scene = Scene();
  if (shadows) {
    scene.directionalLight = DirectionalLight(
      direction: vm.Vector3(-0.4, -1, -0.3),
      castsShadow: true,
    );
  }
  final columns = count < 5 ? count : 5;
  for (var i = 0; i < count; i++) {
    final model = (await tester.runAsync(() => Node.fromGlbBytes(glb)))!;
    final x = (i % columns) - (columns - 1) / 2;
    final z = -(i ~/ columns).toDouble();
    model.localTransform = vm.Matrix4.translation(vm.Vector3(x * 1.2, 0, z));
    if (model.parsedAnimations.isNotEmpty) {
      model.createAnimationClip(model.parsedAnimations.first)
        ..loop = true
        ..play();
    }
    scene.add(model);
  }
  final rows = (count + columns - 1) ~/ columns;
  final camera = PerspectiveCamera(
    position: vm.Vector3(0, 2.5, 3.5 + columns * 0.6),
    target: vm.Vector3(0, 0.5, -(rows - 1) / 2),
  );

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
      home: Center(
        child: RepaintBoundary(
          key: key,
          child: SizedBox(
            width: _size,
            height: _size,
            child: CustomPaint(
              size: Size.infinite,
              painter: _Painter(scene, camera, () {
                encodeStart = watch.elapsedMicroseconds;
              }),
            ),
          ),
        ),
      ),
    ),
  );
  final boundary =
      key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  rendererSubmissions.addCompletionListener(onCompleted);
  final gpuMs = <double>[];
  final cpuMs = <double>[];
  var preSkinned = 0;
  var skinnedVertices = 0;
  for (var i = 0; i < _warmup + _frames; i++) {
    completed = -1;
    scene.update(1 / 60);
    boundary.markNeedsPaint();
    await tester.pump(const Duration(milliseconds: 16));
    await _settleGpu(tester);
    if (i < _warmup || completed < 0) continue;
    gpuMs.add((completed - encodeStart) / 1000.0);
    cpuMs.add((scene.renderStats.latest?.cpuMicros ?? 0) / 1000.0);
    preSkinned = 0;
    skinnedVertices = 0;
    for (final item in scene.renderScene.items) {
      if (item.skin == null) continue;
      // ignore: invalid_use_of_internal_member
      skinnedVertices += item.geometry.uploadedVertexCount;
      if (item.preSkinnedVertices != null) preSkinned++;
    }
  }
  rendererSubmissions.removeCompletionListener(onCompleted);
  scene.dispose();

  double median(List<double> values) {
    if (values.isEmpty) return double.nan;
    final sorted = [...values]..sort();
    return sorted[sorted.length ~/ 2];
  }

  return {
    'frame_to_completion_ms': median(gpuMs),
    'encode_cpu_ms': median(cpuMs),
    'pre_skinned_items': preSkinned,
    'skinned_vertices': skinnedVertices,
    // The compute path's output ring, three frames deep.
    'output_ring_bytes': compute
        ? skinnedVertices * kSkinnedPerVertexSize * 3
        : 0,
  };
}

// How a run skins.
enum _Mode { vertex, compute }

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

// The process's resident set, or -1 where /proc is unavailable.
int _rssMb() {
  try {
    final status = File('/proc/self/status').readAsStringSync();
    final kb = RegExp(r'VmRSS:\s+(\d+)').firstMatch(status)?.group(1);
    return kb == null ? -1 : int.parse(kb) ~/ 1024;
  } catch (_) {
    return -1;
  }
}

void _report(
  IntegrationTestWidgetsFlutterBinding binding,
  Map<String, Object?> data,
) {
  binding.reportData = {
    'compute_skinning_cost.json': base64Encode(utf8.encode(jsonEncode(data))),
  };
}
