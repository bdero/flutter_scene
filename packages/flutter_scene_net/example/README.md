# flutter_scene_net example

A full host-and-join demo lives in the [flutter_scene repository](https://github.com/bdero/flutter_scene/tree/master/examples/flutter_app) as the "Multiplayer" example. The core wiring:

```dart
import 'package:dashwire/dashwire.dart';
import 'package:dashwire_replication/dashwire_replication.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_net/flutter_scene_net.dart';

// A replicated pawn whose pose drives a scene node.
final class Pawn extends TransformReplica {
  @override
  String get typeKey => 'pawn';
}

Future<void> connectAndRender(WireConnection connection, Node sceneRoot) async {
  final registry = ReplicaRegistry()..register(Pawn.new);

  final session = await connectSession(
    connection,
    schemaHash: registry.schemaHash,
  );

  // Replicas spawned by the server become nodes under [sceneRoot]; those
  // backed by TransformReplica interpolate their poses automatically.
  SceneReplication(
    registry: registry,
    session: session,
    root: sceneRoot,
    builders: {'pawn': (replica) => Node()},
  );
}
```

To host from inside the app instead of connecting to a server, use `SceneHost`.
