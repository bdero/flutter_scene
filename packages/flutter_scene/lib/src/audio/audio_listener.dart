import 'package:flutter_scene/src/audio/audio_engine.dart';
import 'package:flutter_scene/src/components/component.dart';

/// Places the ears of the nearest ancestor [AudioEngine] on a node.
///
/// The listener pose follows the owning node's world transform, with
/// the node's local `+Z` as the facing direction and `+Y` as up (the
/// camera convention, so a listener on the camera node hears what the
/// camera sees). Velocity for doppler is derived automatically.
///
/// Optional. With no listener mounted the engine follows the scene's
/// primary camera. When several are mounted, the first mounted wins.
/// {@category Audio}
class AudioListener extends Component {
  AudioEngine? _engine;

  /// The engine this listener registered with, while mounted.
  AudioEngine? get engine => _engine;

  @override
  void onMount() {
    _engine = AudioEngine.findAncestor(node);
    _engine?.registerListener(this);
  }

  @override
  void onUnmount() {
    _engine?.unregisterListener(this);
    _engine = null;
  }
}
