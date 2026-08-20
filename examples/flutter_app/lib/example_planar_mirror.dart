// Planar reflections: a mirror floor driven by a PlanarReflectorComponent.
//
// The component renders one offscreen capture per frame from the camera
// reflected across the floor plane (near plane clamped to the mirror, so
// nothing below it leaks in) and routes it to the mirror's material, a
// `.fmat` declaring the `planar_reflection` engine input
// (assets/planar_mirror.fmat). The material samples it projectively with
// GetPlanarReflection() and falls back to the environment reflection when no
// capture applies (for example inside another capture).

import 'dart:math' as math;

import 'package:flutter/material.dart' hide Material;
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'example_overlay.dart';
import 'example_panel.dart';
import 'example_settings.dart';

class ExamplePlanarMirror extends StatefulWidget {
  const ExamplePlanarMirror({super.key});

  @override
  State<ExamplePlanarMirror> createState() => _ExamplePlanarMirrorState();
}

class _ExamplePlanarMirrorState extends State<ExamplePlanarMirror> {
  final Scene scene = Scene();
  bool loaded = false;
  Object? _loadError;

  final Node _shapes = Node();
  PreprocessedMaterial? _mirrorMaterial;
  PlanarReflectorComponent? _reflector;

  double reflectivity = 1.0;
  double captureScale = 0.5;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final mirrorMaterial = await loadFmatMaterial(
        'assets/planar_mirror.fmat',
      );
      if (!mounted) return;
      _mirrorMaterial = mirrorMaterial;

      // The mirror surface: a floor plane whose reflector captures the scene
      // across its own plane (the node's local +Y) every visible frame.
      final reflector = PlanarReflectorComponent(resolutionScale: captureScale);
      _reflector = reflector;
      final mirror = Node(
        name: 'Mirror',
        mesh: Mesh(PlaneGeometry(width: 10, depth: 10), mirrorMaterial),
      )..addComponent(reflector);
      scene.add(mirror);

      // Floating shapes to reflect.
      final palette = [
        vm.Vector4(0.9, 0.35, 0.3, 1),
        vm.Vector4(0.35, 0.75, 0.95, 1),
        vm.Vector4(0.95, 0.8, 0.3, 1),
        vm.Vector4(0.5, 0.9, 0.5, 1),
      ];
      for (var i = 0; i < 4; i++) {
        final angle = i * math.pi / 2.0;
        final material = PhysicallyBasedMaterial()
          ..baseColorFactor = palette[i]
          ..roughnessFactor = 0.35
          ..metallicFactor = 0.0;
        final geometry = i.isEven
            ? SphereGeometry(radius: 0.5) as Geometry
            : CuboidGeometry(vm.Vector3.all(0.8));
        _shapes.add(
          Node(mesh: Mesh(geometry, material))
            ..position = vm.Vector3(
              math.cos(angle) * 2.2,
              1.0 + 0.4 * (i % 2),
              math.sin(angle) * 2.2,
            ),
        );
      }
      final pillar = PhysicallyBasedMaterial()
        ..baseColorFactor = vm.Vector4(0.8, 0.8, 0.85, 1)
        ..roughnessFactor = 0.6;
      _shapes.add(
        Node(mesh: Mesh(CuboidGeometry(vm.Vector3(0.6, 2.4, 0.6)), pillar))
          ..position = vm.Vector3(0, 1.2, 0),
      );
      scene.add(_shapes);

      scene.directionalLight = DirectionalLight(
        direction: vm.Vector3(-0.4, -1.0, 0.3),
        castsShadow: true,
      );

      setState(() => loaded = true);
    } catch (error, stackTrace) {
      debugPrint('Planar mirror could not load: $error\n$stackTrace');
      if (mounted) setState(() => _loadError = error);
    }
  }

  @override
  void dispose() {
    scene.removeAll();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loadError = _loadError;
    if (loadError != null) {
      return ExampleLoadFailureCard(
        title: 'Planar mirror could not load',
        detail: '$loadError',
      );
    }
    if (!loaded) {
      return const Center(child: CircularProgressIndicator());
    }

    return Stack(
      children: [
        Positioned.fill(
          child: SceneView(
            scene,
            camera: PerspectiveCamera(
              position: vm.Vector3(0, 3.2, -7),
              target: vm.Vector3(0, 0.8, 0),
            ),
            onTick: (elapsed, deltaSeconds) {
              _shapes.rotation = vm.Quaternion.axisAngle(
                vm.Vector3(0, 1, 0),
                elapsed.inMicroseconds / 1e6 * 0.4,
              );
              exampleSettings.applyTo(scene);
            },
          ),
        ),
        ExampleOverlay.bottomLeftPanel(
          child: ExamplePanelCard(
            icon: Icons.water_outlined,
            title: 'Mirror controls',
            bodyPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            body: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _SliderRow(
                  label: 'Reflectivity',
                  value: reflectivity,
                  min: 0,
                  max: 1,
                  onChanged: (v) => setState(() {
                    reflectivity = v;
                    _mirrorMaterial?.parameters.setFloat('reflectivity', v);
                  }),
                ),
                _SliderRow(
                  label: 'Capture scale',
                  value: captureScale,
                  min: 0.1,
                  max: 1,
                  onChanged: (v) => setState(() {
                    captureScale = v;
                    _reflector?.resolutionScale = v;
                  }),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });
  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 110,
          child: Text(
            '$label: ${value.toStringAsFixed(2)}',
            style: const TextStyle(color: Colors.white),
          ),
        ),
        Expanded(
          child: Slider(value: value, min: min, max: max, onChanged: onChanged),
        ),
      ],
    );
  }
}
