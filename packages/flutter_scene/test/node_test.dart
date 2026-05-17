import 'package:flutter_scene/scene.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  group('globalTransform', () {
    test('globalTransform defaults to identity', () {
      final node = Node();
      expect(node.globalTransform, Matrix4.identity());
    });

    test('globalTransform propagates to child node', () {
      final parentNode = Node();
      final childNode = Node();
      parentNode.add(childNode);
      parentNode.localTransform.setTranslationRaw(1.0, 2.0, 3.0);
      // The transform was mutated in place, so the cache must be told.
      parentNode.markTransformDirty();

      expect(childNode.globalTransform, parentNode.globalTransform);
    });

    test('globalTransform applies local transforms in correct order', () {
      final parentNode = Node();
      final childNode = Node();
      parentNode.add(childNode);

      parentNode.localTransform.scaleByDouble(2.0, 2.0, 2.0, 1.0);
      childNode.localTransform.translateByDouble(1.0, 2.0, 3.0, 1.0);
      // Both transforms were mutated in place.
      parentNode.markTransformDirty();
      childNode.markTransformDirty();

      // In addition to the basis vectors being scaled up, the, the child's
      // translation (last column) is magnified by the parent's scale.
      final expectedTransform = Matrix4.columns(
        Vector4(2.0, 0.0, 0.0, 0.0),
        Vector4(0.0, 2.0, 0.0, 0.0),
        Vector4(0.0, 0.0, 2.0, 0.0),
        Vector4(2.0, 4.0, 6.0, 1.0),
      );

      expect(childNode.globalTransform, expectedTransform);
    });

    test('globalTransform cache refreshes after a parent transform change', () {
      final parentNode = Node();
      final childNode = Node();
      parentNode.add(childNode);

      // First read caches the world transforms.
      expect(childNode.globalTransform, Matrix4.identity());

      // Reassigning the parent transform invalidates the child's cache.
      parentNode.localTransform = Matrix4.translation(Vector3(0.0, 5.0, 0.0));
      expect(
        childNode.globalTransform,
        Matrix4.translation(Vector3(0.0, 5.0, 0.0)),
      );
    });
  });
}
