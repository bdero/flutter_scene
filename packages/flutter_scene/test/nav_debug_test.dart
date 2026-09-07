// Covers the drawable form of a baked nav mesh. Pure geometry: the node
// builders upload to the GPU and are exercised by the editor, but everything
// that decides what is drawn is here.

import 'dart:typed_data';

import 'package:flutter_scene/navigation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const _config = NavMeshConfig(
  cellSize: 0.3,
  cellHeight: 0.2,
  agentRadius: 0.4,
  agentHeight: 1.8,
);

/// A flat floor spanning [size] x [size] at height [y], centred on the
/// origin, painted [area].
NavGeometry floor(double size, {double y = 0, int area = NavArea.walkable}) {
  final half = size / 2;
  final builder = NavGeometryBuilder();
  builder.addMesh(
    positions: [
      -half, y, -half, //
      half, y, -half, //
      half, y, half, //
      -half, y, half,
    ],
    triangleIndices: [0, 2, 1, 0, 3, 2],
    area: area,
  );
  return builder.build();
}

void main() {
  test('every polygon fans into triangles and closes into an outline', () {
    final mesh = buildNavMesh(floor(20), _config)!;
    final debug = buildNavDebugGeometry(mesh);

    var expectedTriangles = 0;
    var expectedEdges = 0;
    for (var poly = 0; poly < mesh.polygonCount; poly++) {
      final corners = mesh.vertexCountOf(poly);
      expectedTriangles += corners - 2;
      expectedEdges += corners;
    }

    expect(expectedTriangles, greaterThan(0));
    expect(debug.triangleCount, expectedTriangles);
    expect(debug.positions.length, expectedTriangles * 9);
    expect(debug.colors.length, expectedTriangles * 12);
    expect(debug.outline.length ~/ 6, expectedEdges);
  });

  test('the draw is lifted off the floor it traces', () {
    final mesh = buildNavMesh(floor(20), _config)!;
    final flat = buildNavDebugGeometry(mesh, lift: 0);
    final lifted = buildNavDebugGeometry(mesh, lift: 0.25);

    for (var i = 1; i < flat.positions.length; i += 3) {
      expect(lifted.positions[i], closeTo(flat.positions[i] + 0.25, 1e-6));
    }
    for (var i = 1; i < flat.outline.length; i += 3) {
      expect(lifted.outline[i], closeTo(flat.outline[i] + 0.25, 1e-6));
    }
  });

  test('the colour says what the area is', () {
    const palette = NavDebugPalette();
    final walkable = buildNavDebugGeometry(
      buildNavMesh(floor(20), _config)!,
      palette: palette,
    );
    final water = buildNavDebugGeometry(
      buildNavMesh(floor(20, area: NavArea.slow), _config)!,
      palette: palette,
    );

    expect(walkable.colors[0], closeTo(palette.walkable.r, 1e-6));
    expect(walkable.colors[1], closeTo(palette.walkable.g, 1e-6));
    expect(water.colors[0], closeTo(palette.slow.r, 1e-6));
    expect(water.colors[1], closeTo(palette.slow.g, 1e-6));
    expect(
      water.colors[0],
      isNot(closeTo(walkable.colors[0], 1e-3)),
      reason: 'water and ground have to be told apart at a glance',
    );
  });

  test('the fill is translucent, or it hides what it describes', () {
    final debug = buildNavDebugGeometry(buildNavMesh(floor(20), _config)!);
    for (var i = 3; i < debug.colors.length; i += 4) {
      expect(debug.colors[i], lessThan(1.0));
      expect(debug.colors[i], greaterThan(0.0));
    }
  });

  test('a tint multiplies the palette rather than replacing it', () {
    final mesh = buildNavMesh(floor(20), _config)!;
    final plain = buildNavDebugGeometry(mesh);
    final tinted = buildNavDebugGeometry(mesh, tint: Vector4(0.5, 1, 1, 1));
    expect(tinted.colors[0], closeTo(plain.colors[0] * 0.5, 1e-6));
    expect(tinted.colors[1], closeTo(plain.colors[1], 1e-6));
  });

  test('the bounds cover every position, so the draw is not culled early', () {
    final debug = buildNavDebugGeometry(
      buildNavMesh(floor(20, y: 3), _config)!,
      lift: 0.1,
    );
    for (var i = 0; i < debug.positions.length; i += 3) {
      final point = Vector3(
        debug.positions[i],
        debug.positions[i + 1],
        debug.positions[i + 2],
      );
      // Inclusive: the extreme vertices are exactly on the box, which is
      // what makes it a tight fit rather than a loose one.
      expect(debug.bounds.intersectsWithVector3(point), isTrue);
    }
    expect(debug.bounds.min.y, closeTo(3.1, 0.2));
  });

  test('a mesh with nothing in it draws nothing rather than throwing', () {
    final empty = NavMesh(
      vertices: Float32List(0),
      polygonVertices: Uint16List(0),
      polygonStart: Uint32List(1),
      polygonCount: 0,
      neighbours: Int32List(0),
      areas: Uint8List(0),
      regions: Uint16List(0),
      config: _config,
    );
    final debug = buildNavDebugGeometry(empty);
    expect(debug.isEmpty, isTrue);
    expect(debug.triangleCount, 0);
    expect(debug.outline, isEmpty);
  });
}
