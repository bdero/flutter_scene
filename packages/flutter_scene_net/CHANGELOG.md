# Changelog

## 0.1.0

- `SceneReplication` binds replicas to scene nodes through per-type builders and detaches them on despawn.
- `TransformReplica`-backed replicas get a `NetworkTransformComponent` that interpolates remote poses a fixed delay in the past.
- `TransformReplicaVectors` adapts the record-typed pose to `vector_math` types.
- `SceneHost` runs a dashwire room and WebSocket listener inside the app (with loopback self-join) on dart:io platforms; a throwing stub on web.
