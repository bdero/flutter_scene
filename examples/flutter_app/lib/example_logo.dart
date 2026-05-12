import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

class ExampleLogo extends StatefulWidget {
  const ExampleLogo({super.key, this.elapsedSeconds = 0});
  final double elapsedSeconds;

  @override
  ExampleLogoState createState() => ExampleLogoState();
}

class ExampleLogoState extends State<ExampleLogo> {
  Scene scene = Scene();
  bool loaded = false;

  @override
  void initState() {
    // A warm key light (with shadows) on top of the default IBL environment.
    scene.directionalLight = DirectionalLight(
      direction: vm.Vector3(0.4, -1.0, 0.3),
      color: vm.Vector3(1.0, 0.97, 0.9),
      intensity: 3.0,
      castsShadow: true,
      shadowFrustumSize: 8.0,
    );

    // A simple ground plane to catch the logo's shadow.
    final ground = Node(
      mesh: Mesh(
        CuboidGeometry(vm.Vector3(8.0, 0.1, 8.0)),
        PhysicallyBasedMaterial()
          ..baseColorFactor = vm.Vector4(0.78, 0.78, 0.8, 1.0)
          ..metallicFactor = 0.0
          ..roughnessFactor = 0.9,
      ),
    );
    ground.localTransform = vm.Matrix4.translation(vm.Vector3(0.0, -1.0, 0.0));
    scene.add(ground);

    final loadModel = Node.fromAsset(
      'build/models/flutter_logo_baked.model',
    ).then((value) {
      value.name = 'FlutterLogo';
      scene.add(value);
      debugPrint('Model loaded: ${value.name}');
    });

    Future.wait([loadModel]).then((_) {
      debugPrint('Scene loaded.');
      setState(() {
        loaded = true;
      });
    });

    super.initState();
  }

  @override
  void dispose() {
    // Technically this isn't necessary, since `Node.fromAsset` doesn't perform
    // a caching import.
    scene.removeAll();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!loaded) {
      return const Center(child: CircularProgressIndicator());
    }

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
      position: vm.Vector3(sin(elapsedTime) * 5, 2, cos(elapsedTime) * 5),
      target: vm.Vector3(0, 0, 0),
    );

    scene.render(camera, canvas, viewport: Offset.zero & size);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
