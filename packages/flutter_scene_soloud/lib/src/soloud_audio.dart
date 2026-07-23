import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_soloud/flutter_soloud.dart' as sl;
import 'package:vector_math/vector_math.dart';

// The engine world is left-handed (+Z is the look direction); SoLoud's
// 3D math is right-handed. Every vector crossing into SoLoud negates Z
// so stereo panning comes out on the correct ear.

/// SoLoud implementation of the flutter_scene [AudioEngine] contract.
///
/// Attach to the scene root before mounting sources. Initializes the
/// shared [sl.SoLoud] instance on first mount (leaving an instance the
/// app already initialized untouched) and stops its live voices on
/// unmount. The SoLoud engine itself is never deinitialized here, since
/// clips and other engines may outlive this component.
// TODO(audio): configure the platform audio session (iOS category,
// Android focus) instead of only pausing on lifecycle changes.
class SoloudAudioEngine extends AudioEngine with WidgetsBindingObserver {
  SoloudAudioEngine({
    this.maxActiveVoices = 32,
    this.pauseWhenBackgrounded = true,
  });

  /// Maximum simultaneous voices. SoLoud's default of 16 is low for
  /// scenes with many emitters.
  final int maxActiveVoices;

  /// Pause all live voices while the app is backgrounded.
  final bool pauseWhenBackgrounded;

  final sl.SoLoud _soloud = sl.SoLoud.instance;
  final Completer<void> _ready = Completer<void>();
  bool _observing = false;

  late final SoloudAudioBus _master = SoloudAudioBus._(this, 'master', null);
  final Set<SoloudAudioVoice> _liveVoices = {};

  @override
  String get backendName => 'soloud';

  @override
  AudioBus get masterBus => _master;

  @override
  AudioBus onCreateBus(String name, AudioBus parent) =>
      SoloudAudioBus._(this, name, parent as SoloudAudioBus);

  @override
  Future<void> onLoad() async {
    if (!_soloud.isInitialized) {
      await _soloud.init();
    }
    _soloud.setMaxActiveVoiceCount(maxActiveVoices);
    _master._pushNative();
    WidgetsBinding.instance.addObserver(this);
    _observing = true;
    _ready.complete();
  }

  @override
  void onUnmount() {
    for (final voice in _liveVoices.toList()) {
      voice.stop();
    }
    _liveVoices.clear();
  }

  @override
  void onDetach() {
    if (_observing) {
      WidgetsBinding.instance.removeObserver(this);
      _observing = false;
    }
  }

  @override
  Future<AudioClip> loadClip(String assetKey) async {
    await _ready.future;
    final source = await _soloud.loadAsset(assetKey);
    return SoloudAudioClip._(this, source, _soloud.getLength(source));
  }

  @override
  Future<AudioClip> loadClipFromBytes(String key, Uint8List bytes) async {
    await _ready.future;
    final source = await _soloud.loadMem(key, bytes);
    return SoloudAudioClip._(this, source, _soloud.getLength(source));
  }

  @override
  AudioVoice createVoice(AudioClip clip) {
    if (!_soloud.isInitialized) {
      throw StateError('SoloudAudioEngine is not initialized yet.');
    }
    if (clip is! SoloudAudioClip) {
      throw ArgumentError('createVoice needs a clip loaded by this backend.');
    }
    if (clip.isDisposed) {
      throw StateError('AudioClip is disposed.');
    }
    final voice = SoloudAudioVoice._(this, clip);
    _liveVoices.add(voice);
    return voice;
  }

  @override
  void onSyncListener(
    Vector3 position,
    Vector3 forward,
    Vector3 up,
    Vector3 velocity,
  ) {
    if (!_soloud.isInitialized) return;
    _soloud.set3dListenerParameters(
      position.x,
      position.y,
      -position.z,
      forward.x,
      forward.y,
      -forward.z,
      up.x,
      up.y,
      -up.z,
      velocity.x,
      velocity.y,
      -velocity.z,
    );
  }

  @override
  void onFrameCommit(double deltaSeconds) {
    _liveVoices.removeWhere((voice) => !voice.isPlaying);
  }

  // Voices already paused by the user stay paused across a background
  // round trip; only the ones this observer paused are resumed.
  final Set<SoloudAudioVoice> _pausedByLifecycle = {};

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!pauseWhenBackgrounded) return;
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        for (final voice in _liveVoices) {
          if (!voice.isPaused) {
            voice.pause();
            _pausedByLifecycle.add(voice);
          }
        }
      case AppLifecycleState.resumed:
        for (final voice in _pausedByLifecycle) {
          voice.resume();
        }
        _pausedByLifecycle.clear();
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  // Bus volumes multiply into each voice's native volume, so a bus
  // change re-pushes every live voice.
  void _busVolumeChanged() {
    for (final voice in _liveVoices) {
      voice._pushVolume();
    }
  }
}

/// SoLoud mix bus.
///
/// The master bus maps to SoLoud's global volume; child buses are
/// applied per voice (SoLoud's native bus objects are not exposed by
/// flutter_soloud).
// TODO(audio): route through native SoLoud buses if flutter_soloud
// exposes them, so bus volume changes stop touching every voice.
class SoloudAudioBus implements AudioBus {
  SoloudAudioBus._(this._engine, this.name, this._parent);

  final SoloudAudioEngine _engine;

  @override
  final String name;

  final SoloudAudioBus? _parent;

  @override
  AudioBus? get parent => _parent;

  bool get _isMaster => _parent == null;

  double _volume = 1.0;

  @override
  double get volume => _volume;

  @override
  set volume(double value) {
    _volume = value;
    if (_isMaster) {
      _pushNative();
    } else {
      _engine._busVolumeChanged();
    }
  }

  void _pushNative() {
    if (_engine._soloud.isInitialized) {
      _engine._soloud.setGlobalVolume(_volume);
    }
  }

  // The gain this bus chain contributes to a voice. The master's gain
  // is excluded, since it is applied natively as the global volume.
  double get _effectiveVolume =>
      _isMaster ? 1.0 : _volume * _parent!._effectiveVolume;
}

/// A clip decoded by SoLoud.
class SoloudAudioClip implements AudioClip {
  SoloudAudioClip._(this._engine, this.source, this._duration);

  final SoloudAudioEngine _engine;

  /// The underlying flutter_soloud source, for interop with the raw
  /// SoLoud API.
  final sl.AudioSource source;

  final Duration _duration;

  @override
  Duration? get duration => _duration;

  bool _disposed = false;

  @override
  bool get isDisposed => _disposed;

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    // Stops any voices still playing this clip natively.
    unawaited(_engine._soloud.disposeSource(source));
  }
}

/// One SoLoud playback (a voice handle).
class SoloudAudioVoice implements AudioVoice {
  SoloudAudioVoice._(this._engine, this._clip);

  final SoloudAudioEngine _engine;
  final SoloudAudioClip _clip;

  sl.SoundHandle? _handle;
  bool _started = false;
  bool _stopped = false;
  bool _finished = false;
  bool _paused = false;

  double _volume = 1.0;
  double _pitch = 1.0;
  bool _looping = false;
  SoloudAudioBus? _bus;
  bool _positional = false;

  final Vector3 _position = Vector3.zero();
  final Vector3 _velocity = Vector3.zero();

  // Last attenuation values pushed natively, to skip the extra FFI
  // calls on the steady-state path.
  double? _appliedMin, _appliedMax, _appliedRolloffFactor, _appliedDoppler;
  AudioRolloff? _appliedRolloff;

  @override
  bool get isPlaying {
    if (_stopped || _finished) return false;
    final handle = _handle;
    if (handle != null && !_engine._soloud.getIsValidVoiceHandle(handle)) {
      _finished = true;
      return false;
    }
    return true;
  }

  @override
  bool get isPaused => !_started || _paused;

  @override
  void start() {
    if (_started || _stopped) return;
    _started = true;
    unawaited(_startNative());
  }

  Future<void> _startNative() async {
    final soloud = _engine._soloud;
    final sl.SoundHandle handle;
    if (_positional) {
      handle = await soloud.play3d(
        _clip.source,
        _position.x,
        _position.y,
        -_position.z,
        velX: _velocity.x,
        velY: _velocity.y,
        velZ: -_velocity.z,
        volume: _effectiveVolume,
        looping: _looping,
      );
    } else {
      handle = await soloud.play(
        _clip.source,
        volume: _effectiveVolume,
        looping: _looping,
      );
    }
    _handle = handle;
    // State may have changed while the handle was in flight.
    if (_stopped) {
      unawaited(soloud.stop(handle));
      return;
    }
    if (_pitch != 1.0) soloud.setRelativePlaySpeed(handle, _pitch);
    if (_paused) soloud.setPause(handle, true);
  }

  @override
  void pause() {
    _paused = true;
    final handle = _handle;
    if (handle != null) _engine._soloud.setPause(handle, true);
  }

  @override
  void resume() {
    _paused = false;
    final handle = _handle;
    if (handle != null) _engine._soloud.setPause(handle, false);
  }

  @override
  void stop() {
    if (_stopped) return;
    _stopped = true;
    final handle = _handle;
    if (handle != null) unawaited(_engine._soloud.stop(handle));
  }

  double get _effectiveVolume => _volume * (_bus?._effectiveVolume ?? 1.0);

  void _pushVolume() {
    final handle = _handle;
    if (handle != null && isPlaying) {
      _engine._soloud.setVolume(handle, _effectiveVolume);
    }
  }

  @override
  double get volume => _volume;

  @override
  set volume(double value) {
    _volume = value;
    _pushVolume();
  }

  @override
  double get pitch => _pitch;

  @override
  set pitch(double value) {
    _pitch = value;
    final handle = _handle;
    if (handle != null) _engine._soloud.setRelativePlaySpeed(handle, value);
  }

  @override
  set looping(bool value) {
    _looping = value;
    final handle = _handle;
    if (handle != null) _engine._soloud.setLooping(handle, value);
  }

  @override
  void setBus(AudioBus? bus) {
    _bus = bus as SoloudAudioBus?;
    _pushVolume();
  }

  @override
  void setPositional(bool positional) {
    _positional = positional;
  }

  @override
  void update3d(
    Vector3 position,
    Vector3 velocity,
    AudioAttenuation attenuation,
  ) {
    _position.setFrom(position);
    _velocity.setFrom(velocity);
    final handle = _handle;
    if (handle == null || !isPlaying) return;
    final soloud = _engine._soloud;
    soloud.set3dSourceParameters(
      handle,
      position.x,
      position.y,
      -position.z,
      velocity.x,
      velocity.y,
      -velocity.z,
    );
    if (attenuation.minDistance != _appliedMin ||
        attenuation.maxDistance != _appliedMax) {
      _appliedMin = attenuation.minDistance;
      _appliedMax = attenuation.maxDistance;
      soloud.set3dSourceMinMaxDistance(
        handle,
        attenuation.minDistance,
        attenuation.maxDistance,
      );
    }
    if (attenuation.rolloff != _appliedRolloff ||
        attenuation.rolloffFactor != _appliedRolloffFactor) {
      _appliedRolloff = attenuation.rolloff;
      _appliedRolloffFactor = attenuation.rolloffFactor;
      soloud.set3dSourceAttenuation(
        handle,
        attenuation.rolloff.index,
        attenuation.rolloffFactor,
      );
    }
    if (attenuation.dopplerFactor != _appliedDoppler) {
      _appliedDoppler = attenuation.dopplerFactor;
      soloud.set3dSourceDopplerFactor(handle, attenuation.dopplerFactor);
    }
  }
}
