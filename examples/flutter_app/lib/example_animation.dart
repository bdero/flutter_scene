import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'example_overlay.dart';
import 'example_panel.dart';
import 'example_settings.dart';
import 'lighting_panel.dart';

/// Skeletal animation blending, driven through the declarative API.
///
/// The model and its animation state are declared in `build()`: a
/// [SceneModel] mounts dash.glb as a child of the app-owned [Scene] (the
/// mixed mode, so the shared lighting panel keeps mutating the scene
/// imperatively), and each blend slider just rebuilds with new
/// [SceneAnimationSpec] weights. The widget diffs the specs onto the
/// underlying clips as plain property writes, so dragging a slider costs a
/// field write per frame and the blending itself runs engine-side.
class ExampleAnimation extends StatefulWidget {
  const ExampleAnimation({super.key});

  @override
  ExampleAnimationState createState() => ExampleAnimationState();
}

class ExampleAnimationState extends State<ExampleAnimation> {
  final Scene scene = Scene();

  double _idleWeight = 1.0;
  double _walkWeight = 0.0;
  double _runWeight = 0.0;
  double _speed = 1.0;

  @override
  void dispose() {
    scene.removeAll();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
            // Gating on a loadingBuilder holds the reveal until the
            // declarative model below has loaded.
            loadingBuilder: (context, progress) =>
                const Center(child: CircularProgressIndicator()),
            children: [
              SceneModel(
                'assets_src/dash.glb',
                animations: [
                  SceneAnimationSpec(
                    'Idle',
                    weight: _idleWeight,
                    speed: _speed,
                  ),
                  SceneAnimationSpec(
                    'Walk',
                    weight: _walkWeight,
                    speed: _speed,
                  ),
                  SceneAnimationSpec('Run', weight: _runWeight, speed: _speed),
                ],
              ),
            ],
          ),
        ),
        // Animation weights are grouped in a side panel instead of occupying
        // the entire scene width as unlabeled sliders.
        ExampleOverlay.bottomLeftPanel(child: _buildControls()),
      ],
    );
  }

  Widget _buildControls() {
    final weights = <(String, double, void Function(double))>[
      ('Idle weight', _idleWeight, (v) => _idleWeight = v),
      ('Walk weight', _walkWeight, (v) => _walkWeight = v),
      ('Run weight', _runWeight, (v) => _runWeight = v),
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
          for (final (label, value, apply) in weights)
            LabeledSlider(
              label: label,
              value: value,
              min: 0,
              max: 1,
              onChanged: (v) => setState(() => apply(v)),
            ),
          LabeledSlider(
            label: 'Playback speed',
            value: _speed,
            min: -2,
            max: 2,
            onChanged: (v) => setState(() => _speed = v),
          ),
        ],
      ),
    );
  }
}
