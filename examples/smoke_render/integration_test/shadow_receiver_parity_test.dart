// Proves shadow receiver culling changes no pixels. Every configuration
// renders culling off, on, then off again; the on frame must match the off
// frame byte for byte (the second off frame shows the frame is deterministic).
// Shadow pass draw counts show what the culling saved.
//
// Not part of the smoke matrix. Run on macOS:
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/shadow_receiver_parity_test.dart \
//     -d macos --enable-impeller --enable-flutter-gpu
//
// An extra scene loads from absolute .glb paths (combined into one scene)
// passed as a comma-separated `--dart-define=SHADOW_PARITY_GLBS=...`, and
// `--dart-define=SHADOW_PARITY_SKIP_CITY=true` skips the built-in city. Reading
// outside the app container needs the app sandbox off
// (`com.apple.security.app-sandbox` in macos/Runner/DebugProfile.entitlements).

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_scene/scene.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/render/frame_transients.dart'
    show rendererSubmissions;
// ignore: implementation_imports
import 'package:flutter_scene/src/render/shadow_receiver_culling.dart'
    as receiver_culling;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

const _expectedAndroidImpellerBackend = String.fromEnvironment(
  'SMOKE_EXPECTED_ANDROID_IMPELLER_BACKEND',
);

const _externalGlbs = String.fromEnvironment('SHADOW_PARITY_GLBS');
const _skipCity = bool.fromEnvironment('SHADOW_PARITY_SKIP_CITY');

/// Measures frame cost with culling off and on instead of comparing pixels.
/// Run in profile mode (`flutter drive --profile`).
const _benchmark = bool.fromEnvironment('SHADOW_PARITY_BENCHMARK');

/// Runs every Nth configuration, for slow software rasterizers.
const _stride = int.fromEnvironment('SHADOW_PARITY_STRIDE', defaultValue: 1);

/// Restricts the run to configurations whose name contains this.
const _only = String.fromEnvironment('SHADOW_PARITY_ONLY');

const _width = 768.0;
const _height = 432.0;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final report = <String, Object?>{};
  final captures = <String, String>{};

  if (_expectedAndroidImpellerBackend.isNotEmpty) {
    testWidgets('Android requests the expected Impeller backend', (_) async {
      expect(defaultTargetPlatform, TargetPlatform.android);
      final backend =
          await const MethodChannel(
            'dev.bdero.smoke_render/android_manifest',
          ).invokeMethod<String>(
            'getApplicationMetadataValue',
            'io.flutter.embedding.android.ImpellerBackend',
          );
      expect(backend, _expectedAndroidImpellerBackend);
    });
  }

  testWidgets('shadow receiver culling is pixel-identical', (tester) async {
    await tester.pumpWidget(const SizedBox.expand());
    await tester.pump();
    await Scene.initializeStaticResources();

    final scenes = <_ParityScene>[if (!_skipCity) _buildCity()];
    final externalPaths = [
      for (final path in _externalGlbs.split(','))
        if (path.trim().isNotEmpty) path.trim(),
    ];
    if (externalPaths.isNotEmpty) {
      scenes.add(await _loadExternal(externalPaths));
    }

    final results = <Map<String, Object?>>[];
    for (final parity in scenes) {
      final holder = _CameraHolder(parity.poses.first.camera);
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            body: Center(
              child: RepaintBoundary(
                key: boundaryKey,
                child: SizedBox(
                  width: _width,
                  height: _height,
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: _ParityPainter(parity.scene, holder),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await _settleGpu();
      final boundary =
          boundaryKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;

      Future<
        ({Uint8List rgba, ui.Image image, int draws, int vertices, int micros})
      >
      render({required bool culling, required int frames}) async {
        receiver_culling.debugDisableShadowReceiverCulling = !culling;
        final stats = parity.scene.renderStats;
        final framesBefore = stats.frameCount;
        final pacedBefore = parity.scene.pacedFrameCount;
        for (var i = 0; i < frames; i++) {
          boundary.markNeedsPaint();
          await tester.pump(const Duration(milliseconds: 16));
          await _settleGpu();
        }
        // Every pump must render a fresh frame, or a capture could compare a
        // stale image.
        expect(stats.frameCount - framesBefore, frames);
        expect(parity.scene.pacedFrameCount, pacedBefore);
        final image = await boundary.toImage(pixelRatio: 1.0);
        final bytes = await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        final view = parity.scene.renderStats.latest!.views.first;
        final shadow = view.passes.where((p) => p.name == 'ShadowPass');
        return (
          rgba: bytes!.buffer.asUint8List(),
          image: image,
          draws: shadow.isEmpty ? 0 : shadow.first.counters.draws,
          vertices: shadow.isEmpty ? 0 : shadow.first.counters.vertices,
          micros: shadow.isEmpty ? 0 : shadow.first.cpuMicros,
        );
      }

      final configs = _benchmark ? _benchmarkConfigs(parity) : _configs(parity);
      for (var c = 0; c < configs.length; c++) {
        final config = configs[c];
        if (_only.isNotEmpty && !config.name.contains(_only)) continue;
        if (c % _stride != 0) continue;
        config.apply(parity, holder);
        if (_benchmark) {
          final result = await _benchmarkConfig(parity, holder);
          result['name'] = '${parity.name}__${config.name}';
          results.add(result);
          // ignore: avoid_print
          print('BENCH ${jsonEncode(result)}');
          continue;
        }

        // Settle until two consecutive frames match: the shadow cache
        // refreshes static tiles over several frames after the light or view
        // changes.
        var off = await render(culling: false, frames: 4);
        var settleFrames = 4;
        for (var i = 0; i < 30; i++) {
          final next = await render(culling: false, frames: 1);
          settleFrames++;
          final stable = _diff(off.rgba, next.rgba).pixels == 0;
          off.image.dispose();
          off = next;
          if (stable) break;
        }
        final on = await render(culling: true, frames: 4);
        final offAgain = await render(culling: false, frames: 4);

        final parityDiff = _diff(off.rgba, on.rgba);
        final noiseDiff = _diff(off.rgba, offAgain.rgba);
        final name = '${parity.name}__${config.name}';
        final result = <String, Object?>{
          'name': name,
          'identical': parityDiff.pixels == 0,
          'deterministic': noiseDiff.pixels == 0,
          'diffPixels': parityDiff.pixels,
          'maxChannelDelta': parityDiff.maxDelta,
          'noisePixels': noiseDiff.pixels,
          'settleFrames': settleFrames,
          'shadowDrawsOff': off.draws,
          'shadowDrawsOn': on.draws,
          'shadowVerticesOff': off.vertices,
          'shadowVerticesOn': on.vertices,
          'shadowCpuMicrosOff': off.micros,
          'shadowCpuMicrosOn': on.micros,
        };
        results.add(result);
        // ignore: avoid_print
        print('PARITY ${jsonEncode(result)}');

        // Keep a sample of pairs for eyeballing, and every failure.
        if (parityDiff.pixels != 0 || c % 6 == 0) {
          captures['$name.off.png'] = await _png(off.image);
          captures['$name.on.png'] = await _png(on.image);
        }
        if (parityDiff.pixels != 0) {
          captures['$name.diff.png'] = await _png(
            await _diffImage(
              off.rgba,
              on.rgba,
              off.image.width,
              off.image.height,
            ),
          );
        }
        off.image.dispose();
        on.image.dispose();
        offAgain.image.dispose();
      }
    }
    receiver_culling.debugDisableShadowReceiverCulling = false;

    report['results'] = results;
    binding.reportData = {
      ...captures,
      'parity.json': base64Encode(
        utf8.encode(const JsonEncoder.withIndent('  ').convert(report)),
      ),
    };

    if (_benchmark) return;

    // A config whose own frames differ run to run cannot prove parity; it
    // fails separately so noise is not mistaken for a culling bug.
    final nondeterministic = results.where((r) => r['deterministic'] != true);
    expect(
      nondeterministic.map((r) => r['name']),
      isEmpty,
      reason: 'frames differ with culling unchanged',
    );
    final mismatched = results.where((r) => r['identical'] != true);
    expect(
      mismatched.map((r) => r['name']),
      isEmpty,
      reason: 'culling changed pixels',
    );
    final culled = results.where(
      (r) => (r['shadowDrawsOn'] as int) < (r['shadowDrawsOff'] as int),
    );
    expect(culled, isNotEmpty, reason: 'culling never removed a caster');
  });
}

/// Default light settings across every pose and sun, live and cached, so the
/// numbers describe ordinary use rather than the parity stress variants.
List<_Config> _benchmarkConfigs(_ParityScene parity) => [
  for (final pose in parity.poses)
    for (final sun in _suns.entries)
      for (final cached in [false, true])
        _Config('${pose.name}_${sun.key}_${cached ? 'cached' : 'live'}', (
          scene,
          holder,
        ) {
          holder.camera = pose.camera;
          scene.light
            ..shadowFilter = DirectionalShadowFilter.rotatedPoisson
            ..shadowCascadeCount = 4
            ..cascadeOverlap = 0.0
            ..shadowSoftness = 0.08
            ..cacheStaticShadows = cached
            ..shadowMaxDistance = pose.maxDistance ?? 80.0;
          scene.lightNode.localTransform = _aim(sun.value.$1, sun.value.$2);
          for (final node in scene.staticCandidates) {
            node.shadowStatic = cached;
          }
          scene.catcher?.softness = 0.0;
        }),
];

const _benchWarmupFrames = 30;
const _benchRounds = 6;
const _benchFramesPerBlock = 30;

/// Renders straight into a throwaway canvas (no vsync) and waits for the GPU
/// after each frame, alternating culling off and on in blocks so drift and
/// background load land on both. Reports medians of whole-frame CPU time
/// (`renderStats`, which includes building the culling planes) and of wall
/// time from encode start to GPU completion.
Future<Map<String, Object?>> _benchmarkConfig(
  _ParityScene parity,
  _CameraHolder holder,
) async {
  final scene = parity.scene;
  const viewport = Rect.fromLTWH(0, 0, _width, _height);

  Future<({int cpu, int wall, int shadowCpu, int draws})> frame() async {
    final watch = Stopwatch()..start();
    final recorder = ui.PictureRecorder();
    scene.render(holder.camera, Canvas(recorder), viewport: viewport);
    recorder.endRecording().dispose();
    while (rendererSubmissions.completedThrough <
        rendererSubmissions.latestSubmission) {
      await Future<void>.delayed(Duration.zero);
    }
    watch.stop();
    final stats = scene.renderStats.latest!;
    final shadow = stats.views.first.passes.where(
      (p) => p.name == 'ShadowPass',
    );
    return (
      cpu: stats.cpuMicros,
      wall: watch.elapsedMicroseconds,
      shadowCpu: shadow.isEmpty ? 0 : shadow.first.cpuMicros,
      draws: shadow.isEmpty ? 0 : shadow.first.counters.draws,
    );
  }

  for (final culling in [false, true]) {
    receiver_culling.debugDisableShadowReceiverCulling = !culling;
    for (var i = 0; i < _benchWarmupFrames; i++) {
      await frame();
    }
  }

  final samples = {
    for (final mode in ['off', 'on'])
      mode: (cpu: <int>[], wall: <int>[], shadowCpu: <int>[], draws: <int>[]),
  };
  for (var round = 0; round < _benchRounds; round++) {
    final order = round.isEven ? ['off', 'on'] : ['on', 'off'];
    for (final mode in order) {
      receiver_culling.debugDisableShadowReceiverCulling = mode == 'off';
      final bucket = samples[mode]!;
      for (var i = 0; i < _benchFramesPerBlock; i++) {
        final f = await frame();
        bucket.cpu.add(f.cpu);
        bucket.wall.add(f.wall);
        bucket.shadowCpu.add(f.shadowCpu);
        bucket.draws.add(f.draws);
      }
    }
  }
  receiver_culling.debugDisableShadowReceiverCulling = false;

  int median(List<int> values) => (values.toList()..sort())[values.length ~/ 2];
  int p90(List<int> values) =>
      (values.toList()..sort())[(values.length * 9) ~/ 10];
  return {
    for (final mode in ['off', 'on']) ...{
      'cpuMedianMicros_$mode': median(samples[mode]!.cpu),
      'cpuP90Micros_$mode': p90(samples[mode]!.cpu),
      'wallMedianMicros_$mode': median(samples[mode]!.wall),
      'wallP90Micros_$mode': p90(samples[mode]!.wall),
      'shadowPassCpuMedianMicros_$mode': median(samples[mode]!.shadowCpu),
      'shadowDraws_$mode': median(samples[mode]!.draws),
    },
    'frames': _benchRounds * _benchFramesPerBlock,
  };
}

class _CameraHolder {
  _CameraHolder(this.camera);
  PerspectiveCamera camera;
}

class _ParityPainter extends CustomPainter {
  _ParityPainter(this.scene, this.holder);
  final Scene scene;
  final _CameraHolder holder;

  @override
  void paint(Canvas canvas, Size size) {
    scene.render(holder.camera, canvas, viewport: Offset.zero & size);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _Pose {
  _Pose(this.name, this.camera, {this.maxDistance});
  final String name;
  final PerspectiveCamera camera;
  final double? maxDistance;
}

class _ParityScene {
  _ParityScene(this.name, this.scene, this.poses, this.staticCandidates);
  final String name;
  final Scene scene;
  final List<_Pose> poses;

  /// Nodes toggled `shadowStatic` to route frames through the shadow cache.
  final List<Node> staticCandidates;
  late final DirectionalLight light;
  late final Node lightNode;
  ShadowCatcherMaterial? catcher;
}

class _Config {
  _Config(this.name, this.apply);
  final String name;
  final void Function(_ParityScene scene, _CameraHolder holder) apply;
}

/// Sun travel directions, as (elevation, azimuth) in degrees.
const _suns = <String, (double, double)>{
  'noon': (86.0, 20.0),
  'high': (55.0, 140.0),
  'mid': (35.0, 250.0),
  'low': (12.0, 60.0),
  'grazing': (3.0, 200.0),
};

List<_Config> _configs(_ParityScene parity) {
  final configs = <_Config>[];
  var variant = 0;
  for (final pose in parity.poses) {
    for (final sun in _suns.entries) {
      for (final cached in [false, true]) {
        final v = variant++;
        final filter = DirectionalShadowFilter.values[v % 4];
        final cascadeCount = const [4, 3, 2, 1][(v ~/ 4) % 4];
        final overlap = v % 3 == 0 ? 0.25 : 0.0;
        final softness = v % 5 == 0 ? 0.6 : 0.08;
        final catcherSoftness = v % 7 == 0 ? 1.5 : 0.0;
        final name =
            '${pose.name}_${sun.key}_${cached ? 'cached' : 'live'}'
            '_${filter.name}_c$cascadeCount'
            '${overlap > 0 ? '_overlap' : ''}'
            '${softness > 0.1 ? '_soft' : ''}'
            '${catcherSoftness > 0 ? '_catcher' : ''}';
        configs.add(
          _Config(name, (scene, holder) {
            holder.camera = pose.camera;
            final light = scene.light
              ..shadowFilter = filter
              ..shadowCascadeCount = cascadeCount
              ..cascadeOverlap = overlap
              ..shadowSoftness = softness
              ..cacheStaticShadows = cached
              ..shadowMaxDistance = pose.maxDistance ?? 80.0;
            light.angularRadius = 0.02;
            scene.lightNode.localTransform = _aim(sun.value.$1, sun.value.$2);
            for (final node in scene.staticCandidates) {
              node.shadowStatic = cached;
            }
            scene.catcher?.softness = catcherSoftness;
          }),
        );
      }
    }
  }
  return configs;
}

/// A rotation taking local +Z to the sun's travel direction.
vm.Matrix4 _aim(double elevationDegrees, double azimuthDegrees) {
  final elevation = elevationDegrees * vm.degrees2Radians;
  final azimuth = azimuthDegrees * vm.degrees2Radians;
  final forward = vm.Vector3(
    math.cos(elevation) * math.cos(azimuth),
    -math.sin(elevation),
    math.cos(elevation) * math.sin(azimuth),
  ).normalized();
  final helper = forward.y.abs() > 0.99
      ? vm.Vector3(1, 0, 0)
      : vm.Vector3(0, 1, 0);
  final right = helper.cross(forward).normalized();
  final up = forward.cross(right).normalized();
  return vm.Matrix4(
    right.x,
    right.y,
    right.z,
    0, //
    up.x,
    up.y,
    up.z,
    0, //
    forward.x,
    forward.y,
    forward.z,
    0, //
    0,
    0,
    0,
    1, //
  );
}

void _addLight(_ParityScene parity) {
  parity.light = DirectionalLight(castsShadow: true, intensity: 3.0);
  parity.lightNode = Node()
    ..addComponent(
      DirectionalLightComponent.aimed(parity.light, vm.Vector3(0, 0, 1)),
    );
  parity.scene.add(parity.lightNode);
}

PhysicallyBasedMaterial _pbr(double r, double g, double b) =>
    PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(r, g, b, 1.0)
      ..metallicFactor = 0.0
      ..roughnessFactor = 0.8
      ..vertexColorWeight = 0.0;

PerspectiveCamera _look(
  vm.Vector3 position,
  vm.Vector3 target, {
  double fovDegrees = 60,
  double far = 1000,
}) => PerspectiveCamera(
  position: position,
  target: target,
  up: (target - position).normalized().y.abs() > 0.99
      ? vm.Vector3(0, 0, -1)
      : vm.Vector3(0, 1, 0),
  fovRadiansY: fovDegrees * vm.degrees2Radians,
  fovNear: 0.1,
  fovFar: far,
);

/// A procedural city built to stress the culling: towers on every side of
/// the camera, slabs high overhead that cast long shadows at low sun, thin
/// poles at the view edges, clutter underground, instanced clusters, a live
/// shadow catcher, and mirrored casters.
_ParityScene _buildCity() {
  final scene = Scene()
    ..antiAliasingMode = AntiAliasingMode.none
    // Never re-present a stale image in place of a capture.
    ..maxGpuFramesInFlight = 0
    ..environmentIntensity = 0.25
    ..exposure = 1.0;
  final random = math.Random(7);
  final staticNodes = <Node>[];
  final parity = _ParityScene('city', scene, [
    _Pose('street', _look(vm.Vector3(3, 1.7, 3), vm.Vector3(3, 1.7, -40))),
    _Pose('aerial', _look(vm.Vector3(-30, 35, 40), vm.Vector3(10, 0, -10))),
    _Pose(
      'topdown',
      _look(vm.Vector3(0, 90, 0), vm.Vector3(0, 0, 0), fovDegrees: 50),
      maxDistance: 150,
    ),
    _Pose('skyward', _look(vm.Vector3(-6, 1.5, -6), vm.Vector3(-4, 30, -20))),
    _Pose(
      'distant',
      _look(vm.Vector3(170, 12, 60), vm.Vector3(0, 5, 0), fovDegrees: 35),
      maxDistance: 300,
    ),
  ], staticNodes);
  _addLight(parity);

  scene.add(
    Node(
      mesh: Mesh(PlaneGeometry(width: 600, depth: 600), _pbr(0.6, 0.6, 0.58)),
    ),
  );

  final towerMaterials = [
    _pbr(0.75, 0.55, 0.45),
    _pbr(0.5, 0.6, 0.75),
    _pbr(0.7, 0.7, 0.7),
  ];
  for (var i = -12; i <= 12; i++) {
    for (var j = -12; j <= 12; j++) {
      if (i == 0 || j == 0) continue; // Avenues along both axes.
      final width = 3 + random.nextDouble() * 5;
      final height = 2 + math.pow(random.nextDouble(), 2).toDouble() * 45;
      final node =
          Node(
              mesh: Mesh(
                CuboidGeometry(vm.Vector3(width, height, width)),
                towerMaterials[(i + j) & 3 == 3 ? 0 : ((i + j) & 3)],
              ),
            )
            ..localTransform = vm.Matrix4.translation(
              vm.Vector3(i * 12.0, height / 2, j * 12.0),
            );
      // Mirror a few casters to cover the flipped-winding path.
      if (random.nextDouble() < 0.05) {
        node.localTransform =
            node.localTransform * vm.Matrix4.diagonal3Values(-1, 1, 1);
      }
      staticNodes.add(node);
      scene.add(node);
    }
  }

  final slab = _pbr(0.3, 0.3, 0.35);
  for (var k = 0; k < 40; k++) {
    scene.add(
      Node(mesh: Mesh(CuboidGeometry(vm.Vector3(10, 1, 6)), slab))
        ..localTransform = vm.Matrix4.translation(
          vm.Vector3(
            random.nextDouble() * 300 - 150,
            50 + random.nextDouble() * 70,
            random.nextDouble() * 300 - 150,
          ),
        ),
    );
  }

  final pole = _pbr(0.2, 0.2, 0.2);
  for (var k = 0; k < 250; k++) {
    scene.add(
      Node(
          mesh: Mesh(
            CylinderGeometry(
              bottomRadius: 0.08,
              topRadius: 0.08,
              height: 7,
              radialSegments: 6,
            ),
            pole,
          ),
        )
        ..localTransform = vm.Matrix4.translation(
          vm.Vector3(
            random.nextDouble() * 120 - 60,
            3.5,
            random.nextDouble() * 120 - 60,
          ),
        ),
    );
  }

  final underground = _pbr(0.4, 0.2, 0.2);
  for (var k = 0; k < 80; k++) {
    scene.add(
      Node(mesh: Mesh(CuboidGeometry(vm.Vector3(4, 4, 4)), underground))
        ..localTransform = vm.Matrix4.translation(
          vm.Vector3(
            random.nextDouble() * 200 - 100,
            -30 + random.nextDouble() * 22,
            random.nextDouble() * 200 - 100,
          ),
        ),
    );
  }

  final sphere = _pbr(0.9, 0.8, 0.2);
  for (var k = 0; k < 60; k++) {
    scene.add(
      Node(
          mesh: Mesh(
            SphereGeometry(radius: 1.2, segments: 16, rings: 8),
            sphere,
          ),
        )
        ..localTransform = vm.Matrix4.translation(
          vm.Vector3(
            random.nextDouble() * 160 - 80,
            4 + random.nextDouble() * 25,
            random.nextDouble() * 160 - 80,
          ),
        ),
    );
  }

  final shrub = _pbr(0.25, 0.5, 0.2);
  for (var k = 0; k < 16; k++) {
    final cluster = InstancedMesh(
      geometry: CapsuleGeometry(radius: 0.4, height: 1.6),
      material: shrub,
    );
    final cx = random.nextDouble() * 200 - 100;
    final cz = random.nextDouble() * 200 - 100;
    for (var n = 0; n < 40; n++) {
      cluster.addInstance(
        vm.Matrix4.translation(
          vm.Vector3(
            cx + random.nextDouble() * 10 - 5,
            1.2,
            cz + random.nextDouble() * 10 - 5,
          ),
        ),
      );
    }
    scene.add(Node()..addComponent(InstancedMeshComponent(cluster)));
  }

  // A live catcher whose per-draw softness some configs raise.
  final catcher = ShadowCatcherMaterial(shadowIntensity: 0.9);
  parity.catcher = catcher;
  scene.add(
    Node(mesh: Mesh(PlaneGeometry(width: 20, depth: 20), catcher))
      ..localTransform = vm.Matrix4.translation(vm.Vector3(-18, 12.05, -18)),
  );
  return parity;
}

Future<_ParityScene> _loadExternal(List<String> paths) async {
  final model = Node();
  for (final path in paths) {
    model.add(await Node.fromGlbBytes(await File(path).readAsBytes()));
  }
  final scene = Scene()
    ..antiAliasingMode = AntiAliasingMode.none
    // Never re-present a stale image in place of a capture.
    ..maxGpuFramesInFlight = 0
    ..environmentIntensity = 0.25
    ..exposure = 1.0;
  scene.add(model);
  // Union the meshes directly: an empty leaf node makes combinedWorldBounds
  // report the whole subtree as unbounded.
  vm.Aabb3? union;
  for (final node in model.meshNodes) {
    final local = node.mesh!.localBounds;
    if (local == null) continue;
    final world = vm.Aabb3.copy(local)..transform(node.globalTransform);
    union == null ? union = world : union.hull(world);
  }
  final bounds = union!;
  final center = bounds.center;
  final extent = bounds.max - bounds.min;
  final size = math.max(extent.x, math.max(extent.y, extent.z));
  final eye = center.y;
  final name = paths.first.split('/').last.split('.').first;
  final nodes = <Node>[];
  void collect(Node node) {
    if (node.mesh != null) nodes.add(node);
    node.children.forEach(collect);
  }

  collect(model);
  final parity = _ParityScene(name, scene, [
    _Pose(
      'inside',
      _look(
        vm.Vector3(center.x, eye, center.z),
        vm.Vector3(center.x + size, eye, center.z + size * 0.2),
        far: size * 4,
      ),
      maxDistance: size * 0.6,
    ),
    _Pose(
      'overview',
      _look(center + vm.Vector3(-0.6, 0.5, 0.7) * size, center, far: size * 4),
      maxDistance: size * 1.5,
    ),
    _Pose(
      'corner',
      _look(
        vm.Vector3(
          bounds.min.x + extent.x * 0.15,
          eye + 2,
          bounds.min.z + extent.z * 0.15,
        ),
        center,
        far: size * 4,
      ),
      maxDistance: size,
    ),
  ], nodes);
  _addLight(parity);
  return parity;
}

({int pixels, int maxDelta}) _diff(Uint8List a, Uint8List b) {
  var pixels = 0;
  var maxDelta = 0;
  for (var i = 0; i < a.length; i += 4) {
    var differs = false;
    for (var c = 0; c < 3; c++) {
      final delta = (a[i + c] - b[i + c]).abs();
      if (delta != 0) {
        differs = true;
        if (delta > maxDelta) maxDelta = delta;
      }
    }
    if (differs) pixels++;
  }
  return (pixels: pixels, maxDelta: maxDelta);
}

Future<ui.Image> _diffImage(
  Uint8List a,
  Uint8List b,
  int width,
  int height,
) async {
  final out = Uint8List(a.length);
  for (var i = 0; i < a.length; i += 4) {
    final delta = math.max(
      (a[i] - b[i]).abs(),
      math.max((a[i + 1] - b[i + 1]).abs(), (a[i + 2] - b[i + 2]).abs()),
    );
    final gray = (a[i] + a[i + 1] + a[i + 2]) ~/ 9;
    out[i] = delta > 0 ? 255 : gray;
    out[i + 1] = delta > 0 ? 0 : gray;
    out[i + 2] = delta > 0 ? 0 : gray;
    out[i + 3] = 255;
  }
  final buffer = await ui.ImmutableBuffer.fromUint8List(out);
  final descriptor = ui.ImageDescriptor.raw(
    buffer,
    width: width,
    height: height,
    pixelFormat: ui.PixelFormat.rgba8888,
  );
  final codec = await descriptor.instantiateCodec();
  return (await codec.getNextFrame()).image;
}

Future<String> _png(ui.Image image) async {
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  return base64Encode(png!.buffer.asUint8List());
}

Future<void> _settleGpu() async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (rendererSubmissions.framesInFlight > 0 &&
      DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  await Future<void>.delayed(const Duration(milliseconds: 20));
}
