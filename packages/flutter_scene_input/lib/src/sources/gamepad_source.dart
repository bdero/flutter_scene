import 'dart:async';

import 'package:gamepads/gamepads.dart' as pads;

import 'package:flutter_scene_input/src/core/controls.dart';
import 'package:flutter_scene_input/src/core/input_system.dart';
import 'package:flutter_scene_input/src/core/player_input.dart';
import 'package:flutter_scene_input/src/sources/gamepad_mappings.dart';
import 'package:flutter_scene_input/src/sources/hid_backend.dart';
import 'package:flutter_scene_input/src/sources/hid_backend_base.dart';

/// Where [GamepadSource] reads connected pads and raw events. The default
/// reads the `gamepads` package; tests supply their own.
/// {@category Sources}
abstract interface class GamepadBackend {
  /// The connected pads, as `(id, name)`.
  Future<List<({String id, String name})>> list();

  /// Raw events from every pad.
  Stream<pads.GamepadEvent> get events;
}

/// A [GamepadBackend] over the `gamepads` package.
/// {@category Sources}
final class GamepadsPackageBackend implements GamepadBackend {
  /// The package backend.
  const GamepadsPackageBackend();

  @override
  Future<List<({String id, String name})>> list() async => [
    for (final pad in await pads.Gamepads.list()) (id: pad.id, name: pad.name),
  ];

  @override
  Stream<pads.GamepadEvent> get events => pads.Gamepads.events;
}

/// Publishes gamepads from the `gamepads` package, with each pad its own
/// device.
///
/// Raw events go through the package's normalizer first. Events it cannot
/// map fall back to key spellings the demos observed, so an unusual pad still
/// reaches actions. No deadzone is applied here; deadzones live in bindings.
///
/// The package reports no connects or disconnects, so the source polls the
/// pad list every [pollInterval] and on any event from an unknown pad. A
/// returning pad keeps its device handle when its name and position among
/// same-named pads match.
///
/// On macOS a HID tap also reports pads the GameController framework never
/// lists (Steam Input's virtual pad, generic XInput adapters). Pads both
/// report are kept from the package only. A sandboxed app needs the
/// `com.apple.security.device.usb` entitlement for the tap.
/// {@category Sources}
final class GamepadSource extends InputSource {
  /// A source over [backend] (default the `gamepads` package).
  GamepadSource({
    GamepadBackend? backend,
    pads.GamepadNormalizer? normalizer,
    HidGamepadBackend? hid,
    this.pollInterval = const Duration(seconds: 1),
    this.hidFallback = true,
  }) : _backend = backend ?? const GamepadsPackageBackend(),
       _normalizer = normalizer ?? pads.GamepadNormalizer(),
       _hid = hid ?? createHidGamepadBackend();

  final GamepadBackend _backend;
  final pads.GamepadNormalizer _normalizer;
  final HidGamepadBackend _hid;

  /// How often the pad list is refreshed.
  final Duration pollInterval;

  /// Whether to start the macOS HID tap.
  final bool hidFallback;

  InputSink? _sink;
  StreamSubscription<pads.GamepadEvent>? _events;
  Timer? _timer;
  Future<void>? _inFlight;
  bool _refreshAgain = false;
  final Map<String, _Pad> _pads = {};
  final Map<int, _Pad> _hidPads = {};
  final Set<int> _ignoredHid = {};

  /// Connected pads from the package, by package id.
  Iterable<InputDevice> get devices => [
    for (final pad in _pads.values) pad.device,
    for (final pad in _hidPads.values) pad.device,
  ];

  @override
  void attach(InputSink sink) {
    _sink = sink;
    _events = _backend.events.listen(
      _handleEvent,
      // No plugin on this platform or under a test binding; stay quiet.
      onError: (Object _) {},
    );
    _timer = Timer.periodic(pollInterval, (_) => refresh());
    unawaited(refresh());
    if (hidFallback) {
      _hid.start(onDevice: _handleHidDevice, onValue: _handleHidValue);
    }
  }

  @override
  void detach() {
    _events?.cancel();
    _events = null;
    _timer?.cancel();
    _timer = null;
    _hid.stop();
    final sink = _sink;
    if (sink != null) {
      for (final pad in [..._pads.values, ..._hidPads.values]) {
        sink.disconnectDevice(pad.device);
      }
    }
    _pads.clear();
    _hidPads.clear();
    _ignoredHid.clear();
    _sink = null;
  }

  /// Re-reads the pad list, connecting and disconnecting devices to match.
  ///
  /// A call made while a refresh is running schedules one more pass and
  /// completes when that pass has applied.
  Future<void> refresh() {
    final inFlight = _inFlight;
    if (inFlight != null) {
      _refreshAgain = true;
      return inFlight;
    }
    return _inFlight = _refreshLoop().whenComplete(() => _inFlight = null);
  }

  Future<void> _refreshLoop() async {
    do {
      _refreshAgain = false;
      final List<({String id, String name})> listed;
      try {
        listed = await _backend.list();
      } catch (_) {
        // No plugin on this platform or under a test binding.
        return;
      }
      _applyList(listed);
    } while (_refreshAgain && _sink != null);
  }

  void _applyList(List<({String id, String name})> listed) {
    final sink = _sink;
    if (sink == null) return;
    final byId = {for (final pad in listed) pad.id: pad.name};
    for (final id in _pads.keys.toList()) {
      final name = byId[id];
      // Index-based ids (macOS) can move to a different pad after a
      // disconnect, so a changed name is a different device.
      if (name == null || name != _pads[id]!.name) {
        final pad = _pads.remove(id)!;
        _normalizer.removeDevice(id);
        sink.disconnectDevice(pad.device);
      }
    }
    for (final pad in listed) {
      if (_pads.containsKey(pad.id)) continue;
      _pads[pad.id] = _connect(sink, pad.name, prefix: 'pad');
    }
    // A HID pad the package now lists would report twice.
    final listedNames = {for (final pad in listed) pad.name.toLowerCase()};
    for (final id in _hidPads.keys.toList()) {
      if (!listedNames.contains(_hidPads[id]!.name.toLowerCase())) continue;
      sink.disconnectDevice(_hidPads.remove(id)!.device);
      _ignoredHid.add(id);
    }
  }

  _Pad _connect(InputSink sink, String name, {required String prefix}) {
    final sameName = [
      ..._pads.values,
      ..._hidPads.values,
    ].where((pad) => pad.name == name).length;
    final device = sink.connectDevice(
      DeviceKind.gamepad,
      name: name,
      identity: '$prefix:$name#$sameName',
    );
    return _Pad(device, name);
  }

  void _handleEvent(pads.GamepadEvent event) {
    final sink = _sink;
    if (sink == null) return;
    final pad = _pads[event.gamepadId];
    if (pad == null) {
      // An event can beat the next poll; learn about the pad now.
      unawaited(refresh());
      return;
    }
    if (event.vendorId != null || event.productId != null) {
      sink.updateDevice(
        pad.device,
        vendorId: event.vendorId,
        productId: event.productId,
      );
    }
    final normalized = _normalizer.normalize(event);
    final controls = normalized.isEmpty
        ? controlsForRawKey(event.key, event.value)
        : [for (final e in normalized) ...controlsForNormalized(e)];
    for (final (control, value) in controls) {
      pad.publish(sink, control, value);
    }
  }

  void _handleHidDevice(int id, bool connected) {
    final sink = _sink;
    if (sink == null) return;
    if (!connected) {
      _ignoredHid.remove(id);
      final pad = _hidPads.remove(id);
      if (pad != null) sink.disconnectDevice(pad.device);
      return;
    }
    final info = _hid.info(id);
    final listed = _pads.values.any(
      (pad) => pad.name.toLowerCase() == info.name.toLowerCase(),
    );
    if (listed) {
      _ignoredHid.add(id);
      return;
    }
    final pad = _connect(sink, info.name, prefix: 'hid');
    sink.updateDevice(
      pad.device,
      vendorId: info.vendorId,
      productId: info.productId,
    );
    _hidPads[id] = pad;
  }

  void _handleHidValue(int id, int code, double value) {
    final sink = _sink;
    final pad = _hidPads[id];
    if (sink == null || pad == null || _ignoredHid.contains(id)) return;
    for (final (control, mapped) in controlsForHidCode(code, value)) {
      pad.publish(sink, control, mapped);
    }
  }
}

final class _Pad {
  _Pad(this.device, this.name);

  final InputDevice device;
  final String name;
  final Map<GamepadControl, double> _last = {};

  // Skips repeats, so a stick at rest does not re-evaluate every frame.
  void publish(InputSink sink, GamepadControl control, double value) {
    if (_last[control] == value) return;
    _last[control] = value;
    sink.publish(device, control, value);
  }
}

/// Creates a player for each gamepad that presses a join button while
/// unpaired, the local multiplayer join screen.
///
/// The first pad to join takes the default player when [useDefaultPlayer] is
/// true; later pads get new players.
/// {@category Players and devices}
final class JoinHelper {
  /// Starts watching [system] for join presses.
  JoinHelper(
    this.system, {
    required this.onJoin,
    this.joinControls = const {GamepadControl.south, GamepadControl.start},
    this.useDefaultPlayer = true,
    this.maxPlayers,
  }) {
    system.addUnpairedPressListener(_handlePress);
  }

  /// The system watched.
  final InputSystem system;

  /// Called with the player a pad joined as.
  final void Function(PlayerInput player, InputDevice device) onJoin;

  /// The controls that join.
  final Set<Control> joinControls;

  /// Whether the first join takes the default player.
  final bool useDefaultPlayer;

  /// The most players that may join, or null for no limit.
  final int? maxPlayers;

  final List<PlayerInput> _joined = [];

  /// The players that joined, in join order.
  List<PlayerInput> get joined => List.unmodifiable(_joined);

  /// Stops watching.
  void dispose() => system.removeUnpairedPressListener(_handlePress);

  void _handlePress(InputDevice device, Control control) {
    if (device.kind != DeviceKind.gamepad || !joinControls.contains(control)) {
      return;
    }
    final limit = maxPlayers;
    if (limit != null && _joined.length >= limit) return;
    final player = useDefaultPlayer && _joined.isEmpty
        ? system.defaultPlayer
        : system.createPlayer();
    player.pair(device);
    _joined.add(player);
    onJoin(player, device);
  }
}
