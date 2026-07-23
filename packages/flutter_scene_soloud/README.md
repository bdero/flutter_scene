# flutter_scene_soloud

SoLoud audio backend for [flutter_scene](https://pub.dev/packages/flutter_scene). Implements the abstract audio contract (`AudioEngine`, `AudioVoice`, `AudioBus`, `AudioClip`) over the SoLoud engine through [flutter_soloud](https://pub.dev/packages/flutter_soloud).

## Usage

Attach the engine to the scene root, then use the contract types from flutter_scene:

```dart
import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_soloud/flutter_scene_soloud.dart';

final scene = Scene();
scene.root.addComponent(SoloudAudioEngine());

final ambience = Node();
ambience.addComponent(ClipAudioSource(
  asset: 'assets/sounds/waterfall.ogg',
  autoplay: true,
  looping: true,
));
scene.add(ambience);
```

With no `AudioListener` mounted, the ears follow the scene's primary camera. Serialized `.fscene`/`.fsceneb` scenes containing `audioSource` components play through whichever engine the app mounts.
