import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_scene/src/geometry/geometry.dart';
import 'package:flutter_scene/src/geometry/mesh_geometry.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart' as vm;

/// Immediate-mode wireframe debug visualization utility for lines, rays, boxes, spheres, and axes.
/// {@category Rendering}
class DebugDraw {
  static final List<double> _positions = [];
  static final List<double> _colors = [];

  /// Maximum vertex limit to avoid unbounded accumulation when un-flushed.
  static int maxVertexLimit = 65536;
  static bool _hasWarnedLimit = false;

  /// Draws a wireframe line segment between [start] and [end].
  static void line(vm.Vector3 start, vm.Vector3 end, {vm.Vector4? color}) {
    if (vertexCount >= maxVertexLimit) {
      if (!_hasWarnedLimit) {
        _hasWarnedLimit = true;
        assert(
          false,
          'DebugDraw vertex limit ($maxVertexLimit) exceeded; discarding additional lines.',
        );
      }
      return;
    }
    final c = color ?? vm.Vector4(1.0, 1.0, 1.0, 1.0);

    _positions.addAll([start.x, start.y, start.z, end.x, end.y, end.z]);
    _colors.addAll([c.r, c.g, c.b, c.a, c.r, c.g, c.b, c.a]);
  }

  /// Draws a ray starting at [origin] along [direction] with length [length].
  static void ray(
    vm.Vector3 origin,
    vm.Vector3 direction, {
    double length = 1.0,
    vm.Vector4? color,
  }) {
    line(origin, origin + direction.normalized() * length, color: color);
  }

  /// Draws an axis-aligned bounding box wireframe.
  static void box(vm.Aabb3 bounds, {vm.Vector4? color}) {
    final min = bounds.min;
    final max = bounds.max;

    final p000 = vm.Vector3(min.x, min.y, min.z);
    final p100 = vm.Vector3(max.x, min.y, min.z);
    final p010 = vm.Vector3(min.x, max.y, min.z);
    final p110 = vm.Vector3(max.x, max.y, min.z);
    final p001 = vm.Vector3(min.x, min.y, max.z);
    final p101 = vm.Vector3(max.x, min.y, max.z);
    final p011 = vm.Vector3(min.x, max.y, max.z);
    final p111 = vm.Vector3(max.x, max.y, max.z);

    // Bottom square
    line(p000, p100, color: color);
    line(p100, p101, color: color);
    line(p101, p001, color: color);
    line(p001, p000, color: color);

    // Top square
    line(p010, p110, color: color);
    line(p110, p111, color: color);
    line(p111, p011, color: color);
    line(p011, p010, color: color);

    // Vertical pillars
    line(p000, p010, color: color);
    line(p100, p110, color: color);
    line(p101, p111, color: color);
    line(p001, p011, color: color);
  }

  /// Draws a wireframe sphere at [center] with [radius].
  static void sphere(
    vm.Vector3 center,
    double radius, {
    int segments = 16,
    vm.Vector4? color,
  }) {
    for (var i = 0; i < segments; i++) {
      final a1 = (i / segments) * 2 * math.pi;
      final a2 = ((i + 1) / segments) * 2 * math.pi;

      final c1 = math.cos(a1) * radius;
      final s1 = math.sin(a1) * radius;
      final c2 = math.cos(a2) * radius;
      final s2 = math.sin(a2) * radius;

      // XZ circle
      line(
        center + vm.Vector3(c1, 0, s1),
        center + vm.Vector3(c2, 0, s2),
        color: color,
      );
      // XY circle
      line(
        center + vm.Vector3(c1, s1, 0),
        center + vm.Vector3(c2, s2, 0),
        color: color,
      );
      // YZ circle
      line(
        center + vm.Vector3(0, s1, c1),
        center + vm.Vector3(0, s2, c2),
        color: color,
      );
    }
  }

  /// Draws 3D coordinate axes (RGB = XYZ) for [transform].
  static void axes(vm.Matrix4 transform, {double size = 1.0}) {
    final origin = (transform * vm.Vector4(0, 0, 0, 1)).xyz;
    final xAxis = (transform * vm.Vector4(size, 0, 0, 1)).xyz;
    final yAxis = (transform * vm.Vector4(0, size, 0, 1)).xyz;
    final zAxis = (transform * vm.Vector4(0, 0, size, 1)).xyz;

    line(origin, xAxis, color: vm.Vector4(1, 0, 0, 1));
    line(origin, yAxis, color: vm.Vector4(0, 1, 0, 1));
    line(origin, zAxis, color: vm.Vector4(0, 0, 1, 1));
  }

  /// Total number of line vertices accumulated for the current frame.
  static int get vertexCount => _positions.length ~/ 3;

  /// Builds a [MeshGeometry] containing all accumulated line segments and clears the buffer.
  static MeshGeometry? flushMesh({
    GeometryBufferArena? bufferArena,
    GeometryStorage storage = GeometryStorage.fixed,
  }) {
    if (_positions.isEmpty) return null;

    final posList = Float32List.fromList(_positions);
    final colList = Float32List.fromList(_colors);
    _positions.clear();
    _colors.clear();
    _hasWarnedLimit = false;

    return MeshGeometry.fromArrays(
      positions: posList,
      colors: colList,
      primitiveType: gpu.PrimitiveType.line,
      bufferArena: bufferArena,
      storage: storage,
    );
  }

  /// Clears all accumulated debug geometry without building.
  static void clear() {
    _positions.clear();
    _colors.clear();
    _hasWarnedLimit = false;
  }
}
