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
