# Changelog

## 0.2.0

- `PredictedTransformComponent` with `PredictedController`, client-side prediction of an owned entity with authoritative input-replay reconciliation, so local input renders instantly while the sim stays server-authoritative. Selected per entity through `SceneReplication`'s `localPrediction` seam.
- `PredictedPhysicsComponent` with `PredictedPhysicsController`, rollback prediction for an owned physics body. Mispredictions restore a retained world snapshot, adopt the authoritative pose, and replay pending inputs through the simulation. Needs a snapshot-capable backend (rapier).
- `PredictedPhysicsController.onWorldRestored` fires after a rollback restore. A restore rewinds to the body set its snapshot captured, so a controller managing bodies dynamically (remote-player proxies) allocates a fixed pool before the first snapshot rather than recreating them.
- `NetworkTransformComponent` re-anchors its interpolation buffer after an idle gap, so a resuming remote eases in instead of snapping.
- The interpolation delay adapts to measured arrival cadence and jitter, easing between `minDelay` and the configured ceiling, so clean links render remotes barely behind while jittery ones buffer deep.
- `SceneReplication.inputTargetDepth` passes the input buffer depth through to the client (1 suits local or stable links).
- `SceneReplication.minInterpolationDelay` and `SceneReplication.adaptiveInterpolation` reach the interpolation buffer, so an app can floor the adaptive delay or hold it fixed.
- Both predicted components reconcile at the tick the authoritative pose was snapshotted at, not the input ack's, so a deferred snapshot no longer discards the travel in between. They wait for a snapshot to date the pose before reconciling at all.
- Both predicted components take `maxCatchUpTicks` and snap to authority past it, so a backgrounded tab or a long hitch does not replay every missed tick in one frame.
- Requires `dashwire_replication` 0.2.1 for the input-command and prediction substrate.

## 0.1.0

- `SceneReplication` binds replicas to scene nodes through per-type builders and detaches them on despawn.
- `TransformReplica`-backed replicas get a `NetworkTransformComponent` that interpolates remote poses a fixed delay in the past.
- `TransformReplicaVectors` adapts the record-typed pose to `vector_math` types.
- `SceneHost` runs a dashwire room and WebSocket listener inside the app (with loopback self-join) on dart:io platforms; a throwing stub on web.
