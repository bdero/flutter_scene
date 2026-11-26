// Covers PolylineGeometry's CPU side: the vertices and draw range its
// vertex shader reads, dash resampling, and the factory's argument checks.
// Also covers expandPolyline, the CPU strip expansion the trail ribbon
// uses. All of it is pure, so it runs without a GPU context.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_scene/src/camera.dart';
import 'package:flutter_scene/src/geometry/polyline_geometry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

ui.Offset _toScreen(Matrix4 viewProjection, Vector3 world, ui.Size size) {
  final clip = viewProjection.transformed(
    Vector4(world.x, world.y, world.z, 1.0),
  );
  return ui.Offset(
    (clip.x / clip.w * 0.5 + 0.5) * size.width,
    (clip.y / clip.w * 0.5 + 0.5) * size.height,
  );
}

Vector3 _vertex(Float32List positions, int index) => Vector3(
  positions[index * 3],
  positions[index * 3 + 1],
  positions[index * 3 + 2],
);

void _expectVector(Vector3 actual, Vector3 expected, {double tol = 1e-5}) {
  expect(actual.x, closeTo(expected.x, tol));
  expect(actual.y, closeTo(expected.y, tol));
  expect(actual.z, closeTo(expected.z, tol));
}

void main() {
  const size = ui.Size(800, 600);
  final camera = PerspectiveCamera(
    position: Vector3(0, 0, 5),
    target: Vector3(0, 0, 0),
  );
  final viewProjection = camera.getViewTransform(size);

  group('PolylineGeometry construction', () {
    test('rejects fewer than two points', () {
      expect(() => PolylineGeometry([Vector3(0, 0, 0)]), throwsArgumentError);
    });

    test('rejects a mismatched perVertexWidth length', () {
      expect(
        () => PolylineGeometry(
          [Vector3(-1, 0, 0), Vector3(1, 0, 0)],
          perVertexWidth: [1.0],
        ),
        throwsArgumentError,
      );
    });

    test('rejects a mismatched perVertexColor length', () {
      expect(
        () => PolylineGeometry(
          [Vector3(-1, 0, 0), Vector3(1, 0, 0)],
          perVertexColor: [Vector4(1, 1, 1, 1)],
        ),
        throwsArgumentError,
      );
    });
  });

  group('diskPointIndices', () {
    test('round caps add the two end points', () {
      expect(diskPointIndices(5, PolylineCap.round), [0, 4]);
    });

    test('butt caps add no disks', () {
      expect(diskPointIndices(5, PolylineCap.butt), isEmpty);
    });
  });

  group('expandPolyline worldUnits', () {
    final points = [Vector3(-1, 0, 0), Vector3(1, 0, 0)];
    final expanded = expandPolyline(
      points,
      widths: [0.5, 0.5],
      widthMode: PolylineWidthMode.worldUnits,
      diskPoints: const <int>[],
      drawStart: 0.0,
      drawEnd: 1.0,
      viewProjection: viewProjection,
      cameraPosition: camera.position,
      viewportSize: size,
    );

    test('emits two vertices per point', () {
      expect(expanded.positions, hasLength(points.length * 2 * 3));
    });

    test('the strip edges are one width apart', () {
      for (var i = 0; i < points.length; i++) {
        final left = _vertex(expanded.positions, i * 2);
        final right = _vertex(expanded.positions, i * 2 + 1);
        expect(left.distanceTo(right), closeTo(0.5, 1e-5));
      }
    });

    test('the offset is perpendicular to the view direction', () {
      for (var i = 0; i < points.length; i++) {
        final left = _vertex(expanded.positions, i * 2);
        final right = _vertex(expanded.positions, i * 2 + 1);
        final viewDirection = camera.position - points[i];
        expect((left - right).dot(viewDirection), closeTo(0, 1e-5));
      }
    });

    test('normals are unit length', () {
      final count = expanded.normals.length ~/ 3;
      for (var v = 0; v < count; v++) {
        expect(_vertex(expanded.normals, v).length, closeTo(1, 1e-5));
      }
    });
  });

  group('expandPolyline screenPixels', () {
    test('the strip is the requested pixel width on screen', () {
      final points = [Vector3(-1, 0, 0), Vector3(1, 0, 0)];
      final expanded = expandPolyline(
        points,
        widths: [24.0, 24.0],
        widthMode: PolylineWidthMode.screenPixels,
        diskPoints: const <int>[],
        drawStart: 0.0,
        drawEnd: 1.0,
        viewProjection: viewProjection,
        cameraPosition: camera.position,
        viewportSize: size,
      );
      for (var i = 0; i < points.length; i++) {
        final left = _toScreen(
          viewProjection,
          _vertex(expanded.positions, i * 2),
          size,
        );
        final right = _toScreen(
          viewProjection,
          _vertex(expanded.positions, i * 2 + 1),
          size,
        );
        expect((left - right).distance, closeTo(24, 0.5));
      }
    });

    test('a closer line and a farther line keep the same pixel width', () {
      ({Float32List positions, Float32List normals}) atDepth(double z) =>
          expandPolyline(
            [Vector3(-1, 0, z), Vector3(1, 0, z)],
            widths: [16.0, 16.0],
            widthMode: PolylineWidthMode.screenPixels,
            diskPoints: const <int>[],
            drawStart: 0.0,
            drawEnd: 1.0,
            viewProjection: viewProjection,
            cameraPosition: camera.position,
            viewportSize: size,
          );
      double pixelWidth(Float32List positions) {
        final left = _toScreen(viewProjection, _vertex(positions, 0), size);
        final right = _toScreen(viewProjection, _vertex(positions, 1), size);
        return (left - right).distance;
      }

      final near = pixelWidth(atDepth(2).positions);
      final far = pixelWidth(atDepth(-3).positions);
      expect(near, closeTo(16, 0.5));
      expect(far, closeTo(16, 0.5));
      expect((near - far).abs(), lessThan(0.5));
    });
  });

  group('buildPolylineVertices', () {
    final points = [Vector3(0, 0, 0), Vector3(3, 0, 0), Vector3(3, 4, 0)];
    final colors = [
      Vector4(1, 0, 0, 1),
      Vector4(0, 1, 0, 1),
      Vector4(0, 0, 1, 1),
    ];
    final mesh = buildPolylineVertices(
      points,
      widths: [2.0, 4.0, 6.0],
      colors: colors,
      diskPoints: const [2],
    );
    List<double> vertex(int index) => mesh.vertices.sublist(
      index * polylineVertexFloats,
      (index + 1) * polylineVertexFloats,
    );

    test('emits two strip vertices per point and a disk per cap', () {
      expect(
        mesh.vertices,
        hasLength((points.length * 2 + 17) * polylineVertexFloats),
      );
      // Two triangles per segment, sixteen per disk.
      expect(mesh.indices, hasLength((2 * 2 + 16) * 3));
    });

    test('a strip vertex carries its point and both neighbors', () {
      final middle = vertex(2);
      expect(middle.sublist(0, 3), [3, 0, 0]);
      expect(middle.sublist(3, 6), [0, 0, 0]);
      expect(middle.sublist(6, 9), [3, 4, 0]);
    });

    test('an end point stands in for its missing neighbor', () {
      expect(vertex(0).sublist(3, 6), [0, 0, 0]);
      expect(vertex(4).sublist(6, 9), [3, 4, 0]);
    });

    test('the two sides of a point differ only in side and u', () {
      final left = vertex(2);
      final right = vertex(3);
      // Shape: side, unused, half width, disk flag.
      expect(left.sublist(9, 13), [-1, 0, 2, 0]);
      expect(right.sublist(9, 13), [1, 0, 2, 0]);
      expect(left[16], 0);
      expect(right[16], 1);
      expect(left.sublist(0, 9), right.sublist(0, 9));
    });

    test('arcs are fractions of the length and v is the distance', () {
      // The line is 3 + 4 = 7 units long.
      final middle = vertex(2);
      expect(middle[13], closeTo(3 / 7, 1e-6));
      expect(middle[14], 0);
      expect(middle[15], 1);
      expect(middle[17], 3);
      expect(vertex(4)[17], 7);
    });

    test('each vertex takes its point color', () {
      expect(vertex(3).sublist(18, 22), [0, 1, 0, 1]);
    });

    test('a disk is a center and a unit ring around its point', () {
      const base = 6;
      final center = vertex(base);
      expect(center.sublist(0, 3), [3, 4, 0]);
      // A disk has no tangent, so its neighbors are the point.
      expect(center.sublist(3, 9), [3, 4, 0, 3, 4, 0]);
      expect(center.sublist(9, 13), [0, 0, 3, 1]);
      for (var k = 0; k < 16; k++) {
        final rim = vertex(base + 1 + k);
        expect(rim[9] * rim[9] + rim[10] * rim[10], closeTo(1, 1e-6));
        expect(rim[12], 1);
      }
    });

    test('a zero-length line has no arc to divide by', () {
      final flat = buildPolylineVertices(
        [Vector3(1, 1, 1), Vector3(1, 1, 1)],
        widths: [1.0, 1.0],
        colors: [Vector4.zero(), Vector4.zero()],
        diskPoints: const [],
      );
      expect(flat.vertices.every((value) => value.isFinite), isTrue);
    });
  });

  group('polylineDrawRange', () {
    final points = [Vector3(0, 0, 0), Vector3(2, 0, 0), Vector3(2, 2, 0)];

    test('the whole line spans both end points', () {
      expect(polylineDrawRange(points, 0.0, 1.0), [0, 1, 0, 0, 0, 2, 2, 0]);
    });

    test('a trimmed range ends part way along a segment', () {
      final range = polylineDrawRange(points, 0.25, 0.75);
      expect(range.sublist(0, 2), [0.25, 0.75]);
      expect(range.sublist(2, 5), [1, 0, 0]);
      expect(range.sublist(5, 8), [2, 1, 0]);
    });

    test('the range clamps to the line', () {
      expect(polylineDrawRange(points, -1.0, 3.0).sublist(0, 2), [0, 1]);
    });

    test('a zero-length line keeps the whole range', () {
      final flat = [Vector3(1, 1, 1), Vector3(1, 1, 1)];
      expect(polylineDrawRange(flat, 0.5, 0.5).sublist(0, 2), [0, 1]);
    });
  });

  group('expandPolyline draw range', () {
    ({Float32List positions, Float32List normals}) expand(
      double drawStart,
      double drawEnd,
    ) => expandPolyline(
      [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(2, 0, 0), Vector3(3, 0, 0)],
      widths: List<double>.filled(4, 1.0),
      widthMode: PolylineWidthMode.worldUnits,
      diskPoints: const <int>[],
      drawStart: drawStart,
      drawEnd: drawEnd,
      viewProjection: viewProjection,
      cameraPosition: camera.position,
      viewportSize: size,
    );

    double pairWidth(Float32List positions, int point) => _vertex(
      positions,
      point * 2,
    ).distanceTo(_vertex(positions, point * 2 + 1));

    test('the full range leaves every point at width', () {
      final expanded = expand(0.0, 1.0);
      for (var i = 0; i < 4; i++) {
        expect(pairWidth(expanded.positions, i), closeTo(1.0, 1e-5));
      }
    });

    test('a point past drawEnd collapses onto the end boundary', () {
      // Length 3; drawEnd 0.5 means the visible range ends at arc 1.5.
      final expanded = expand(0.0, 0.5);
      // Point 2 (arc 2) is past the range.
      expect(pairWidth(expanded.positions, 2), closeTo(0, 1e-5));
      _expectVector(_vertex(expanded.positions, 4), Vector3(1.5, 0, 0));
    });

    test('a point before drawStart collapses onto the start boundary', () {
      final expanded = expand(0.5, 1.0);
      // Point 0 (arc 0) is before the range.
      expect(pairWidth(expanded.positions, 0), closeTo(0, 1e-5));
      _expectVector(_vertex(expanded.positions, 0), Vector3(1.5, 0, 0));
    });
  });

  group('round caps', () {
    ({Float32List positions, Float32List normals}) expand(
      List<Vector3> points, {
      required PolylineCap cap,
      double width = 2.0,
    }) {
      return expandPolyline(
        points,
        widths: List<double>.filled(points.length, width),
        widthMode: PolylineWidthMode.worldUnits,
        diskPoints: diskPointIndices(points.length, cap),
        drawStart: 0.0,
        drawEnd: 1.0,
        viewProjection: viewProjection,
        cameraPosition: camera.position,
        viewportSize: size,
      );
    }

    test('round caps add a disk at each end', () {
      final expanded = expand([
        Vector3(-1, 0, 0),
        Vector3(1, 0, 0),
      ], cap: PolylineCap.round);
      // The strip (2 points) plus a 17-vertex disk at each end.
      expect(expanded.positions, hasLength((2 * 2 + 2 * 17) * 3));
    });

    test('butt caps add no disk vertices', () {
      final expanded = expand([
        Vector3(-1, 0, 0),
        Vector3(1, 0, 0),
      ], cap: PolylineCap.butt);
      expect(expanded.positions, hasLength(2 * 2 * 3));
    });

    test('a cap disk rim sits at the line half-width', () {
      final expanded = expand([
        Vector3(-1, 0, 0),
        Vector3(1, 0, 0),
      ], cap: PolylineCap.round);
      // Strip is 4 vertices; the first disk's center is vertex 4 and
      // its rim is vertices 5..20.
      final center = _vertex(expanded.positions, 4);
      for (var k = 0; k < 16; k++) {
        final rim = _vertex(expanded.positions, 5 + k);
        expect(center.distanceTo(rim), closeTo(1.0, 1e-4));
      }
    });

    test('a cap disk faces the camera', () {
      final start = Vector3(-1, 0, 0);
      final expanded = expand([
        start,
        Vector3(1, 0, 0),
      ], cap: PolylineCap.round);
      // The first disk triangle is (center, rim[1], rim[0]). The engine
      // front face is opposite the right-hand normal, so that normal
      // points away from the camera.
      final center = _vertex(expanded.positions, 4);
      final rim0 = _vertex(expanded.positions, 5);
      final rim1 = _vertex(expanded.positions, 6);
      final geometricNormal = (rim1 - center).cross(rim0 - center);
      expect(geometricNormal.dot(camera.position - start), lessThan(0));
    });

    test('a disk is emitted for every requested disk point', () {
      final expanded = expandPolyline(
        [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(2, 0, 0)],
        widths: List<double>.filled(3, 2.0),
        widthMode: PolylineWidthMode.worldUnits,
        diskPoints: const <int>[0, 1, 2],
        drawStart: 0.0,
        drawEnd: 1.0,
        viewProjection: viewProjection,
        cameraPosition: camera.position,
        viewportSize: size,
      );
      // The strip is 3 points (6 vertices) plus a 17-vertex disk each.
      expect(expanded.positions, hasLength((3 * 2 + 3 * 17) * 3));
    });
  });

  group('resampleDashed', () {
    final white = Vector4(1, 1, 1, 1);

    test('splits a line into dashes joined by zero-width gaps', () {
      final result = resampleDashed(
        [Vector3(0, 0, 0), Vector3(10, 0, 0)],
        List<double>.filled(2, 1.0),
        [white, white],
        const DashPattern(dashLength: 3, gapLength: 1),
      );
      // Dashes (0,3), (4,7), (8,10): 3 + 4 + 3 points.
      expect(result.points, hasLength(10));
      // One zero-width gap connector on each side of each interior gap.
      expect(result.widths.where((w) => w == 0.0), hasLength(4));
    });

    test('the line keeps full-width end points for the caps', () {
      final result = resampleDashed(
        [Vector3(0, 0, 0), Vector3(10, 0, 0)],
        List<double>.filled(2, 2.0),
        [white, white],
        const DashPattern(dashLength: 3, gapLength: 1),
      );
      expect(result.widths.first, 2.0);
      expect(result.widths.last, 2.0);
      _expectVector(result.points.first, Vector3(0, 0, 0));
      _expectVector(result.points.last, Vector3(10, 0, 0));
    });

    test('a zero-length line is returned unchanged', () {
      final points = [Vector3(0, 0, 0), Vector3(0, 0, 0)];
      final result = resampleDashed(
        points,
        [1.0, 1.0],
        [white, white],
        const DashPattern(dashLength: 1, gapLength: 1),
      );
      expect(result.points, same(points));
    });

    test('dash cap indices mark both ends of every dash', () {
      final result = resampleDashed(
        [Vector3(0, 0, 0), Vector3(10, 0, 0)],
        List<double>.filled(2, 2.0),
        [white, white],
        const DashPattern(dashLength: 3, gapLength: 1, cap: PolylineCap.round),
      );
      // Dashes (0,3), (4,7), (8,10): two boundary points each.
      expect(result.dashCapIndices, hasLength(6));
      // Every marked index is a full-width dash boundary, never a gap.
      for (final index in result.dashCapIndices) {
        expect(result.widths[index], 2.0);
      }
    });
  });
}
