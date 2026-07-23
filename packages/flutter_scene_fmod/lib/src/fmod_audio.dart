import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_fmod/src/ffi/fmod_bindings.dart';
import 'package:flutter_scene_fmod/src/ffi/fmod_library.dart';
import 'package:vector_math/vector_math.dart';

// FMOD's 3D math is left-handed by default, matching the engine world
// (+Z is the look direction), so vectors pass through unconverted.

/// FMOD Studio implementation of the flutter_scene [AudioEngine]
/// contract.
///
/// Attach to the scene root before mounting sources. The contract
/// surface (clips, `ClipAudioSource`, buses, one-shots) plays through
/// the FMOD Core layer; the Studio layer adds [loadBankAsset]/
/// [loadBankFile], [FmodEventSource] for authored events, and
/// [studioBus] for buses mixed in FMOD Studio.
///
/// Requires a user-supplied FMOD Engine SDK; see the package README for
/// setup and licensing. When the libraries cannot be found the engine
/// logs the setup instructions once and stays inert, so the rest of the
/// scene keeps running.
class FmodAudioEngine extends AudioEngine with WidgetsBindingObserver {
  FmodAudioEngine({
    this.maxChannels = 256,
    this.liveUpdate = false,
    this.headerVersion = kFmodDefaultHeaderVersion,
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

  FmodBindings? _fmod;
  Pointer<Void> _system = nullptr;
  Pointer<Void> _coreSystem = nullptr;
  Pointer<Void> _masterGroup = nullptr;

  // Scratch natives reused across per-frame calls.
  Pointer<Fmod3dAttributes> _attributesScratch = nullptr;
  Pointer<FmodVector> _vectorScratchA = nullptr;
  Pointer<FmodVector> _vectorScratchB = nullptr;
  Pointer<Int32> _intScratch = nullptr;
  Pointer<Uint32> _uintScratch = nullptr;

  final Completer<void> _ready = Completer<void>();
  Object? _initializationError;
  bool _observing = false;

  late final FmodAudioBus _master = FmodAudioBus._(this, 'master', null);

  /// Completes when the engine finishes initializing (successfully or
  /// not); check [isAvailable] afterwards.
  Future<void> get ready => _ready.future;

  /// Whether the FMOD system initialized and calls will play audio.
  bool get isAvailable => _fmod != null && _initializationError == null;

  @override
  String get backendName => 'fmod';

  @override
  AudioBus get masterBus => _master;

  @override
  Future<void> onLoad() async {
    try {
      final fmod = FmodBindings(FmodLibrary.open());
      final systemOut = calloc<Pointer<Void>>();
      try {
        fmod.check(
          fmod.Studio_System_Create(systemOut, headerVersion),
          'Studio_System_Create',
        );
        _system = systemOut.value;
        fmod.check(
          fmod.Studio_System_Initialize(
            _system,
            maxChannels,
            liveUpdate ? fmodStudioInitLiveUpdate : fmodStudioInitNormal,
            fmodInitNormal,
            nullptr,
          ),
          'Studio_System_Initialize',
        );
        systemOut.value = nullptr;
        fmod.check(
          fmod.Studio_System_GetCoreSystem(_system, systemOut),
          'Studio_System_GetCoreSystem',
        );
        _coreSystem = systemOut.value;
      } finally {
        calloc.free(systemOut);
      }
      _fmod = fmod;
      _allocateScratch();
      final groupOut = calloc<Pointer<Void>>();
      fmod.check(
        fmod.System_GetMasterChannelGroup(_coreSystem, groupOut),
        'System_GetMasterChannelGroup',
      );
      _masterGroup = groupOut.value;
      calloc.free(groupOut);
      _master._group = _masterGroup;
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

  void _allocateScratch() {
    _attributesScratch = calloc<Fmod3dAttributes>();
    _vectorScratchA = calloc<FmodVector>();
    _vectorScratchB = calloc<FmodVector>();
    _intScratch = calloc<Int32>();
    _uintScratch = calloc<Uint32>();
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
    final fmod = _fmod;
    if (fmod != null) {
      fmod.Studio_System_Release(_system);
      calloc.free(_attributesScratch);
      calloc.free(_vectorScratchA);
      calloc.free(_vectorScratchB);
      calloc.free(_intScratch);
      calloc.free(_uintScratch);
      _fmod = null;
      _system = nullptr;
      _coreSystem = nullptr;
      _masterGroup = nullptr;
    }
  }

  FmodBindings get _requireFmod {
    final fmod = _fmod;
    if (fmod == null) {
      throw StateError(
        _initializationError == null
            ? 'FmodAudioEngine is not initialized yet.'
            : 'FmodAudioEngine failed to initialize: $_initializationError',
      );
    }
    return fmod;
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
    return _clipFromBytes(bytes.buffer.asUint8List());
  }

  @override
  Future<AudioClip> loadClipFromBytes(String key, Uint8List bytes) async {
    await ready;
    return _clipFromBytes(bytes);
  }

  Future<AudioClip> _clipFromBytes(Uint8List bytes) async {
    final fmod = _requireFmod;
    // FMOD_OPENMEMORY needs the version-sensitive FMOD_CREATESOUNDEXINFO
    // struct, so the bytes go through a temp file instead; the sample is
    // fully decoded at create time and the file is deleted right after.
    // TODO(audio): bind FMOD_CREATESOUNDEXINFO and load from memory to
    // skip the temp-file round trip.
    final directory = await Directory.systemTemp.createTemp('fscene_fmod');
    final file = File('${directory.path}/clip');
    await file.writeAsBytes(bytes, flush: true);
    try {
      final pathUtf8 = file.path.toNativeUtf8();
      final soundOut = calloc<Pointer<Void>>();
      try {
        fmod.check(
          fmod.System_CreateSound(
            _coreSystem,
            pathUtf8,
            fmod3d | fmodCreateSample,
            nullptr,
            soundOut,
          ),
          'System_CreateSound',
        );
        fmod.check(
          fmod.Sound_GetLength(soundOut.value, _uintScratch, fmodTimeUnitMs),
          'Sound_GetLength',
        );
        return FmodAudioClip._(
          this,
          soundOut.value,
          Duration(milliseconds: _uintScratch.value),
        );
      } finally {
        calloc.free(pathUtf8);
        calloc.free(soundOut);
      }
    } finally {
      await directory.delete(recursive: true);
    }
  }

  @override
  AudioVoice createVoice(AudioClip clip) {
    final fmod = _requireFmod;
    if (clip is! FmodAudioClip) {
      throw ArgumentError('createVoice needs a clip loaded by this backend.');
    }
    if (clip.isDisposed) {
      throw StateError('AudioClip is disposed.');
    }
    final channelOut = calloc<Pointer<Void>>();
    try {
      fmod.check(
        fmod.System_PlaySound(
          _coreSystem,
          clip._sound,
          _masterGroup,
          1,
          channelOut,
        ),
        'System_PlaySound',
      );
      final voice = FmodAudioVoice._(this, channelOut.value);
      _liveVoices.add(voice);
      return voice;
    } finally {
      calloc.free(channelOut);
    }
  }

  /// Loads a Studio bank bundled as a Flutter asset.
  Future<FmodBank> loadBankAsset(String assetKey) async {
    await ready;
    final fmod = _requireFmod;
    final bytes = await rootBundle.load(assetKey);
    final data = bytes.buffer.asUint8List();
    final buffer = calloc<Uint8>(data.length);
    buffer.asTypedList(data.length).setAll(0, data);
    final bankOut = calloc<Pointer<Void>>();
    try {
      fmod.check(
        fmod.Studio_System_LoadBankMemory(
          _system,
          buffer,
          data.length,
          fmodStudioLoadMemory,
          fmodStudioLoadBankNormal,
          bankOut,
        ),
        'Studio_System_LoadBankMemory',
      );
      return FmodBank._(this, bankOut.value);
    } finally {
      calloc.free(buffer);
      calloc.free(bankOut);
    }
  }

  /// Loads a Studio bank from a file path.
  Future<FmodBank> loadBankFile(String path) async {
    await ready;
    final fmod = _requireFmod;
    final pathUtf8 = path.toNativeUtf8();
    final bankOut = calloc<Pointer<Void>>();
    try {
      fmod.check(
        fmod.Studio_System_LoadBankFile(
          _system,
          pathUtf8,
          fmodStudioLoadBankNormal,
          bankOut,
        ),
        'Studio_System_LoadBankFile',
      );
      return FmodBank._(this, bankOut.value);
    } finally {
      calloc.free(pathUtf8);
      calloc.free(bankOut);
    }
  }

  /// Returns a handle to a bus authored in FMOD Studio (a `bus:/` path).
  /// Its banks must be loaded first.
  FmodStudioBus studioBus(String path) {
    final fmod = _requireFmod;
    final pathUtf8 = path.toNativeUtf8();
    final busOut = calloc<Pointer<Void>>();
    try {
      fmod.check(
        fmod.Studio_System_GetBus(_system, pathUtf8, busOut),
        'Studio_System_GetBus',
      );
      return FmodStudioBus._(this, path, busOut.value);
    } finally {
      calloc.free(pathUtf8);
      calloc.free(busOut);
    }
  }

  @override
  void onSyncListener(
    Vector3 position,
    Vector3 forward,
    Vector3 up,
    Vector3 velocity,
  ) {
    final fmod = _fmod;
    if (fmod == null) return;
    final attributes = _attributesScratch.ref;
    _writeVector(attributes.position, position);
    _writeVector(attributes.velocity, velocity);
    _writeVector(attributes.forward, forward);
    _writeVector(attributes.up, up);
    fmod.check(
      fmod.Studio_System_SetListenerAttributes(
        _system,
        0,
        _attributesScratch,
        nullptr,
      ),
      'Studio_System_SetListenerAttributes',
    );
  }

  @override
  void onFrameCommit(double deltaSeconds) {
    final fmod = _fmod;
    if (fmod == null) return;
    fmod.check(fmod.Studio_System_Update(_system), 'Studio_System_Update');
    _liveVoices.removeWhere((voice) => !voice.isPlaying);
  }

  static void _writeVector(FmodVector target, Vector3 source) {
    target.x = source.x;
    target.y = source.y;
    target.z = source.z;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!pauseWhenBackgrounded || !isAvailable) return;
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _fmod!.ChannelGroup_SetPaused(_masterGroup, 1);
      case AppLifecycleState.resumed:
        _fmod!.ChannelGroup_SetPaused(_masterGroup, 0);
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

  Pointer<Void> _group = nullptr;

  void _create() {
    final fmod = _engine._requireFmod;
    final nameUtf8 = name.toNativeUtf8();
    final groupOut = calloc<Pointer<Void>>();
    try {
      fmod.check(
        fmod.System_CreateChannelGroup(_engine._coreSystem, nameUtf8, groupOut),
        'System_CreateChannelGroup',
      );
      _group = groupOut.value;
      final parentGroup = _parent?._group ?? _engine._masterGroup;
      fmod.check(
        fmod.ChannelGroup_AddGroup(parentGroup, _group, 1, nullptr),
        'ChannelGroup_AddGroup',
      );
      if (_volume != 1.0) _push();
    } finally {
      calloc.free(nameUtf8);
      calloc.free(groupOut);
    }
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
    final fmod = _engine._fmod;
    if (fmod == null || _group == nullptr) return;
    fmod.check(
      fmod.ChannelGroup_SetVolume(_group, _volume),
      'ChannelGroup_SetVolume',
    );
  }
}

/// A bus authored in FMOD Studio.
class FmodStudioBus {
  FmodStudioBus._(this._engine, this.path, this._bus);

  final FmodAudioEngine _engine;

  /// The Studio bus path (`bus:/...`).
  final String path;

  final Pointer<Void> _bus;

  double _volume = 1.0;

  double get volume => _volume;

  set volume(double value) {
    _volume = value;
    final fmod = _engine._fmod;
    if (fmod == null) return;
    fmod.check(fmod.Studio_Bus_SetVolume(_bus, value), 'Studio_Bus_SetVolume');
  }
}

/// A loaded FMOD Studio bank.
class FmodBank {
  FmodBank._(this._engine, this._bank);

  final FmodAudioEngine _engine;
  final Pointer<Void> _bank;
  bool _unloaded = false;

  /// Unloads the bank, stopping its events.
  void unload() {
    if (_unloaded) return;
    _unloaded = true;
    final fmod = _engine._fmod;
    if (fmod == null) return;
    fmod.check(fmod.Studio_Bank_Unload(_bank), 'Studio_Bank_Unload');
  }
}

/// A clip decoded by FMOD Core.
class FmodAudioClip implements AudioClip {
  FmodAudioClip._(this._engine, this._sound, this._duration);

  final FmodAudioEngine _engine;
  final Pointer<Void> _sound;
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
    final fmod = _engine._fmod;
    if (fmod == null) return;
    fmod.check(fmod.Sound_Release(_sound), 'Sound_Release');
  }
}

/// One FMOD Core playback (a channel).
class FmodAudioVoice implements AudioVoice {
  FmodAudioVoice._(this._engine, this._channel);

  final FmodAudioEngine _engine;
  final Pointer<Void> _channel;

  bool _started = false;
  bool _stopped = false;
  bool _finished = false;
  bool _paused = false;
  bool _looping = false;
  bool _positional = true;
  int _rolloffFlag = fmod3dInverseRolloff;

  double? _appliedMin, _appliedMax, _appliedDoppler;

  @override
  bool get isPlaying {
    if (_stopped || _finished) return false;
    final fmod = _engine._fmod;
    if (fmod == null) return false;
    final alive = fmod.checkChannel(
      fmod.Channel_IsPlaying(_channel, _engine._intScratch),
      'Channel_IsPlaying',
    );
    if (!alive || _engine._intScratch.value == 0) {
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
    _applyMode();
    final fmod = _engine._fmod;
    if (fmod == null) return;
    fmod.checkChannel(
      fmod.Channel_SetPaused(_channel, _paused ? 1 : 0),
      'Channel_SetPaused',
    );
  }

  @override
  void pause() {
    _paused = true;
    if (!_started) return;
    final fmod = _engine._fmod;
    if (fmod == null) return;
    fmod.checkChannel(fmod.Channel_SetPaused(_channel, 1), 'Channel_SetPaused');
  }

  @override
  void resume() {
    _paused = false;
    if (!_started) return;
    final fmod = _engine._fmod;
    if (fmod == null) return;
    fmod.checkChannel(fmod.Channel_SetPaused(_channel, 0), 'Channel_SetPaused');
  }

  @override
  void stop() {
    if (_stopped) return;
    _stopped = true;
    final fmod = _engine._fmod;
    if (fmod == null) return;
    fmod.checkChannel(fmod.Channel_Stop(_channel), 'Channel_Stop');
  }

  double _volume = 1.0;

  @override
  double get volume => _volume;

  @override
  set volume(double value) {
    _volume = value;
    final fmod = _engine._fmod;
    if (fmod == null) return;
    fmod.checkChannel(
      fmod.Channel_SetVolume(_channel, value),
      'Channel_SetVolume',
    );
  }

  double _pitch = 1.0;

  @override
  double get pitch => _pitch;

  @override
  set pitch(double value) {
    _pitch = value;
    final fmod = _engine._fmod;
    if (fmod == null) return;
    fmod.checkChannel(
      fmod.Channel_SetPitch(_channel, value),
      'Channel_SetPitch',
    );
  }

  @override
  set looping(bool value) {
    _looping = value;
    _applyMode();
  }

  @override
  void setBus(AudioBus? bus) {
    final fmod = _engine._fmod;
    if (fmod == null) return;
    final group = bus == null
        ? _engine._masterGroup
        : (bus as FmodAudioBus)._group;
    if (group == nullptr) return;
    fmod.checkChannel(
      fmod.Channel_SetChannelGroup(_channel, group),
      'Channel_SetChannelGroup',
    );
  }

  @override
  void setPositional(bool positional) {
    _positional = positional;
    _applyMode();
  }

  void _applyMode() {
    final fmod = _engine._fmod;
    if (fmod == null) return;
    final mode =
        (_positional ? fmod3d | _rolloffFlag : fmod2d) |
        (_looping ? fmodLoopNormal : fmodLoopOff);
    fmod.checkChannel(fmod.Channel_SetMode(_channel, mode), 'Channel_SetMode');
  }

  @override
  void update3d(
    Vector3 position,
    Vector3 velocity,
    AudioAttenuation attenuation,
  ) {
    final fmod = _engine._fmod;
    if (fmod == null || _stopped || _finished) return;
    final positionScratch = _engine._vectorScratchA;
    final velocityScratch = _engine._vectorScratchB;
    FmodAudioEngine._writeVector(positionScratch.ref, position);
    FmodAudioEngine._writeVector(velocityScratch.ref, velocity);
    if (!fmod.checkChannel(
      fmod.Channel_Set3DAttributes(_channel, positionScratch, velocityScratch),
      'Channel_Set3DAttributes',
    )) {
      _finished = true;
      return;
    }
    // AudioRolloff.none has no FMOD mode flag; a linear rolloff whose
    // min distance never ends approximates it. Exponential maps to
    // FMOD's inverse-tapered curve, the closest available.
    // TODO(audio): honor AudioAttenuation.rolloffFactor; FMOD's rolloff
    // scale is global (System_Set3DSettings), not per channel.
    final rolloffFlag = switch (attenuation.rolloff) {
      AudioRolloff.none => fmod3dLinearRolloff,
      AudioRolloff.inverse => fmod3dInverseRolloff,
      AudioRolloff.linear => fmod3dLinearRolloff,
      AudioRolloff.exponential => fmod3dInverseTaperedRolloff,
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
      fmod.checkChannel(
        fmod.Channel_Set3DMinMaxDistance(_channel, min, max),
        'Channel_Set3DMinMaxDistance',
      );
    }
    if (attenuation.dopplerFactor != _appliedDoppler) {
      _appliedDoppler = attenuation.dopplerFactor;
      fmod.checkChannel(
        fmod.Channel_Set3DDopplerLevel(_channel, attenuation.dopplerFactor),
        'Channel_Set3DDopplerLevel',
      );
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
  Pointer<Void> _description = nullptr;
  Pointer<Void> _instance = nullptr;

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
      final fmod = engine._requireFmod;
      final pathUtf8 = eventPath.toNativeUtf8();
      final descriptionOut = calloc<Pointer<Void>>();
      try {
        fmod.check(
          fmod.Studio_System_GetEvent(engine._system, pathUtf8, descriptionOut),
          'Studio_System_GetEvent',
        );
        _description = descriptionOut.value;
      } finally {
        calloc.free(pathUtf8);
        calloc.free(descriptionOut);
      }
      if (autoplay) play();
    } on FmodException catch (error) {
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
    final engine = _fmodEngine;
    final fmod = engine?._fmod;
    if (fmod != null && _instance != nullptr) {
      fmod.Studio_EventInstance_Stop(_instance, fmodStudioStopImmediate);
      fmod.Studio_EventInstance_Release(_instance);
    }
    _instance = nullptr;
  }

  @override
  void play() {
    final engine = _fmodEngine;
    if (engine == null || _description == nullptr) return;
    final fmod = engine._requireFmod;
    if (_instance == nullptr) {
      final instanceOut = calloc<Pointer<Void>>();
      try {
        fmod.check(
          fmod.Studio_EventDescription_CreateInstance(
            _description,
            instanceOut,
          ),
          'Studio_EventDescription_CreateInstance',
        );
        _instance = instanceOut.value;
      } finally {
        calloc.free(instanceOut);
      }
      fmod.Studio_EventInstance_SetVolume(_instance, _volume);
      if (_pitch != 1.0) fmod.Studio_EventInstance_SetPitch(_instance, _pitch);
      for (final entry in parameters.entries) {
        _pushParameter(entry.key, entry.value);
      }
      if (positional && isMounted) _push3d();
    }
    fmod.check(
      fmod.Studio_EventInstance_SetPaused(_instance, 0),
      'Studio_EventInstance_SetPaused',
    );
    fmod.check(
      fmod.Studio_EventInstance_Start(_instance),
      'Studio_EventInstance_Start',
    );
  }

  @override
  void pause() {
    final fmod = _fmodEngine?._fmod;
    if (fmod == null || _instance == nullptr) return;
    fmod.Studio_EventInstance_SetPaused(_instance, 1);
  }

  @override
  void stop() {
    final fmod = _fmodEngine?._fmod;
    if (fmod == null || _instance == nullptr) return;
    fmod.Studio_EventInstance_Stop(_instance, fmodStudioStopAllowFadeout);
  }

  @override
  bool get isPlaying {
    final engine = _fmodEngine;
    final fmod = engine?._fmod;
    if (fmod == null || _instance == nullptr) return false;
    fmod.Studio_EventInstance_GetPlaybackState(_instance, engine!._intScratch);
    final state = engine._intScratch.value;
    return state == fmodStudioPlaybackPlaying ||
        state == fmodStudioPlaybackStarting ||
        state == fmodStudioPlaybackSustaining;
  }

  double _volume;

  @override
  double get volume => _volume;

  @override
  set volume(double value) {
    _volume = value;
    final fmod = _fmodEngine?._fmod;
    if (fmod == null || _instance == nullptr) return;
    fmod.Studio_EventInstance_SetVolume(_instance, value);
  }

  double _pitch;

  @override
  double get pitch => _pitch;

  @override
  set pitch(double value) {
    _pitch = value;
    final fmod = _fmodEngine?._fmod;
    if (fmod == null || _instance == nullptr) return;
    fmod.Studio_EventInstance_SetPitch(_instance, value);
  }

  /// Sets a Studio parameter on the live instance (and remembers it for
  /// future instances).
  void setParameter(String name, double value) {
    parameters[name] = value;
    _pushParameter(name, value);
  }

  void _pushParameter(String name, double value) {
    final fmod = _fmodEngine?._fmod;
    if (fmod == null || _instance == nullptr) return;
    final nameUtf8 = name.toNativeUtf8();
    try {
      fmod.check(
        fmod.Studio_EventInstance_SetParameterByName(
          _instance,
          nameUtf8,
          value,
          0,
        ),
        'Studio_EventInstance_SetParameterByName',
      );
    } finally {
      calloc.free(nameUtf8);
    }
  }

  @override
  void onTransformSync(Vector3 position, Vector3 velocity) {
    _push3d(velocity: velocity);
  }

  void _push3d({Vector3? velocity}) {
    final engine = _fmodEngine;
    final fmod = engine?._fmod;
    if (fmod == null || _instance == nullptr) return;
    final transform = node.globalTransform;
    final rotation = transform.getRotation();
    final attributes = engine!._attributesScratch.ref;
    FmodAudioEngine._writeVector(
      attributes.position,
      transform.getTranslation(),
    );
    FmodAudioEngine._writeVector(
      attributes.velocity,
      velocity ?? Vector3.zero(),
    );
    FmodAudioEngine._writeVector(
      attributes.forward,
      rotation.transform(Vector3(0, 0, 1))..normalize(),
    );
    FmodAudioEngine._writeVector(
      attributes.up,
      rotation.transform(Vector3(0, 1, 0))..normalize(),
    );
    fmod.Studio_EventInstance_Set3DAttributes(
      _instance,
      engine._attributesScratch,
    );
    if (overrideDistances) {
      fmod.Studio_EventInstance_SetProperty(
        _instance,
        fmodStudioEventPropertyMinDistance,
        attenuation.minDistance,
      );
      fmod.Studio_EventInstance_SetProperty(
        _instance,
        fmodStudioEventPropertyMaxDistance,
        attenuation.maxDistance,
      );
    }
  }
}
