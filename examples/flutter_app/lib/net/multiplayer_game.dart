/// Shared multiplayer schema and server simulation.
///
/// Pure Dart on purpose, the in-app host uses it directly, and the same file
/// could drive a headless `dart run` server unchanged.
library;

import 'dart:math';

import 'package:dashwire_replication/dashwire_replication.dart';

/// Half-extent of the square play field on the XZ plane.
const double fieldHalfSize = 11;
const double moveSpeed = 8;
const double playerRadius = 0.5;
const double pelletPickupRadius = 1.0;
const int pelletTotal = 24;
const int gameTickRate = 30;
const int gamePort = 8123;

final class NetPlayer extends TransformReplica {
  NetPlayer() {
    hue = rep('hue', 0.0, codec: Codecs.quantized(1), mode: SendMode.spawnOnly);
    name = rep('name', '', codec: Codecs.string, mode: SendMode.onChange);
    score = rep('score', 0, codec: Codecs.varUint, mode: SendMode.onChange);
    input = rep(
      'input',
      (0.0, 0.0, 0.0),
      codec: Codecs.vec3(0.05),
      write: Authority.owner,
      validate: (peer, v) => v.$1.abs() <= 1.05 && v.$3.abs() <= 1.05,
    );
  }

  @override
  String get typeKey => 'net.player';

  late final Rep<double> hue;
  late final Rep<String> name;
  late final Rep<int> score;

  /// Owner-written movement intent on the XZ plane, clamped server-side.
  late final Rep<Vec3> input;
}

final class NetPellet extends TransformReplica {
  NetPellet();

  @override
  String get typeKey => 'net.pellet';
}

ReplicaRegistry multiplayerRegistry() => ReplicaRegistry()
  ..register(NetPlayer.new)
  ..register(NetPellet.new);

/// Advances a player pose by [dt] under movement [input] on the XZ plane.
///
/// Shared by the authoritative server tick and client-side prediction so the
/// two integrate motion identically.
(Vec3, Quat) advancePlayer(
  Vec3 position,
  Quat rotation,
  Vec3 input,
  double dt,
) {
  var (dx, _, dz) = input;
  final length = sqrt(dx * dx + dz * dz);
  if (length > 1) {
    dx /= length;
    dz /= length;
  }
  final (x, y, z) = position;
  final moved = (
    (x + dx * moveSpeed * dt).clamp(-fieldHalfSize, fieldHalfSize),
    y,
    (z + dz * moveSpeed * dt).clamp(-fieldHalfSize, fieldHalfSize),
  );
  if (length <= 0.01) return (moved, rotation);
  // Face the travel direction (yaw about +Y).
  final yaw = atan2(dx, dz);
  return (moved, (0, sin(yaw / 2), 0, cos(yaw / 2)));
}

/// Builds the authoritative game room, join/leave spawns players, the tick
/// integrates owner input and awards pellet pickups.
Room buildMultiplayerRoom({Random? random}) {
  final rng = random ?? Random();
  final players = <int, NetPlayer>{};
  final pellets = <NetPellet>[];
  late final Room room;

  (double, double, double) scatter(double y) => (
    (rng.nextDouble() * 2 - 1) * fieldHalfSize,
    y,
    (rng.nextDouble() * 2 - 1) * fieldHalfSize,
  );

  room = Room(
    registry: multiplayerRegistry(),
    tickRate: gameTickRate,
    onJoin: (session) {
      final player = NetPlayer()
        ..hue.value = rng.nextDouble() * 360
        ..name.value = 'player ${session.peerId}';
      player.position.value = scatter(playerRadius);
      room.host.spawn(player, owner: session.peerId);
      players[session.peerId] = player;
    },
    onLeave: (session) {
      final player = players.remove(session.peerId);
      if (player?.id != null) room.host.despawn(player!.id!);
    },
    onTick: (tick) {
      const dt = 1.0 / gameTickRate;
      for (final player in players.values) {
        final (position, rotation) = advancePlayer(
          player.position.value,
          player.rotation.value,
          player.input.value,
          dt,
        );
        player.position.value = position;
        player.rotation.value = rotation;
        for (final pellet in pellets) {
          final (px, _, pz) = pellet.position.value;
          final (cx, _, cz) = player.position.value;
          final ddx = px - cx;
          final ddz = pz - cz;
          if (ddx * ddx + ddz * ddz < pelletPickupRadius * pelletPickupRadius) {
            player.score.value += 1;
            pellet.position.value = scatter(0.25);
          }
        }
      }
    },
  );

  for (var i = 0; i < pelletTotal; i++) {
    final pellet = NetPellet();
    pellet.position.value = scatter(0.25);
    room.host.spawn(pellet, importance: 0.3);
    pellets.add(pellet);
  }
  return room;
}
