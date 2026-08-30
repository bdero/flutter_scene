/// dashwire multiplayer for flutter_scene.
///
/// Replicas whose types extend [TransformReplica] become scene nodes through
/// a [SceneReplication] binding. Poses you do not own render slightly in the
/// past through interpolation; the entity you own can instead be predicted so
/// local input renders instantly. [SceneHost] runs a room inside the app on
/// dart:io platforms so a game can host without a separate server.
library;

export 'src/component_sync.dart'
    show
        ComponentReplica,
        PropertyWire,
        SyncedProperty,
        UnknownSyncedComponent,
        UnknownSyncedProperty,
        UnsyncableProperty,
        canSync,
        wireFor;
export 'src/hosting/hosting.dart' show SceneHost;
export 'src/network_events.dart'
    show
        DuplicateNetworkEvent,
        NetworkEvent,
        NetworkEventHandler,
        UnknownNetworkEvent,
        decodeNetworkEvent,
        encodeNetworkEvent,
        networkEventFields;
export 'src/network_identity.dart'
    show
        NetworkIdentityCodec,
        NetworkIdentityComponent,
        decodeSyncedProperty,
        encodeSyncedProperty,
        syncedPropertyFields;
export 'src/network_transform_codec.dart'
    show NetworkTransformCodec, registerNetComponentCodecs;
export 'src/network_prefabs.dart'
    show
        DuplicateNetworkPrefab,
        NetworkNodeBuilder,
        NetworkPrefab,
        NetworkPrefabs;
export 'src/network_session.dart'
    show
        ConnectionApproval,
        ConnectionApprover,
        NetworkClient,
        NetworkRole,
        NetworkSession,
        SessionAlreadyRunning,
        UnknownPlayerPrefab;
export 'src/network_transform.dart' show NetworkTransformComponent;
// TODO(lagcomp): export PhysicsWorldHistory once something consumes it. The
// server-side rewind needs the peer's last acked tick, which the host does
// not record yet, and rewind lands on whole ticks where hit registration
// wants the two bracketing snapshots interpolated.
export 'src/predicted_physics.dart'
    show PredictedPhysicsComponent, PredictedPhysicsController;
export 'src/predicted_transform.dart'
    show PredictedController, PredictedTransformComponent, PredictionController;
export 'src/scene_replication.dart'
    show LocalPredictionBuilder, ReplicaNodeBuilder, SceneReplication;
export 'src/transform_replica.dart' show TransformReplicaVectors;
