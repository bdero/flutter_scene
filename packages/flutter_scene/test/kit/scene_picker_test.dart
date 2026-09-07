// Covers ScenePicker: a hit on any part of an object resolves to the object,
// and a marquee catches the objects whose centres fall inside it.

import 'dart:ui' show Rect, Size;

import 'package:flutter_scene/kit.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

// Stub geometry and material carrying bounds but no drawable data, so the
// tests run without a Flutter GPU context. Bounds are what the marquee reads.
class _StubGeometry extends Geometry {
  _StubGeometry(Aabb3 aabb) {
    setLocalBounds(
      aabb,
      Sphere.centerRadius(
        (aabb.min + aabb.max) * 0.5,
        ((aabb.max - aabb.min) * 0.5).length,
      ),
    );
  }

  @override
  void bind(
    gpu.RenderPass pass,
    TransientWriter transientsBuffer,
    Matrix4 modelTransform,
    Matrix4 cameraTransform,
    Vector3 cameraPosition, {
    gpu.Shader? shaderOverride,
    double depthBias = 0.0,
  }) => throw UnsupportedError('Stub geometry is not renderable');
}

class _StubMaterial extends Material {
  @override
  void bind(
    gpu.RenderPass pass,
    TransientWriter transientsBuffer,
    Lighting lighting,
  ) => throw UnsupportedError('Stub material is not renderable');
}

Node _boundedNode(String name, Vector3 position, {double radius = 0.5}) => Node(
  name: name,
  localTransform: Matrix4.translation(position),
  mesh: Mesh.primitives(
    primitives: [
      MeshPrimitive(
        _StubGeometry(
          Aabb3.minMax(
            Vector3(-radius, -radius, -radius),
            Vector3(radius, radius, radius),
          ),
        ),
        _StubMaterial(),
      ),
    ],
  ),
);

void main() {
  const viewSize = Size(400.0, 400.0);

  // Straight down over the origin: world X is screen X, world Z is screen -Y.
  OrthographicCamera overhead() => OrthographicCamera(
    position: Vector3(0.0, 40.0, 0.0),
    target: Vector3.zero(),
    up: Vector3(0.0, 0.0, 1.0),
    height: 40.0,
    near: 0.1,
    far: 200.0,
  );

  group('selectableOwnerOf', () {
    test('resolves a part to the object it belongs to', () {
      final root = Node(name: 'root');
      final unit = Node(name: 'unit');
      final body = Node(name: 'body');
      final hat = Node(name: 'hat');
      root.add(unit);
      unit.add(body);
      body.add(hat);

      final picker = ScenePicker(root);
      expect(picker.selectableOwnerOf(hat), same(unit));
      expect(picker.selectableOwnerOf(body), same(unit));
      expect(picker.selectableOwnerOf(unit), same(unit));
    });

    test('honours a custom notion of an object', () {
      final root = Node(name: 'root');
      final group = Node(name: 'group');
      final unit = Node(name: 'unit_a');
      final hat = Node(name: 'hat');
      root.add(group);
      group.add(unit);
      unit.add(hat);

      final picker = ScenePicker(
        root,
        isSelectable: (node) => node.name.startsWith('unit_'),
      );
      expect(picker.selectableOwnerOf(hat), same(unit));
      expect(picker.selectableOwnerOf(group), isNull);
    });

    test('returns null when nothing on the way up qualifies', () {
      final root = Node(name: 'root');
      final loose = Node(name: 'loose');
      root.add(loose);

      final picker = ScenePicker(root, isSelectable: (node) => false);
      expect(picker.selectableOwnerOf(loose), isNull);
    });
  });

  group('allSelectables', () {
    test('collects objects and does not descend into them', () {
      final root = Node(name: 'root');
      final a = Node(name: 'a');
      final b = Node(name: 'b');
      a.add(Node(name: 'a_part'));
      root.add(a);
      root.add(b);

      final picker = ScenePicker(root);
      expect(picker.allSelectables().map((n) => n.name), ['a', 'b']);
    });

    test('finds nested objects when the predicate says so', () {
      final root = Node(name: 'root');
      final group = Node(name: 'group');
      final unit = Node(name: 'unit_a');
      root.add(group);
      group.add(unit);

      final picker = ScenePicker(
        root,
        isSelectable: (node) => node.name.startsWith('unit_'),
      );
      expect(picker.allSelectables(), [unit]);
    });
  });

  group('selectablesInScreenRect', () {
    late Node root;
    late ScenePicker picker;

    setUp(() {
      root = Node(name: 'root');
      // Spread across the ground: 40 world units span 400 pixels, so one world
      // unit is 10 pixels and the origin is at (200, 200).
      root.add(_boundedNode('near', Vector3(0.0, 0.0, 0.0)));
      root.add(_boundedNode('right', Vector3(5.0, 0.0, 0.0)));
      root.add(_boundedNode('far', Vector3(0.0, 0.0, -15.0)));
      picker = ScenePicker(root);
    });

    test('catches the objects inside the box', () {
      final caught = picker.selectablesInScreenRect(
        const Rect.fromLTRB(180.0, 180.0, 280.0, 220.0),
        camera: overhead(),
        viewSize: viewSize,
      );
      expect(caught.map((n) => n.name), containsAll(['near', 'right']));
      expect(caught.map((n) => n.name), isNot(contains('far')));
    });

    test('catches nothing when the box is empty ground', () {
      final caught = picker.selectablesInScreenRect(
        const Rect.fromLTRB(0.0, 0.0, 20.0, 20.0),
        camera: overhead(),
        viewSize: viewSize,
      );
      expect(caught, isEmpty);
    });

    test('requireFullyInside excludes a partly-covered object', () {
      final camera = overhead();
      // A box that contains the origin but clips the edge of a 1-unit cube:
      // its centre is inside, its corners are not.
      const tight = Rect.fromLTRB(197.0, 197.0, 203.0, 203.0);

      expect(
        picker
            .selectablesInScreenRect(tight, camera: camera, viewSize: viewSize)
            .map((n) => n.name),
        contains('near'),
      );
      expect(
        picker.selectablesInScreenRect(
          tight,
          camera: camera,
          viewSize: viewSize,
          requireFullyInside: true,
        ),
        isEmpty,
      );
    });

    test('ignores objects with no geometry to bound', () {
      root.add(Node(name: 'empty'));
      final caught = picker.selectablesInScreenRect(
        const Rect.fromLTRB(0.0, 0.0, 400.0, 400.0),
        camera: overhead(),
        viewSize: viewSize,
      );
      expect(caught.map((n) => n.name), isNot(contains('empty')));
    });
  });
}
