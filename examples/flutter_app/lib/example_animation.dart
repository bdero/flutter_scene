import 'dart:math';

import 'package:flutter/material.dart';

import 'package:flutter_scene/camera.dart';
import 'package:flutter_scene/node.dart';
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

  @override
  void initState() {
    final dashModel =
        Node.fromAsset('build/models/dash.model').then((modelNode) {
      for (final animation in modelNode.parsedAnimations) {
        debugPrint('Animation: ${animation.name}');
      }

      const List<String> animationNames = [
        "Run",
        "Walk",
        "Idle",
      ];

      const int dimension = 6;
      const double start = -(dimension - 1) / 2;
      const double end = start + dimension - 1;
      for (double x = start; x <= end; x++) {
        for (double y = start; y <= end; y++) {
          for (double z = start; z <= end; z++) {
            // Clone the model and randomize the rotation.
            final clone = modelNode.clone();
            clone.localTransform =
                vm.Matrix4.translation(vm.Vector3(x, y, z) * 4);
            clone.localTransform
                .rotate(vm.Vector3(0, 1, 0), Random().nextDouble() * 2 * pi);
            scene.add(clone);

            // Instantiate an animation with a bunch of random stuff.
            final animationName =
                animationNames[Random().nextInt(animationNames.length)];
            final animation = clone.findAnimationByName(animationName)!;
            final clip = clone.createAnimationClip(animation);
            clip.loop = true;
            clip.play();
            clip.playbackTimeScale = 0.5 + Random().nextDouble() * 1.5;
            if (Random().nextBool()) {
              clip.playbackTimeScale *= -1;
            }
            clip.weight = 0.5 + Random().nextDouble() * 0.5;
          }
        }
      }
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
    const double distance = 30;
    final camera = PerspectiveCamera(
      position: vm.Vector3(
          sin(elapsedTime) * distance, 2, cos(elapsedTime) * distance),
      target: vm.Vector3(0, 1.5, 0),
    );

    scene.render(camera, canvas, viewport: Offset.zero & size);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
