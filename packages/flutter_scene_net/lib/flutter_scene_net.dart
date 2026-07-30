/// dashwire multiplayer for flutter_scene.
///
/// Replicas whose types extend [TransformReplica] become scene nodes through
/// a [SceneReplication] binding; remote poses render slightly in the past
/// through interpolation. [SceneHost] runs a room inside the app on
/// dart:io platforms so a game can host without a separate server.
library;

export 'src/hosting/hosting.dart' show SceneHost;
export 'src/network_transform.dart' show NetworkTransformComponent;
export 'src/scene_replication.dart' show ReplicaNodeBuilder, SceneReplication;
export 'src/transform_replica.dart' show TransformReplicaVectors;
