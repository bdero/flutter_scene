import 'package:flutter_scene/kit.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NodePool', () {
    test('spawns and despawns nodes recycling instances', () {
      var createdCount = 0;
      final pool = NodePool(
        () {
          createdCount++;
          return Node();
        },
        initialSize: 3,
        maxSize: 5,
      );

      expect(pool.idleCount, equals(3));
      expect(pool.activeCount, equals(0));
      expect(createdCount, equals(3));

      final parent = Node();
      final n1 = pool.spawn(parent: parent, transform: vm.Matrix4.identity());

      expect(pool.idleCount, equals(2));
      expect(pool.activeCount, equals(1));
      expect(parent.children.contains(n1), isTrue);

      pool.despawn(n1);

      expect(pool.idleCount, equals(3));
      expect(pool.activeCount, equals(0));
      expect(parent.children.contains(n1), isFalse);
    });

    test('despawnAll reclaims all active nodes', () {
      final pool = NodePool(() => Node(), initialSize: 0);
      final parent = Node();

      pool.spawn(parent: parent);
      pool.spawn(parent: parent);
      pool.spawn(parent: parent);

      expect(pool.activeCount, equals(3));
      expect(parent.children.length, equals(3));

      pool.despawnAll();

      expect(pool.activeCount, equals(0));
      expect(pool.idleCount, equals(3));
      expect(parent.children.length, equals(0));
    });
  });
}
