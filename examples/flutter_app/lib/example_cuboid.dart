import 'dart:math';

import 'package:flutter/material.dart';

import 'package:flutter_scene/camera.dart';
import 'package:flutter_scene/geometry/geometry.dart';
import 'package:flutter_scene/material/unlit_material.dart';
import 'package:flutter_scene/mesh.dart';
import 'package:flutter_scene/scene.dart';

import 'package:vector_math/vector_math.dart' as vm;

class ExampleCuboid extends StatefulWidget {
  const ExampleCuboid({super.key, this.elapsedSeconds = 0});
  final double elapsedSeconds;

  @override
  ExampleCuboidState createState() => ExampleCuboidState();
}

class ExampleCuboidState extends State<ExampleCuboid> {
  Scene scene = Scene();

  @override
  void initState() {
    final mesh = Mesh(CuboidGeometry(vm.Vector3(1, 1, 1)), UnlitMaterial());
    scene.addMesh(mesh);

    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _ScenePainter(scene, widget.elapsedSeconds),
    );
  }
}

class _ScenePainter extends CustomPainter {
  _ScenePainter(this.scene, this.elapsedTime);
  Scene scene;
  double elapsedTime;

  @override
  void paint(Canvas canvas, Size size) {
    final camera = PerspectiveCamera(
      position: vm.Vector3(sin(elapsedTime) * 5, 2, cos(elapsedTime) * 5),
      target: vm.Vector3(0, 0, 0),
    );

    scene.render(camera, canvas, viewport: Offset.zero & size);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
