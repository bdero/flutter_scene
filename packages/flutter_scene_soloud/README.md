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

## Codec libraries

The build hook downloads prebuilt Ogg, Vorbis, Opus, and FLAC libraries for the target on first build, so an app's first build needs network access. Offline builds and targets without prebuilts pick one of these under `hooks.user_defines.flutter_soloud` in the app's `pubspec.yaml` (the app's, not this package's).

```yaml
hooks:
  user_defines:
    flutter_soloud:
      linux_use_system_libs: true   # link the distro's packages
      # linux_force_build_libs: true  # or compile them from source
      # no_xiph_libs: true            # or build without them; Ogg, Opus, and FLAC loads throw
```

`macos_` and `windows_` variants of the first two exist as well. Prebuilts cover Linux x64 and arm64, macOS, Windows x64, Android, and iOS.

## Web

Add the SoLoud loader to `web/index.html`.

```html
<script src="assets/packages/flutter_soloud/web/init_soloud.js" defer></script>
```
