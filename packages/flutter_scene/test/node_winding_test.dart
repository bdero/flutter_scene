import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';
import 'package:test/test.dart';

// Regression coverage for issue #134: a node whose accumulated transform has
// negative determinant (a mirror / negative scale) reverses triangle winding,
// and the renderer must flip cull winding for it (Node.windingFlipped).

Node _node(Matrix4 transform) => Node(localTransform: transform);

// `Matrix4.diagonal3Values(x, y, z)` is a pure scale (determinant x*y*z).
Matrix4 _scale(double x, double y, double z) =>
    Matrix4.diagonal3Values(x, y, z);

void main() {
  test('identity transform does not flip winding', () {
    expect(_node(Matrix4.identity()).windingFlipped, isFalse);
  });

  test('a single negative-axis scale flips winding (any axis)', () {
    expect(_node(_scale(-1, 1, 1)).windingFlipped, isTrue); // X
    expect(_node(_scale(1, -1, 1)).windingFlipped, isTrue); // Y
    expect(_node(_scale(1, 1, -1)).windingFlipped, isTrue); // Z
  });

  test('two negative scales cancel', () {
    expect(_node(_scale(-1, -1, 1)).windingFlipped, isFalse);
  });

  test('parity accumulates down the hierarchy', () {
    final parent = _node(_scale(-1, 1, 1));
    final normalChild = _node(Matrix4.identity());
    final mirroredChild = _node(_scale(-1, 1, 1));
    parent.add(normalChild);
    parent.add(mirroredChild);

    expect(parent.windingFlipped, isTrue);
    expect(normalChild.windingFlipped, isTrue); // inherits parent's flip
    expect(mirroredChild.windingFlipped, isFalse); // own flip cancels parent's
  });

  test('winding parity updates when a transform changes', () {
    final node = _node(Matrix4.identity());
    expect(node.windingFlipped, isFalse);
    node.localTransform = _scale(-1, 1, 1);
    expect(node.windingFlipped, isTrue);
  });
}
