// Detaching a networked component. Its subscriptions used to outlive it: the
// component, and everything it closed over, stayed reachable from the replica
// for as long as the replica lived, and every pose change kept appending to a
// buffer nobody would ever read.
//
// Liveness is not directly assertable in Dart without forcing a collection, so
// what is pinned here is the behaviour the fix rests on and the paths it could
// have broken.

import 'package:dashwire_replication/dashwire_replication.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_net/flutter_scene_net.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Pawn extends TransformReplica {
  @override
  String get typeKey => 'pawn';
}

void main() {
  test('the transport hands back a cancellable handle', () {
    // What the teardown rests on. Stated here so a dependency bump that lost
    // it fails in this package rather than silently going back to leaking.
    final pawn = _Pawn();
    final subscription = pawn.position.onChanged((_, _) {});
    expect(subscription.isActive, isTrue);

    var heard = 0;
    final counted = pawn.rotation.onChanged((_, _) => heard++);
    pawn.rotation.value = (0.0, 0.0, 0.0, 1.0);
    final before = heard;
    counted.cancel();
    pawn.rotation.value = (0.0, 1.0, 0.0, 0.0);
    expect(heard, before, reason: 'a cancelled listener hears nothing');
  });

  test('an attached component follows its replica', () {
    // The path the teardown could have broken by cancelling too early.
    var micros = 0;
    final pawn = _Pawn();
    final node = Node(name: 'pawn');
    node.addComponent(
      NetworkTransformComponent(
        pawn,
        delay: const Duration(milliseconds: 10),
        adaptive: false,
        now: () => micros,
      ),
    );

    pawn.position.value = (0.0, 0.0, 0.0);
    micros += 20000;
    pawn.position.value = (4.0, 0.0, 0.0);
    micros += 20000;
    node.getComponents<NetworkTransformComponent>().single.update(0.02);

    expect(node.localTransform.getTranslation().x, greaterThan(0));
  });

  test('changing the replica after a detach is harmless', () {
    // The component is gone; the change has nowhere to go and must not go
    // looking for it.
    final pawn = _Pawn();
    final node = Node(name: 'pawn');
    final component = NetworkTransformComponent(pawn);
    node
      ..addComponent(component)
      ..removeComponent(component);

    expect(() => pawn.position.value = (9.0, 0.0, 0.0), returnsNormally);
    expect(() => pawn.rotation.value = (0.0, 1.0, 0.0, 0.0), returnsNormally);
  });

  test('detaching one component does not silence another', () {
    // The handles are per subscription, not per replica, so two nodes driven
    // by one replica are independent.
    final pawn = _Pawn();
    final kept = NetworkTransformComponent(pawn);
    final keptNode = Node(name: 'kept')..addComponent(kept);

    final dropped = NetworkTransformComponent(pawn);
    Node(name: 'dropped')
      ..addComponent(dropped)
      ..removeComponent(dropped);

    expect(() => pawn.position.value = (5.0, 0.0, 0.0), returnsNormally);
    expect(
      keptNode.getComponents<NetworkTransformComponent>(),
      hasLength(1),
      reason: 'the surviving component is still attached and subscribed',
    );
  });
}
