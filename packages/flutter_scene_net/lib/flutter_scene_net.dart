/// dashwire multiplayer for flutter_scene.
///
/// Replicas whose types extend [TransformReplica] become scene nodes through
/// a [SceneReplication] binding. Poses you do not own render slightly in the
/// past through interpolation; the entity you own can instead be predicted so
/// local input renders instantly. [SceneHost] runs a room inside the app on
/// dart:io platforms so a game can host without a separate server.
library;

export 'src/hosting/hosting.dart' show SceneHost;
export 'src/network_transform.dart' show NetworkTransformComponent;
export 'src/predicted_transform.dart'
    show PredictStep, PredictedTransformComponent;
export 'src/scene_replication.dart' show ReplicaNodeBuilder, SceneReplication;
export 'src/transform_replica.dart' show TransformReplicaVectors;
