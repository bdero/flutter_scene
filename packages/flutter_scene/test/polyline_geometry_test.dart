// Covers PolylineGeometry: the camera-facing strip expansion math,
// round cap disks, the draw-on range, and the factory's argument
// checks. The expansion is pure (it takes a view-projection matrix),
// so it runs without a GPU context; the PolylineGeometry class itself
// uploads to the GPU and is exercised by the example app.

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
      cap: PolylineCap.butt,
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
        cap: PolylineCap.butt,
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
            cap: PolylineCap.butt,
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

  group('expandPolyline draw range', () {
    ({Float32List positions, Float32List normals}) expand(
      double drawStart,
      double drawEnd,
    ) => expandPolyline(
      [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(2, 0, 0), Vector3(3, 0, 0)],
      widths: List<double>.filled(4, 1.0),
      widthMode: PolylineWidthMode.worldUnits,
      cap: PolylineCap.butt,
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
        cap: cap,
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
  });
}
