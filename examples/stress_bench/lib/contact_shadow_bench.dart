// Contact shadow GPU cost benchmark. Renders one scene offscreen with contact
// shadows off, marched per pixel, and marched in wavefronts, and reports the
// GPU time per frame of each, so the differences are the pass costs.
//
// Frames render back to back with GPU pacing off, then a trailing empty
// submission waits for the GPU, so wall time over a batch is GPU throughput
// whenever the GPU is the bottleneck (the report's `cpu` column says whether
// it was).
//
//   flutter run -d macos --profile --enable-flutter-gpu \
//     -t lib/contact_shadow_bench.dart
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_scene/scene.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/contact_shadows.dart'
    show ContactShadowMethod;
// ignore: implementation_imports
import 'package:flutter_scene/src/gpu/raster_sync.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'src/bench_exit.dart';

const int kBatch = int.fromEnvironment('bench.batch', defaultValue: 30);
const int kBatches = int.fromEnvironment('bench.batches', defaultValue: 9);
// A pattern the config names must match, and the sizes to run, for a
// narrower run.
final RegExp kOnly = RegExp(
  const String.fromEnvironment('bench.only', defaultValue: '.'),
);
const String kSizes = String.fromEnvironment(
  'bench.sizes',
  defaultValue: '1920x1080,3840x2160',
);

enum _Contact { off, fragment, wavefront }

class _Config {
  const _Config(
    this.contact, {
    this.points = false,
    this.taa = false,
    this.tier = RenderQualityTier.high,
  });
  final _Contact contact;
  final bool points;
  final bool taa;
  final RenderQualityTier tier;

  String get name =>
      '${tier.name}${taa ? '_taa' : ''}_${contact.name}'
      '${points ? '_points' : ''}';
}

final _configs = [
  for (final taa in [false, true]) ...[
    _Config(_Contact.off, taa: taa),
    _Config(_Contact.fragment, taa: taa),
    _Config(_Contact.wavefront, taa: taa),
    _Config(_Contact.off, taa: taa, points: true),
    _Config(_Contact.fragment, taa: taa, points: true),
    _Config(_Contact.wavefront, taa: taa, points: true),
  ],
  for (final tier in [RenderQualityTier.medium, RenderQualityTier.low]) ...[
    _Config(_Contact.off, tier: tier),
    _Config(_Contact.fragment, tier: tier),
    _Config(_Contact.wavefront, tier: tier),
  ],
];

final _sizes = [
  for (final size in kSizes.split(','))
    (int.parse(size.split('x')[0]), int.parse(size.split('x')[1])),
];

void main() {
  runApp(
    const Directionality(textDirection: TextDirection.ltr, child: _Bench()),
  );
}

class _Bench extends StatefulWidget {
  const _Bench();
  @override
  State<_Bench> createState() => _BenchState();
}

class _BenchState extends State<_Bench> {
  String _status = 'loading';

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    await Scene.preload(compute: true);
    final results = <Map<String, Object>>[];
    for (final (width, height) in _sizes) {
      for (final config in _configs) {
        if (!kOnly.hasMatch(config.name)) continue;
        if (!mounted) return;
        setState(() => _status = '${width}x$height ${config.name}');
        results.add(await _measure(config, width, height));
      }
    }
    debugPrint('BENCH_JSON ${jsonEncode(results)}');
    debugPrint('BENCH_DONE');
    benchExit();
  }

  Future<Map<String, Object>> _measure(
    _Config config,
    int width,
    int height,
  ) async {
    final (:scene, :camera, :sun, :points) = _buildScene();
    scene.maxGpuFramesInFlight = 0;
    scene.renderQuality.tier = config.tier;
    scene.antiAliasingMode = config.taa
        ? AntiAliasingMode.taa
        : AntiAliasingMode.fxaa;
    sun.contactShadows = config.contact != _Contact.off;
    for (final light in points) {
      light.contactShadows = config.points && config.contact != _Contact.off;
    }
    if (config.contact == _Contact.fragment) {
      // ignore: invalid_use_of_internal_member
      scene.contactShadows.methodOverride = ContactShadowMethod.fragment;
    }
    final viewport = ui.Rect.fromLTWH(
      0,
      0,
      width.toDouble(),
      height.toDouble(),
    );
    void frame() {
      final recorder = ui.PictureRecorder();
      scene.render(
        camera,
        ui.Canvas(recorder),
        viewport: viewport,
        pixelRatio: 1.0,
      );
      recorder.endRecording().dispose();
    }

    // Compiles pipelines and settles temporal state.
    for (var i = 0; i < 40; i++) {
      frame();
      await awaitRasterThread();
    }

    final wall = <double>[];
    final cpu = <double>[];
    for (var b = 0; b < kBatches; b++) {
      await awaitRasterThread();
      final total = Stopwatch()..start();
      final encode = Stopwatch();
      for (var i = 0; i < kBatch; i++) {
        encode.start();
        frame();
        encode.stop();
      }
      await awaitRasterThread();
      total.stop();
      wall.add(total.elapsedMicroseconds / 1000.0 / kBatch);
      cpu.add(encode.elapsedMicroseconds / 1000.0 / kBatch);
    }
    scene.dispose();
    final result = {
      'size': '${width}x$height',
      'config': config.name,
      'ms': _median(wall),
      'min': wall.reduce(math.min),
      'cpu': _median(cpu),
    };
    debugPrint(
      'BENCH ${result['size']} ${config.name.padRight(28)} '
      'ms ${(result['ms'] as double).toStringAsFixed(3)} '
      'min ${(result['min'] as double).toStringAsFixed(3)} '
      'cpu ${(result['cpu'] as double).toStringAsFixed(3)}',
    );
    return result;
  }

  @override
  Widget build(BuildContext context) => Center(child: Text(_status));
}

double _median(List<double> values) {
  final sorted = [...values]..sort();
  return sorted[sorted.length ~/ 2];
}

// A courtyard of pillars and crates on a ground plane, lit low by the sun so
// most of the frame carries contact shadow, plus three point lights.
({Scene scene, Camera camera, DirectionalLight sun, List<PointLight> points})
_buildScene() {
  final scene = Scene();
  final material = PhysicallyBasedMaterial()
    ..baseColorFactor = vm.Vector4(0.75, 0.74, 0.70, 1.0)
    ..metallicFactor = 0.0
    ..roughnessFactor = 0.9
    ..vertexColorWeight = 0.0;
  scene.add(Node(mesh: Mesh(PlaneGeometry(width: 60, depth: 60), material)));
  final random = math.Random(7);
  for (var i = 0; i < 240; i++) {
    final x = random.nextDouble() * 40 - 20;
    final z = random.nextDouble() * 40 - 30;
    final tall = random.nextBool();
    final size = tall
        ? vm.Vector3(0.3, 1.5 + random.nextDouble() * 2.5, 0.3)
        : vm.Vector3(
            0.4 + random.nextDouble() * 0.8,
            0.2 + random.nextDouble() * 0.6,
            0.4 + random.nextDouble() * 0.8,
          );
    scene.add(
      Node(mesh: Mesh(CuboidGeometry(size), material))
        ..localTransform = vm.Matrix4.translation(vm.Vector3(x, size.y / 2, z)),
    );
  }
  final sun = DirectionalLight(
    castsShadow: true,
    shadowMaxDistance: 40.0,
    contactShadowDistance: 0.6,
  );
  scene.add(
    Node()..addComponent(
      DirectionalLightComponent.aimed(sun, vm.Vector3(-0.6, -0.55, -0.4)),
    ),
  );
  final points = <PointLight>[];
  for (final position in [
    vm.Vector3(-3, 1.2, -2),
    vm.Vector3(2, 1.0, -5),
    vm.Vector3(0, 1.5, -9),
  ]) {
    final light = PointLight(intensity: 6.0, range: 10.0);
    points.add(light);
    scene.add(
      Node()
        ..localTransform = vm.Matrix4.translation(position)
        ..addComponent(PointLightComponent(light)),
    );
  }
  return (
    scene: scene,
    camera: PerspectiveCamera(
      position: vm.Vector3(0, 3.5, 6),
      target: vm.Vector3(0, 0, -6),
    ),
    sun: sun,
    points: points,
  );
}
