import 'dart:async';
import 'dart:io';

import 'package:dashwire/dashwire.dart';
import 'package:dashwire/server.dart';
import 'package:dashwire_replication/dashwire_replication.dart';

/// Runs a [Room] inside the app with a WebSocket listener, the listen-server
/// topology. The hosting player joins over an in-process loopback via
/// [connectLocal]; others connect to `ws://<address>:<port>`.
final class SceneHost {
  SceneHost._(this.room, this._server, this.addresses);

  static bool get isSupported => true;

  /// Binds a WebSocket server on [port] (0 picks one), wires it into
  /// [room], and starts the room's tick pump.
  static Future<SceneHost> start({required Room room, int port = 0}) async {
    final server = await WebSocketWireServer.bind(
      InternetAddress.anyIPv4,
      port,
    );
    room
      ..accept(server.connections)
      ..start();
    final addresses = <String>[];
    try {
      for (final interface in await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      )) {
        for (final address in interface.addresses) {
          if (!address.isLoopback) addresses.add(address.address);
        }
      }
    } on SocketException {
      // Interface enumeration can be restricted (sandboxes); hosting still
      // works, the UI just cannot display a LAN address.
    }
    return SceneHost._(room, server, addresses);
  }

  final Room room;
  final WebSocketWireServer _server;

  /// Non-loopback IPv4 addresses other devices can join through.
  final List<String> addresses;

  int get port => _server.port;

  /// Connects the hosting player to its own room in-process.
  Future<WireConnection> connectLocal() async {
    final (clientEnd, serverEnd) = LoopbackConnection.pair();
    unawaited(room.admit(serverEnd));
    return clientEnd;
  }

  Future<void> stop() async {
    await room.stop();
    await _server.close();
  }
}
