# flutter_scene_net

[dashwire](https://pub.dev/packages/dashwire) multiplayer for [flutter_scene](https://pub.dev/packages/flutter_scene). Binds replicated state to the scene graph so networked entities become nodes that render smoothly.

- `SceneReplication` maps replicas to scene nodes through per-type builders, spawning and despawning nodes as the server dictates.
- Replicas that extend `TransformReplica` get a `NetworkTransformComponent`, an interpolation buffer that renders remote poses a fixed delay in the past so motion stays smooth under jitter.
- `SceneHost` runs a dashwire room and WebSocket listener inside the app, so a game can host from one device with a loopback self-join, no separate server process. Native only; a throwing stub on web.

See the Multiplayer example in the [flutter_scene repository](https://github.com/bdero/flutter_scene/tree/master/examples/flutter_app) for a full host-and-join demo.

## Usage

```dart
final replication = SceneReplication(
  registry: registry,
  session: session,
  root: sceneRoot,
  builders: {'pawn': (replica) => Node()},
);
```

Server-authoritative state flows in over a dashwire `Session`; each replica type names a builder that produces its scene node.
