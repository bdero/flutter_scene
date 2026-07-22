import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'example_overlay.dart';
import 'example_panel.dart';
import 'example_settings.dart';
import 'lighting_panel.dart';

class ExampleAnimation extends StatefulWidget {
  const ExampleAnimation({super.key});

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
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // The scene hot reloads in place. The clips below are held by reference and
    // re-bound automatically across a reload (their playback state and the
    // slider bindings survive), so no reload callback is needed.
    final modelNode = await loadScene('assets_src/dash.glb');
    if (!mounted) {
      return;
    }

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

    debugPrint('Scene loaded.');
    if (!mounted) {
      return;
    }
    setState(() {
      loaded = true;
    });
  }

  @override
  void dispose() {
    // Optional: the scene is dropped with this State. `Node.fromAsset` caches
    // the imported model template (shared across clones), so its GPU resources
    // persist for the session regardless.
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
        Positioned.fill(
          child: SceneView(
            scene,
            cameraBuilder: (elapsed) {
              final rotationAmount = elapsed.inMicroseconds / 1e6 * 0.5;
              const distance = 6.0;
              return PerspectiveCamera(
                position: vm.Vector3(
                  sin(rotationAmount) * distance,
                  2,
                  cos(rotationAmount) * distance,
                ),
                target: vm.Vector3(0, 1.5, 0),
              );
            },
            onTick: (elapsed, deltaSeconds) => exampleSettings.applyTo(scene),
          ),
        ),
        // Animation weights are grouped in a side panel instead of occupying
        // the entire scene width as unlabeled sliders.
        if (idleClip != null)
          ExampleOverlay.bottomLeftPanel(child: _buildControls()),
      ],
    );
  }

  Widget _buildControls() {
    final clips = <(String, AnimationClip)>[
      ('Idle weight', idleClip!),
      ('Walk weight', walkClip!),
      ('Run weight', runClip!),
    ];
    return ExamplePanelCard(
      icon: Icons.animation,
      title: 'Animation controls',
      width: 280,
      maxBodyHeight: 300,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (label, clip) in clips)
            LabeledSlider(
              label: label,
              value: clip.weight,
              min: 0,
              max: 1,
              onChanged: (value) => setState(() => clip.weight = value),
            ),
          LabeledSlider(
            label: 'Playback speed',
            value: walkClip!.playbackTimeScale,
            min: -2,
            max: 2,
            onChanged: (value) => setState(() {
              idleClip!.playbackTimeScale = value;
              walkClip!.playbackTimeScale = value;
              runClip!.playbackTimeScale = value;
            }),
          ),
        ],
      ),
    );
  }
}
