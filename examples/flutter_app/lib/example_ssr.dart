import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'example_settings.dart';

/// Demonstrates screen-space reflections: a dark floor reflects a ring of
/// lit objects standing on it. The camera orbits at a low, grazing angle
/// where the reflections read most strongly.
class ExampleSsr extends StatefulWidget {
  const ExampleSsr({super.key});

  @override
  ExampleSsrState createState() => ExampleSsrState();
}

class ExampleSsrState extends State<ExampleSsr> {
  Scene scene = Scene();

  @override
  void initState() {
    super.initState();

    scene.root.addComponent(
      DirectionalLightComponent(
        DirectionalLight(
          direction: vm.Vector3(-0.5, -1.0, -0.4),
          intensity: 3.0,
          castsShadow: true,
          shadowMaxDistance: 30.0,
        ),
      ),
    );

    // A large, dark, smooth floor at y = 0. Screen-space reflections compose
    // over the lit image, so the surrounding objects appear mirrored in it.
    final floor = Node(
      mesh: Mesh(
        PlaneGeometry(width: 40, depth: 40),
        PhysicallyBasedMaterial()
          ..baseColorFactor = vm.Vector4(0.02, 0.02, 0.025, 1.0)
          ..roughnessFactor = 0.1
          ..metallicFactor = 0.0,
      ),
    );
    scene.add(floor);

    // A ring of brightly colored objects sitting on the floor.
    final palette = <vm.Vector4>[
      vm.Vector4(0.90, 0.25, 0.25, 1.0),
      vm.Vector4(0.95, 0.65, 0.20, 1.0),
      vm.Vector4(0.25, 0.80, 0.40, 1.0),
      vm.Vector4(0.25, 0.55, 0.95, 1.0),
      vm.Vector4(0.70, 0.35, 0.90, 1.0),
      vm.Vector4(0.95, 0.85, 0.30, 1.0),
    ];
    const count = 6;
    const ringRadius = 4.0;
    for (var i = 0; i < count; i++) {
      final angle = (i / count) * 2 * pi;
      final geometry = i.isEven
          ? SphereGeometry(radius: 0.9)
          : CuboidGeometry(vm.Vector3(1.4, 1.6, 1.4));
      final height = i.isEven ? 0.9 : 0.8;
      final node =
          Node(
              mesh: Mesh(
                geometry,
                PhysicallyBasedMaterial()
                  ..baseColorFactor = palette[i]
                  ..roughnessFactor = 0.4
                  ..metallicFactor = 0.0,
              ),
            )
            ..localTransform = vm.Matrix4.translation(
              vm.Vector3(
                cos(angle) * ringRadius,
                height,
                sin(angle) * ringRadius,
              ),
            );
      scene.add(node);
    }

    scene.environmentIntensity = 0.5;
    scene.screenSpaceReflections.enabled = true;
  }

  @override
  Widget build(BuildContext context) {
    return SceneView(
      scene,
      cameraBuilder: (elapsed) {
        final t = elapsed.inMicroseconds / 1e6;
        // Orbit slowly at a low height for a grazing view of the floor, where
        // the reflections are strongest.
        return PerspectiveCamera(
          position: vm.Vector3(sin(t * 0.3) * 9, 2.2, cos(t * 0.3) * 9),
          target: vm.Vector3(0, 1.0, 0),
          fovFar: 50,
        );
      },
      onTick: (elapsed, deltaSeconds) => exampleSettings.applyTo(scene),
    );
  }
}
