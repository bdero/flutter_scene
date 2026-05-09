import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// Loads a `.glb` file at runtime via [Node.fromGlbAsset], skipping the
/// offline `.model` import step. Demonstrates the Phase 1 runtime importer.
class ExampleRuntimeGlb extends StatefulWidget {
  const ExampleRuntimeGlb({
    super.key,
    this.elapsedSeconds = 0,
    required this.assetPath,
    this.cameraDistance = 5.0,
    this.cameraTargetY = 0.0,
    this.autoPlayFirstAnimation = false,
  });

  final double elapsedSeconds;
  final String assetPath;
  final double cameraDistance;
  final double cameraTargetY;
  final bool autoPlayFirstAnimation;

  @override
  ExampleRuntimeGlbState createState() => ExampleRuntimeGlbState();
}

class ExampleRuntimeGlbState extends State<ExampleRuntimeGlb> {
  Scene scene = Scene();
  bool loaded = false;
  String? error;

  @override
  void initState() {
    super.initState();
    Node.fromGlbAsset(widget.assetPath).then((node) {
      node.name = 'GLB';
      scene.add(node);
      debugPrint(
        'Runtime-loaded GLB ${widget.assetPath} '
        '(animations: ${node.parsedAnimations.length})',
      );
      if (widget.autoPlayFirstAnimation && node.parsedAnimations.isNotEmpty) {
        node.createAnimationClip(node.parsedAnimations.first)
          ..loop = true
          ..play();
      }
      setState(() => loaded = true);
    }).catchError((Object e, StackTrace st) {
      debugPrint('Failed to runtime-load ${widget.assetPath}: $e\n$st');
      setState(() => error = '$e');
    });

    // Match the environment setup the existing 'Car' example uses, so visual
    // comparisons against the offline-imported `.model` render are apples to
    // apples. Without this we'd render against the default royal_esplanade
    // env at default exposure/intensity, which gives subtly different colors.
    EnvironmentMap.fromAssets(
      radianceImagePath: 'assets/little_paris_eiffel_tower.png',
      irradianceImagePath: 'assets/little_paris_eiffel_tower_irradiance.png',
    ).then((environment) {
      scene.environment.environmentMap = environment;
      scene.environment.exposure = 2.0;
      scene.environment.intensity = 2.0;
    });
  }

  @override
  void dispose() {
    scene.removeAll();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Failed to load ${widget.assetPath}\n\n$error'),
        ),
      );
    }
    if (!loaded) return const Center(child: CircularProgressIndicator());
    return CustomPaint(
      painter: _ScenePainter(
        scene,
        widget.elapsedSeconds,
        widget.cameraDistance,
        widget.cameraTargetY,
      ),
    );
  }
}

class _ScenePainter extends CustomPainter {
  _ScenePainter(this.scene, this.elapsedTime, this.distance, this.targetY);
  final Scene scene;
  final double elapsedTime;
  final double distance;
  final double targetY;

  @override
  void paint(Canvas canvas, Size size) {
    final camera = PerspectiveCamera(
      position: vm.Vector3(
        sin(elapsedTime) * distance,
        distance * 0.4,
        cos(elapsedTime) * distance,
      ),
      target: vm.Vector3(0, targetY, 0),
    );
    scene.render(camera, canvas, viewport: Offset.zero & size);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
