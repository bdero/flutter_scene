// Nav volumes: the box that overrides an area after voxelization, and the
// reason it exists. A surface tagged non-walkable only asks the voxelizer to
// fall back to its slope test; carving the space is the only way to stop an
// agent walking along the bottom of a pool it was refused entry to.

import 'dart:typed_data';

import 'package:scene/navigation.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// A flat floor spanning [size] x [size] at y = [height], as two triangles.
NavGeometry floor({double size = 10, double height = 0, int area = 0}) {
  final half = size / 2;
  return NavGeometry(
    vertices: Float32List.fromList([
      -half, height, -half, //
      half, height, -half, //
      half, height, half, //
      -half, height, half,
    ]),
    indices: Uint32List.fromList([0, 2, 1, 0, 3, 2]),
    areas: Uint8List.fromList([area, area]),
  );
}

/// Merges two geometries into one soup.
NavGeometry merge(NavGeometry a, NavGeometry b) {
  final offset = a.vertices.length ~/ 3;
  return NavGeometry(
    vertices: Float32List.fromList([...a.vertices, ...b.vertices]),
    indices: Uint32List.fromList([
      ...a.indices,
      for (final i in b.indices) i + offset,
    ]),
    areas: Uint8List.fromList([...a.areas, ...b.areas]),
  );
}

const _config = NavMeshConfig(
  cellSize: 0.3,
  cellHeight: 0.2,
  agentRadius: 0.3,
  agentHeight: 1.6,
);

/// How much walkable surface a bake produced, as a polygon count.
int polygonsOf(NavMesh? mesh) => mesh?.polygonCount ?? 0;

void main() {
  group('NavVolume', () {
    test('contains tests the closed box', () {
      final volume = NavVolume(
        min: Vector3(-1, -1, -1),
        max: Vector3(1, 1, 1),
      );
      expect(volume.contains(0, 0, 0), isTrue);
      expect(volume.contains(1, 1, 1), isTrue, reason: 'the corner counts');
      expect(volume.contains(1.01, 0, 0), isFalse);
      expect(volume.contains(0, -1.01, 0), isFalse);
    });

    test('a box carves the spans whose surface falls inside it', () {
      final geometry = floor(size: 12);
      final open = buildNavMesh(geometry, _config);
      expect(polygonsOf(open), greaterThan(0), reason: 'a floor bakes');

      final carved = buildNavMesh(
        geometry,
        _config,
        volumes: [
          NavVolume(
            min: Vector3(-10, -1, -10),
            max: Vector3(10, 1, 10),
          ),
        ],
      );
      expect(
        polygonsOf(carved),
        0,
        reason: 'the whole floor was inside the volume',
      );
    });

    test('a volume above the surface leaves it alone', () {
      final geometry = floor(size: 12);
      final mesh = buildNavMesh(
        geometry,
        _config,
        volumes: [
          NavVolume(
            min: Vector3(-10, 5, -10),
            max: Vector3(10, 8, 10),
          ),
        ],
      );
      expect(polygonsOf(mesh), greaterThan(0));
    });

    test('carving reaches the floor under a surface, not just the top', () {
      // The case water is the reason for: a pool surface at y = 0 over a bed
      // at y = -2. Tagging the surface alone would leave the bed walkable.
      final geometry = merge(
        floor(size: 12, height: 0),
        floor(size: 12, height: -2),
      );
      final both = buildNavMesh(geometry, _config);
      expect(polygonsOf(both), greaterThan(0));

      final carved = buildNavMesh(
        geometry,
        _config,
        volumes: [
          NavVolume(
            min: Vector3(-10, -5, -10),
            max: Vector3(10, 1, 10),
          ),
        ],
      );
      expect(
        polygonsOf(carved),
        0,
        reason: 'both the surface and the bed were carved',
      );
    });

    test('a volume can paint an area instead of erasing it', () {
      final geometry = floor(size: 12);
      final mesh = buildNavMesh(
        geometry,
        _config,
        volumes: [
          NavVolume(
            min: Vector3(-10, -1, -10),
            max: Vector3(10, 1, 10),
            area: NavArea.slow,
          ),
        ],
      );
      expect(polygonsOf(mesh), greaterThan(0), reason: 'painted, not carved');
      var slow = 0;
      for (var i = 0; i < mesh!.polygonCount; i++) {
        if (mesh.areas[i] == NavArea.slow) slow++;
      }
      expect(slow, mesh.polygonCount);
    });

    test('the later volume wins where two overlap', () {
      final geometry = floor(size: 12);
      final mesh = buildNavMesh(
        geometry,
        _config,
        volumes: [
          NavVolume(
            min: Vector3(-10, -1, -10),
            max: Vector3(10, 1, 10),
          ),
          NavVolume(
            min: Vector3(-10, -1, -10),
            max: Vector3(10, 1, 10),
            area: NavArea.walkable,
          ),
        ],
      );
      expect(
        polygonsOf(mesh),
        greaterThan(0),
        reason: 'the second volume put the floor back',
      );
    });

    test('no volumes is exactly the old bake', () {
      final geometry = floor(size: 12);
      expect(
        polygonsOf(buildNavMesh(geometry, _config, volumes: const [])),
        polygonsOf(buildNavMesh(geometry, _config)),
      );
    });
  });

  test('applyNavVolumes on an empty list touches nothing', () {
    final field = rasterizeNavGeometry(floor(size: 6), _config)!;
    final before = <int>[];
    for (var i = 0; i < field.columnCount; i++) {
      var span = field.columnAt(i);
      while (span != null) {
        before.add(span.area);
        span = span.next;
      }
    }
    applyNavVolumes(field, const []);
    final after = <int>[];
    for (var i = 0; i < field.columnCount; i++) {
      var span = field.columnAt(i);
      while (span != null) {
        after.add(span.area);
        span = span.next;
      }
    }
    expect(after, before);
  });
}
