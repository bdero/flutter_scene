import 'package:flutter/foundation.dart';
import 'package:flutter_scene/src/audio/audio_attenuation.dart';
import 'package:flutter_scene/src/audio/audio_engine.dart';
import 'package:flutter_scene/src/audio/velocity_tracker.dart';
import 'package:flutter_scene/src/components/component.dart';
import 'package:vector_math/vector_math.dart';

/// A sound emitter attached to a node.
///
/// The abstract base owns what every backend can honor, transport,
/// gain, pitch, and the per-frame world-transform sync for positional
/// playback. Concrete sources add their content model, `ClipAudioSource`
/// plays an `AudioClip` on any backend, and backend packages may add
/// event-style sources with their own surface.
///
/// A source resolves the nearest ancestor [AudioEngine] on mount and is
/// inert without one, so mount the engine before the sources.
/// {@category Audio}
abstract class AudioSource extends Component {
  /// Begins (or restarts) playback.
  void play();

  /// Pauses playback, keeping the position; [play] resumes.
  void pause();

  /// Stops playback and rewinds.
  void stop();

  /// Whether the source is currently playing (not paused or stopped).
  bool get isPlaying;

  /// Gain for this source. `1.0` is unity.
  double get volume;
  set volume(double value);

  /// Playback rate multiplier. `1.0` is natural rate.
  double get pitch;
  set pitch(double value);

  /// Whether playback is spatialized at the node's world position.
  /// When `false` the source plays flat (music, UI). Changing it while
  /// playing takes effect on the next [play].
  bool positional = true;

  /// Spatialization parameters, re-applied every frame while playing
  /// positionally. Sources whose attenuation is authored externally
  /// (event middleware) treat this as an override hint at most.
  AudioAttenuation attenuation = AudioAttenuation();

  AudioEngine? _engine;

  /// The nearest ancestor engine, resolved while mounted.
  AudioEngine? get engine => _engine;

  final VelocityTracker _velocity = VelocityTracker();

  @override
  @mustCallSuper
  void onMount() {
    _engine = AudioEngine.findAncestor(node);
  }

  @override
  @mustCallSuper
  void onUnmount() {
    _engine = null;
    _velocity.reset();
  }

  @override
  void update(double deltaSeconds) {
    if (!positional || _engine == null) return;
    final position = node.globalTransform.getTranslation();
    onTransformSync(position, _velocity.derive(node, position, deltaSeconds));
  }

  /// Concrete-source hook receiving this frame's world position and
  /// velocity while the source is positional and mounted under an
  /// engine. Subclasses overriding [update] must call `super.update`
  /// to keep receiving it.
  @protected
  void onTransformSync(Vector3 position, Vector3 velocity);
}
