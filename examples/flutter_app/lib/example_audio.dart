import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_soloud/flutter_scene_soloud.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'example_action_hint.dart';
import 'example_settings.dart';

/// Spatial audio through the SoLoud backend. An emitter orbits the camera
/// carrying a looping hum (pan and doppler as it passes), and tapping
/// plays a one-shot chime at a random position, marked by a brief cube.
/// The listener follows the camera automatically.
class ExampleAudio extends StatefulWidget {
  const ExampleAudio({super.key});

  @override
  ExampleAudioState createState() => ExampleAudioState();
}

/// Orbits the owning node about the world Y axis at [radius].
class _OrbitComponent extends Component {
  _OrbitComponent(this.radius, this.radiansPerSecond);

  final double radius;
  final double radiansPerSecond;
  double _angle = 0;

  @override
  void update(double deltaSeconds) {
    _angle += radiansPerSecond * deltaSeconds;
    node.localTransform = vm.Matrix4.translation(
      vm.Vector3(sin(_angle) * radius, 1.0, cos(_angle) * radius),
    );
  }
}

class ExampleAudioState extends State<ExampleAudio> {
  Scene scene = Scene();
  late final SoloudAudioEngine engine;
  AudioClip? chime;
  final random = Random();

  // Chime markers with their removal deadlines. Expired outside the
  // scene's component walk (removing a node from a component's update
  // mutates the child list mid-iteration).
  final List<(Node, DateTime)> _markers = [];

  @override
  void initState() {
    engine = SoloudAudioEngine();
    scene.root.addComponent(engine);
    engine.loadClip('assets/sounds/chime.wav').then((clip) => chime = clip);

    // The orbiting emitter, audible and visible.
    final emitter =
        Node(
            mesh: Mesh(
              SphereGeometry(radius: 0.3),
              UnlitMaterial()..baseColorFactor = vm.Vector4(1.0, 0.6, 0.1, 1.0),
            ),
          )
          ..addComponent(_OrbitComponent(5.0, 0.9))
          ..addComponent(
            ClipAudioSource(
              asset: 'assets/sounds/hum_loop.wav',
              autoplay: true,
              looping: true,
              attenuation: AudioAttenuation(
                minDistance: 2.0,
                maxDistance: 40.0,
              ),
            ),
          );
    scene.add(emitter);

    // A reference cube at the origin so the orbit reads spatially.
    scene.add(
      Node(
        mesh: Mesh(
          CuboidGeometry(vm.Vector3(1, 1, 1), debugColors: true),
          UnlitMaterial(),
        ),
      ),
    );

    super.initState();
  }

  @override
  void dispose() {
    chime?.dispose();
    super.dispose();
  }

  void _playChime() {
    final clip = chime;
    if (clip == null) return;
    final position = vm.Vector3(
      (random.nextDouble() - 0.5) * 12,
      random.nextDouble() * 3,
      (random.nextDouble() - 0.5) * 12,
    );
    engine.playOneShot(
      clip,
      position: position,
      pitch: 0.9 + random.nextDouble() * 0.2,
    );
    // Mark where the chime came from, briefly.
    final marker = Node(
      mesh: Mesh(
        CuboidGeometry(vm.Vector3(0.4, 0.4, 0.4)),
        UnlitMaterial()..baseColorFactor = vm.Vector4(0.3, 0.8, 1.0, 1.0),
      ),
    );
    marker.localTransform = vm.Matrix4.translation(position);
    scene.add(marker);
    _markers.add((marker, DateTime.now().add(const Duration(seconds: 1))));
  }

  void _expireMarkers() {
    if (_markers.isEmpty) return;
    final now = DateTime.now();
    _markers.removeWhere((entry) {
      final (node, deadline) = entry;
      if (now.isBefore(deadline)) return false;
      scene.remove(node);
      return true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        GestureDetector(
          onTapDown: (_) => _playChime(),
          child: SceneView(
            scene,
            cameraBuilder: (elapsed) => PerspectiveCamera(
              position: vm.Vector3(0, 2.5, -9),
              target: vm.Vector3(0, 0.5, 0),
            ),
            onTick: (elapsed, deltaSeconds) {
              _expireMarkers();
              exampleSettings.applyTo(scene);
            },
          ),
        ),
        const ExampleActionHint(
          message: 'Tap to play a chime at a random position',
        ),
      ],
    );
  }
}
