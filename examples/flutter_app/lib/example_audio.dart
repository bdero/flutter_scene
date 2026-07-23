import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_soloud/flutter_scene_soloud.dart';
import 'package:http/http.dart' as http;
import 'package:vector_math/vector_math.dart' as vm;

import 'example_action_hint.dart';
import 'example_overlay.dart';
import 'example_panel.dart';
import 'example_settings.dart';
import 'lighting_panel.dart' show LabeledSlider;

/// Spatial audio through the SoLoud backend. An emitter orbits the scene
/// carrying a looping hum (pan and doppler as it passes), tapping plays
/// a one-shot chime at a random position marked by a brief cube, and a
/// CC0 music track downloads at startup and loops through a `music` bus.
/// The mixer panel drives the contract's bus volumes. The listener
/// follows the camera automatically.
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

// "Merfolk Music Box" by Komiku, CC0 1.0, hosted on Wikimedia Commons.
const _musicUrl =
    'https://upload.wikimedia.org/wikipedia/commons/6/69/'
    'Komiku_-_46_-_Merfolk_Music_Box.ogg';
const _musicCredit = '"Merfolk Music Box" by Komiku (CC0)';

class ExampleAudioState extends State<ExampleAudio> {
  Scene scene = Scene();
  late final SoloudAudioEngine engine;
  late final AudioBus musicBus;
  late final AudioBus sfxBus;
  AudioClip? chime;
  ClipAudioSource? music;
  String musicStatus = 'Downloading music…';
  final random = Random();

  // Chime markers with their removal deadlines. Expired outside the
  // scene's component walk (removing a node from a component's update
  // mutates the child list mid-iteration).
  final List<(Node, DateTime)> _markers = [];

  @override
  void initState() {
    engine = SoloudAudioEngine();
    scene.root.addComponent(engine);
    musicBus = engine.createBus('music');
    sfxBus = engine.createBus('sfx');
    engine.loadClip('assets/sounds/chime.wav').then((clip) => chime = clip);
    _loadMusic();

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
              bus: sfxBus,
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

  Future<void> _loadMusic() async {
    try {
      final response = await http.get(Uri.parse(_musicUrl));
      if (response.statusCode != 200) {
        throw StateError('HTTP ${response.statusCode}');
      }
      final clip = await engine.loadClipFromBytes(
        'merfolk_music_box',
        response.bodyBytes,
      );
      if (!mounted) {
        clip.dispose();
        return;
      }
      final source = ClipAudioSource(
        clip: clip,
        autoplay: true,
        looping: true,
        positional: false,
        bus: musicBus,
      );
      scene.add(Node()..addComponent(source));
      setState(() {
        music = source;
        musicStatus = 'Music: $_musicCredit';
      });
    } catch (error) {
      debugPrint('Music download failed. $error');
      if (mounted) {
        setState(() => musicStatus = 'Music download failed (offline?)');
      }
    }
  }

  @override
  void dispose() {
    chime?.dispose();
    music?.clip?.dispose();
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
      volume: 0.6,
      pitch: 0.9 + random.nextDouble() * 0.2,
      bus: sfxBus,
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

  Widget _mixerPanel() {
    final music = this.music;
    return ExamplePanelCard(
      icon: Icons.music_note,
      title: 'Mixer',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          LabeledSlider(
            label: 'Music',
            value: musicBus.volume,
            min: 0,
            max: 1,
            onChanged: (value) => setState(() => musicBus.volume = value),
          ),
          LabeledSlider(
            label: 'Effects',
            value: sfxBus.volume,
            min: 0,
            max: 1,
            onChanged: (value) => setState(() => sfxBus.volume = value),
          ),
          if (music != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(
                  () => music.isPlaying ? music.pause() : music.play(),
                ),
                icon: Icon(
                  music.isPlaying ? Icons.pause : Icons.play_arrow,
                  size: 18,
                ),
                label: Text(music.isPlaying ? 'Pause music' : 'Play music'),
              ),
            ),
          const SizedBox(height: 4),
          Text(
            musicStatus,
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
        ],
      ),
    );
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
        ExampleOverlay.topCenterAction(
          child: const ExampleActionHint(
            message: 'Tap to play a chime at a random position',
          ),
        ),
        ExampleOverlay.bottomRightPanel(
          child: SizedBox(width: 300, child: _mixerPanel()),
        ),
      ],
    );
  }
}
