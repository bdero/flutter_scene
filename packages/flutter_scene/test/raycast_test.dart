// Covers scene raycasting: hit math (distance, point, normal, barycentrics,
// interpolated UV), filtering (visibility, layers, raycastable, predicate,
// maxDistance), occlusion ordering, and transforms (including non-uniform
// scale and the importer's scene-root handedness flip). GPU-gated: geometry
// upload needs a device, so the whole suite skips without one (the hit math
// itself is deterministic CPU code).

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/widgets.dart' show Offset, Size;
import 'package:flutter_scene/scene.dart' hide Material;
// The packed-triangle intersector is test-only surface; reach it directly.
// ignore: implementation_imports
import 'package:flutter_scene/src/raycast.dart'
    show PackedTriangleHit, intersectPackedTriangles, intersectSoATriangles;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_scene/src/gpu/gpu.dart'
    as gpu
    show IndexType, RenderPass, Shader;
import 'package:vector_math/vector_math.dart';

/// A bare [Geometry] whose only purpose is to exercise the CPU-side raycast
/// data contract without a GPU upload.
class _RaycastDataGeometry extends Geometry {
  @override
  void bind(
    gpu.RenderPass pass,
    TransientWriter transientsBuffer,
    Matrix4 modelTransform,
    Matrix4 cameraTransform,
    Vector3 cameraPosition, {
    gpu.Shader? shaderOverride,
  }) {}
}

bool _gpuAvailable() {
  try {
    Scene();
    return true;
  } catch (_) {
    return false;
  }
}

/// A unit quad in the XY plane at z = 0, facing +Z, with v = 0 at the top
/// (the glTF convention): two triangles spanning (-0.5,-0.5)..(0.5,0.5).
MeshGeometry _quad() => MeshGeometry.fromArrays(
  positions: Float32List.fromList([
    -0.5,
    -0.5,
    0,
    0.5,
    -0.5,
    0,
    0.5,
    0.5,
    0,
    -0.5,
    0.5,
    0,
  ]),
  texCoords: Float32List.fromList([0, 1, 1, 1, 1, 0, 0, 0]),
  indices: [0, 1, 2, 0, 2, 3],
);

Node _quadNode({String name = 'quad', Matrix4? transform}) => Node(
  name: name,
  localTransform: transform,
  mesh: Mesh(_quad(), UnlitMaterial()),
);

Ray _rayTo(Vector3 origin, Vector3 target) =>
    Ray.originDirection(origin, target - origin);

/// Hand-packs vertices into the unskinned 48-byte engine layout:
/// position(3) normal(3) uv(2) color(4) floats per vertex.
ByteData _packUnskinned(List<double> positions, List<double> uvs) {
  final vertexCount = positions.length ~/ 3;
  final bytes = ByteData(vertexCount * 48);
  for (var v = 0; v < vertexCount; v++) {
    for (var c = 0; c < 3; c++) {
      bytes.setFloat32(v * 48 + c * 4, positions[v * 3 + c], Endian.little);
    }
    bytes.setFloat32(v * 48 + 24, uvs[v * 2], Endian.little);
    bytes.setFloat32(v * 48 + 28, uvs[v * 2 + 1], Endian.little);
  }
  return bytes;
}

ByteData _packIndices16(List<int> indices) {
  final bytes = ByteData(indices.length * 2);
  for (var i = 0; i < indices.length; i++) {
    bytes.setUint16(i * 2, indices[i], Endian.little);
  }
  return bytes;
}

void main() {
  group('packed triangle intersection (GPU-free)', () {
    final vertices = _packUnskinned(
      [-0.5, -0.5, 0, 0.5, -0.5, 0, 0.5, 0.5, 0, -0.5, 0.5, 0],
      [0, 1, 1, 1, 1, 0, 0, 0],
    );
    final indices = _packIndices16([0, 1, 2, 0, 2, 3]);

    List<PackedTriangleHit> cast(Ray ray, {double maxDistance = 1e9}) {
      final hits = <PackedTriangleHit>[];
      intersectPackedTriangles(
        vertices: vertices,
        stride: 48,
        indices: indices,
        indexType: gpu.IndexType.int16,
        indexCount: 6,
        vertexCount: 4,
        localRay: ray,
        maxDistance: maxDistance,
        emit: hits.add,
      );
      return hits;
    }

    test('center hit interpolates uv and reports t', () {
      // The quad center lies on the shared diagonal; both triangles may
      // report an edge-inclusive hit with identical attributes.
      final hits = cast(
        Ray.originDirection(Vector3(0, 0, 5), Vector3(0, 0, -1)),
      );
      expect(hits, isNotEmpty);
      expect(hits.first.t, closeTo(5.0, 1e-6));
      expect(hits.first.uv.x, closeTo(0.5, 1e-6));
      expect(hits.first.uv.y, closeTo(0.5, 1e-6));
    });

    test('off-center hit interpolates toward the corner uv', () {
      final hits = cast(
        Ray.originDirection(Vector3(0.4, -0.1, 5), Vector3(0, 0, -1)),
      );
      expect(hits, hasLength(1));
      expect(hits.first.uv.x, closeTo(0.9, 1e-5));
      expect(hits.first.uv.y, closeTo(0.6, 1e-5));
      final b = hits.first.barycentrics;
      expect(b.x + b.y + b.z, closeTo(1.0, 1e-6));
    });

    test('backface hits; parallel and out-of-range rays miss', () {
      expect(
        cast(Ray.originDirection(Vector3(0.3, -0.2, -5), Vector3(0, 0, 1))),
        hasLength(1),
      );
      expect(
        cast(Ray.originDirection(Vector3(0, 0, 5), Vector3(1, 0, 0))),
        isEmpty,
      );
      expect(
        cast(
          Ray.originDirection(Vector3(0, 0, 5), Vector3(0, 0, -1)),
          maxDistance: 4.0,
        ),
        isEmpty,
      );
    });

    test('triangleIndex distinguishes the two quad triangles', () {
      final lower = cast(
        Ray.originDirection(Vector3(0.3, -0.4, 5), Vector3(0, 0, -1)),
      );
      final upper = cast(
        Ray.originDirection(Vector3(-0.4, 0.3, 5), Vector3(0, 0, -1)),
      );
      expect(lower.single.triangleIndex, 0);
      expect(upper.single.triangleIndex, 1);
    });

    test('local normal is the geometric face normal', () {
      final hit = cast(
        Ray.originDirection(Vector3(0.3, -0.2, 5), Vector3(0, 0, -1)),
      ).single;
      expect(hit.localNormal.dot(Vector3(0, 0, 1)).abs(), closeTo(1.0, 1e-6));
    });
  });

  group('structure-of-arrays triangle intersection (GPU-free)', () {
    // The same quad as the interleaved test, but position and texcoord come
    // from separate tightly packed lists.
    final positions = Float32List.fromList([
      -0.5, -0.5, 0, //
      0.5, -0.5, 0, //
      0.5, 0.5, 0, //
      -0.5, 0.5, 0, //
    ]);
    final texCoords = Float32List.fromList([0, 1, 1, 1, 1, 0, 0, 0]);
    final indices = _packIndices16([0, 1, 2, 0, 2, 3]);

    List<PackedTriangleHit> cast(Ray ray) {
      final hits = <PackedTriangleHit>[];
      intersectSoATriangles(
        positions: positions,
        texCoords: texCoords,
        indices: indices,
        indexType: gpu.IndexType.int16,
        indexCount: 6,
        vertexCount: 4,
        localRay: ray,
        maxDistance: 1e9,
        emit: hits.add,
      );
      return hits;
    }

    test('matches the interleaved intersector on a center hit', () {
      final hits = cast(
        Ray.originDirection(Vector3(0, 0, 5), Vector3(0, 0, -1)),
      );
      expect(hits, isNotEmpty);
      expect(hits.first.t, closeTo(5.0, 1e-6));
      expect(hits.first.uv.x, closeTo(0.5, 1e-6));
      expect(hits.first.uv.y, closeTo(0.5, 1e-6));
    });

    test('interpolates uv toward a corner like the interleaved path', () {
      final hits = cast(
        Ray.originDirection(Vector3(0.4, -0.1, 5), Vector3(0, 0, -1)),
      );
      expect(hits, hasLength(1));
      expect(hits.first.uv.x, closeTo(0.9, 1e-5));
      expect(hits.first.uv.y, closeTo(0.6, 1e-5));
    });

    test('reports a zero uv when texcoords are absent', () {
      final hits = <PackedTriangleHit>[];
      intersectSoATriangles(
        positions: positions,
        texCoords: null,
        indices: indices,
        indexType: gpu.IndexType.int16,
        indexCount: 6,
        vertexCount: 4,
        localRay: Ray.originDirection(Vector3(0, 0, 5), Vector3(0, 0, -1)),
        maxDistance: 1e9,
        emit: hits.add,
      );
      expect(hits, isNotEmpty);
      expect(hits.first.uv, Vector2.zero());
    });
  });

  group('structure-of-arrays raycast data wiring (GPU-free)', () {
    test('setRaycastAttributes retains the index data', () {
      // Regression: the SoA upload path uploaded the index buffer to the GPU
      // but did not retain it for the CPU raycast, so an indexed mesh was
      // raycast as a non-indexed triangle list (picking missed the surface).
      final geometry = _RaycastDataGeometry();
      final indices = ByteData(6);
      geometry.setRaycastAttributes(
        positions: Float32List(9),
        texCoords: Float32List(6),
        indices: indices,
      );
      final data = geometry.cpuMeshData;
      expect(data.positions, isNotNull);
      expect(data.texCoords, isNotNull);
      expect(data.indices, same(indices));
      // SoA geometry does not expose the interleaved buffer.
      expect(data.vertices, isNull);
    });
  });

  group('Camera.screenPointToRay (GPU-free)', () {
    test('center of the view unprojects along the camera forward', () {
      final camera = PerspectiveCamera(
        position: Vector3(1, 2, 3),
        target: Vector3(1, 2, -7),
      );
      final ray = camera.screenPointToRay(
        const Offset(200, 150),
        const Size(400, 300),
      );
      final direction = ray.direction.normalized();
      expect(direction.dot(Vector3(0, 0, -1)), closeTo(1.0, 1e-4));
      // The near point lies in front of the eye along the forward axis.
      expect((ray.origin - camera.position).dot(direction), greaterThan(0));
    });

    test('round-trips a projected world point', () {
      final camera = PerspectiveCamera(
        position: Vector3(0, 0, 5),
        target: Vector3.zero(),
      );
      const viewSize = Size(400, 300);
      final world = Vector3(-1.0, 0.5, 0.0);

      // Project the point to screen space the way the renderer does.
      final clip =
          camera.getViewTransform(viewSize) *
                  Vector4(world.x, world.y, world.z, 1)
              as Vector4;
      final screen = Offset(
        (clip.x / clip.w + 1) / 2 * viewSize.width,
        (1 - clip.y / clip.w) / 2 * viewSize.height,
      );

      // The unprojected ray must pass through the original point.
      final ray = camera.screenPointToRay(screen, viewSize);
      final direction = ray.direction.normalized();
      final toPoint = world - ray.origin;
      final along = toPoint.dot(direction);
      final offAxis = (toPoint - direction * along).length;
      expect(along, greaterThan(0));
      expect(offAxis, lessThan(1e-3));
    });
  });

  if (!_gpuAvailable()) {
    test('scene raycast integration requires a GPU context', () {
      markTestSkipped('No Impeller GPU context');
    });
    return;
  }

  group('hit math', () {
    test('center hit reports distance, point, normal, and uv', () {
      final root = Node()..add(_quadNode());
      final hit = raycastNode(
        root,
        Ray.originDirection(Vector3(0, 0, 5), Vector3(0, 0, -1)),
      );
      expect(hit, isNotNull);
      expect(hit!.distance, closeTo(5.0, 1e-5));
      expect(hit.worldPoint.z, closeTo(0.0, 1e-5));
      expect(hit.worldNormal.dot(Vector3(0, 0, 1)), closeTo(1.0, 1e-5));
      expect(hit.uv!.x, closeTo(0.5, 1e-5));
      expect(hit.uv!.y, closeTo(0.5, 1e-5));
    });

    test('uv interpolates across the surface (gltf v=0 at top)', () {
      final root = Node()..add(_quadNode());
      // Near the top-right corner of the quad.
      final hit = raycastNode(
        root,
        _rayTo(Vector3(0.4, 0.4, 5), Vector3(0.4, 0.4, 0)),
      );
      expect(hit!.uv!.x, closeTo(0.9, 1e-5));
      expect(hit.uv!.y, closeTo(0.1, 1e-5)); // near top => v near 0
    });

    test('barycentrics sum to one and match the triangle', () {
      final root = Node()..add(_quadNode());
      final hit = raycastNode(
        root,
        _rayTo(Vector3(0.1, -0.2, 5), Vector3(0.1, -0.2, 0)),
      )!;
      final b = hit.barycentrics;
      expect(b.x + b.y + b.z, closeTo(1.0, 1e-5));
      expect(b.x, greaterThanOrEqualTo(0));
      expect(b.y, greaterThanOrEqualTo(0));
      expect(b.z, greaterThanOrEqualTo(0));
    });

    test('backfaces hit, with the normal facing the ray origin', () {
      final root = Node()..add(_quadNode());
      final hit = raycastNode(
        root,
        Ray.originDirection(Vector3(0, 0, -5), Vector3(0, 0, 1)),
      );
      expect(hit, isNotNull);
      expect(hit!.worldNormal.dot(Vector3(0, 0, -1)), closeTo(1.0, 1e-5));
    });

    test('misses outside the quad and beyond maxDistance', () {
      final root = Node()..add(_quadNode());
      expect(
        raycastNode(
          root,
          Ray.originDirection(Vector3(2, 2, 5), Vector3(0, 0, -1)),
        ),
        isNull,
      );
      expect(
        raycastNode(
          root,
          Ray.originDirection(Vector3(0, 0, 5), Vector3(0, 0, -1)),
          maxDistance: 4.0,
        ),
        isNull,
      );
    });
  });

  group('transforms', () {
    test('rotated and translated nodes hit with world-space results', () {
      // Quad rotated 90 degrees about Y (now in the YZ plane) at x = 2.
      final transform =
          Matrix4.translation(Vector3(2, 0, 0)) *
          Matrix4.rotationY(math.pi / 2);
      final root = Node()..add(_quadNode(transform: transform as Matrix4));
      final hit = raycastNode(
        root,
        Ray.originDirection(Vector3(5, 0, 0), Vector3(-1, 0, 0)),
      );
      expect(hit, isNotNull);
      expect(hit!.distance, closeTo(3.0, 1e-5));
      expect(hit.worldPoint.x, closeTo(2.0, 1e-4));
    });

    test('non-uniform scale keeps distances in world units', () {
      final root = Node()
        ..add(_quadNode(transform: Matrix4.diagonal3(Vector3(3.0, 0.5, 1.0))));
      // The quad now spans x in [-1.5, 1.5], y in [-0.25, 0.25].
      final hit = raycastNode(
        root,
        Ray.originDirection(Vector3(1.2, 0.2, 5), Vector3(0, 0, -1)),
      );
      expect(hit, isNotNull);
      expect(hit!.distance, closeTo(5.0, 1e-4));
      expect(hit.uv!.x, closeTo(1.2 / 3.0 + 0.5, 1e-4));
    });

    test('a mirroring root transform (handedness flip) still hits', () {
      final root = Node(localTransform: Matrix4.diagonal3(Vector3(1, 1, -1)))
        ..add(_quadNode());
      final hit = raycastNode(
        root,
        Ray.originDirection(Vector3(0, 0, 5), Vector3(0, 0, -1)),
      );
      expect(hit, isNotNull);
      expect(hit!.distance, closeTo(5.0, 1e-5));
    });
  });

  group('filtering and occlusion', () {
    test('nearest hit wins; raycastAll sorts by distance', () {
      final root = Node()
        ..add(
          _quadNode(
            name: 'far',
            transform: Matrix4.translation(Vector3(0, 0, -2)),
          ),
        )
        ..add(
          _quadNode(
            name: 'near',
            transform: Matrix4.translation(Vector3(0, 0, 2)),
          ),
        );
      final ray = Ray.originDirection(Vector3(0, 0, 5), Vector3(0, 0, -1));
      expect(raycastNode(root, ray)!.node.name, 'near');
      final all = raycastNodeAll(root, ray);
      expect(all.map((h) => h.node.name).toList(), ['near', 'far']);
    });

    test('invisible nodes are skipped by default, included on request', () {
      final blocker = _quadNode(
        name: 'blocker',
        transform: Matrix4.translation(Vector3(0, 0, 2)),
      )..visible = false;
      final root = Node()
        ..add(blocker)
        ..add(_quadNode(name: 'panel'));
      final ray = Ray.originDirection(Vector3(0, 0, 5), Vector3(0, 0, -1));
      expect(raycastNode(root, ray)!.node.name, 'panel');
      expect(
        raycastNode(root, ray, includeInvisible: true)!.node.name,
        'blocker',
      );
    });

    test('raycastable=false makes a node ray-transparent', () {
      final glass = _quadNode(
        name: 'glass',
        transform: Matrix4.translation(Vector3(0, 0, 2)),
      )..raycastable = false;
      final root = Node()
        ..add(glass)
        ..add(_quadNode(name: 'panel'));
      final hit = raycastNode(
        root,
        Ray.originDirection(Vector3(0, 0, 5), Vector3(0, 0, -1)),
      );
      expect(hit!.node.name, 'panel');
    });

    test('layerMask and where filter candidates', () {
      final ui = _quadNode(name: 'ui')..layers = 1 << 2;
      final world = _quadNode(
        name: 'world',
        transform: Matrix4.translation(Vector3(0, 0, 1)),
      );
      final root = Node()
        ..add(ui)
        ..add(world);
      final ray = Ray.originDirection(Vector3(0, 0, 5), Vector3(0, 0, -1));
      expect(raycastNode(root, ray, layerMask: 1 << 2)!.node.name, 'ui');
      expect(
        raycastNode(root, ray, where: (n) => n.name != 'world')!.node.name,
        'ui',
      );
    });
  });
}
