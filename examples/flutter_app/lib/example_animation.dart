import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

class ExampleAnimation extends StatefulWidget {
  const ExampleAnimation({super.key, this.elapsedSeconds = 0});
  final double elapsedSeconds;

  @override
  ExampleAnimationState createState() => ExampleAnimationState();
}

class ExampleAnimationState extends State<ExampleAnimation> {
  Scene scene = Scene();
  bool loaded = false;
  AnimationClip? idleClip;
  AnimationClip? runClip;
  AnimationClip? walkClip;

  @override
  void initState() {
    final dashModel = Node.fromAsset('build/models/dash.model').then((
      modelNode,
    ) {
      for (final animation in modelNode.parsedAnimations) {
        debugPrint('Animation: ${animation.name}');
      }

      scene.add(modelNode);

      idleClip =
          modelNode.createAnimationClip(modelNode.findAnimationByName('Idle')!)
            ..loop = true
            ..play();
      walkClip =
          modelNode.createAnimationClip(modelNode.findAnimationByName('Walk')!)
            ..loop = true
            ..weight = 0
            ..play();
      runClip =
          modelNode.createAnimationClip(modelNode.findAnimationByName('Run')!)
            ..loop = true
            ..weight = 0
            ..play();
    });

    Future.wait([dashModel]).then((_) {
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
    return Stack(
      children: [
        SizedBox.expand(
          child: CustomPaint(
            painter: _ScenePainter(scene, widget.elapsedSeconds),
          ),
        ),
        // Door open slider
        if (idleClip != null)
          Column(
            children: [
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final clip in [idleClip, walkClip, runClip])
                    Slider(
                      value: clip!.weight,
                      onChanged: (value) {
                        clip.weight = value;
                      },
                    ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Slider(
                    min: -2,
                    max: 2,
                    value: walkClip!.playbackTimeScale,
                    onChanged: (value) {
                      idleClip!.playbackTimeScale = value;
                      walkClip!.playbackTimeScale = value;
                      runClip!.playbackTimeScale = value;
                    },
                  ),
                ],
              ),
            ],
          ),
      ],
    );
  }
}

class _ScenePainter extends CustomPainter {
  _ScenePainter(this.scene, this.elapsedTime);
  Scene scene;
  double elapsedTime;

  @override
  void paint(Canvas canvas, Size size) {
    double rotationAmount = elapsedTime * 0.5;
    const double distance = 6;
    final camera = PerspectiveCamera(
      position: vm.Vector3(
        sin(rotationAmount) * distance,
        2,
        cos(rotationAmount) * distance,
      ),
      target: vm.Vector3(0, 1.5, 0),
    );

    scene.render(camera, canvas, viewport: Offset.zero & size);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
