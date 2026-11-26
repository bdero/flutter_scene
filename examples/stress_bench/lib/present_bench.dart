// Presentation benchmark: a SceneView filling the window, a background behind
// it and a HUD above, timed per frame. Query parameters choose the
// presentation (`presentation=flutterCanvas`, the default, or `domCanvas`)
// and drop the background (`background=0`) or the HUD (`hud=0`).
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'src/bench_exit.dart';
import 'src/bench_marks.dart';

final String kPresentation =
    Uri.base.queryParameters['presentation'] ?? 'flutterCanvas';
final bool kBackground = Uri.base.queryParameters['background'] != '0';
final bool kHud = Uri.base.queryParameters['hud'] != '0';
const int kWarmupFrames = int.fromEnvironment(
  'bench.warmup',
  defaultValue: 180,
);
const int kMeasuredFrames = int.fromEnvironment(
  'bench.frames',
  defaultValue: 600,
);

void main() {
  runApp(const PresentBenchApp());
}

class PresentBenchApp extends StatelessWidget {
  const PresentBenchApp({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: PresentBench(),
  );
}

class PresentBench extends StatefulWidget {
  const PresentBench({super.key});

  @override
  State<PresentBench> createState() => _PresentBenchState();
}

class _PresentBenchState extends State<PresentBench> {
  // Created once the backend is ready; WebGPU acquires its device first.
  Scene? _scene;
  final Node _field = Node(name: 'field');
  final ValueNotifier<String> _hud = ValueNotifier('warming up');

  final List<double> _build = [];
  final List<double> _raster = [];
  final List<double> _interval = [];
  int _frames = 0;
  int? _lastVsyncUs;
  bool _measuring = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await Scene.initializeStaticResources();
    _buildScene(Scene());
    if (!mounted) return;
    setState(() {});
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  void _buildScene(Scene scene) {
    _scene = scene;
    scene.directionalLight = DirectionalLight(
      direction: vm.Vector3(-0.5, -1.0, -0.4),
      castsShadow: true,
    );
    scene.add(
      Node(
        mesh: Mesh(
          PlaneGeometry(width: 40, depth: 40),
          PhysicallyBasedMaterial()
            ..baseColorFactor = vm.Vector4(0.55, 0.57, 0.6, 1)
            ..roughnessFactor = 0.85,
        ),
      ),
    );
    final sphere = SphereGeometry(radius: 0.45);
    final cube = CuboidGeometry(vm.Vector3(0.8, 0.8, 0.8));
    const side = 20;
    for (var i = 0; i < side * side; i++) {
      final x = i % side, z = i ~/ side;
      final t = x / (side - 1);
      _field.add(
        Node(
          mesh: Mesh(
            i.isEven ? sphere : cube,
            PhysicallyBasedMaterial()
              ..baseColorFactor = vm.Vector4(0.9, 0.35 + 0.5 * t, 0.2, 1)
              ..roughnessFactor = 0.1 + 0.8 * (z / (side - 1))
              ..metallicFactor = (x + z).isEven ? 1.0 : 0.0,
          ),
          localTransform: vm.Matrix4.translation(
            vm.Vector3(
              (x - side / 2) * 1.6,
              0.6 + math.sin(i * 0.7) * 0.3,
              (z - side / 2) * 1.6,
            ),
          ),
        ),
      );
    }
    scene.add(_field);
  }

  void _onTimings(List<ui.FrameTiming> timings) {
    if (_done) return;
    for (final timing in timings) {
      _frames++;
      final vsync = timing.timestampInMicroseconds(ui.FramePhase.vsyncStart);
      if (_frames == kWarmupFrames) {
        _measuring = true;
        benchMark('bench_start');
      }
      if (_measuring) {
        _build.add(timing.buildDuration.inMicroseconds / 1000);
        _raster.add(timing.rasterDuration.inMicroseconds / 1000);
        final last = _lastVsyncUs;
        if (last != null) _interval.add((vsync - last) / 1000);
      }
      _lastVsyncUs = vsync;
      if (_measuring && _build.length >= kMeasuredFrames) {
        benchMark('bench_end');
        _finish();
        return;
      }
    }
    if (_frames % 30 == 0) {
      _hud.value = '$kPresentation  frame $_frames';
    }
  }

  static Map<String, double> _stats(List<double> samples) {
    final sorted = List<double>.from(samples)..sort();
    double at(double p) => sorted[((sorted.length - 1) * p).round()];
    return {
      'mean': sorted.reduce((a, b) => a + b) / sorted.length,
      'p50': at(0.5),
      'p90': at(0.9),
      'p99': at(0.99),
    };
  }

  void _finish() {
    _done = true;
    final view = View.of(context);
    final json = jsonEncode({
      'presentation': kPresentation,
      'background': kBackground,
      'hud': kHud,
      'size':
          '${view.physicalSize.width.toInt()}x${view.physicalSize.height.toInt()}',
      'dpr': view.devicePixelRatio,
      'gpu': gpuRendererName(),
      'frames': _build.length,
      'build': _stats(_build),
      'raster': _stats(_raster),
      'interval': _stats(_interval),
      'paced': _scene!.pacedFrameCount,
    });
    print('BENCH_JSON $json');
    benchExit();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Paints behind the scene, so the DOM path needs a canvas below it.
        if (kBackground)
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF203040), Color(0xFF605040)],
              ),
            ),
          ),
        if (_scene case final scene?)
          SceneView(
            scene,
            webPresentation: kPresentation == 'domCanvas'
                ? ScenePresentation.domCanvas
                : ScenePresentation.flutterCanvas,
            cameraBuilder: (elapsed) {
              final t = elapsed.inMicroseconds / 1e6 * 0.3;
              return PerspectiveCamera(
                position: vm.Vector3(math.sin(t) * 22, 12, math.cos(t) * 22),
                target: vm.Vector3.zero(),
              );
            },
          ),
        // Paints above the scene.
        if (kHud)
          Positioned(
            left: 16,
            top: 16,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xAA000000),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: ValueListenableBuilder<String>(
                  valueListenable: _hud,
                  builder: (context, value, _) => Text(
                    value,
                    style: const TextStyle(color: Colors.white, fontSize: 18),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
