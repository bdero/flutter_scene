import 'package:meta/meta.dart';

import 'package:flutter_scene_input/src/core/controls.dart';
import 'package:flutter_scene_input/src/core/player_input.dart';

/// A monotonic time source for hold durations and tap windows.
/// {@category Players and devices}
abstract interface class InputClock {
  /// Seconds since an arbitrary fixed origin, never decreasing.
  double get seconds;
}

/// The default [InputClock], backed by a [Stopwatch].
/// {@category Players and devices}
final class StopwatchInputClock implements InputClock {
  /// Starts a clock at zero.
  StopwatchInputClock() : _stopwatch = Stopwatch()..start();

  final Stopwatch _stopwatch;

  @override
  double get seconds => _stopwatch.elapsedMicroseconds / 1e6;
}

/// One physical or virtual input device.
/// {@category Players and devices}
final class InputDevice {
  InputDevice._(
    this.handle,
    this.kind, {
    required this.name,
    this.identity,
    int? vendorId,
    int? productId,
    this.isVirtual = false,
  }) : _vendorId = vendorId,
       _productId = productId;

  /// A small integer that stays the same for this device for the life of the
  /// [InputSystem], across disconnects and reconnects.
  final int handle;

  /// The kind of device.
  final DeviceKind kind;

  /// A human-readable name, as reported by the platform.
  String name;

  /// The key a returning device is matched on, or null when the source cannot
  /// tell devices apart.
  final String? identity;

  /// The USB vendor id, when known.
  int? get vendorId => _vendorId;
  int? _vendorId;

  /// The USB product id, when known.
  int? get productId => _productId;
  int? _productId;

  /// Whether this device exists only to carry injected input.
  final bool isVirtual;

  /// Whether the device is currently connected.
  bool get connected => _connected;
  bool _connected = true;

  @override
  String toString() => 'InputDevice($handle, ${kind.name}, $name)';
}

/// The channel an [InputSource] publishes through. Implemented by
/// [InputSystem].
/// {@category Players and devices}
abstract interface class InputSink {
  /// Registers a device, or reconnects the disconnected device with the same
  /// [identity], keeping its handle.
  InputDevice connectDevice(
    DeviceKind kind, {
    required String name,
    String? identity,
    int? vendorId,
    int? productId,
  });

  /// Marks [device] disconnected and releases everything it held.
  void disconnectDevice(InputDevice device);

  /// Updates what is known about [device], for sources that learn a name or
  /// USB ids only after connecting.
  void updateDevice(
    InputDevice device, {
    String? name,
    int? vendorId,
    int? productId,
  });

  /// Records the level of a digital or analog [control] on [device].
  void publish(InputDevice device, Control control, double value);

  /// Adds displacement to a delta [control] on [device]. Displacement
  /// accumulates until each read window takes it.
  void publishDelta(InputDevice device, Control control, double dx, double dy);
}

/// A device backend feeding an [InputSystem]: keyboard, mouse, gamepads, or
/// anything else (MIDI, a wheel, a replay, the network) without a package
/// change.
/// {@category Players and devices}
abstract class InputSource {
  /// Starts publishing into [sink].
  void attach(InputSink sink);

  /// Stops publishing and releases platform listeners.
  void detach();

  /// Called at the start of each frame, before read windows advance, for
  /// backends that must be polled.
  void poll(double deltaSeconds) {}
}

/// The devices, sources, and players of one app.
///
/// Devices not paired to a specific player feed [defaultPlayer], so a single
/// player game never pairs anything.
/// {@category Players and devices}
final class InputSystem implements InputSink {
  /// A system reading time from [clock].
  InputSystem({InputClock? clock}) : clock = clock ?? StopwatchInputClock() {
    _defaultPlayer = PlayerInput.internal(this);
    _players.add(_defaultPlayer);
  }

  /// The shared system most apps use.
  static final InputSystem instance = InputSystem();

  /// The time source for hold durations and tap windows.
  final InputClock clock;

  /// Returns a key's label on the current keyboard layout, or null to use its
  /// code name. The Flutter layer installs one reading logical keys.
  String? Function(KeyControl control)? keyLabelResolver;

  /// Returns art for a control in prompts (an asset path, an image), passed
  /// through as `ControlLabel.glyph`.
  Object? Function(Control control, GamepadLayoutStyle style)? glyphResolver;

  final List<InputDevice> _devices = [];
  final List<InputSource> _sources = [];
  final List<PlayerInput> _players = [];
  final List<void Function()> _deviceListeners = [];
  final List<void Function(InputDevice device, Control control)>
  _unpairedPressListeners = [];
  late final PlayerInput _defaultPlayer;
  int _nextHandle = 1;

  /// Every device seen, connected or not, in connection order.
  List<InputDevice> get devices => List.unmodifiable(_devices);

  /// The player every unpaired device feeds.
  PlayerInput get defaultPlayer => _defaultPlayer;

  /// Every player, the default one first.
  List<PlayerInput> get players => List.unmodifiable(_players);

  /// Creates an additional player. Pair devices to it with
  /// [PlayerInput.pair].
  PlayerInput createPlayer() {
    final player = PlayerInput.internal(this)
      ..textEntryActive = _defaultPlayer.textEntryActive;
    _players.add(player);
    return player;
  }

  /// Removes [player]; its devices return to [defaultPlayer].
  void removePlayer(PlayerInput player) {
    if (identical(player, _defaultPlayer)) {
      throw StateError('The default player cannot be removed');
    }
    if (!_players.remove(player)) return;
    for (final device in player.pairedDevices.toList()) {
      player.unpair(device);
    }
  }

  /// Attaches [source].
  void addSource(InputSource source) {
    _sources.add(source);
    source.attach(this);
  }

  /// Detaches [source]. Returns whether it was attached.
  bool removeSource(InputSource source) {
    if (!_sources.remove(source)) return false;
    source.detach();
    return true;
  }

  /// Registers [listener] for device connects, disconnects, and pairing
  /// changes.
  void addDeviceListener(void Function() listener) =>
      _deviceListeners.add(listener);

  /// Unregisters [listener].
  void removeDeviceListener(void Function() listener) =>
      _deviceListeners.remove(listener);

  /// Registers [listener] for presses on devices no player has paired, the
  /// hook a join-by-button-press flow watches.
  void addUnpairedPressListener(
    void Function(InputDevice device, Control control) listener,
  ) => _unpairedPressListeners.add(listener);

  /// Unregisters [listener].
  void removeUnpairedPressListener(
    void Function(InputDevice device, Control control) listener,
  ) => _unpairedPressListeners.remove(listener);

  /// Polls sources, then advances every player's frame window.
  void advanceFrame(double deltaSeconds) {
    for (final source in _sources) {
      source.poll(deltaSeconds);
    }
    for (final player in _players) {
      player.advanceFrame(deltaSeconds);
    }
  }

  /// Advances every player's fixed-step window.
  void advanceFixedStep(double fixedDt) {
    for (final player in _players) {
      player.advanceFixedStep(fixedDt);
    }
  }

  @override
  InputDevice connectDevice(
    DeviceKind kind, {
    required String name,
    String? identity,
    int? vendorId,
    int? productId,
  }) {
    if (identity != null) {
      for (final device in _devices) {
        if (device.identity == identity && device.kind == kind) {
          device
            ..name = name
            .._connected = true;
          notifyDevicesChanged();
          return device;
        }
      }
    }
    final device = InputDevice._(
      _nextHandle++,
      kind,
      name: name,
      identity: identity,
      vendorId: vendorId,
      productId: productId,
    );
    _devices.add(device);
    notifyDevicesChanged();
    return device;
  }

  /// A device that only carries input injected into one player.
  @internal
  InputDevice createVirtualDevice(DeviceKind kind) => InputDevice._(
    _nextHandle++,
    kind,
    name: 'injected ${kind.name}',
    isVirtual: true,
  );

  @override
  void disconnectDevice(InputDevice device) {
    if (!device._connected) return;
    device._connected = false;
    ownerOf(device).releaseDevice(device);
    notifyDevicesChanged();
  }

  @override
  void updateDevice(
    InputDevice device, {
    String? name,
    int? vendorId,
    int? productId,
  }) {
    var changed = false;
    if (name != null && name != device.name) {
      device.name = name;
      changed = true;
    }
    if (vendorId != null && vendorId != device._vendorId) {
      device._vendorId = vendorId;
      changed = true;
    }
    if (productId != null && productId != device._productId) {
      device._productId = productId;
      changed = true;
    }
    if (changed) notifyDevicesChanged();
  }

  @override
  void publish(InputDevice device, Control control, double value) {
    if (!device._connected) return;
    final owner = ownerOf(device);
    if (_unpairedPressListeners.isNotEmpty &&
        value.abs() >= 0.5 &&
        control.kind == ControlKind.digital &&
        !_players.any((player) => player.pairedDevices.contains(device))) {
      for (final listener in List.of(_unpairedPressListeners)) {
        listener(device, control);
      }
      // A listener may have paired the device; route to the new owner.
      ownerOf(device).receive(device, control, value);
      return;
    }
    owner.receive(device, control, value);
  }

  @override
  void publishDelta(InputDevice device, Control control, double dx, double dy) {
    if (!device._connected) return;
    ownerOf(device).receiveDelta(device, control, dx, dy);
  }

  /// The player [device] feeds.
  PlayerInput ownerOf(InputDevice device) {
    for (final player in _players) {
      if (player.pairedDevices.contains(device)) return player;
    }
    return _defaultPlayer;
  }

  /// Tells device listeners something changed.
  void notifyDevicesChanged() {
    for (final listener in List.of(_deviceListeners)) {
      listener();
    }
  }
}
