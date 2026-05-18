import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/camera.dart';
import 'package:flutter_scene/src/geometry/mesh_geometry.dart';

/// How a [PolylineGeometry]'s width is measured.
enum PolylineWidthMode {
  /// The width is a constant number of screen pixels at every distance,
  /// so a route line keeps the same on-screen thickness as the camera
  /// zooms.
  screenPixels,

  /// The width is a fixed distance in scene units, so the line looks
  /// thinner the further it is from the camera.
  worldUnits,
}

/// How a [PolylineGeometry] finishes its two end points.
enum PolylineCap {
  /// The strip ends flat at the end point.
  butt,

  /// A half-disk rounds the end off to the line's half-width.
  round,
}

/// How a [PolylineGeometry] turns corners.
enum PolylineJoin {
  /// The strip bends through a shared averaged direction. Cheap, but it
  /// can pinch on very sharp turns.
  miter,

  /// A disk fills each corner, rounding the outside of the bend.
  round,
}

// Triangle-fan segments in a round cap or join disk.
const int _diskSegments = 16;

/// A thick, camera-facing line through a list of points.
///
/// `PolylineGeometry` builds a triangle strip that always faces the
/// camera, which suits navigation routes and other overlay lines. The
/// strip is regenerated for the current view by [updateForCamera], which
/// should be called every frame before rendering.
///
/// The result is an ordinary triangle mesh: pair it with any material,
/// and use [perVertexColor] for gradient or distance-fade effects.
///
/// Round caps and joins ([PolylineCap.round], [PolylineJoin.round]) add
/// camera-facing disks at the end and corner points. Dashes, an animated
/// draw-on range, and a GPU vertex-shader expansion that avoids the
/// per-frame rebuild are planned follow-ups; see
/// `docs/dynamic_geometry.md`.
class PolylineGeometry extends MeshGeometry {
  /// Creates a polyline through [points] (at least two).
  ///
  /// [width] is measured per [widthMode]. [perVertexWidth] overrides it
  /// per point for tapering, and [perVertexColor] sets a color per
  /// point for gradients. [cap] and [join] select rounded ends and
  /// corners. The strip is a placeholder until the first
  /// [updateForCamera] call.
  factory PolylineGeometry(
    List<Vector3> points, {
    double width = 8.0,
    PolylineWidthMode widthMode = PolylineWidthMode.screenPixels,
    PolylineCap cap = PolylineCap.butt,
    PolylineJoin join = PolylineJoin.miter,
    List<double>? perVertexWidth,
    List<Vector4>? perVertexColor,
  }) {
    if (points.length < 2) {
      throw ArgumentError('A polyline needs at least two points');
    }
    final copied = <Vector3>[for (final p in points) p.clone()];
    final count = copied.length;
    if (perVertexWidth != null && perVertexWidth.length != count) {
      throw ArgumentError('perVertexWidth must have one entry per point');
    }
    if (perVertexColor != null && perVertexColor.length != count) {
      throw ArgumentError('perVertexColor must have one entry per point');
    }
    final widths =
        perVertexWidth != null
            ? List<double>.of(perVertexWidth)
            : List<double>.filled(count, width);

    // Cumulative arc length at each point, for the texture v coordinate.
    final distances = List<double>.filled(count, 0.0);
    for (var i = 1; i < count; i++) {
      distances[i] = distances[i - 1] + copied[i].distanceTo(copied[i - 1]);
    }
    Vector4 colorOf(int i) => perVertexColor?[i] ?? Vector4(1.0, 1.0, 1.0, 1.0);

    // Texture coordinates and colors do not depend on the camera, so
    // they are set once here. The placeholder positions collapse the
    // strip onto the points until updateForCamera runs.
    final diskPoints = diskPointIndices(count, cap, join);
    final stripVertexCount = count * 2;
    final vertexCount =
        stripVertexCount + diskPoints.length * (_diskSegments + 1);
    final positions = Float32List(vertexCount * 3);
    final normals = Float32List(vertexCount * 3);
    final texCoords = Float32List(vertexCount * 2);
    final colors = Float32List(vertexCount * 4);

    void writeVertex(int v, Vector3 at, double u, double texV, Vector4 color) {
      positions[v * 3] = at.x;
      positions[v * 3 + 1] = at.y;
      positions[v * 3 + 2] = at.z;
      normals[v * 3 + 2] = 1.0;
      texCoords[v * 2] = u;
      texCoords[v * 2 + 1] = texV;
      colors[v * 4] = color.x;
      colors[v * 4 + 1] = color.y;
      colors[v * 4 + 2] = color.z;
      colors[v * 4 + 3] = color.w;
    }

    final indices = <int>[];

    // The strip: two vertices per point.
    for (var i = 0; i < count; i++) {
      final color = colorOf(i);
      writeVertex(i * 2, copied[i], 0.0, distances[i], color);
      writeVertex(i * 2 + 1, copied[i], 1.0, distances[i], color);
    }
    for (var i = 0; i < count - 1; i++) {
      final a = i * 2;
      indices
        ..addAll([a, a + 2, a + 1])
        ..addAll([a + 1, a + 2, a + 3]);
    }

    // A triangle-fan disk for each round cap or join point.
    for (var ord = 0; ord < diskPoints.length; ord++) {
      final point = diskPoints[ord];
      final base = stripVertexCount + ord * (_diskSegments + 1);
      final color = colorOf(point);
      for (var k = 0; k <= _diskSegments; k++) {
        writeVertex(base + k, copied[point], 0.5, distances[point], color);
      }
      for (var k = 0; k < _diskSegments; k++) {
        final next = (k + 1) % _diskSegments;
        indices.addAll([base, base + 1 + next, base + 1 + k]);
      }
    }

    return PolylineGeometry._(
      copied,
      widths,
      widthMode,
      cap,
      join,
      positions: positions,
      normals: normals,
      texCoords: texCoords,
      colors: colors,
      indices: indices,
    );
  }

  PolylineGeometry._(
    this._points,
    this._widths,
    this._widthMode,
    this._cap,
    this._join, {
    required super.positions,
    required super.normals,
    required super.texCoords,
    required super.colors,
    required super.indices,
  }) : super.fromArrays(storage: GeometryStorage.updatable);

  final List<Vector3> _points;
  final List<double> _widths;
  final PolylineWidthMode _widthMode;
  final PolylineCap _cap;
  final PolylineJoin _join;

  /// Rebuilds the camera-facing strip for [camera] and [viewportSize].
  ///
  /// Call once per frame before rendering. Reuses the GPU buffers.
  void updateForCamera(Camera camera, ui.Size viewportSize) {
    final expanded = expandPolyline(
      _points,
      widths: _widths,
      widthMode: _widthMode,
      cap: _cap,
      join: _join,
      viewProjection: camera.getViewTransform(viewportSize),
      cameraPosition: camera.position,
      viewportSize: viewportSize,
    );
    updatePositions(expanded.positions);
    updateNormals(expanded.normals);
  }
}

/// The polyline point indices that receive a round cap or join disk, in
/// the order [expandPolyline] emits them: the two end points first,
/// then the interior points.
List<int> diskPointIndices(int count, PolylineCap cap, PolylineJoin join) {
  final indices = <int>[];
  if (cap == PolylineCap.round) {
    indices
      ..add(0)
      ..add(count - 1);
  }
  if (join == PolylineJoin.round) {
    for (var i = 1; i < count - 1; i++) {
      indices.add(i);
    }
  }
  return indices;
}

/// Expands [points] into a camera-facing triangle strip's vertex
/// positions and normals, including round cap and join disks.
///
/// Pure: it takes the view-projection matrix rather than touching the
/// GPU, so it can be exercised without a render context. The strip is
/// two vertices per point; each round cap or join adds a disk of
/// `1 + 16` vertices.
({Float32List positions, Float32List normals}) expandPolyline(
  List<Vector3> points, {
  required List<double> widths,
  required PolylineWidthMode widthMode,
  required PolylineCap cap,
  required PolylineJoin join,
  required Matrix4 viewProjection,
  required Vector3 cameraPosition,
  required ui.Size viewportSize,
}) {
  final count = points.length;
  final tangents = _pointTangents(points);
  final viewDirections = <Vector3>[
    for (final p in points) _towardCamera(cameraPosition, p),
  ];

  // Strip edge vertices, computed per point.
  final left = List<Vector3>.filled(count, Vector3.zero());
  final right = List<Vector3>.filled(count, Vector3.zero());

  if (widthMode == PolylineWidthMode.worldUnits) {
    for (var i = 0; i < count; i++) {
      var across = tangents[i].cross(viewDirections[i]);
      if (across.length2 < 1e-12) across = _anyPerpendicular(tangents[i]);
      across = across.normalized() * (widths[i] / 2.0);
      left[i] = points[i] - across;
      right[i] = points[i] + across;
    }
  } else {
    final inverse = Matrix4.inverted(viewProjection);
    final clip = <Vector4>[
      for (final p in points)
        viewProjection.transformed(Vector4(p.x, p.y, p.z, 1.0)),
    ];
    final width = viewportSize.width;
    final height = viewportSize.height;
    for (var i = 0; i < count; i++) {
      final here = clip[i];
      final w = here.w.abs() < 1e-6 ? 1e-6 : here.w;
      final previous = clip[i == 0 ? 0 : i - 1];
      final next = clip[i == count - 1 ? count - 1 : i + 1];
      // Screen-space direction between the neighbors.
      var screenX = (_ndcX(next) - _ndcX(previous)) * width;
      var screenY = -(_ndcY(next) - _ndcY(previous)) * height;
      var length = math.sqrt(screenX * screenX + screenY * screenY);
      if (length < 1e-9) {
        screenX = 1.0;
        screenY = 0.0;
        length = 1.0;
      }
      screenX /= length;
      screenY /= length;
      // Perpendicular, offset by half the pixel width, expressed in NDC.
      final half = widths[i] / 2.0;
      final ndcOffsetX = -screenY * half * 2.0 / width;
      final ndcOffsetY = -screenX * half * 2.0 / height;
      left[i] = _unproject(
        inverse,
        here.x + ndcOffsetX * w,
        here.y + ndcOffsetY * w,
        here.z,
        w,
      );
      right[i] = _unproject(
        inverse,
        here.x - ndcOffsetX * w,
        here.y - ndcOffsetY * w,
        here.z,
        w,
      );
    }
  }

  final diskPoints = diskPointIndices(count, cap, join);
  final vertexCount = count * 2 + diskPoints.length * (_diskSegments + 1);
  final positions = Float32List(vertexCount * 3);
  final normals = Float32List(vertexCount * 3);

  for (var i = 0; i < count; i++) {
    _writePair(positions, normals, i, left[i], right[i], viewDirections[i]);
  }

  var base = count * 2;
  for (final point in diskPoints) {
    // The strip half-width at the point, recovered from its two edges,
    // works for both world and screen modes.
    final radius = (left[point] - right[point]).length / 2.0;
    base = _emitDisk(
      positions,
      normals,
      base,
      points[point],
      viewDirections[point],
      radius,
    );
  }
  return (positions: positions, normals: normals);
}

List<Vector3> _pointTangents(List<Vector3> points) {
  final count = points.length;
  return <Vector3>[
    for (var i = 0; i < count; i++)
      () {
        final Vector3 delta;
        if (i == 0) {
          delta = points[1] - points[0];
        } else if (i == count - 1) {
          delta = points[count - 1] - points[count - 2];
        } else {
          delta = points[i + 1] - points[i - 1];
        }
        return delta.length2 < 1e-12
            ? Vector3(1.0, 0.0, 0.0)
            : delta.normalized();
      }(),
  ];
}

// Emits a camera-facing disk: a center vertex and a ring, fanned into
// triangles. The disk is nudged slightly toward the camera so it draws
// over the strip rather than z-fighting with it.
int _emitDisk(
  Float32List positions,
  Float32List normals,
  int base,
  Vector3 center,
  Vector3 viewDirection,
  double radius,
) {
  final faceCenter = center + viewDirection * (radius * 0.1);
  final u = _anyPerpendicular(viewDirection);
  final v = viewDirection.cross(u);
  _writeVertex(positions, normals, base, faceCenter, viewDirection);
  for (var k = 0; k < _diskSegments; k++) {
    final angle = 2.0 * math.pi * k / _diskSegments;
    final rim =
        faceCenter +
        u * (radius * math.cos(angle)) +
        v * (radius * math.sin(angle));
    _writeVertex(positions, normals, base + 1 + k, rim, viewDirection);
  }
  return base + 1 + _diskSegments;
}

double _ndcX(Vector4 clip) => clip.x / (clip.w.abs() < 1e-6 ? 1e-6 : clip.w);

double _ndcY(Vector4 clip) => clip.y / (clip.w.abs() < 1e-6 ? 1e-6 : clip.w);

Vector3 _unproject(Matrix4 inverse, double x, double y, double z, double w) {
  final world = inverse.transformed(Vector4(x, y, z, w));
  final iw = world.w.abs() < 1e-9 ? 1e-9 : world.w;
  return Vector3(world.x / iw, world.y / iw, world.z / iw);
}

Vector3 _towardCamera(Vector3 cameraPosition, Vector3 point) {
  final direction = cameraPosition - point;
  return direction.length2 < 1e-12
      ? Vector3(0.0, 0.0, 1.0)
      : direction.normalized();
}

Vector3 _anyPerpendicular(Vector3 direction) {
  final reference =
      direction.x.abs() < 0.9 ? Vector3(1.0, 0.0, 0.0) : Vector3(0.0, 1.0, 0.0);
  return direction.cross(reference).normalized();
}

void _writeVertex(
  Float32List positions,
  Float32List normals,
  int vertex,
  Vector3 position,
  Vector3 normal,
) {
  final base = vertex * 3;
  positions[base] = position.x;
  positions[base + 1] = position.y;
  positions[base + 2] = position.z;
  normals[base] = normal.x;
  normals[base + 1] = normal.y;
  normals[base + 2] = normal.z;
}

void _writePair(
  Float32List positions,
  Float32List normals,
  int point,
  Vector3 left,
  Vector3 right,
  Vector3 normal,
) {
  _writeVertex(positions, normals, point * 2, left, normal);
  _writeVertex(positions, normals, point * 2 + 1, right, normal);
}
