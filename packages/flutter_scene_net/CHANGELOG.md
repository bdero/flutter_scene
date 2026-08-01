# Changelog

## Unreleased

- `PredictedTransformComponent` with `PredictedController`, client-side prediction of an owned entity with authoritative input-replay reconciliation, so local input renders instantly while the sim stays server-authoritative. Selected per entity through `SceneReplication`'s `localPrediction` seam.
- `PredictedPhysicsComponent` with `PredictedPhysicsController`, rollback prediction for an owned physics body. Mispredictions restore a retained world snapshot, adopt the authoritative pose, and replay pending inputs through the simulation; `onWorldRestored` tells the controller so dynamically created bodies (remote-player proxies) can be revalidated. Needs a snapshot-capable backend (rapier).
- `PhysicsWorldHistory`, a server-side per-tick world snapshot ring that rewinds hit queries to the client-rendered tick and restores the present, capped by `maxRewindTicks`.
- `NetworkTransformComponent` re-anchors its interpolation buffer after an idle gap, so a resuming remote eases in instead of snapping.
- Requires the input-command and prediction substrate from the next `dashwire`/`dashwire_replication` release.

## 0.1.0

- `SceneReplication` binds replicas to scene nodes through per-type builders and detaches them on despawn.
- `TransformReplica`-backed replicas get a `NetworkTransformComponent` that interpolates remote poses a fixed delay in the past.
- `TransformReplicaVectors` adapts the record-typed pose to `vector_math` types.
- `SceneHost` runs a dashwire room and WebSocket listener inside the app (with loopback self-join) on dart:io platforms; a throwing stub on web.
