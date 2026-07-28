import 'dart:async';

import 'package:dashwire/dashwire.dart';
import 'package:dashwire_replication/dashwire_replication.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' hide Colors;

import 'network_transform.dart';
import 'predicted_transform.dart';
import 'transform_replica.dart';

/// Builds the scene subtree representing [replica] at spawn time.
typedef ReplicaNodeBuilder = Node Function(Replica replica);

/// Supplies the client-side prediction step for an owned [replica], or null to
/// interpolate it like any other entity.
typedef LocalPredictionBuilder = PredictStep? Function(Replica replica);

/// Binds a replication client to a scene graph.
///
/// Spawned replicas become nodes under [root] through per-type builders.
/// [TransformReplica]s get a [NetworkTransformComponent] that renders their
/// pose interpolated in the past; the entity this client owns is instead
/// driven by a [PredictedTransformComponent] when a `localPrediction` step is
/// supplied, so local input renders instantly. Despawns detach the node.
final class SceneReplication {
  SceneReplication({
    required ReplicaRegistry registry,
    required this.session,
    required this.root,
    required Map<String, ReplicaNodeBuilder> builders,
    this.interpolationDelay = const Duration(milliseconds: 100),
    LocalPredictionBuilder? localPrediction,
    void Function(Replica replica, Node node)? onSpawn,
    void Function(Replica replica, Node node)? onDespawn,
  }) : _builders = builders,
       _localPrediction = localPrediction,
       _onSpawn = onSpawn,
       _onDespawn = onDespawn {
    client = ReplicationClient(
      registry: registry,
      session: session,
      onSpawn: _spawned,
      onDespawn: _despawned,
    );
  }

  final Session session;

  /// Parent for every replicated node.
  final Node root;

  final Map<String, ReplicaNodeBuilder> _builders;
  final Duration interpolationDelay;
  final LocalPredictionBuilder? _localPrediction;
  final void Function(Replica, Node)? _onSpawn;
  final void Function(Replica, Node)? _onDespawn;
  late final ReplicationClient client;
  final Map<NetId, Node> _nodes = {};

  int get localPeerId => client.localPeerId;

  Iterable<Replica> get replicas => client.replicas.values;

  Node? nodeFor(NetId id) => _nodes[id];

  /// This client's owned replica of type [T], if spawned.
  T? owned<T extends Replica>() => client.replicas.values
      .whereType<T>()
      .where((r) => r.owner == localPeerId)
      .firstOrNull;

  void _spawned(Replica replica) {
    final builder = _builders[replica.typeKey];
    if (builder == null) return;
    final node = builder(replica);
    if (replica is TransformReplica) {
      node.localTransform = Matrix4.compose(
        replica.positionVector,
        replica.rotationQuaternion,
        Vector3(1, 1, 1),
      );
      // Predict the entity this client owns so its input renders instantly;
      // interpolate everything else in the past for smoothness.
      final predict = replica.owner == localPeerId
          ? _localPrediction?.call(replica)
          : null;
      node.addComponent(
        predict != null
            ? PredictedTransformComponent(replica, step: predict)
            : NetworkTransformComponent(replica, delay: interpolationDelay),
      );
    }
    root.add(node);
    _nodes[replica.id!] = node;
    _onSpawn?.call(replica, node);
  }

  void _despawned(Replica replica) {
    final node = _nodes.remove(replica.id);
    if (node == null) return;
    _onDespawn?.call(replica, node);
    root.remove(node);
  }

  /// Sends pending owner-authority writes. Call once per frame or tick.
  void flush() => client.flush();

  /// Closes the session and detaches every replicated node.
  Future<void> close() async {
    await session.close();
    for (final node in _nodes.values) {
      root.remove(node);
    }
    _nodes.clear();
  }
}
