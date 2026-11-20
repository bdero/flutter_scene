// Measures the traced irradiance feed's GPU cost and BVH build time, saving
// traced_gi_cost.json to build/smoke/.
//
// The GPU cost of one trace comes from dispatching the trace and gathers
// several times in one command buffer and comparing completion times against
// a single dispatch, which cancels queueing and the frame's other work.
//
// Not part of the smoke matrix. Needs compute (Flutter 3.53 or newer on Metal
// or Vulkan, or WebGPU). Run on macOS:
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/traced_gi_cost_test.dart \
//     -d macos --enable-impeller --enable-flutter-gpu

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_scene/scene.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
// ignore: implementation_imports
import 'package:flutter_scene/src/render/engine_compute_shaders.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/render/frame_transients.dart'
    show rendererSubmissions;
// ignore: implementation_imports
import 'package:flutter_scene/src/render/gi_scene.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/render/irradiance_trace.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:smoke_render/smoke_scenes.dart';
import 'package:vector_math/vector_math.dart' as vm;

const _size = 256.0;
const _repeats = 9;

typedef _Setup = ({Scene scene, Camera camera});

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the traced feed costs', (tester) async {
    await tester.pumpWidget(const SizedBox.expand());
    await tester.pump();
    await Scene.preload(smaa: true);
    await tester.runAsync(EngineComputeShaders.whenLoaded);
    final report = <String, Object?>{'compute': gpu.supportsCompute};
    if (!gpu.supportsCompute) {
      binding.reportData = {
        'traced_gi_cost.json': base64Encode(utf8.encode(jsonEncode(report))),
      };
      return;
    }

    final room = kSmokeScenes.firstWhere((s) => s.id == 'irradiance_field');
    final configs = <String, _Setup Function()>{
      'room_600_probes': () => room.setup(),
      'room_2048_probes': () {
        final setup = room.setup();
        setup.scene.globalIllumination.resolution = vm.Vector3(16, 8, 16);
        return setup;
      },
      'spheres_600_probes': () => _spheres(vm.Vector3(10, 6, 10)),
      'spheres_2048_probes': () => _spheres(vm.Vector3(16, 8, 16)),
      'spheres_2048_probes_budget_512': () {
        final setup = _spheres(vm.Vector3(16, 8, 16));
        setup.scene.globalIllumination.probeUpdateBudget = 512;
        return setup;
      },
      'one_262k_triangle_mesh_600_probes': () {
        final setup = room.setup();
        setup.scene.add(
          Node(
            mesh: Mesh(
              SphereGeometry(radius: 0.4, segments: 512, rings: 256),
              PhysicallyBasedMaterial(),
            ),
          )..localTransform = vm.Matrix4.translation(vm.Vector3(0.8, 0.4, 0.6)),
        );
        return setup;
      },
    };

    tracedIrradianceEnabled = true;
    for (final MapEntry(key: name, value: setup) in configs.entries) {
      report[name] = await _measure(tester, setup);
    }
    tracedIrradianceEnabled = false;
    debugTraceRepeats = 1;
    debugGatherRepeats = 1;
    debugOnTraceCompleted = null;

    binding.reportData = {
      'traced_gi_cost.json': base64Encode(utf8.encode(jsonEncode(report))),
    };
    // ignore: avoid_print
    print('traced gi cost: ${jsonEncode(report)}');
  });
}

Future<Map<String, Object?>> _measure(
  WidgetTester tester,
  _Setup Function() build,
) async {
  final setup = build();
  final scene = setup.scene..globalIllumination.enabled = true;
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

  final samples = <double>[];
  debugOnTraceCompleted = (elapsed) =>
      samples.add(elapsed.inMicroseconds / 1000.0);
  Future<double> run(int traces, int frames, {int gathers = 1}) async {
    debugTraceRepeats = traces;
    debugGatherRepeats = gathers;
    samples.clear();
    for (var i = 0; i < frames; i++) {
      boundary.markNeedsPaint();
      await tester.pump(const Duration(milliseconds: 16));
      await _settleGpu(tester);
    }
    if (samples.isEmpty) return double.nan;
    final sorted = [...samples]..sort();
    return sorted[sorted.length ~/ 2];
  }

  // The bottom levels build on another isolate, so warm up until they land.
  await run(1, 40);
  final bvhMs = GiScene.debugLastBuild.inMicroseconds / 1000.0;
  final single = await run(1, 15);
  final traced = await run(_repeats, 15);
  final gathered = await run(1, 15, gathers: _repeats);
  debugTraceRepeats = 1;
  debugGatherRepeats = 1;
  scene.dispose();

  final layoutCounts = scene.globalIllumination.resolution;
  final probes = layoutCounts.x * layoutCounts.y * layoutCounts.z;
  return {
    'probes': probes,
    'rays': probes * kTracedRaysPerProbe,
    'last_mesh_build_ms': bvhMs,
    'single_submit_ms': single,
    'trace_ms': (traced - single) / (_repeats - 1),
    'gathers_ms': (gathered - single) / (_repeats - 1),
  };
}

// The irradiance room with a 7 by 7 grid of finely tessellated spheres on
// its floor, about 200k triangles.
_Setup _spheres(vm.Vector3 resolution) {
  final room = kSmokeScenes.firstWhere((s) => s.id == 'irradiance_field');
  final setup = room.setup();
  setup.scene.globalIllumination.resolution = resolution;
  final sphere = SphereGeometry(radius: 0.12, segments: 64, rings: 32);
  final material = PhysicallyBasedMaterial()
    ..baseColorFactor = vm.Vector4(0.8, 0.8, 0.8, 1.0)
    ..metallicFactor = 0.0
    ..roughnessFactor = 0.9;
  for (var x = 0; x < 7; x++) {
    for (var z = 0; z < 7; z++) {
      setup.scene.add(
        Node(mesh: Mesh(sphere, material))
          ..localTransform = vm.Matrix4.translation(
            vm.Vector3(-1.2 + x * 0.4, 0.12, -1.2 + z * 0.4),
          ),
      );
    }
  }
  return setup;
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
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
});
