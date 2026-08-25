import 'package:flutter_scene/kit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DebugDraw', () {
    setUp(() {
      DebugDraw.clear();
    });

    test('accumulates lines, rays, boxes, and axes', () {
      expect(DebugDraw.vertexCount, equals(0));

      DebugDraw.line(vm.Vector3.zero(), vm.Vector3(1, 0, 0));
      expect(DebugDraw.vertexCount, equals(2));

      DebugDraw.ray(vm.Vector3.zero(), vm.Vector3(0, 1, 0), length: 2.0);
      expect(DebugDraw.vertexCount, equals(4));

      DebugDraw.box(vm.Aabb3.minMax(vm.Vector3(0, 0, 0), vm.Vector3(1, 1, 1)));
      expect(DebugDraw.vertexCount, equals(4 + 24));

      DebugDraw.clear();
      expect(DebugDraw.vertexCount, equals(0));
    });
  });
}
