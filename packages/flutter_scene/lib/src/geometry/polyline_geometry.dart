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
/// Joins use an averaged corner direction, which can spike on very
/// sharp turns. Caps are flat. Dashes, an animated draw-on range, and a
/// GPU vertex-shader expansion that avoids the per-frame rebuild are
/// planned follow-ups; see `docs/dynamic_geometry.md`.
class PolylineGeometry extends MeshGeometry {
  /// Creates a polyline through [points] (at least two).
  ///
  /// [width] is measured per [widthMode]. [perVertexWidth] overrides it
  /// per point for tapering, and [perVertexColor] sets a color per
  /// point for gradients. The strip is a placeholder until the first
  /// [updateForCamera] call.
  factory PolylineGeometry(
    List<Vector3> points, {
    double width = 8.0,
    PolylineWidthMode widthMode = PolylineWidthMode.screenPixels,
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

    // Texture coordinates and colors do not depend on the camera, so
    // they are set once here. The placeholder positions collapse the
    // strip onto the points until updateForCamera runs.
    final texCoords = Float32List(count * 2 * 2);
    final colors = Float32List(count * 2 * 4);
    final placeholder = Float32List(count * 2 * 3);
    final normals = Float32List(count * 2 * 3);
    var distance = 0.0;
    for (var i = 0; i < count; i++) {
      if (i > 0) distance += copied[i].distanceTo(copied[i - 1]);
      final color = perVertexColor?[i] ?? Vector4(1.0, 1.0, 1.0, 1.0);
      for (var side = 0; side < 2; side++) {
        final v = i * 2 + side;
        placeholder[v * 3] = copied[i].x;
        placeholder[v * 3 + 1] = copied[i].y;
        placeholder[v * 3 + 2] = copied[i].z;
        normals[v * 3 + 2] = 1.0;
        texCoords[v * 2] = side.toDouble();
        texCoords[v * 2 + 1] = distance;
        colors[v * 4] = color.x;
        colors[v * 4 + 1] = color.y;
        colors[v * 4 + 2] = color.z;
        colors[v * 4 + 3] = color.w;
      }
    }

    final indices = <int>[];
    for (var i = 0; i < count - 1; i++) {
      final a = i * 2;
      indices
        ..addAll([a, a + 2, a + 1])
        ..addAll([a + 1, a + 2, a + 3]);
    }

    return PolylineGeometry._(
      copied,
      widths,
      widthMode,
      positions: placeholder,
      normals: normals,
      texCoords: texCoords,
      colors: colors,
      indices: indices,
    );
  }

  PolylineGeometry._(
    this._points,
    this._widths,
    this._widthMode, {
    required super.positions,
    required super.normals,
    required super.texCoords,
    required super.colors,
    required super.indices,
  }) : super.fromArrays(storage: GeometryStorage.updatable);

  final List<Vector3> _points;
  final List<double> _widths;
  final PolylineWidthMode _widthMode;

  /// Rebuilds the camera-facing strip for [camera] and [viewportSize].
  ///
  /// Call once per frame before rendering. Reuses the GPU buffers.
  void updateForCamera(Camera camera, ui.Size viewportSize) {
    final expanded = expandPolyline(
      _points,
      widths: _widths,
      widthMode: _widthMode,
      viewProjection: camera.getViewTransform(viewportSize),
      cameraPosition: camera.position,
      viewportSize: viewportSize,
    );
    updatePositions(expanded.positions);
    updateNormals(expanded.normals);
  }
}

/// Expands [points] into a camera-facing triangle-strip's vertex
/// positions and normals.
///
/// Pure: it takes the view-projection matrix rather than touching the
/// GPU, so it can be exercised without a render context. Returns two
/// vertices per point (the strip edges), with normals facing the
/// camera.
({Float32List positions, Float32List normals}) expandPolyline(
  List<Vector3> points, {
  required List<double> widths,
  required PolylineWidthMode widthMode,
  required Matrix4 viewProjection,
  required Vector3 cameraPosition,
  required ui.Size viewportSize,
}) {
  final count = points.length;
  final positions = Float32List(count * 2 * 3);
  final normals = Float32List(count * 2 * 3);
  final tangents = _pointTangents(points);

  if (widthMode == PolylineWidthMode.worldUnits) {
    for (var i = 0; i < count; i++) {
      final point = points[i];
      final viewDirection = _towardCamera(cameraPosition, point);
      var across = tangents[i].cross(viewDirection);
      if (across.length2 < 1e-12) across = _anyPerpendicular(tangents[i]);
      across = across.normalized() * (widths[i] / 2.0);
      _writePair(
        positions,
        normals,
        i,
        point - across,
        point + across,
        viewDirection,
      );
    }
    return (positions: positions, normals: normals);
  }

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
    final viewDirection = _towardCamera(cameraPosition, points[i]);
    final left = _unproject(
      inverse,
      here.x + ndcOffsetX * w,
      here.y + ndcOffsetY * w,
      here.z,
      w,
    );
    final right = _unproject(
      inverse,
      here.x - ndcOffsetX * w,
      here.y - ndcOffsetY * w,
      here.z,
      w,
    );
    _writePair(positions, normals, i, left, right, viewDirection);
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

void _writePair(
  Float32List positions,
  Float32List normals,
  int point,
  Vector3 left,
  Vector3 right,
  Vector3 normal,
) {
  final base = point * 2 * 3;
  positions[base] = left.x;
  positions[base + 1] = left.y;
  positions[base + 2] = left.z;
  positions[base + 3] = right.x;
  positions[base + 4] = right.y;
  positions[base + 5] = right.z;
  for (var v = 0; v < 6; v += 3) {
    normals[base + v] = normal.x;
    normals[base + v + 1] = normal.y;
    normals[base + v + 2] = normal.z;
  }
}
