// Gaussian splat rendering demo. The splat types live under lib/src (not yet
// part of the public barrel); a dev app may import them directly.
// ignore_for_file: implementation_imports

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene/src/components/splat_component.dart';
import 'package:flutter_scene/src/splats/gaussian_splats.dart';
import 'package:flutter_scene/src/splats/splat_data.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'example_settings.dart';

/// A procedural Gaussian splat nebula (60k anisotropic splats) with a PBR
/// sphere parked inside it, proving splats and forward-rendered geometry
/// occlude each other correctly in one scene. The camera orbits slowly; the
/// panel exposes the splat knobs.
///
/// TODO(splats): also load a captured `.ply`/`.splat` asset (downloaded by
/// the asset hook) once the example asset pipeline grows a splat step.
class ExampleSplats extends StatefulWidget {
  const ExampleSplats({super.key});

  @override
  ExampleSplatsState createState() => ExampleSplatsState();
}

class ExampleSplatsState extends State<ExampleSplats> {
  Scene scene = Scene();
  SplatComponent? _splats;
  bool _ready = false;

  double _opacity = 1.0;
  double _splatScale = 1.0;
  bool _antialiased = true;
  bool _orbit = true;
  vm.Vector3 _cameraPosition = vm.Vector3(0, 4, 14);

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

    final splats = GaussianSplats.fromData(_nebula(seed: 7));
    final component = SplatComponent(splats);
    _splats = component;
    scene.add(Node()..addComponent(component));

    // A shiny sphere inside the cloud: splats in front of it must cover it,
    // and it must occlude the splats behind it.
    final sphere = Node(
      mesh: Mesh(
        SphereGeometry(radius: 1.2),
        PhysicallyBasedMaterial()
          ..baseColorFactor = vm.Vector4(0.9, 0.85, 0.8, 1.0)
          ..metallicFactor = 1.0
          ..roughnessFactor = 0.15,
      ),
    )..localTransform = vm.Matrix4.translation(vm.Vector3(2.5, 0.4, 0));
    scene.add(sphere);

    if (mounted) setState(() => _ready = true);
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
        final len = 0.10 + rng.nextDouble() * 0.22;
        final scale = vm.Vector3(len * 3.0, len * 0.8, len);
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
      final len = 0.05 + rng.nextDouble() * 0.2;
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
                target: vm.Vector3(0, 0, 0),
              );
            },
            onTick: (elapsed, deltaSeconds) => exampleSettings.applyTo(scene),
          ),
        ),
        Positioned(left: 12, bottom: 12, child: _panel()),
      ],
    );
  }

  Widget _panel() {
    final splats = _splats;
    if (splats == null) return const SizedBox.shrink();
    return Card(
      color: Colors.black.withValues(alpha: 0.55),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                splats.opacity = v;
              }),
            ),
            _slider(
              'Splat scale',
              _splatScale,
              0.2,
              2.5,
              (v) => setState(() {
                _splatScale = v;
                splats.splatScale = v;
              }),
            ),
            Row(
              children: [
                _toggle(
                  'Antialiased',
                  _antialiased,
                  (v) => setState(() {
                    _antialiased = v;
                    splats.antialiased = v;
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
