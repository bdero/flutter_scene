import 'package:flutter/foundation.dart';
import 'package:flutter_scene/src/audio/audio_attenuation.dart';
import 'package:flutter_scene/src/audio/audio_bus.dart';
import 'package:flutter_scene/src/audio/audio_clip.dart';
import 'package:flutter_scene/src/audio/audio_listener.dart';
import 'package:flutter_scene/src/audio/audio_voice.dart';
import 'package:flutter_scene/src/audio/velocity_tracker.dart';
import 'package:flutter_scene/src/camera.dart';
import 'package:flutter_scene/src/components/component.dart';
import 'package:flutter_scene/src/node.dart';
import 'package:vector_math/vector_math.dart';

/// The audio playback system for a subtree of the scene graph.
///
/// Attach a concrete [AudioEngine] subclass (from a backend package) to
/// a node, typically the scene root, before mounting sources.
/// Descendant `AudioSource` components and [AudioListener]s resolve the
/// nearest ancestor engine on mount; a source mounted with no ancestor
/// engine stays inert.
///
/// Each frame the scene driver syncs the listener and lets the backend
/// flush. The listener is the first mounted [AudioListener] in the
/// engine's subtree; with none mounted, the ears follow the scene's
/// primary camera, so spatial audio works with no listener setup.
///
/// Backends implement clip loading ([loadClip]), voice creation
/// ([createVoice]), bus creation ([onCreateBus]), and the per-frame
/// hooks ([onSyncListener], [onFrameCommit]). App-lifecycle policy
/// (pausing playback while backgrounded, platform audio-session setup)
/// is a backend concern; see the backend package's documentation.
/// {@category Audio}
abstract class AudioEngine extends Component {
  /// Identifier of the concrete backend, suitable for logging (for
  /// example `"soloud"`).
  String get backendName;

  /// The root of the bus hierarchy. Every voice not routed elsewhere
  /// plays through it.
  AudioBus get masterBus;

  /// Gain applied to all playback. Shorthand for the master bus volume.
  double get masterVolume => masterBus.volume;
  set masterVolume(double value) => masterBus.volume = value;

  final Map<String, AudioBus> _buses = {};

  /// Creates a named mix bus routed into [parent] (the master bus when
  /// null). Names must be unique; `"master"` is reserved.
  AudioBus createBus(String name, {AudioBus? parent}) {
    if (name == 'master' || _buses.containsKey(name)) {
      throw ArgumentError('An audio bus named "$name" already exists.');
    }
    final bus = onCreateBus(name, parent ?? masterBus);
    _buses[name] = bus;
    return bus;
  }

  /// Returns the bus created with [createBus] under [name], the master
  /// bus for `"master"`, or null.
  AudioBus? findBus(String name) => name == 'master' ? masterBus : _buses[name];

  /// Backend hook creating the concrete bus. Called by [createBus].
  @protected
  AudioBus onCreateBus(String name, AudioBus parent);

  /// Loads and decodes an audio asset (a Flutter asset key) into a
  /// playable clip. Completes after the engine finishes initializing.
  Future<AudioClip> loadClip(String assetKey);

  /// Creates a paused single-use voice playing [clip]. See [AudioVoice]
  /// for the configure-then-[AudioVoice.start] flow. Throws when the
  /// engine is not ready or [clip] is disposed.
  AudioVoice createVoice(AudioClip clip);

  /// Plays [clip] once, fire and forget. With a [position] the sound is
  /// spatialized there (stationary); without one it plays flat. The
  /// returned voice can adjust or stop the playback.
  AudioVoice playOneShot(
    AudioClip clip, {
    Vector3? position,
    double volume = 1.0,
    double pitch = 1.0,
    AudioBus? bus,
    AudioAttenuation? attenuation,
  }) {
    final voice = createVoice(clip);
    voice.volume = volume;
    voice.pitch = pitch;
    voice.setBus(bus);
    voice.setPositional(position != null);
    if (position != null) {
      voice.update3d(
        position,
        Vector3.zero(),
        attenuation ?? _oneShotAttenuation,
      );
    }
    voice.start();
    return voice;
  }

  static final AudioAttenuation _oneShotAttenuation = AudioAttenuation();

  // Mounted listeners in this engine's subtree, in mount order. The
  // first is active.
  final List<AudioListener> _listeners = [];

  /// The listener whose node currently provides the ears, or null when
  /// the engine is following the camera fallback.
  AudioListener? get activeListener =>
      _listeners.isEmpty ? null : _listeners.first;

  @internal
  void registerListener(AudioListener listener) {
    _listeners.add(listener);
  }

  @internal
  void unregisterListener(AudioListener listener) {
    _listeners.remove(listener);
    if (_listeners.isEmpty) _listenerVelocity.reset();
  }

  final VelocityTracker _listenerVelocity = VelocityTracker();

  /// Per-frame driver entry point, called by the scene after component
  /// ticks. Resolves the listener pose, then hands control to the
  /// backend hooks. User code should not call this directly.
  @internal
  void frameSync(double deltaSeconds, {Camera? fallbackCamera}) {
    if (!enabled || !isMounted || !isLoaded) return;
    final listenerNode = activeListener?.node;
    if (listenerNode != null) {
      final transform = listenerNode.globalTransform;
      final position = transform.getTranslation();
      final rotation = transform.getRotation();
      // Matches the camera convention. The listener node's local +Z is
      // the facing direction and +Y is up.
      final forward = rotation.transform(Vector3(0, 0, 1))..normalize();
      final up = rotation.transform(Vector3(0, 1, 0))..normalize();
      final velocity = _listenerVelocity.derive(
        listenerNode,
        position,
        deltaSeconds,
      );
      onSyncListener(position, forward, up, velocity);
    } else if (fallbackCamera != null) {
      final position = fallbackCamera.position;
      onSyncListener(
        position,
        fallbackCamera.forward,
        fallbackCamera.up,
        _cameraVelocity.deriveFromPosition(position, deltaSeconds),
      );
    }
    onFrameCommit(deltaSeconds);
  }

  final PositionVelocityTracker _cameraVelocity = PositionVelocityTracker();

  /// Backend hook receiving this frame's listener pose (world space).
  @protected
  void onSyncListener(
    Vector3 position,
    Vector3 forward,
    Vector3 up,
    Vector3 velocity,
  );

  /// Backend hook run once per frame after the listener and all source
  /// transforms are current. Backends that batch native commands flush
  /// here.
  @protected
  void onFrameCommit(double deltaSeconds) {}

  /// Returns the nearest [AudioEngine] on [node] or an ancestor, or
  /// null.
  static AudioEngine? findAncestor(Node node) {
    for (Node? current = node; current != null; current = current.parent) {
      final engine = current.getComponent<AudioEngine>();
      if (engine != null) return engine;
    }
    return null;
  }
}
