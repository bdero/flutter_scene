/// Headless multiplayer arena server.
///
/// `dart run tool/multiplayer_host.dart` hosts the same authoritative room
/// the in-app host runs (rapier world, input commands, pellets), so clients
/// on any platform, including web builds, can join `ws://<host>:8123`.
library;

import 'dart:io';

import 'package:dashwire/server.dart';
import 'package:example_app/net/multiplayer_game.dart';

Future<void> main() async {
  final (room, world) = buildMultiplayerRoom();
  final server = await WebSocketWireServer.bind(
    InternetAddress.anyIPv4,
    gamePort,
  );
  room
    ..accept(server.connections)
    ..start();
  stdout.writeln('hosting the multiplayer arena on ws://localhost:$gamePort');
  await ProcessSignal.sigint.watch().first;
  await room.stop();
  await server.close();
  world.dispose();
}
