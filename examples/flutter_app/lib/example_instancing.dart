import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'example_settings.dart';

class ExampleInstancing extends StatefulWidget {
  const ExampleInstancing({super.key});

  @override
  ExampleInstancingState createState() => ExampleInstancingState();
}

class ExampleInstancingState extends State<ExampleInstancing> {
  Scene scene = Scene();

  @override
  void initState() {
    // A single InstancedMesh draws a whole grid of cubes: one geometry,
    // one material, and one render item shared by every instance.
    final instancedMesh = InstancedMesh(
      geometry: CuboidGeometry(vm.Vector3(0.6, 0.6, 0.6), debugColors: true),
      material: UnlitMaterial(),
    );
    const halfExtent = 7;
    for (int x = -halfExtent; x <= halfExtent; x++) {
      for (int z = -halfExtent; z <= halfExtent; z++) {
        instancedMesh.addInstance(
          vm.Matrix4.translation(vm.Vector3(x * 1.4, 0, z * 1.4)),
        );
      }
    }
    scene.add(Node()..addComponent(InstancedMeshComponent(instancedMesh)));

    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return SceneView(
      scene,
      cameraBuilder: (elapsed) {
        final t = elapsed.inMicroseconds / 1e6;
        return PerspectiveCamera(
          position: vm.Vector3(sin(t * 0.3) * 18, 12, cos(t * 0.3) * 18),
          target: vm.Vector3(0, 0, 0),
        );
      },
      onTick: (elapsed, deltaSeconds) => exampleSettings.applyTo(scene),
    );
  }
}
