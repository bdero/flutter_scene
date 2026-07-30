/// Shared multiplayer schema and server simulation.
///
/// Pure Dart on purpose, the in-app host uses it directly, and the same file
/// could drive a headless `dart run` server unchanged. The arena is a rapier
/// world built identically on the server and on each predicting client, so
/// client rollback prediction replays the same physics the server runs.
library;

import 'dart:math';
import 'dart:typed_data';

import 'package:dashwire/dashwire.dart';
import 'package:dashwire_replication/dashwire_replication.dart';
import 'package:flutter_scene_rapier/flutter_scene_rapier.dart';
import 'package:scene/physics.dart';
import 'package:vector_math/vector_math.dart';

/// Half-extent of the square play field on the XZ plane.
const double fieldHalfSize = 11;
const double playerRadius = 0.5;
const double pelletPickupRadius = 1.0;
const int pelletTotal = 24;
const int gameTickRate = 30;
const int gamePort = 8123;

/// Force pushing the ball toward the input direction, newtons.
const double playerForce = 8;

/// Linear damping so a released ball settles instead of coasting.
const double playerDamping = 1.5;

final class NetPlayer extends TransformReplica {
  NetPlayer() {
    hue = rep('hue', 0.0, codec: Codecs.quantized(1), mode: SendMode.spawnOnly);
    name = rep('name', '', codec: Codecs.string, mode: SendMode.onChange);
    score = rep('score', 0, codec: Codecs.varUint, mode: SendMode.onChange);
    // Velocities let a predicting client rebuild the full authoritative body
    // state at the acked tick, so a rollback replay is exact.
    velocity = rep('velocity', (0.0, 0.0, 0.0), codec: Codecs.vec3(0.001));
    angularVelocity = rep('angularVelocity', (
      0.0,
      0.0,
      0.0,
    ), codec: Codecs.vec3(0.001));
  }

  @override
  String get typeKey => 'net.player';

  late final Rep<double> hue;
  late final Rep<String> name;
  late final Rep<int> score;
  late final Rep<Vec3> velocity;
  late final Rep<Vec3> angularVelocity;
}

/// Encodes a player's movement intent for an input command. The client sends
/// these tick-stamped; the server and the client prediction both decode and
/// feed them to [applyPlayerInput].
Uint8List encodePlayerInput(double strafe, double forward) =>
    (ByteWriter(8)
          ..writeF32(strafe)
          ..writeF32(forward))
        .toBytes();

/// Decodes an input command payload to a clamped XZ movement vector.
(double, double) decodePlayerInput(Uint8List bytes) {
  final r = ByteReader(bytes);
  return (r.readF32().clamp(-1.0, 1.0), r.readF32().clamp(-1.0, 1.0));
}

final class NetPellet extends TransformReplica {
  NetPellet();

  @override
  String get typeKey => 'net.pellet';
}

ReplicaRegistry multiplayerRegistry() => ReplicaRegistry()
  ..register(NetPlayer.new)
  ..register(NetPellet.new);

/// Builds the arena physics world, a ground slab and four containing walls.
/// Built identically by the server room and by each predicting client, so
/// both sides simulate the same static environment. Await
/// `RapierWorld.ensureInitialized()` first on the web.
PhysicsSimulation buildArenaWorld() {
  final world = RapierWorld();
  const wall = 0.5; // wall half-thickness
  final reach = fieldHalfSize + wall; // inner wall face
  final ground = world.createBody(
    target: SimplePoseTarget(translation: Vector3(0, -0.2, 0)),
    type: BodyType.fixed,
  );
  world.createColliders(
    ground,
    BoxShape(halfExtents: Vector3(reach + 2 * wall, 0.2, reach + 2 * wall)),
  );
  for (final (x, z, half) in [
    (reach + wall, 0.0, Vector3(wall, 0.75, reach + 2 * wall)),
    (-reach - wall, 0.0, Vector3(wall, 0.75, reach + 2 * wall)),
    (0.0, reach + wall, Vector3(reach + 2 * wall, 0.75, wall)),
    (0.0, -reach - wall, Vector3(reach + 2 * wall, 0.75, wall)),
  ]) {
    final body = world.createBody(
      target: SimplePoseTarget(translation: Vector3(x, 0.75, z)),
      type: BodyType.fixed,
    );
    world.createColliders(body, BoxShape(halfExtents: half));
  }
  return world;
}

/// Creates a player ball resting at [position] and returns its body handle.
int createPlayerBody(PhysicsSimulation world, Vector3 position) {
  final body = world.createBody(
    target: SimplePoseTarget(translation: position),
    type: BodyType.dynamic_,
  );
  world.setBodyLinearDamping(body, playerDamping);
  world.createColliders(
    body,
    const SphereShape(radius: playerRadius),
    material: const PhysicsMaterial(friction: 0.8, restitution: 0.3),
  );
  return body;
}

/// Applies one tick of movement input to a player ball, a horizontal push
/// the next step integrates. Shared by the authoritative server tick and
/// client prediction so the two simulate identically.
void applyPlayerInput(PhysicsSimulation world, int body, Uint8List input) {
  var (dx, dz) = decodePlayerInput(input);
  final length = sqrt(dx * dx + dz * dz);
  if (length > 1) {
    dx /= length;
    dz /= length;
  }
  if (length < 0.01) return;
  world.applyForce(body, Vector3(dx * playerForce, 0, dz * playerForce));
}

/// Builds the authoritative game room and its physics world. Join/leave
/// spawns player balls, the tick applies owner input, steps the world,
/// publishes body state, and awards pellet pickups. The caller owns the
/// returned world and disposes it after the room stops.
(Room, PhysicsSimulation) buildMultiplayerRoom({Random? random}) {
  final rng = random ?? Random();
  final world = buildArenaWorld();
  final players = <int, NetPlayer>{};
  final bodies = <int, int>{};
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
      final (x, y, z) = player.position.value;
      bodies[session.peerId] = createPlayerBody(world, Vector3(x, y, z));
      room.host.spawn(player, owner: session.peerId);
      players[session.peerId] = player;
    },
    onLeave: (session) {
      final body = bodies.remove(session.peerId);
      if (body != null) world.destroyBody(body);
      final player = players.remove(session.peerId);
      if (player?.id != null) room.host.despawn(player!.id!);
    },
    onTick: (tick) {
      const dt = 1.0 / gameTickRate;
      // Consume each peer's authoritative input for the tick (hold-last on a
      // gap), then advance the whole world one step.
      for (final entry in players.entries) {
        final command = room.input(entry.key, tick);
        if (command == null) continue;
        applyPlayerInput(world, bodies[entry.key]!, command);
      }
      world.step(dt);
      for (final entry in players.entries) {
        final player = entry.value;
        final body = bodies[entry.key]!;
        final (position, rotation) = world.readBodyPose(body);
        player.position.value = (position.x, position.y, position.z);
        player.rotation.value = (
          rotation.x,
          rotation.y,
          rotation.z,
          rotation.w,
        );
        final linear = world.readBodyLinearVelocity(body);
        final angular = world.readBodyAngularVelocity(body);
        player.velocity.value = (linear.x, linear.y, linear.z);
        player.angularVelocity.value = (angular.x, angular.y, angular.z);
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
  return (room, world);
}
