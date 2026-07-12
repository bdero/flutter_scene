import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'example_overlay.dart';
import 'example_settings.dart';

class ExampleAnimation extends StatefulWidget {
  const ExampleAnimation({super.key});

  @override
  ExampleAnimationState createState() => ExampleAnimationState();
}

class ExampleAnimationState extends State<ExampleAnimation> {
  Scene scene = Scene();
  bool loaded = false;
  bool _controlsOpen = true;
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
    return SizedBox(
      width: 280,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final bodyMaxHeight = constraints.hasBoundedHeight
              ? min(300.0, max(0.0, constraints.maxHeight - 57.0))
              : 300.0;

          return Card(
            color: Colors.black54,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: () =>
                      setState(() => _controlsOpen = !_controlsOpen),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.animation,
                          color: Colors.white,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Animation controls',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Icon(
                          _controlsOpen
                              ? Icons.expand_less
                              : Icons.expand_more,
                          color: Colors.white,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_controlsOpen) ...[
                  const Divider(height: 1, color: Colors.white24),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: bodyMaxHeight),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final (label, clip) in clips)
                            _slider(
                              label,
                              clip.weight,
                              0,
                              1,
                              (value) =>
                                  setState(() => clip.weight = value),
                            ),
                          _slider(
                            'Playback speed',
                            walkClip!.playbackTimeScale,
                            -2,
                            2,
                            (value) => setState(() {
                              idleClip!.playbackTimeScale = value;
                              walkClip!.playbackTimeScale = value;
                              runClip!.playbackTimeScale = value;
                            }),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        '$label: ${value.toStringAsFixed(2)}',
        style: const TextStyle(color: Colors.white70, fontSize: 12),
      ),
      Slider(value: value, min: min, max: max, onChanged: onChanged),
    ],
  );
}
