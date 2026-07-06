// Gaussian splat rendering demo. The splat types live under lib/src (not yet
// part of the public barrel); a dev app may import them directly.
// ignore_for_file: implementation_imports

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene/src/components/splat_component.dart';
import 'package:flutter_scene/src/geometry/splat_geometry.dart';
import 'package:flutter_scene/src/splats/gaussian_splats.dart';
import 'package:flutter_scene/src/splats/splat_data.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'example_settings.dart';

/// Gaussian splat rendering: a procedural nebula (60k anisotropic splats)
/// and, when `assets_src/strawberry.splat` is present (fetched by
/// `tool/fetch_splat_asset.sh`, a CC BY capture by danylyon), a real 1.5M
/// splat macro capture. A PBR sphere sits inside each scene proving splats
/// and forward-rendered geometry occlude each other, and an animated crop
/// box demonstrates GPU-side cropping.
class ExampleSplats extends StatefulWidget {
  const ExampleSplats({super.key});

  @override
  ExampleSplatsState createState() => ExampleSplatsState();
}

enum _SplatSource { nebula, capture }

class ExampleSplatsState extends State<ExampleSplats> {
  Scene scene = Scene();
  bool _ready = false;

  final Map<_SplatSource, Node> _sourceNodes = {};
  final Map<_SplatSource, SplatComponent> _sources = {};
  _SplatSource _active = _SplatSource.nebula;

  // Local-space X extent of each set, used to scale the crop sweep.
  static const Map<_SplatSource, double> _cropExtent = {
    _SplatSource.nebula: 10.0,
    _SplatSource.capture: 1.2,
  };

  double _opacity = 1.0;
  double _splatScale = 1.0;
  bool _antialiased = true;
  bool _cropSweep = false;
  bool _orbit = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    scene.skybox = Skybox(
      GradientSkySource(
        zenithColor: vm.Vector3(0.008, 0.008, 0.02),
        horizonColor: vm.Vector3(0.02, 0.015, 0.045),
        groundColor: vm.Vector3(0.005, 0.005, 0.012),
        sunColor: vm.Vector3(0.06, 0.06, 0.09),
      ),
    );

    final nebula = SplatComponent(GaussianSplats.fromData(_nebula(seed: 7)));
    _sources[_SplatSource.nebula] = nebula;
    _sourceNodes[_SplatSource.nebula] = Node()..addComponent(nebula);

    // The captured asset is optional (fetched by tool/fetch_splat_asset.sh).
    try {
      final capture = SplatComponent(
        await GaussianSplats.fromAsset('assets_src/strawberry.splat'),
      );
      _sources[_SplatSource.capture] = capture;
      // Training captures are y-down; flip upright and scale up to scene
      // size.
      _sourceNodes[_SplatSource.capture] = Node(
        localTransform: vm.Matrix4.compose(
          vm.Vector3(0, 1.0, 0),
          vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), math.pi),
          vm.Vector3.all(4.0),
        ),
      )..addComponent(capture);
    } catch (_) {
      // Asset absent; the nebula still demonstrates everything.
    }

    for (final entry in _sourceNodes.entries) {
      entry.value.visible = entry.key == _active;
      scene.add(entry.value);
    }

    // A shiny sphere inside the cloud: splats in front of it must cover it,
    // and it must occlude the splats behind it.
    scene.add(
      Node(
        mesh: Mesh(
          SphereGeometry(radius: 1.2),
          PhysicallyBasedMaterial()
            ..baseColorFactor = vm.Vector4(0.9, 0.85, 0.8, 1.0)
            ..metallicFactor = 1.0
            ..roughnessFactor = 0.15,
        ),
      )..localTransform = vm.Matrix4.translation(vm.Vector3(2.5, 0.4, 0)),
    );

    if (mounted) setState(() => _ready = true);
  }

  SplatComponent get _activeSplats => _sources[_active]!;

  void _setActive(_SplatSource source) {
    setState(() {
      _active = source;
      for (final entry in _sourceNodes.entries) {
        entry.value.visible = entry.key == source;
      }
      _applyKnobs();
    });
  }

  void _applyKnobs() {
    final splats = _activeSplats;
    splats.opacity = _opacity;
    splats.splatScale = _splatScale;
    splats.antialiased = _antialiased;
    if (!_cropSweep) splats.setCropBox(null);
  }

  void _tickCrop(Duration elapsed) {
    if (!_cropSweep) return;
    final splats = _activeSplats;
    final extent = _cropExtent[_active]!;
    final t = elapsed.inMicroseconds / 1e6;
    // A wipe: a big exclude box slides through the set, eating and then
    // restoring it. Evaluated per splat on the GPU, so this is free to
    // animate.
    final sweep = math.sin(t * 0.5) * extent;
    splats.setCropBox(
      vm.Matrix4.compose(
        vm.Vector3(sweep - extent, 0, 0),
        vm.Quaternion.identity(),
        vm.Vector3(extent, extent * 2, extent * 2),
      ),
      mode: SplatCropMode.exclude,
    );
  }

  /// Builds a three-armed spiral nebula with a bright core. Anisotropic
  /// splats stretch along their arm's tangent, showing off oriented
  /// covariances; colors are authored in linear space.
  static SplatData _nebula({required int seed}) {
    const arms = 3;
    const perArm = 17000;
    const core = 9000;
    const count = arms * perArm + core;
    final rng = math.Random(seed);
    final data = SplatData.zeroed(count);

    double gauss() {
      // Box-Muller.
      final u = math.max(rng.nextDouble(), 1e-9);
      return math.sqrt(-2 * math.log(u)) *
          math.cos(2 * math.pi * rng.nextDouble());
    }

    void writeSplat(
      int i, {
      required vm.Vector3 position,
      required vm.Vector3 scale,
      required double yaw,
      required vm.Vector3 color,
      required double opacity,
    }) {
      final p = i * 3, q = i * 4;
      data.positions[p] = position.x;
      data.positions[p + 1] = position.y;
      data.positions[p + 2] = position.z;
      data.scales[p] = scale.x;
      data.scales[p + 1] = scale.y;
      data.scales[p + 2] = scale.z;
      // Rotation about +Y by yaw: aligns local x with the arm tangent.
      data.rotations[q + 1] = math.sin(yaw / 2);
      data.rotations[q + 3] = math.cos(yaw / 2);
      data.colors[p] = color.x;
      data.colors[p + 1] = color.y;
      data.colors[p + 2] = color.z;
      data.opacities[i] = opacity;
    }

    final armColors = [
      vm.Vector3(0.25, 0.45, 1.0), // blue
      vm.Vector3(0.65, 0.3, 1.0), // violet
      vm.Vector3(0.2, 0.9, 0.85), // teal
    ];

    var i = 0;
    for (var arm = 0; arm < arms; arm++) {
      final armBase = arm * 2 * math.pi / arms;
      for (var n = 0; n < perArm; n++, i++) {
        final r = 1.2 + 7.5 * math.sqrt(rng.nextDouble());
        final theta = armBase + r * 0.55 + gauss() * (0.35 / math.sqrt(r));
        final spread = 0.25 + r * 0.06;
        final position = vm.Vector3(
          r * math.cos(theta) + gauss() * spread,
          gauss() * spread * 0.35,
          r * math.sin(theta) + gauss() * spread,
        );
        // The arm tangent direction (derivative of the spiral) is close to
        // the angular direction; stretch splats along it.
        final tangentYaw = -(theta + math.pi / 2);
        final len = 0.06 + rng.nextDouble() * 0.12;
        final scale = vm.Vector3(len * 2.2, len * 0.7, len);
        final t = ((r - 1.2) / 7.5).clamp(0.0, 1.0);
        final color =
            armColors[arm] * (0.35 + 0.5 * t) +
            vm.Vector3(1.0, 0.85, 0.6) * (1.0 - t) * 0.5;
        writeSplat(
          i,
          position: position,
          scale: scale,
          yaw: tangentYaw,
          color: color * (2.2 - 1.4 * t),
          opacity: 0.25 + rng.nextDouble() * 0.5,
        );
      }
    }
    for (var n = 0; n < core; n++, i++) {
      final position = vm.Vector3(gauss() * 0.9, gauss() * 0.45, gauss() * 0.9);
      final len = 0.04 + rng.nextDouble() * 0.1;
      final heat = math.max(0.0, 1.0 - position.length / 2.2);
      writeSplat(
        i,
        position: position,
        scale: vm.Vector3(len, len, len),
        yaw: rng.nextDouble() * math.pi,
        color: vm.Vector3(1.0, 0.9, 0.7) * (1.5 + 6.0 * heat * heat),
        opacity: 0.35 + rng.nextDouble() * 0.55,
      );
    }
    return data;
  }

  vm.Vector3 _cameraPosition = vm.Vector3(0, 4, 14);

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const ColoredBox(
        color: Color(0xFF040408),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Stack(
      children: [
        Positioned.fill(
          child: SceneView(
            scene,
            cameraBuilder: (elapsed) {
              if (_orbit) {
                final t = elapsed.inMicroseconds / 1e6;
                _cameraPosition = vm.Vector3(
                  math.sin(t * 0.12) * 14,
                  4.0 + math.sin(t * 0.05) * 2.0,
                  math.cos(t * 0.12) * 14,
                );
              }
              return PerspectiveCamera(
                position: _cameraPosition,
                target: vm.Vector3(0, 0.5, 0),
              );
            },
            onTick: (elapsed, deltaSeconds) {
              _tickCrop(elapsed);
              exampleSettings.applyTo(scene);
            },
          ),
        ),
        Positioned(left: 12, bottom: 12, child: _panel()),
      ],
    );
  }

  Widget _panel() {
    final splats = _activeSplats;
    final hasCapture = _sources.containsKey(_SplatSource.capture);
    return Card(
      color: Colors.black.withValues(alpha: 0.55),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasCapture)
              SegmentedButton<_SplatSource>(
                segments: const [
                  ButtonSegment(
                    value: _SplatSource.nebula,
                    label: Text('Nebula'),
                  ),
                  ButtonSegment(
                    value: _SplatSource.capture,
                    label: Text('Strawberry'),
                  ),
                ],
                selected: {_active},
                onSelectionChanged: (s) => _setActive(s.first),
              )
            else
              const Text(
                'Run tool/fetch_splat_asset.sh for the captured scene',
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
            const SizedBox(height: 4),
            Text(
              '${splats.splats.count} splats',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            _slider(
              'Opacity',
              _opacity,
              0.0,
              1.0,
              (v) => setState(() {
                _opacity = v;
                _applyKnobs();
              }),
            ),
            _slider(
              'Splat scale',
              _splatScale,
              0.2,
              2.5,
              (v) => setState(() {
                _splatScale = v;
                _applyKnobs();
              }),
            ),
            Row(
              children: [
                _toggle(
                  'Antialiased',
                  _antialiased,
                  (v) => setState(() {
                    _antialiased = v;
                    _applyKnobs();
                  }),
                ),
                const SizedBox(width: 12),
                _toggle(
                  'Crop sweep',
                  _cropSweep,
                  (v) => setState(() {
                    _cropSweep = v;
                    _applyKnobs();
                  }),
                ),
                const SizedBox(width: 12),
                _toggle('Orbit', _orbit, (v) => setState(() => _orbit = v)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 78,
          child: Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
        SizedBox(
          width: 160,
          child: Slider(value: value, min: min, max: max, onChanged: onChanged),
        ),
        SizedBox(
          width: 34,
          child: Text(
            value.toStringAsFixed(2),
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _toggle(String label, bool value, ValueChanged<bool> onChanged) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}
