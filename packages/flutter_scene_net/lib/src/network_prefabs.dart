/// The spawn table: what the server can spawn, and what a client builds when
/// it does.
///
/// A replicated object has two halves that have to agree. The server decides
/// one exists and sends its type key and its fields; the client has to know
/// what that type key means — which node to build, and which of its properties
/// the incoming fields are. Both halves come from the same
/// [NetworkIdentityComponent] declaration, which is the point: the wire layout
/// is not written twice, so it cannot disagree with itself.
///
/// dashwire checks that for real. A registry hashes every registered type's
/// field names, codecs, send modes and authority, and the two ends exchange
/// that hash at handshake. A server and a client that loaded different versions
/// of the document are refused at connect, rather than agreeing to run and
/// reading each other's fields as the wrong ones.
library;

import 'package:dashwire_replication/dashwire_replication.dart';
import 'package:flutter_scene/fscene.dart';
import 'package:flutter_scene/scene.dart' show Node;

import 'component_sync.dart';
import 'network_events.dart';
import 'network_identity.dart';

/// Builds the scene node for a spawned replica of one type.
typedef NetworkNodeBuilder = Node Function();

/// One spawnable type: what it is called on the wire, what replicates, and
/// what to build when one appears.
class NetworkPrefab {
  /// Declares a prefab that replicates [synced] and builds nodes with [build].
  const NetworkPrefab({
    required this.typeKey,
    required this.synced,
    required this.build,
    this.events = const [],
  });

  /// Declares a prefab from an authored [identity].
  ///
  /// The identity is usually the one on the prefab's own root node, so what
  /// the designer marked as replicated is exactly what goes over the wire.
  factory NetworkPrefab.of(
    NetworkIdentityComponent identity, {
    required NetworkNodeBuilder build,
  }) => NetworkPrefab(
    typeKey: identity.typeKey,
    synced: List.unmodifiable(identity.synced),
    build: build,
  );

  /// The type key both ends look this up by.
  final String typeKey;

  /// What replicates, in wire order.
  final List<SyncedProperty> synced;

  /// The events it can send, in wire order.
  final List<NetworkEvent> events;

  /// Builds the node a spawn of this type becomes.
  final NetworkNodeBuilder build;
}

/// Two prefabs claiming the same type key.
class DuplicateNetworkPrefab implements Exception {
  DuplicateNetworkPrefab(this.typeKey);

  final String typeKey;

  @override
  String toString() =>
      'flutter_scene_net: two prefabs are registered as "$typeKey". A type key '
      'is how the two ends agree what a spawn is, so it has to name exactly '
      'one thing.';
}

/// The spawn table, ready to hand to a replication client or a host.
///
/// Registering here does two things at once, and they have to stay in step: it
/// teaches the [ReplicaRegistry] how to build a replica of each type, and it
/// produces the [builders] map that turns one into a scene node. Doing both
/// from one prefab list is what keeps them in step.
class NetworkPrefabs {
  /// Builds a table from [prefabs], resolving their properties through
  /// [registry].
  ///
  /// Every prefab is validated as it is added — a property that cannot be
  /// carried, or one its component does not declare, throws here rather than
  /// at the first spawn. A spawn table is built at startup and a spawn happens
  /// mid-match; the first is a much better place to find out.
  NetworkPrefabs({
    required List<NetworkPrefab> prefabs,
    required FsceneComponentRegistry registry,
  }) : _registry = registry {
    for (final prefab in prefabs) {
      if (_prefabs.containsKey(prefab.typeKey)) {
        throw DuplicateNetworkPrefab(prefab.typeKey);
      }
      // Built and thrown away: this is the validation, and it is why a bad
      // declaration surfaces at startup.
      _replicaFor(prefab);
      _prefabs[prefab.typeKey] = prefab;
    }
  }

  final FsceneComponentRegistry _registry;
  final Map<String, NetworkPrefab> _prefabs = {};

  /// The registered type keys.
  Iterable<String> get typeKeys => _prefabs.keys;

  /// The prefab for [typeKey], or null.
  NetworkPrefab? prefabFor(String typeKey) => _prefabs[typeKey];

  ComponentReplica _replicaFor(NetworkPrefab prefab) => ComponentReplica(
    typeKey: prefab.typeKey,
    properties: prefab.synced,
    events: prefab.events,
    registry: _registry,
  );

  /// Registers every prefab's replica factory into [into].
  ///
  /// The factory produces an unbound replica: fully declared, with nowhere to
  /// read from yet. A client binds it to a node when the spawn arrives; a
  /// server binds it to the node it spawned from.
  void registerInto(ReplicaRegistry into) {
    for (final prefab in _prefabs.values) {
      into.register(() => _replicaFor(prefab));
    }
  }

  /// A fresh registry holding every prefab.
  ReplicaRegistry toRegistry() {
    final registry = ReplicaRegistry();
    registerInto(registry);
    return registry;
  }

  /// Builds the node for a spawned [replica] and binds the two together.
  ///
  /// Returns null for a replica this table does not know, which is what a
  /// client sees when the server spawns something a stale build has never
  /// heard of. Nothing is built for it rather than something wrong being.
  Node? spawn(Replica replica) {
    final prefab = _prefabs[replica.typeKey];
    if (prefab == null) return null;
    final node = prefab.build();
    if (replica is ComponentReplica) {
      replica.bind(node);
      // The spawn payload has already landed by the time this runs, so the
      // node starts at the state the server sent rather than at its prefab
      // defaults and a frame of the wrong pose.
      replica.push();
    }
    return node;
  }

  /// The node builders [SceneReplication] takes, one per registered type.
  Map<String, Node Function(Replica)> get builders => {
    for (final entry in _prefabs.entries)
      entry.key: (replica) => spawn(replica) ?? entry.value.build(),
  };
}
