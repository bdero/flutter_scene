import 'dart:async';

import 'package:dashwire/dashwire.dart';
import 'package:dashwire_replication/dashwire_replication.dart' hide Authority;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_net/flutter_scene_net.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'net/multiplayer_game.dart';

/// Multiplayer arena. Host a game in-app (desktop/mobile) and join it from
/// other instances by address, including web builds; movement is
/// server-authoritative with interpolated remote poses.
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
  String? _status;
  Timer? _hud;

  @override
  void initState() {
    super.initState();
    final ground = Node(
      mesh: Mesh(
        CuboidGeometry(
          vm.Vector3(fieldHalfSize * 2 + 2, 0.4, fieldHalfSize * 2 + 2),
        ),
        PhysicallyBasedMaterial()
          ..baseColorFactor = vm.Vector4(0.16, 0.19, 0.23, 1),
      ),
    )..localTransform = vm.Matrix4.translation(vm.Vector3(0, -0.2, 0));
    scene.add(ground);
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
    final host = await SceneHost.start(
      room: buildMultiplayerRoom(),
      port: gamePort,
    );
    _host = host;
    await _start(host.connectLocal);
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

  void _onTick(Duration elapsed, double deltaSeconds) {
    final replication = _replication;
    if (replication == null) return;
    double axis(
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

    replication.owned<NetPlayer>()?.input.value = (
      axis(
        LogicalKeyboardKey.keyA,
        LogicalKeyboardKey.keyD,
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.arrowRight,
      ),
      0.0,
      axis(
        LogicalKeyboardKey.keyW,
        LogicalKeyboardKey.keyS,
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.arrowDown,
      ),
    );
    replication.flush();
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
            onTick: _onTick,
            cameraBuilder: (elapsed) => PerspectiveCamera(
              position: vm.Vector3(0, 22, 18),
              target: vm.Vector3(0, 0, 0),
            ),
          ),
        ),
        if (!connected)
          Center(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Multiplayer arena'),
                    const SizedBox(height: 12),
                    if (SceneHost.isSupported)
                      FilledButton(
                        onPressed: _hostGame,
                        child: const Text('Host on this device'),
                      ),
                    if (!SceneHost.isSupported)
                      const Text('Hosting needs a desktop or mobile build.'),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: 260,
                      child: TextField(
                        controller: _address,
                        decoration: const InputDecoration(
                          labelText: 'host address',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: _joinGame,
                      child: const Text('Join'),
                    ),
                    if (_status != null) ...[
                      const SizedBox(height: 8),
                      Text(_status!, style: const TextStyle(fontSize: 12)),
                    ],
                  ],
                ),
              ),
            ),
          )
        else
          Positioned(
            left: 12,
            top: 12,
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
                      ', move with WASD/arrows',
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
