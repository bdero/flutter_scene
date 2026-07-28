# Changelog

## Unreleased

- `PredictedTransformComponent` with `PredictedController`, client-side prediction of an owned entity with authoritative input-replay reconciliation, so local input renders instantly while the sim stays server-authoritative. Selected per entity through `SceneReplication`'s `localPrediction` seam.
- `NetworkTransformComponent` re-anchors its interpolation buffer after an idle gap, so a resuming remote eases in instead of snapping.
- Requires the input-command and prediction substrate from the next `dashwire`/`dashwire_replication` release.

## 0.1.0

- `SceneReplication` binds replicas to scene nodes through per-type builders and detaches them on despawn.
- `TransformReplica`-backed replicas get a `NetworkTransformComponent` that interpolates remote poses a fixed delay in the past.
- `TransformReplicaVectors` adapts the record-typed pose to `vector_math` types.
- `SceneHost` runs a dashwire room and WebSocket listener inside the app (with loopback self-join) on dart:io platforms; a throwing stub on web.
