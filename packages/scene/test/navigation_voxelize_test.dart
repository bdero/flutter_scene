import 'dart:typed_data';

import 'package:scene/src/navigation/heightfield.dart';
import 'package:scene/src/navigation/nav_config.dart';
import 'package:scene/src/navigation/nav_geometry.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// A flat quad on the XZ plane at [y], from (0,0) to [size].
void addFloor(NavGeometryBuilder builder, double size, {double y = 0}) {
  builder.addMesh(
    positions: [0, y, 0, size, y, 0, size, y, size, 0, y, size],
    triangleIndices: const [0, 2, 1, 0, 3, 2],
  );
}

void main() {
  const config = NavMeshConfig(cellSize: 0.5, cellHeight: 0.2);

  test('a flat floor rasterizes to one walkable span per covered column', () {
    final builder = NavGeometryBuilder();
    addFloor(builder, 4);
    final field = rasterizeNavGeometry(builder.build(), config)!;

    // The grid is padded by the agent radius, so the floor sits inside it.
    var walkableColumns = 0;
    var spans = 0;
    for (var i = 0; i < field.columnCount; i++) {
      var span = field.columnAt(i);
      if (span != null) walkableColumns++;
      while (span != null) {
        spans++;
        expect(span.area, NavArea.walkable);
        expect(span.max, greaterThan(span.min));
        span = span.next;
      }
    }
    expect(walkableColumns, greaterThan(0));
    expect(
      spans,
      walkableColumns,
      reason: 'a single flat surface is one span per column, never several',
    );

    // 4x4 units at half-unit cells is 8x8 columns of floor.
    expect(walkableColumns, 64);
  });

  test('a steep triangle is not walkable', () {
    final builder = NavGeometryBuilder()
      ..addMesh(
        // A near-vertical wall: 4 units tall over 0.5 across.
        positions: [0, 0, 0, 0.5, 4, 0, 0.5, 4, 4],
        triangleIndices: const [0, 1, 2],
      );
    final field = rasterizeNavGeometry(builder.build(), config)!;

    var any = false;
    for (var i = 0; i < field.columnCount; i++) {
      var span = field.columnAt(i);
      while (span != null) {
        any = true;
        expect(span.area, NavArea.nonWalkable);
        span = span.next;
      }
    }
    expect(
      any,
      isTrue,
      reason: 'a wall is still rasterized, just not walkable',
    );
  });

  test('an overpass keeps both surfaces in one column', () {
    final builder = NavGeometryBuilder();
    addFloor(builder, 4);
    addFloor(builder, 4, y: 5);
    final field = rasterizeNavGeometry(builder.build(), config)!;

    var columnsWithTwo = 0;
    for (var i = 0; i < field.columnCount; i++) {
      var count = 0;
      var span = field.columnAt(i);
      while (span != null) {
        count++;
        span = span.next;
      }
      if (count == 2) columnsWithTwo++;
    }
    expect(
      columnsWithTwo,
      64,
      reason: 'voxelizing exists so a bridge over a road keeps both decks',
    );
  });

  test('surfaces within the climb threshold merge into one span', () {
    // A step of one cell height: the agent can walk up it, so the two
    // surfaces belong to the same run rather than reading as a ledge.
    final builder = NavGeometryBuilder();
    addFloor(builder, 4);
    addFloor(builder, 4, y: 0.2);
    final field = rasterizeNavGeometry(builder.build(), config)!;

    for (var i = 0; i < field.columnCount; i++) {
      var count = 0;
      var span = field.columnAt(i);
      while (span != null) {
        count++;
        span = span.next;
      }
      expect(count, lessThanOrEqualTo(1));
    }
  });

  test('the field is padded so an edge-flush floor has room to erode', () {
    final builder = NavGeometryBuilder();
    addFloor(builder, 4);
    final geometry = builder.build();
    final field = rasterizeNavGeometry(geometry, config)!;

    final bounds = geometry.bounds!;
    expect(field.min.x, lessThan(bounds.$1.x));
    expect(field.min.z, lessThan(bounds.$1.z));
    expect(field.max.x, greaterThan(bounds.$2.x));
  });

  test('empty geometry bakes to nothing rather than throwing', () {
    expect(rasterizeNavGeometry(NavGeometryBuilder().build(), config), isNull);
    expect(
      rasterizeNavGeometry(
        NavGeometry(vertices: Float32List(0), indices: Uint32List(0)),
        config,
      ),
      isNull,
    );
  });

  test('a builder transform lands the mesh in world space', () {
    final builder = NavGeometryBuilder()
      ..addMesh(
        positions: [0, 0, 0, 1, 0, 0, 1, 0, 1],
        triangleIndices: const [0, 1, 2],
        transform: Matrix4.translationValues(10, 2, -5),
      );
    final bounds = builder.build().bounds!;
    expect(bounds.$1, Vector3(10, 2, -5));
    expect(bounds.$2, Vector3(11, 2, -4));
  });
}
