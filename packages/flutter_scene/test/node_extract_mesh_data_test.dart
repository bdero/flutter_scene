// Covers Node.extractMeshData, which flattens a subtree's geometry into one
// snapshot with the transforms baked in. Uses stub geometry so the walk can
// be exercised without a Flutter GPU context.

import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// Geometry that skips shader-library and GPU access, retaining just enough
/// CPU data for [Geometry.extractMeshData] to read.
class _StubGeometry extends Geometry {
  _StubGeometry(Float32List positions, {Float32List? normals}) {
    setRaycastAttributes(positions: positions, normals: normals);
    setVertexStreams(const [], positions.length ~/ 3);
  }

  /// Geometry that retains nothing, standing in for a caller-managed buffer.
  _StubGeometry.unreadable();

  @override
  void bind(
    gpu.RenderPass pass,
    TransientWriter transientsBuffer,
    Matrix4 modelTransform,
    Matrix4 cameraTransform,
    Vector3 cameraPosition, {
    gpu.Shader? shaderOverride,
    double depthBias = 0.0,
  }) {
    throw UnsupportedError('Stub geometry is not renderable');
  }
}

class _StubMaterial extends Material {
  @override
  void bind(
    gpu.RenderPass pass,
    TransientWriter transientsBuffer,
    Lighting lighting,
  ) {
    throw UnsupportedError('Stub material is not renderable');
  }
}

/// A triangle in the XZ plane, offset along X by [x].
Mesh _triangle({double x = 0, Float32List? normals}) => Mesh(
  _StubGeometry(
    Float32List.fromList([
      x, 0, 0, //
      x + 1, 0, 0, //
      x, 0, 1,
    ]),
    normals: normals,
  ),
  _StubMaterial(),
);

void main() {
  test('bakes descendant transforms into the vertices', () {
    final root = Node(name: 'root');
    final child = Node(
      name: 'child',
      localTransform: Matrix4.translation(Vector3(0, 5, 0)),
      mesh: _triangle(),
    );
    root.add(child);

    final data = root.extractMeshData();
    expect(data.vertexCount, 3);
    expect(data.positions.sublist(0, 3), [0, 5, 0]);
    expect(data.positions.sublist(3, 6), [1, 5, 0]);
  });

  test('leaves the subtree root transform out by default', () {
    final root = Node(
      name: 'root',
      localTransform: Matrix4.translation(Vector3(100, 0, 0)),
      mesh: _triangle(),
    );

    expect(root.extractMeshData().positions.sublist(0, 3), [0, 0, 0]);
    expect(
      root
          .extractMeshData(transform: root.localTransform)
          .positions
          .sublist(0, 3),
      [100, 0, 0],
    );
  });

  test('the transform parameter reaches world space', () {
    final parent = Node(
      name: 'parent',
      localTransform: Matrix4.translation(Vector3(0, 0, 7)),
    );
    final child = Node(name: 'child', mesh: _triangle());
    parent.add(child);

    final data = child.extractMeshData(transform: child.globalTransform);
    expect(data.positions.sublist(0, 3), [0, 0, 7]);
  });

  test('merges several primitives and rebases their indices', () {
    final node = Node(name: 'multi')
      ..mesh = Mesh.primitives(
        primitives: [
          _triangle().primitives.first,
          _triangle(x: 10).primitives.first,
        ],
      );

    final data = node.extractMeshData();
    expect(data.vertexCount, 6);
    expect(data.triangleCount, 2);
    expect(data.positions.sublist(9, 12), [10, 0, 0]);
    // The second primitive's corners address its own vertices, not the
    // first primitive's.
    expect(data.toTriMeshShape().indices, [0, 1, 2, 3, 4, 5]);
  });

  test('drops an attribute that one primitive is missing', () {
    final normals = Float32List.fromList([0, 1, 0, 0, 1, 0, 0, 1, 0]);
    final root = Node(
      name: 'root',
      mesh: _triangle(normals: normals),
    );
    root.add(Node(name: 'bare', mesh: _triangle(x: 10)));

    final data = root.extractMeshData();
    expect(data.vertexCount, 6);
    expect(data.normals, isNull);

    // With every part carrying normals they survive.
    final allNormals =
        Node(
          name: 'root',
          mesh: _triangle(normals: normals),
        )..add(
          Node(
            name: 'also',
            mesh: _triangle(x: 10, normals: normals),
          ),
        );
    expect(allNormals.extractMeshData().normals, hasLength(18));
  });

  test('a subtree with no geometry throws', () {
    final root = Node(name: 'empty')..add(Node(name: 'also-empty'));
    expect(root.extractMeshData, throwsStateError);
  });

  test('unreadable geometry throws rather than going missing', () {
    final node = Node(
      name: 'managed',
      mesh: Mesh(_StubGeometry.unreadable(), _StubMaterial()),
    );
    expect(node.extractMeshData, throwsStateError);
  });

  test('non-triangle geometry throws', () {
    final mesh = _triangle();
    mesh.primitives.first.geometry.primitiveType = gpu.PrimitiveType.line;
    final node = Node(name: 'lines', mesh: mesh);
    expect(node.extractMeshData, throwsStateError);
  });

  test('instanced meshes throw', () {
    final node = Node(name: 'instanced')
      ..addComponent(
        InstancedMeshComponent(
          InstancedMesh(
            geometry: _StubGeometry(
              Float32List.fromList([0, 0, 0, 1, 0, 0, 0, 0, 1]),
            ),
            material: _StubMaterial(),
          ),
        ),
      );
    expect(node.extractMeshData, throwsStateError);
  });

  test('feeds a collision shape in the collider node frame', () {
    final root = Node(name: 'root');
    root.add(
      Node(
        name: 'hill',
        localTransform: Matrix4.translation(Vector3(0, 2, 0)),
        mesh: _triangle(),
      ),
    );

    final shape = root.extractMeshData().toTriMeshShape();
    expect(shape.indices, [0, 1, 2]);
    expect(shape.vertices.sublist(0, 3), [0, 2, 0]);
  });
}
