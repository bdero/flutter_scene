import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart'
    show
        CuboidGeometry,
        DirectionalLight,
        DirectionalLightComponent,
        Mesh,
        Node,
        PerspectiveCamera,
        PhysicallyBasedMaterial,
        PlaneGeometry,
        ReflectionProbeComponent,
        Scene,
        SceneView,
        SphereGeometry;
import 'package:vector_math/vector_math.dart' as vm;

import 'example_settings.dart';

/// A colored room with mirror spheres lit through a reflection probe: the
/// probe captures the room once and the spheres reflect the walls with
/// parallax-corrected sampling, so the reflections track the room as the
/// camera orbits instead of floating at infinity.
class ExampleReflectionProbes extends StatefulWidget {
  const ExampleReflectionProbes({super.key});

  @override
  State<ExampleReflectionProbes> createState() =>
      _ExampleReflectionProbesState();
}

class _ExampleReflectionProbesState extends State<ExampleReflectionProbes> {
  final Scene scene = Scene();
  final PerspectiveCamera camera = PerspectiveCamera(
    position: vm.Vector3(0, 2.2, 5.4),
    target: vm.Vector3(0, 1.0, 0),
  );
  ReflectionProbeComponent? _probe;

  @override
  void initState() {
    super.initState();
    scene.add(
      Node()..addComponent(
        DirectionalLightComponent.aimed(
          DirectionalLight(intensity: 2.5, castsShadow: true),
          vm.Vector3(-0.4, -1.0, -0.3),
        ),
      ),
    );

    PhysicallyBasedMaterial wall(double r, double g, double b) =>
        PhysicallyBasedMaterial()
          ..baseColorFactor = vm.Vector4(r, g, b, 1.0)
          ..metallicFactor = 0.0
          ..roughnessFactor = 0.85
          ..vertexColorWeight = 0.0;

    scene.add(
      Node(mesh: Mesh(PlaneGeometry(width: 8, depth: 8), wall(0.7, 0.7, 0.7))),
    );
    scene.add(
      Node(
        mesh: Mesh(
          CuboidGeometry(vm.Vector3(0.15, 3.2, 8.0)),
          wall(0.75, 0.1, 0.08),
        ),
      )..localTransform = vm.Matrix4.translation(vm.Vector3(-4.0, 1.6, 0)),
    );
    scene.add(
      Node(
        mesh: Mesh(
          CuboidGeometry(vm.Vector3(0.15, 3.2, 8.0)),
          wall(0.08, 0.2, 0.8),
        ),
      )..localTransform = vm.Matrix4.translation(vm.Vector3(4.0, 1.6, 0)),
    );
    scene.add(
      Node(
        mesh: Mesh(
          CuboidGeometry(vm.Vector3(8.0, 3.2, 0.15)),
          wall(0.9, 0.65, 0.15),
        ),
      )..localTransform = vm.Matrix4.translation(vm.Vector3(0, 1.6, -4.0)),
    );

    final mirror = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.95, 0.95, 0.95, 1.0)
      ..metallicFactor = 1.0
      ..roughnessFactor = 0.05
      ..vertexColorWeight = 0.0;
    final brushed = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.9, 0.85, 0.75, 1.0)
      ..metallicFactor = 1.0
      ..roughnessFactor = 0.3
      ..vertexColorWeight = 0.0;
    for (var i = 0; i < 3; i++) {
      scene.add(
        Node(mesh: Mesh(SphereGeometry(radius: 0.6), i == 1 ? brushed : mirror))
          ..localTransform = vm.Matrix4.translation(
            vm.Vector3((i - 1) * 1.7, 0.85, (i - 1).abs() * -0.6),
          ),
      );
    }

    // The probe box wraps the room; captures happen once on activation and
    // again on request (the settings drawer's render scale does not affect
    // the capture).
    final probe = ReflectionProbeComponent(
      extents: vm.Vector3(4.0, 2.5, 5.5),
      blendDistance: 3.0,
      faceResolution: 256,
    );
    _probe = probe;
    scene.add(
      Node()
        ..addComponent(probe)
        ..localTransform = vm.Matrix4.translation(vm.Vector3(0, 1.6, 0.8)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        SceneView(
          scene,
          camera: camera,
          onTick: (elapsed, deltaSeconds) {
            final t = elapsed.inMicroseconds / 1e6;
            camera.position = vm.Vector3(
              math.sin(t * 0.25) * 4.6,
              2.2,
              math.cos(t * 0.25) * 4.6 + 1.2,
            );
            exampleSettings.applyTo(scene);
          },
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.small(
            tooltip: 'Re-capture probe',
            onPressed: () => _probe?.requestCapture(),
            child: const Icon(Icons.camera),
          ),
        ),
      ],
    );
  }
}
