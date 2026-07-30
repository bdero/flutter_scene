import 'dart:async';

import 'package:dashwire/dashwire.dart';
import 'package:dashwire_replication/dashwire_replication.dart' hide Authority;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_scene/physics.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_net/flutter_scene_net.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'example_overlay.dart';
import 'example_panel.dart';
import 'net/multiplayer_game.dart';

/// Multiplayer arena. Host a game in-app (desktop/mobile) and join it from
/// other instances by address, including web builds; players are balls in a
/// server-authoritative rapier world, remote poses interpolate and the local
/// ball is rollback-predicted in a matching client-side world.
class ExampleMultiplayer extends StatefulWidget {
  const ExampleMultiplayer({super.key});

  @override
  State<ExampleMultiplayer> createState() => _ExampleMultiplayerState();
}

class _ExampleMultiplayerState extends State<ExampleMultiplayer> {
  final Scene scene = Scene();
  final Node arena = Node();
  final TextEditingController _address = TextEditingController(
    text: 'localhost:$gamePort',
  );
  final FocusNode _focus = FocusNode();
  final Set<LogicalKeyboardKey> _pressed = {};

  SceneHost? _host;
  SceneReplication? _replication;
  PhysicsSimulation? _serverWorld;
  final List<PhysicsSimulation> _clientWorlds = [];
  String? _status;
  Timer? _hud;

  /// Artificial round-trip latency injected on the hosted (loopback)
  /// connection, so prediction is demonstrable on one machine.
  int _simLatencyMs = 0;

  /// Whether the local player is predicted (instant input) or interpolated
  /// like a remote (renders in the past). Toggle to feel the difference.
  bool _predict = true;

  @override
  void initState() {
    super.initState();
    final ground = Node(
      mesh: Mesh(
        CuboidGeometry(
          vm.Vector3(fieldHalfSize * 2 + 5, 0.4, fieldHalfSize * 2 + 5),
        ),
        PhysicallyBasedMaterial()
          ..baseColorFactor = vm.Vector4(0.16, 0.19, 0.23, 1),
      ),
    )..localTransform = vm.Matrix4.translation(vm.Vector3(0, -0.2, 0));
    scene.add(ground);
    // Visuals matching the arena's wall colliders (see buildArenaWorld).
    final wallMaterial = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.22, 0.26, 0.31, 1);
    for (final (x, z, size) in [
      (fieldHalfSize + 1, 0.0, vm.Vector3(1, 1.5, fieldHalfSize * 2 + 3)),
      (-fieldHalfSize - 1, 0.0, vm.Vector3(1, 1.5, fieldHalfSize * 2 + 3)),
      (0.0, fieldHalfSize + 1, vm.Vector3(fieldHalfSize * 2 + 3, 1.5, 1)),
      (0.0, -fieldHalfSize - 1, vm.Vector3(fieldHalfSize * 2 + 3, 1.5, 1)),
    ]) {
      scene.add(
        Node(mesh: Mesh(CuboidGeometry(size), wallMaterial))
          ..localTransform = vm.Matrix4.translation(vm.Vector3(x, 0.75, z)),
      );
    }
    scene.add(arena);
    // A 2 Hz HUD refresh; scene state itself never triggers rebuilds.
    _hud = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => setState(() {}),
    );
  }

  Node _playerNode(Replica replica) {
    final player = replica as NetPlayer;
    final color = HSVColor.fromAHSV(
      1,
      player.hue.value % 360,
      0.65,
      0.9,
    ).toColor();
    final isMe = player.owner == _replication?.localPeerId;
    final body = Node(
      mesh: Mesh(
        SphereGeometry(radius: playerRadius),
        PhysicallyBasedMaterial()
          ..baseColorFactor = vm.Vector4(color.r, color.g, color.b, 1),
      ),
    );
    // A nose marker makes facing visible; the local player gets a white one.
    body.add(
      Node(
          mesh: Mesh(
            CuboidGeometry(vm.Vector3(0.15, 0.15, 0.5)),
            UnlitMaterial()
              ..baseColorFactor = isMe
                  ? vm.Vector4(1, 1, 1, 1)
                  : vm.Vector4(0.1, 0.1, 0.1, 1),
          ),
        )
        ..localTransform = vm.Matrix4.translation(
          vm.Vector3(0, 0.2, playerRadius),
        ),
    );
    return body;
  }

  Node _pelletNode(Replica replica) => Node(
    mesh: Mesh(
      SphereGeometry(radius: 0.18),
      UnlitMaterial()..baseColorFactor = vm.Vector4(1, 0.85, 0.35, 1),
    ),
  );

  Future<void> _start(Future<WireConnection> Function() connect) async {
    setState(() => _status = 'connecting');
    try {
      final session = await connectSession(
        await connect(),
        schemaHash: multiplayerRegistry().schemaHash,
      );
      _replication = SceneReplication(
        registry: multiplayerRegistry(),
        session: session,
        root: arena,
        builders: {'net.player': _playerNode, 'net.pellet': _pelletNode},
        // Predict the local ball in a client-side copy of the arena world so
        // movement is instant; mispredictions (a bump from another ball) roll
        // the world back to the acked tick and replay unacked inputs. Remote
        // players stay interpolated. When prediction is off the local player
        // interpolates too, so it visibly lags input under latency.
        // TODO(wasm): enable on web once the rapier wasm carries the
        // snapshot/restore exports and the Dart-side marshalling lands.
        localPrediction: (replica) {
          if (!_predict || kIsWeb) return null;
          final controller = _PlayerController(_pressed, replica as NetPlayer);
          _clientWorlds.add(controller.simulation);
          return controller;
        },
      );
      session.done.whenComplete(() {
        if (mounted && _replication != null) _leave();
      });
      setState(() => _status = null);
    } catch (error) {
      setState(() => _status = 'failed: $error');
    }
  }

  Future<void> _hostGame() async {
    final (room, world) = buildMultiplayerRoom();
    _serverWorld = world;
    final host = await SceneHost.start(room: room, port: gamePort);
    _host = host;
    await _start(() async {
      final connection = await host.connectLocal();
      if (_simLatencyMs == 0) return connection;
      return SimulatorConnection(
        connection,
        SimulatedConditions(
          latency: Duration(milliseconds: _simLatencyMs ~/ 2),
          jitter: const Duration(milliseconds: 10),
          unreliableLoss: 0.02,
        ),
      );
    });
  }

  Future<void> _joinGame() async {
    final address = _address.text.trim();
    await _start(() => connectWebSocket(Uri.parse('ws://$address')));
  }

  Future<void> _leave() async {
    final replication = _replication;
    final host = _host;
    _replication = null;
    _host = null;
    await replication?.close();
    await host?.stop();
    for (final world in _clientWorlds) {
      world.dispose();
    }
    _clientWorlds.clear();
    _serverWorld?.dispose();
    _serverWorld = null;
    if (mounted) setState(() => _status = null);
  }

  @override
  void dispose() {
    _hud?.cancel();
    _focus.dispose();
    _address.dispose();
    _leave();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connected = _replication != null;
    return Stack(
      children: [
        KeyboardListener(
          focusNode: _focus,
          autofocus: true,
          onKeyEvent: (event) {
            if (event is KeyDownEvent) _pressed.add(event.logicalKey);
            if (event is KeyUpEvent) _pressed.remove(event.logicalKey);
          },
          child: SceneView(
            scene,
            cameraBuilder: (elapsed) => PerspectiveCamera(
              position: vm.Vector3(0, 22, 18),
              target: vm.Vector3(0, 0, 0),
            ),
          ),
        ),
        if (!connected)
          ExampleStatusCard(
            child: DefaultTextStyle.merge(
              style: const TextStyle(color: Colors.white),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Multiplayer arena',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Host on this device, then push your ball with WASD or '
                    'arrows; players are physics bodies that shove each other. '
                    'Add simulated latency and toggle prediction to feel the '
                    'difference, the predicted ball stays instant and rolls '
                    'back to replay on a mispredicted bump, while an '
                    'interpolated local player lags by the round trip. For two '
                    'clients, open a second copy and Join the address the host '
                    'shows.',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      const Text(
                        'Local prediction',
                        style: TextStyle(color: Colors.white, fontSize: 13),
                      ),
                      const Spacer(),
                      Switch(
                        value: _predict,
                        onChanged: (v) => setState(() => _predict = v),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      const Text(
                        'Sim latency',
                        style: TextStyle(color: Colors.white, fontSize: 13),
                      ),
                      const Spacer(),
                      for (final ms in const [0, 100, 250])
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: OutlinedButton(
                            onPressed: () => setState(() => _simLatencyMs = ms),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              backgroundColor: _simLatencyMs == ms
                                  ? Colors.white24
                                  : null,
                              side: BorderSide(
                                color: _simLatencyMs == ms
                                    ? Colors.white
                                    : Colors.white38,
                              ),
                              minimumSize: const Size(0, 32),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                            ),
                            child: Text(ms == 0 ? 'off' : '${ms}ms'),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (SceneHost.isSupported)
                    FilledButton(
                      onPressed: _hostGame,
                      child: const Text('Host on this device'),
                    ),
                  if (!SceneHost.isSupported)
                    const Text(
                      'Hosting needs a desktop or mobile build.',
                      style: TextStyle(color: Colors.white70),
                    ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _address,
                    style: const TextStyle(color: Colors.white),
                    cursorColor: Colors.white,
                    decoration: const InputDecoration(
                      labelText: 'host address',
                      labelStyle: TextStyle(color: Colors.white70),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.white38),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.white),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: _joinGame,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white54),
                    ),
                    child: const Text('Join'),
                  ),
                  if (_status != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _status!,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          )
        else
          ExampleOverlay.topCenter(
            child: DefaultTextStyle(
              style: const TextStyle(color: Colors.white, fontSize: 13),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_host != null)
                      Text(
                        _host!.addresses.isEmpty
                            ? 'hosting on port ${_host!.port}'
                            : 'hosting, join at '
                                  '${_host!.addresses.first}:${_host!.port}',
                      ),
                    Text(
                      'rtt ${_replication!.session.clock.rttMillis.toStringAsFixed(0)}ms'
                      '${_simLatencyMs > 0 ? ' (+$_simLatencyMs sim)' : ''}'
                      '  ${_predict ? 'predicted' : 'interpolated'}',
                    ),
                    const Text(
                      'move with WASD or arrows',
                      style: TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                    for (final player
                        in _replication!.replicas.whereType<NetPlayer>())
                      Text(
                        '${player.name.value}: ${player.score.value}'
                        '${player.owner == _replication!.localPeerId ? '  (you)' : ''}',
                      ),
                    const SizedBox(height: 6),
                    OutlinedButton(
                      onPressed: _leave,
                      child: const Text('Leave'),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Samples keyboard movement and drives a client-side copy of the arena
/// world, the same physics the server runs, so the local ball is
/// rollback-predicted and reconciled.
class _PlayerController implements PredictedPhysicsController {
  _PlayerController(this._pressed, this.player)
    : simulation = buildArenaWorld() {
    bodyHandle = createPlayerBody(simulation, player.positionVector);
  }

  final Set<LogicalKeyboardKey> _pressed;
  final NetPlayer player;

  @override
  final PhysicsSimulation simulation;

  @override
  late final int bodyHandle;

  @override
  void applyInput(Uint8List input, double dt) =>
      applyPlayerInput(simulation, bodyHandle, input);

  @override
  vm.Vector3? get authoritativeLinearVelocity {
    final (x, y, z) = player.velocity.value;
    return vm.Vector3(x, y, z);
  }

  @override
  vm.Vector3? get authoritativeAngularVelocity {
    final (x, y, z) = player.angularVelocity.value;
    return vm.Vector3(x, y, z);
  }

  double _axis(
    LogicalKeyboardKey minus,
    LogicalKeyboardKey plus,
    LogicalKeyboardKey minusAlt,
    LogicalKeyboardKey plusAlt,
  ) {
    var value = 0.0;
    if (_pressed.contains(minus) || _pressed.contains(minusAlt)) value -= 1;
    if (_pressed.contains(plus) || _pressed.contains(plusAlt)) value += 1;
    return value;
  }

  @override
  Uint8List sampleInput() {
    // Screen-right is world -X under the fixed overhead camera, so negate the
    // strafe axis to keep A left and D right.
    final strafe = -_axis(
      LogicalKeyboardKey.keyA,
      LogicalKeyboardKey.keyD,
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowRight,
    );
    final forward = _axis(
      LogicalKeyboardKey.keyW,
      LogicalKeyboardKey.keyS,
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.arrowDown,
    );
    return encodePlayerInput(strafe, forward);
  }
}
