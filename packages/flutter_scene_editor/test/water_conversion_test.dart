// Which surfaces can become water. The decision is about a shape, so it needs
// no scene and no GPU: a plane and a terrain have a footprint, and a cube is
// not an area of water.

import 'package:flutter_scene_editor/src/inspector/water_conversion.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene/scene.dart';
import 'package:vector_math/vector_math.dart' show Vector3;

const LocalId _id = LocalId(1, 1);

GeometryResource _geometry(ProceduralGeometry shape) =>
    GeometryResource(_id, procedural: shape);

void main() {
  test('a plane offers its own width and depth', () {
    final footprint = footprintOf(
      _geometry(PlaneGeometrySpec(width: 30, depth: 12)),
    );
    expect(footprint, isNotNull);
    expect(footprint!.width, 30);
    expect(footprint.depth, 12);
  });

  test('a terrain offers the ground it covers', () {
    // A sculpted basin is exactly the thing someone wants to fill.
    final footprint = footprintOf(
      _geometry(TerrainGeometrySpec(width: 120, depth: 80)),
    );
    expect(footprint!.width, 120);
    expect(footprint.depth, 80);
  });

  test('a cube is not an area of water', () {
    expect(
      footprintOf(_geometry(CuboidGeometrySpec(extents: Vector3(1, 1, 1)))),
      isNull,
    );
  });

  test('a sphere is not either', () {
    expect(footprintOf(_geometry(SphereGeometrySpec())), isNull);
  });

  test('an imported mesh has no footprint to read', () {
    // Reading one off would mean guessing at something the author never said.
    expect(footprintOf(GeometryResource(_id, vertices: _id)), isNull);
  });

  test('a non-geometry resource is not a surface', () {
    expect(footprintOf(MaterialResource(_id, type: 'physicallyBased')), isNull);
    expect(footprintOf(null), isNull);
  });
}
