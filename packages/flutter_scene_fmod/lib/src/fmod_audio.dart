import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart';
import 'package:flutter_scene/scene.dart';
import 'package:fmod/fmod.dart' as fmod;
import 'package:vector_math/vector_math.dart';

// FMOD's 3D math is left-handed by default, matching the engine world
// (+Z is the look direction), so vectors pass through unconverted.

/// FMOD Studio implementation of the flutter_scene [AudioEngine]
/// contract, over the `fmod` bindings package.
///
/// Attach to the scene root before mounting sources. The contract
/// surface (clips, `ClipAudioSource`, buses, one-shots) plays through
/// the FMOD Core layer; the Studio layer adds [loadBankAsset]/
/// [loadBankFile], [FmodEventSource] for authored events, and
/// [studioBus] for buses mixed in FMOD Studio. The full bindings are
/// reachable through [system] for anything beyond the contract.
///
/// Requires a user-supplied FMOD Engine SDK; see the package README for
/// setup and licensing. When the libraries cannot be found the engine
/// logs the setup instructions once and stays inert, so the rest of the
/// scene keeps running.
class FmodAudioEngine extends AudioEngine with WidgetsBindingObserver {
  FmodAudioEngine({
    this.maxChannels = 256,
    this.liveUpdate = false,
    this.headerVersion = fmod.kFmodDefaultHeaderVersion,
    this.pauseWhenBackgrounded = true,
  });

  /// Maximum virtual voices passed to system initialization.
  final int maxChannels;

  /// Enable FMOD Studio live update (profiling/mixing from the Studio
  /// tool over the network). Development builds only.
  final bool liveUpdate;

  /// The FMOD header version handshake. Override when using an SDK
  /// series other than the bindings' default.
  final int headerVersion;

  /// Pause all playback while the app is backgrounded.
  final bool pauseWhenBackgrounded;

  fmod.FmodStudioSystem? _system;

  /// The underlying FMOD Studio system, for raw access past the
  /// contract surface. Null until initialization completes (await
  /// [ready]) and when initialization failed.
  fmod.FmodStudioSystem? get system => _system;

  final Completer<void> _ready = Completer<void>();
  Object? _initializationError;
  bool _observing = false;

  late final FmodAudioBus _master = FmodAudioBus._(this, 'master', null);

  /// Completes when the engine finishes initializing (successfully or
  /// not); check [isAvailable] afterwards.
  Future<void> get ready => _ready.future;

  /// Whether the FMOD system initialized and calls will play audio.
  bool get isAvailable => _system != null;

  @override
  String get backendName => 'fmod';

  @override
  AudioBus get masterBus => _master;

  @override
  Future<void> onLoad() async {
    try {
      final system = fmod.FmodStudioSystem.create(
        maxChannels: maxChannels,
        liveUpdate: liveUpdate,
        headerVersion: headerVersion,
      );
      _system = system;
      _master._group = system.core.masterChannelGroup;
      _master._push();
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    } catch (error) {
      _initializationError = error;
      debugPrint(
        'FmodAudioEngine failed to initialize and will stay silent. $error',
      );
    } finally {
      _ready.complete();
    }
  }

  @override
  void onUnmount() {
    for (final voice in _liveVoices.toList()) {
      voice.stop();
    }
    _liveVoices.clear();
    for (final source in _eventSources.toList()) {
      source._releaseInstance();
    }
  }

  @override
  void onDetach() {
    if (_observing) {
      WidgetsBinding.instance.removeObserver(this);
      _observing = false;
    }
    _system?.release();
    _system = null;
  }

  fmod.FmodStudioSystem get _requireSystem {
    final system = _system;
    if (system == null) {
      throw StateError(
        _initializationError == null
            ? 'FmodAudioEngine is not initialized yet.'
            : 'FmodAudioEngine failed to initialize: $_initializationError',
      );
    }
    return system;
  }

  @override
  AudioBus onCreateBus(String name, AudioBus parent) {
    final bus = FmodAudioBus._(this, name, parent as FmodAudioBus);
    if (isAvailable) bus._create();
    return bus;
  }

  final Set<FmodAudioVoice> _liveVoices = {};
  final Set<FmodEventSource> _eventSources = {};

  @override
  Future<AudioClip> loadClip(String assetKey) async {
    await ready;
    final bytes = await rootBundle.load(assetKey);
    return FmodAudioClip._(
      await _requireSystem.core.createSoundFromBytes(
        bytes.buffer.asUint8List(),
      ),
    );
  }

  @override
  Future<AudioClip> loadClipFromBytes(String key, Uint8List bytes) async {
    await ready;
    return FmodAudioClip._(
      await _requireSystem.core.createSoundFromBytes(bytes),
    );
  }

  @override
  AudioVoice createVoice(AudioClip clip) {
    final system = _requireSystem;
    if (clip is! FmodAudioClip) {
      throw ArgumentError('createVoice needs a clip loaded by this backend.');
    }
    if (clip.isDisposed) {
      throw StateError('AudioClip is disposed.');
    }
    final voice = FmodAudioVoice._(system.core.playSound(clip._sound));
    _liveVoices.add(voice);
    return voice;
  }

  /// Loads a Studio bank bundled as a Flutter asset.
  Future<fmod.FmodBank> loadBankAsset(String assetKey) async {
    await ready;
    final bytes = await rootBundle.load(assetKey);
    return _requireSystem.loadBankMemory(bytes.buffer.asUint8List());
  }

  /// Loads a Studio bank from a file path.
  Future<fmod.FmodBank> loadBankFile(String path) async {
    await ready;
    return _requireSystem.loadBankFile(path);
  }

  /// Returns a handle to a bus authored in FMOD Studio (a `bus:/` path).
  /// Its banks must be loaded first.
  fmod.FmodStudioBus studioBus(String path) => _requireSystem.getBus(path);

  @override
  void onSyncListener(
    Vector3 position,
    Vector3 forward,
    Vector3 up,
    Vector3 velocity,
  ) {
    _system?.setListenerAttributes(
      position: position,
      velocity: velocity,
      forward: forward,
      up: up,
    );
  }

  @override
  void onFrameCommit(double deltaSeconds) {
    final system = _system;
    if (system == null) return;
    system.update();
    _liveVoices.removeWhere((voice) => !voice.isPlaying);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final system = _system;
    if (!pauseWhenBackgrounded || system == null) return;
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        system.core.masterChannelGroup.paused = true;
      case AppLifecycleState.resumed:
        system.core.masterChannelGroup.paused = false;
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }
}

/// A contract-level mix bus backed by an FMOD Core channel group.
///
/// Clip voices and one-shots route through these. Buses authored in
/// FMOD Studio are separate; see [FmodAudioEngine.studioBus].
class FmodAudioBus implements AudioBus {
  FmodAudioBus._(this._engine, this.name, this._parent);

  final FmodAudioEngine _engine;

  @override
  final String name;

  final FmodAudioBus? _parent;

  @override
  AudioBus? get parent => _parent;

  fmod.FmodChannelGroup? _group;

  void _create() {
    _group = _engine._requireSystem.core.createChannelGroup(
      name,
      parent: _parent?._group,
    );
    if (_volume != 1.0) _push();
  }

  double _volume = 1.0;

  @override
  double get volume => _volume;

  @override
  set volume(double value) {
    _volume = value;
    _push();
  }

  void _push() {
    _group?.volume = _volume;
  }
}

/// A clip decoded by FMOD Core.
class FmodAudioClip implements AudioClip {
  FmodAudioClip._(this._sound);

  final fmod.FmodSound _sound;

  @override
  Duration? get duration => _sound.duration;

  @override
  bool get isDisposed => _sound.isReleased;

  @override
  void dispose() => _sound.release();
}

/// One FMOD Core playback (a channel).
class FmodAudioVoice implements AudioVoice {
  FmodAudioVoice._(this._channel);

  final fmod.FmodChannel _channel;

  bool _started = false;
  bool _stopped = false;
  bool _paused = false;
  bool _looping = false;
  bool _positional = true;
  int _rolloffFlag = fmod.fmod3dInverseRolloff;

  double? _appliedMin, _appliedMax, _appliedDoppler;

  @override
  bool get isPlaying {
    if (_stopped) return false;
    return _channel.isPlaying;
  }

  @override
  bool get isPaused => !_started || _paused;

  @override
  void start() {
    if (_started || _stopped) return;
    _started = true;
    _applyMode();
    _channel.paused = _paused;
  }

  @override
  void pause() {
    _paused = true;
    if (_started) _channel.paused = true;
  }

  @override
  void resume() {
    _paused = false;
    if (_started) _channel.paused = false;
  }

  @override
  void stop() {
    if (_stopped) return;
    _stopped = true;
    _channel.stop();
  }

  double _volume = 1.0;

  @override
  double get volume => _volume;

  @override
  set volume(double value) {
    _volume = value;
    _channel.volume = value;
  }

  double _pitch = 1.0;

  @override
  double get pitch => _pitch;

  @override
  set pitch(double value) {
    _pitch = value;
    _channel.pitch = value;
  }

  @override
  set looping(bool value) {
    _looping = value;
    _applyMode();
  }

  @override
  void setBus(AudioBus? bus) {
    final group = (bus as FmodAudioBus?)?._group;
    if (group != null) _channel.channelGroup = group;
  }

  @override
  void setPositional(bool positional) {
    _positional = positional;
    _applyMode();
  }

  void _applyMode() {
    final mode =
        (_positional ? fmod.fmod3d | _rolloffFlag : fmod.fmod2d) |
        (_looping ? fmod.fmodLoopNormal : fmod.fmodLoopOff);
    _channel.setMode(mode);
  }

  @override
  void update3d(
    Vector3 position,
    Vector3 velocity,
    AudioAttenuation attenuation,
  ) {
    if (_stopped) return;
    _channel.set3dAttributes(position, velocity);
    // AudioRolloff.none has no FMOD mode flag; a linear rolloff whose
    // min distance never ends approximates it. Exponential maps to
    // FMOD's inverse-tapered curve, the closest available.
    // TODO(audio): honor AudioAttenuation.rolloffFactor; FMOD's rolloff
    // scale is global (System_Set3DSettings), not per channel.
    final rolloffFlag = switch (attenuation.rolloff) {
      AudioRolloff.none => fmod.fmod3dLinearRolloff,
      AudioRolloff.inverse => fmod.fmod3dInverseRolloff,
      AudioRolloff.linear => fmod.fmod3dLinearRolloff,
      AudioRolloff.exponential => fmod.fmod3dInverseTaperedRolloff,
    };
    if (rolloffFlag != _rolloffFlag) {
      _rolloffFlag = rolloffFlag;
      _applyMode();
    }
    final (min, max) = attenuation.rolloff == AudioRolloff.none
        ? (1e9, 1e9)
        : (attenuation.minDistance, attenuation.maxDistance);
    if (min != _appliedMin || max != _appliedMax) {
      _appliedMin = min;
      _appliedMax = max;
      _channel.set3dMinMaxDistance(min, max);
    }
    if (attenuation.dopplerFactor != _appliedDoppler) {
      _appliedDoppler = attenuation.dopplerFactor;
      _channel.dopplerLevel = attenuation.dopplerFactor;
    }
  }
}

/// Plays an event authored in FMOD Studio at a node.
///
/// The event's banks must be loaded (see [FmodAudioEngine.loadBankAsset])
/// before the source mounts, or [play] is called. Attenuation, routing,
/// and looping are authored in Studio; the contract's
/// `AudioSource.attenuation` is ignored unless [overrideDistances] is
/// set, which pushes its min/max distances onto the instance.
class FmodEventSource extends AudioSource {
  FmodEventSource(
    this.eventPath, {
    this.autoplay = false,
    Map<String, double>? parameters,
    double volume = 1.0,
    double pitch = 1.0,
    bool positional = true,
    this.overrideDistances = false,
  }) : _volume = volume,
       _pitch = pitch,
       parameters = Map.of(parameters ?? const {}) {
    this.positional = positional;
  }

  /// The Studio event path (`event:/...`).
  final String eventPath;

  /// Begin the event as soon as the source is mounted and loaded.
  bool autoplay;

  /// Initial event parameter values, applied to every new instance.
  /// Use [setParameter] for live changes.
  final Map<String, double> parameters;

  /// Push the contract attenuation's min/max distances onto the event,
  /// overriding the authored values.
  bool overrideDistances;

  FmodAudioEngine? _fmodEngine;
  fmod.FmodEventDescription? _description;
  fmod.FmodEventInstance? _instance;

  @override
  Future<void> onLoad() async {
    final engine = this.engine;
    if (engine is! FmodAudioEngine) {
      if (engine != null) {
        debugPrint(
          'FmodEventSource "$eventPath" mounted under a ${engine.backendName} '
          'engine; it stays silent.',
        );
      }
      return;
    }
    await engine.ready;
    if (!engine.isAvailable || !isMounted) return;
    _fmodEngine = engine;
    engine._eventSources.add(this);
    try {
      _description = engine._requireSystem.getEvent(eventPath);
      if (autoplay) play();
    } on fmod.FmodException catch (error) {
      debugPrint(
        'FmodEventSource could not resolve "$eventPath" (are its banks '
        'loaded?). $error',
      );
    }
  }

  @override
  void onMount() {
    super.onMount();
    if (isLoaded && autoplay) play();
  }

  @override
  void onUnmount() {
    _releaseInstance();
    _fmodEngine?._eventSources.remove(this);
    _fmodEngine = null;
    super.onUnmount();
  }

  void _releaseInstance() {
    final instance = _instance;
    if (instance != null && _fmodEngine?.isAvailable == true) {
      instance.stop(mode: fmod.FmodStopMode.immediate);
      instance.release();
    }
    _instance = null;
  }

  @override
  void play() {
    final description = _description;
    if (description == null) return;
    var instance = _instance;
    if (instance == null) {
      instance = description.createInstance();
      _instance = instance;
      instance.volume = _volume;
      if (_pitch != 1.0) instance.pitch = _pitch;
      for (final entry in parameters.entries) {
        instance.setParameter(entry.key, entry.value);
      }
      if (positional && isMounted) _push3d();
    }
    instance.paused = false;
    instance.start();
  }

  @override
  void pause() {
    _instance?.paused = true;
  }

  @override
  void stop() {
    _instance?.stop();
  }

  @override
  bool get isPlaying {
    final instance = _instance;
    if (instance == null) return false;
    return switch (instance.playbackState) {
      fmod.FmodPlaybackState.playing ||
      fmod.FmodPlaybackState.starting ||
      fmod.FmodPlaybackState.sustaining => true,
      _ => false,
    };
  }

  double _volume;

  @override
  double get volume => _volume;

  @override
  set volume(double value) {
    _volume = value;
    _instance?.volume = value;
  }

  double _pitch;

  @override
  double get pitch => _pitch;

  @override
  set pitch(double value) {
    _pitch = value;
    _instance?.pitch = value;
  }

  /// Sets a Studio parameter on the live instance (and remembers it for
  /// future instances).
  void setParameter(String name, double value) {
    parameters[name] = value;
    _instance?.setParameter(name, value);
  }

  @override
  void onTransformSync(Vector3 position, Vector3 velocity) {
    _push3d(velocity: velocity);
  }

  void _push3d({Vector3? velocity}) {
    final instance = _instance;
    if (instance == null) return;
    final transform = node.globalTransform;
    final rotation = transform.getRotation();
    instance.set3dAttributes(
      position: transform.getTranslation(),
      velocity: velocity ?? Vector3.zero(),
      forward: rotation.transform(Vector3(0, 0, 1))..normalize(),
      up: rotation.transform(Vector3(0, 1, 0))..normalize(),
    );
    if (overrideDistances) {
      instance.minimumDistance = attenuation.minDistance;
      instance.maximumDistance = attenuation.maxDistance;
    }
  }
}
