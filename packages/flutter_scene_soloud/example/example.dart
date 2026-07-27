// Attach the SoLoud backend to a scene and play a spatial clip.
import 'package:flutter_scene/audio.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_soloud/flutter_scene_soloud.dart';

Future<void> main() async {
  final scene = Scene();

  // A backend audio engine drives the scene's audio contract. Attach it to
  // the scene root; the listener follows the active camera.
  final engine = SoloudAudioEngine();
  scene.root.addComponent(engine);

  // Load a clip and attach it to a node as a looping spatial source that
  // plays as soon as it mounts.
  final clip = await engine.loadClip('assets/sound.wav');
  scene.add(
    Node()..addComponent(
      ClipAudioSource(clip: clip, autoplay: true, looping: true),
    ),
  );
}
