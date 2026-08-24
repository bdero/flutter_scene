import 'package:flutter_scene/kit.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DayNightCycleComponent', () {
    test('sun direction at noon points high in the sky', () {
      final cycle = DayNightCycleComponent(timeOfDay: 12.0);
      final dir = cycle.sunDirection;

      expect(dir.y, greaterThan(0.7));
    });

    test('sun direction at midnight points downward', () {
      final cycle = DayNightCycleComponent(timeOfDay: 0.0);
      final dir = cycle.sunDirection;

      expect(dir.y, lessThan(-0.7));
    });

    test('aims directional light along +Z into the scene', () {
      final sunLight = DirectionalLight();
      final sunNode = Node()..addComponent(DirectionalLightComponent(sunLight));
      final root = Node();
      root.add(sunNode);

      final cycle = DayNightCycleComponent(
        timeOfDay: 12.0,
        latitude: 34.0,
        sunLightNode: sunNode,
      );
      root.addComponent(cycle);

      cycle.update(0.1);

      // Light travels along local +Z; at noon, +Z should point downwards into the ground
      final forward = (sunNode.globalTransform * vm.Vector4(0, 0, 1, 0)).xyz;
      expect(forward.y, lessThan(-0.7));

      final pos = sunNode.position;
      expect(pos.y, greaterThan(50.0));
      expect(sunLight.intensity, greaterThan(50000.0));
    });

    test('overhead noon at equator does not degenerate', () {
      final sunLight = DirectionalLight();
      final sunNode = Node()..addComponent(DirectionalLightComponent(sunLight));
      final root = Node();
      root.add(sunNode);

      final cycle = DayNightCycleComponent(
        timeOfDay: 12.0,
        latitude: 0.0,
        sunLightNode: sunNode,
      );
      root.addComponent(cycle);

      cycle.update(0.1);

      final forward = (sunNode.globalTransform * vm.Vector4(0, 0, 1, 0)).xyz;
      expect(forward.y, closeTo(-1.0, 0.001));
    });

    test('updates correctly when sun node is parented under transform', () {
      final parentNode = Node()
        ..localTransform = (vm.Matrix4.identity()
          ..scaleByVector3(vm.Vector3(1.0, 1.0, -1.0)));
      final sunLight = DirectionalLight();
      final sunNode = Node()..addComponent(DirectionalLightComponent(sunLight));
      parentNode.add(sunNode);

      final root = Node();
      root.add(parentNode);

      final cycle = DayNightCycleComponent(
        timeOfDay: 12.0,
        latitude: 34.0,
        sunLightNode: sunNode,
      );
      root.addComponent(cycle);

      cycle.update(0.1);

      final worldPos = (sunNode.globalTransform * vm.Vector4(0, 0, 0, 1)).xyz;
      expect(worldPos.y, greaterThan(50.0));
    });
  });
}
