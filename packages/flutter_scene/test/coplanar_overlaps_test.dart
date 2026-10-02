// CPU tests for the coplanar overlap lint. Stub geometry reports box
// triangles as its retained CPU data, so no GPU is needed.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene/src/coplanar_overlaps.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/render/render_scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

// An axis-aligned box of [size] centered on the origin, as triangles with
// outward (counterclockwise) winding.
Float32List _boxTriangles(Vector3 size) {
  final h = size / 2;
  final corners = [
    for (final z in [-h.z, h.z])
      for (final y in [-h.y, h.y])
        for (final x in [-h.x, h.x]) Vector3(x, y, z),
  ];
  // Faces as quads of corner indices, counterclockwise seen from outside.
  const faces = [
    [0, 2, 3, 1], // -z
    [4, 5, 7, 6], // +z
    [0, 4, 6, 2], // -x
    [1, 3, 7, 5], // +x
    [0, 1, 5, 4], // -y
    [2, 6, 7, 3], // +y
  ];
  final out = <double>[];
  for (final f in faces) {
    for (final tri in [
      [f[0], f[1], f[2]],
      [f[0], f[2], f[3]],
    ]) {
      for (final i in tri) {
        out.addAll([corners[i].x, corners[i].y, corners[i].z]);
      }
    }
  }
  return Float32List.fromList(out);
}

// A unit sphere of [rings] by [segments] quads, as triangles.
Float32List _sphereTriangles({required int rings, required int segments}) {
  Vector3 at(int ring, int segment) {
    final theta = ring / rings * 3.141592653589793;
    final phi = segment / segments * 2 * 3.141592653589793;
    return Vector3(
      math.sin(theta) * math.cos(phi),
      math.cos(theta),
      math.sin(theta) * math.sin(phi),
    );
  }

  final out = <double>[];
  for (var r = 0; r < rings; r++) {
    for (var s = 0; s < segments; s++) {
      final a = at(r, s), b = at(r + 1, s);
      final c = at(r + 1, s + 1), d = at(r, s + 1);
      for (final p in [a, b, c, a, c, d]) {
        out.addAll([p.x, p.y, p.z]);
      }
    }
  }
  return Float32List.fromList(out);
}

class _BoxGeometry extends _MeshGeometry {
  _BoxGeometry(this.size) : super(_boxTriangles(size));

  final Vector3 size;

  @override
  Aabb3? get localBounds => Aabb3.minMax(-size / 2, size / 2);
}

// Retained CPU triangles, unindexed.
class _MeshGeometry extends Geometry {
  _MeshGeometry(this._positions);

  final Float32List _positions;

  @override
  ({
    ByteData? vertices,
    Float32List? positions,
    Float32List? texCoords,
    ByteData? indices,
    gpu.IndexType indexType,
    int vertexCount,
    int indexCount,
  })
  get cpuMeshData => (
    vertices: null,
    positions: _positions,
    texCoords: null,
    indices: null,
    indexType: gpu.IndexType.int16,
    vertexCount: _positions.length ~/ 3,
    indexCount: 0,
  );

  @override
  Aabb3? get localBounds => Aabb3.minMax(Vector3.all(-1), Vector3.all(1));

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

RenderItem _instanced(
  Geometry geometry,
  Material material,
  List<Vector3> positions,
) => RenderItem(geometry: geometry, material: material)
  ..visible = true
  ..instanceTransforms = [for (final p in positions) Matrix4.translation(p)];

RenderItem _single(Geometry geometry, Material material, Vector3 position) =>
    RenderItem(geometry: geometry, material: material)
      ..visible = true
      ..worldTransform.setFrom(Matrix4.translation(position));

void main() {
  test('finds barriers longer than their spacing, with the fix', () {
    final piece = _BoxGeometry(Vector3(0.5, 0.9, 8.4));
    final red = _StubMaterial();
    final white = _StubMaterial();
    // Alternating colors every 8 m, so each joint is red against white.
    final overlaps = findCoplanarOverlaps([
      _instanced(piece, red, [Vector3(0, 0.45, 0), Vector3(0, 0.45, 16)]),
      _instanced(piece, white, [Vector3(0, 0.45, 8)]),
    ]);
    expect(overlaps, isNotEmpty);
    // The side and top faces overlap 0.4 m at each of the two joints.
    expect(overlaps.every((o) => o.exact), isTrue);
    expect(
      overlaps.map((o) => o.center.z.round()).toSet(),
      containsAll([4, 12]),
    );
    final side = overlaps.firstWhere((o) => o.normal.x.abs() > 0.9);
    expect(side.area, closeTo(0.4 * 0.9, 1e-3));
    // Two different materials share no geometry identity, so the spacing
    // hint comes only from same-mesh neighbors.
    final hinted = findCoplanarOverlaps([
      _instanced(piece, red, [Vector3(0, 0.45, 0), Vector3(0, 0.45, 8)])
        ..instanceColors = [Vector4(1, 0, 0, 1), Vector4(1, 1, 1, 1)],
    ]);
    expect(hinted.first.hint, contains('8.40 m long'));
    expect(hinted.first.hint, contains('make them 8.00 m long'));
  });

  test('abutting pieces do not overlap', () {
    final piece = _BoxGeometry(Vector3(0.5, 0.9, 8.0));
    expect(
      findCoplanarOverlaps([
        _instanced(piece, _StubMaterial(), [Vector3(0, 0.45, 0)]),
        _instanced(piece, _StubMaterial(), [Vector3(0, 0.45, 8)]),
      ]),
      isEmpty,
    );
  });

  test('surfaces sharing a material still overlap', () {
    // Vertex colors, texture coordinates, or normals can still tell their
    // pixels apart, so one material does not make an overlap invisible.
    final piece = _BoxGeometry(Vector3(0.5, 0.9, 8.4));
    final material = _StubMaterial();
    expect(
      findCoplanarOverlaps([
        _instanced(piece, material, [Vector3(0, 0.45, 0), Vector3(0, 0.45, 8)]),
      ]),
      isNotEmpty,
    );
  });

  test('a sliced scan finds what a whole one does', () {
    final piece = _BoxGeometry(Vector3(0.5, 0.9, 8.4));
    final items = [
      _instanced(piece, _StubMaterial(), [
        for (var i = 0; i < 40; i++) Vector3(0, 0.45, i * 8.0),
      ]),
    ];
    final whole = findCoplanarOverlaps(items);
    final scan = CoplanarOverlapScan(items);
    var slices = 0;
    while (!scan.advance(Duration.zero)) {
      slices++;
    }
    expect(slices, greaterThan(1));
    expect(scan.result!.length, whole.length);
    expect(
      scan.result!.map((o) => o.area).toList(),
      whole.map((o) => o.area).toList(),
    );
  });

  test('a dense curved mesh groups its planes in linear time', () {
    // A sphere, nearly every triangle its own plane. Searching every plane
    // per triangle took over 100 million comparisons at this size.
    final sphere = _MeshGeometry(_sphereTriangles(rings: 64, segments: 128));
    debugCoplanarPlaneComparisons = 0;
    final overlaps = findCoplanarOverlaps([
      _single(sphere, _StubMaterial(), Vector3.zero()),
    ]);
    expect(overlaps, isEmpty);
    expect(debugCoplanarPlaneComparisons, lessThan(16 * 16128));
  });

  test('a layer resolves an overlay flush with its surface', () {
    final wall = _BoxGeometry(Vector3(10, 5, 0.3));
    final screen = _BoxGeometry(Vector3(8, 3, 0.3));
    final overlay = _StubMaterial();
    final items = [
      _single(wall, _StubMaterial(), Vector3(0, 0, 0)),
      _single(screen, overlay, Vector3(0, 0, 0)),
    ];
    expect(findCoplanarOverlaps(items), isNotEmpty);
    overlay.depthLayer = 1;
    expect(findCoplanarOverlaps(items), isEmpty);
  });

  test('near-coplanar faces count only past the precision at distance', () {
    final wall = _BoxGeometry(Vector3(10, 5, 0.3));
    final screen = _BoxGeometry(Vector3(8, 3, 0.3));
    final items = [
      _single(wall, _StubMaterial(), Vector3(0, 0, 200)),
      // 5 mm in front of the wall's -z face.
      _single(screen, _StubMaterial(), Vector3(0, 0, 200 - 0.005)),
    ];
    // No eye, no near check: only exact overlaps count.
    expect(findCoplanarOverlaps(items), isEmpty);
    // 24-bit depth with near 0.1, seen from the origin: 8 steps at 200 m is
    // about 19 cm, far more than 5 mm.
    final near = findCoplanarOverlaps(
      items,
      eye: Vector3.zero(),
      separationAt: (d) => 8 * d * d / (0.1 * 16777216),
    );
    expect(near, isNotEmpty);
    expect(near.first.exact, isFalse);
    expect(near.first.separation, closeTo(0.005, 1e-4));
  });

  test('summarizes overlaps by node pair for the log', () {
    final piece = _BoxGeometry(Vector3(0.5, 0.9, 8.4));
    final overlaps = findCoplanarOverlaps([
      _instanced(piece, _StubMaterial(), [Vector3(0, 0.45, 0)]),
      _instanced(piece, _StubMaterial(), [Vector3(0, 0.45, 8)]),
    ]);
    final text = describeCoplanarOverlaps(overlaps)!;
    expect(text, contains('flicker (z-fighting)'));
    expect(text, contains('Material.depthLayer'));
    expect(describeCoplanarOverlaps(const []), isNull);
  });

  test('clips convex polygons and measures them', () {
    final square = [0.0, 0.0, 2.0, 0.0, 2.0, 2.0, 0.0, 2.0];
    final shifted = [1.0, 1.0, 3.0, 1.0, 3.0, 3.0, 1.0, 3.0];
    final overlap = polygonAreaAndCentroid(clipConvexPolygons(square, shifted));
    expect(overlap.area, closeTo(1.0, 1e-9));
    expect(overlap.cx, closeTo(1.5, 1e-9));
    expect(overlap.cy, closeTo(1.5, 1e-9));
    // Clockwise clip input is reoriented.
    final clockwise = [1.0, 1.0, 1.0, 3.0, 3.0, 3.0, 3.0, 1.0];
    expect(
      polygonAreaAndCentroid(clipConvexPolygons(square, clockwise)).area,
      closeTo(1.0, 1e-9),
    );
  });
}
