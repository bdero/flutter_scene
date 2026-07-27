// Attach the FMOD backend to a scene and play a spatial clip.
//
// FMOD is proprietary; nothing here ships the SDK. Set FMOD_SDK_PATH (or
// FMOD_LIBRARY_PATH) to a downloaded FMOD Engine SDK before running. See the
// README for setup, and `FmodEventSource` for playing FMOD Studio events.
import 'package:flutter_scene/audio.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_fmod/flutter_scene_fmod.dart';

Future<void> main() async {
  final scene = Scene();

  // A backend audio engine drives the scene's audio contract. Attach it to
  // the scene root; the listener follows the active camera.
  final engine = FmodAudioEngine();
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
