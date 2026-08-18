import 'package:flutter_scene/scene.dart';
// The authored TRS decomposition is internal; these tests reach it directly.
// ignore: implementation_imports
import 'package:flutter_scene/src/animation.dart' show DecomposedTransform;
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

    test('globalTransform setter solves through a transformed parent', () {
      final parentTransform =
          Matrix4.diagonal3Values(1, 1, -1) *
          Matrix4.compose(
            Vector3(3, -2, 7),
            Quaternion.axisAngle(Vector3(1, 0, 0), 0.7),
            Vector3.all(0.016),
          );
      final parentNode = Node(localTransform: parentTransform.clone());
      final childNode = Node();
      parentNode.add(childNode);
      final desiredGlobal = Matrix4.compose(
        Vector3(4, 5, 6),
        Quaternion.axisAngle(Vector3(0, 1, 0), 0.35),
        Vector3(1, 2, 3),
      );

      childNode.globalTransform = desiredGlobal;

      _expectMatrixNear(childNode.globalTransform, desiredGlobal);
      _expectMatrixNear(parentNode.globalTransform, parentTransform);
    });
  });

  group('clone', () {
    test('preserves mirrored transform winding', () {
      final root = Node(
        localTransform: Matrix4.identity()..setEntry(2, 2, -1.0),
      );
      root.add(Node());
      expect(root.windingFlipped, isTrue);

      final clone = root.clone();
      expect(clone.windingFlipped, isTrue);
    });

    test('clone owns its own transform matrix', () {
      final source = Node(
        localTransform: Matrix4.translation(Vector3(1.0, 2.0, 3.0)),
      );
      final clone = source.clone();
      expect(identical(clone.localTransform, source.localTransform), isFalse);

      clone.localTransform.setTranslationRaw(9.0, 9.0, 9.0);
      clone.markTransformDirty();

      expect(source.localTransform.getTranslation(), Vector3(1.0, 2.0, 3.0));
    });
  });

  group('in-place transform edits', () {
    test('mutating localTransform without marking dirty throws', () {
      final node = Node();
      node.globalTransform; // Fill the cache.
      node.localTransform.setTranslationRaw(1.0, 2.0, 3.0);

      expect(() => node.globalTransform, throwsStateError);
    });

    test('marking dirty after an in-place edit is accepted', () {
      final node = Node();
      node.globalTransform;
      node.localTransform.setTranslationRaw(1.0, 2.0, 3.0);
      node.markTransformDirty();

      expect(node.globalTransform.getTranslation(), Vector3(1.0, 2.0, 3.0));
    });

    test('the check is per node, so an edit is caught at its own read', () {
      final parent = Node();
      final child = Node();
      parent.add(child);
      child.globalTransform;
      parent.localTransform.setTranslationRaw(1.0, 0.0, 0.0);

      // The child's own matrix is untouched, so only the parent reports.
      expect(() => child.globalTransform, returnsNormally);
      expect(() => parent.globalTransform, throwsStateError);
    });

    test('mutateLocalTransform edits in place and marks dirty', () {
      final node = Node();
      node.globalTransform; // Fill the cache.
      node.mutateLocalTransform(
        (m) => m.translateByVector3(Vector3(0.0, 1.0, 0.0)),
      );

      // No throw, and the edit is reflected, so the cache was invalidated.
      expect(node.globalTransform.getTranslation(), Vector3(0.0, 1.0, 0.0));
    });

    test('mutateLocalTransform clears the authored decomposition', () {
      final node = Node()..scale = Vector3(2.0, 2.0, 2.0);
      expect(node.localTransformTrs, isNotNull);
      node.mutateLocalTransform((m) => m.setTranslationRaw(1.0, 0.0, 0.0));

      expect(node.localTransformTrs, isNull);
    });
  });

  group('position, rotation, and scale', () {
    test('a fresh node reads identity components', () {
      final node = Node();
      _expectVector3Near(node.position, Vector3.zero());
      _expectQuaternionNear(node.rotation, Quaternion.identity());
      _expectVector3Near(node.scale, Vector3.all(1.0));
    });

    test('components read back from a matrix transform', () {
      final translation = Vector3(1.0, 2.0, 3.0);
      final rotation = Quaternion.axisAngle(Vector3(0.0, 1.0, 0.0), 0.7);
      final scale = Vector3(2.0, 3.0, 4.0);
      final node = Node(
        localTransform: Matrix4.compose(translation, rotation, scale),
      );

      _expectVector3Near(node.position, translation);
      _expectQuaternionNear(node.rotation, rotation);
      _expectVector3Near(node.scale, scale);
    });

    test('setting position leaves rotation and scale alone', () {
      final rotation = Quaternion.axisAngle(Vector3(1.0, 0.0, 0.0), 0.4);
      final scale = Vector3(2.0, 3.0, 4.0);
      final node = Node(
        localTransform: Matrix4.compose(
          Vector3(1.0, 2.0, 3.0),
          rotation,
          scale,
        ),
      );

      node.position = Vector3(-5.0, 0.5, 8.0);

      _expectVector3Near(node.position, Vector3(-5.0, 0.5, 8.0));
      _expectQuaternionNear(node.rotation, rotation);
      _expectVector3Near(node.scale, scale);
      _expectVector3Near(
        node.localTransform.getTranslation(),
        Vector3(-5.0, 0.5, 8.0),
      );
    });

    test('setting rotation leaves position and scale alone', () {
      final node = Node(
        localTransform: Matrix4.compose(
          Vector3(1.0, 2.0, 3.0),
          Quaternion.axisAngle(Vector3(0.0, 1.0, 0.0), 0.7),
          Vector3(2.0, 3.0, 4.0),
        ),
      );

      final rotation = Quaternion.axisAngle(Vector3(0.0, 0.0, 1.0), 1.1);
      node.rotation = rotation;

      _expectQuaternionNear(node.rotation, rotation);
      _expectVector3Near(node.position, Vector3(1.0, 2.0, 3.0));
      _expectVector3Near(node.scale, Vector3(2.0, 3.0, 4.0));
      _expectMatrixNear(
        node.localTransform,
        Matrix4.compose(
          Vector3(1.0, 2.0, 3.0),
          rotation,
          Vector3(2.0, 3.0, 4.0),
        ),
      );
    });

    test('setting scale leaves position and rotation alone', () {
      final rotation = Quaternion.axisAngle(Vector3(0.0, 1.0, 0.0), 0.7);
      final node = Node(
        localTransform: Matrix4.compose(
          Vector3(1.0, 2.0, 3.0),
          rotation,
          Vector3(2.0, 3.0, 4.0),
        ),
      );

      node.scale = Vector3(0.5, 0.25, 8.0);

      _expectVector3Near(node.scale, Vector3(0.5, 0.25, 8.0));
      _expectVector3Near(node.position, Vector3(1.0, 2.0, 3.0));
      _expectQuaternionNear(node.rotation, rotation);
    });

    test('a component assignment refreshes the world transform', () {
      final parent = Node();
      final child = Node();
      parent.add(child);
      // Fill both caches first, so a missed invalidation would show.
      expect(child.globalTransform, Matrix4.identity());

      parent.position = Vector3(0.0, 5.0, 0.0);
      child.position = Vector3(1.0, 0.0, 0.0);

      _expectVector3Near(
        child.globalTransform.getTranslation(),
        Vector3(1.0, 5.0, 0.0),
      );
      _expectVector3Near(child.position, Vector3(1.0, 0.0, 0.0));
    });

    test('a parent scale magnifies a child position', () {
      final parent = Node()..scale = Vector3.all(2.0);
      final child = Node()..position = Vector3(1.0, 2.0, 3.0);
      parent.add(child);

      _expectVector3Near(
        child.globalTransform.getTranslation(),
        Vector3(2.0, 4.0, 6.0),
      );
    });

    test('compound assignment moves the node', () {
      final node = Node()..position = Vector3(1.0, 1.0, 1.0);
      node.position += Vector3(0.0, 2.0, 0.0);

      _expectVector3Near(node.position, Vector3(1.0, 3.0, 1.0));
    });

    test('a mirrored scale set here reads back on the axis it was set', () {
      final node = Node()..scale = Vector3(1.0, -1.0, 1.0);

      _expectVector3Near(node.scale, Vector3(1.0, -1.0, 1.0));
      expect(node.localTransform.determinant(), lessThan(0.0));
      expect(node.windingFlipped, isTrue);
    });

    test('a mirror decomposed from a matrix reports on X', () {
      // Documented decompose behavior: the negative sign lands on X no
      // matter which axis the matrix mirrored.
      final node = Node(
        localTransform: Matrix4.diagonal3Values(1.0, -1.0, 1.0),
      );

      _expectVector3Near(node.scale, Vector3(-1.0, 1.0, 1.0));
      // The transform itself is unchanged by reading it.
      expect(node.localTransform.determinant(), lessThan(0.0));
    });

    test('an authored mirror survives a position or rotation change', () {
      final node = Node();
      node.setLocalTransformTrs(
        DecomposedTransform(
          translation: Vector3.zero(),
          rotation: Quaternion.identity(),
          scale: Vector3(1.0, -1.0, 1.0),
        ),
      );

      _expectVector3Near(node.scale, Vector3(1.0, -1.0, 1.0));

      node.position = Vector3(4.0, 0.0, 0.0);
      _expectVector3Near(node.scale, Vector3(1.0, -1.0, 1.0));
      _expectVector3Near(
        node.localTransformTrs!.scale,
        Vector3(1.0, -1.0, 1.0),
      );

      node.rotation = Quaternion.axisAngle(Vector3(0.0, 1.0, 0.0), 0.5);
      _expectVector3Near(node.scale, Vector3(1.0, -1.0, 1.0));
      _expectVector3Near(node.position, Vector3(4.0, 0.0, 0.0));
    });

    test('a position change reaches the pose animation anchors to', () {
      final node = Node();
      final rotation = Quaternion.axisAngle(Vector3(0.0, 1.0, 0.0), 0.3);
      node.setLocalTransformTrs(
        DecomposedTransform(
          translation: Vector3(1.0, 0.0, 0.0),
          rotation: rotation,
          scale: Vector3(2.0, 2.0, 2.0),
        ),
      );

      node.position = Vector3(0.0, 7.0, 0.0);

      final trs = node.localTransformTrs!;
      _expectVector3Near(trs.translation, Vector3(0.0, 7.0, 0.0));
      _expectQuaternionNear(trs.rotation, rotation);
      _expectVector3Near(trs.scale, Vector3(2.0, 2.0, 2.0));
    });

    test('assigning localTransform replaces what the components report', () {
      final node = Node()..scale = Vector3(1.0, -1.0, 1.0);
      expect(node.localTransformTrs, isNotNull);

      node.localTransform = Matrix4.translation(Vector3(0.0, 0.0, 9.0));

      expect(node.localTransformTrs, isNull);
      _expectVector3Near(node.position, Vector3(0.0, 0.0, 9.0));
      _expectVector3Near(node.scale, Vector3.all(1.0));
    });
  });

  group('in-place component edits', () {
    test('editing the returned position throws at the next read', () {
      final node = Node();
      node.position.x = 5.0;

      expect(() => node.globalTransform, throwsStateError);
    });

    test('editing the returned rotation or scale throws too', () {
      final rotated = Node();
      rotated.rotation.x = 0.5;
      expect(() => rotated.position, throwsStateError);

      final scaled = Node();
      scaled.scale.setValues(2.0, 2.0, 2.0);
      expect(() => scaled.globalTransform, throwsStateError);
    });

    test('read, edit, and assign back is accepted', () {
      final node = Node();
      final position = node.position;
      position.x = 5.0;
      node.position = position;

      _expectVector3Near(node.position, Vector3(5.0, 0.0, 0.0));
      expect(() => node.globalTransform, returnsNormally);
    });

    test('editing a clone of the returned value is accepted', () {
      final node = Node();
      final scratch = node.position.clone()..x = 5.0;

      expect(scratch.x, 5.0);
      expect(() => node.globalTransform, returnsNormally);
    });

    test('an untouched copy is not reported', () {
      final node = Node()..position = Vector3(1.0, 2.0, 3.0);
      final position = node.position;

      expect(() => node.globalTransform, returnsNormally);
      _expectVector3Near(position, Vector3(1.0, 2.0, 3.0));
    });
  });
}

void _expectMatrixNear(Matrix4 actual, Matrix4 expected) {
  for (var i = 0; i < 16; i++) {
    expect(actual.storage[i], closeTo(expected.storage[i], 1e-5));
  }
}

void _expectVector3Near(Vector3 actual, Vector3 expected) {
  for (var i = 0; i < 3; i++) {
    expect(actual.storage[i], closeTo(expected.storage[i], 1e-5));
  }
}

void _expectQuaternionNear(Quaternion actual, Quaternion expected) {
  // A quaternion and its negation are the same rotation.
  final sign = actual.storage[3] * expected.storage[3] < 0 ? -1.0 : 1.0;
  for (var i = 0; i < 4; i++) {
    expect(actual.storage[i] * sign, closeTo(expected.storage[i], 1e-5));
  }
}
