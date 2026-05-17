import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

class ExampleInstancing extends StatefulWidget {
  const ExampleInstancing({super.key, this.elapsedSeconds = 0});
  final double elapsedSeconds;

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
      geometry: CuboidGeometry(vm.Vector3(0.6, 0.6, 0.6)),
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
    return CustomPaint(painter: _ScenePainter(scene, widget.elapsedSeconds));
  }
}

class _ScenePainter extends CustomPainter {
  _ScenePainter(this.scene, this.elapsedTime);
  Scene scene;
  double elapsedTime;

  @override
  void paint(Canvas canvas, Size size) {
    final camera = PerspectiveCamera(
      position: vm.Vector3(
        sin(elapsedTime * 0.3) * 18,
        12,
        cos(elapsedTime * 0.3) * 18,
      ),
      target: vm.Vector3(0, 0, 0),
    );

    scene.render(camera, canvas, viewport: Offset.zero & size);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
