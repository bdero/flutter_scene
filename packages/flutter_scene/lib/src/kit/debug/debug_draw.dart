import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_scene/src/geometry/geometry.dart';
import 'package:flutter_scene/src/geometry/mesh_geometry.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/node.dart';
import 'package:flutter_scene/src/physics/collider.dart';
import 'package:scene/physics.dart' as sim;
import 'package:vector_math/vector_math.dart' as vm;

/// Immediate-mode wireframe debug visualization utility for lines, rays, boxes,
/// spheres, axes, and physics colliders.
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

  /// Draws the wireframe of a physics [shape] posed by [transform].
  ///
  /// [sim.TriMeshShape] draws every triangle edge and [sim.ConvexHullShape]
  /// marks its points, either of which can exhaust [maxVertexLimit] on dense
  /// collision geometry. [sim.HeightFieldShape] draws nothing.
  static void shape(
    sim.Shape shape,
    vm.Matrix4 transform, {
    vm.Vector4? color,
    int segments = 16,
  }) {
    vm.Vector3 at(double x, double y, double z) =>
        transform.transform3(vm.Vector3(x, y, z));

    switch (shape) {
      case sim.SphereShape(:final radius):
        for (var axis = 0; axis < 3; axis++) {
          _ring(at, radius, 0, axis, segments, color);
        }
      case sim.BoxShape(:final halfExtents):
        final e = halfExtents;
        final corners = [
          for (final sx in const [-1.0, 1.0])
            for (final sy in const [-1.0, 1.0])
              for (final sz in const [-1.0, 1.0])
                at(e.x * sx, e.y * sy, e.z * sz),
        ];
        for (final (i, j) in _boxEdges) {
          line(corners[i], corners[j], color: color);
        }
      case sim.CapsuleShape(:final radius, :final halfHeight):
        _ring(at, radius, halfHeight, 1, segments, color);
        _ring(at, radius, -halfHeight, 1, segments, color);
        _cap(at, radius, halfHeight, 1, segments, color);
        _cap(at, radius, -halfHeight, -1, segments, color);
        _sides(at, radius, halfHeight, color);
      case sim.CylinderShape(:final radius, :final halfHeight):
        _ring(at, radius, halfHeight, 1, segments, color);
        _ring(at, radius, -halfHeight, 1, segments, color);
        _sides(at, radius, halfHeight, color);
      case sim.TriMeshShape(:final vertices, :final indices):
        for (var i = 0; i + 2 < indices.length; i += 3) {
          final a = indices[i] * 3;
          final b = indices[i + 1] * 3;
          final c = indices[i + 2] * 3;
          final va = at(vertices[a], vertices[a + 1], vertices[a + 2]);
          final vb = at(vertices[b], vertices[b + 1], vertices[b + 2]);
          final vc = at(vertices[c], vertices[c + 1], vertices[c + 2]);
          line(va, vb, color: color);
          line(vb, vc, color: color);
          line(vc, va, color: color);
        }
      case sim.ConvexHullShape(:final points):
        // The hull's topology is the backend's, so mark the input points.
        for (var i = 0; i + 2 < points.length; i += 3) {
          final v = at(points[i], points[i + 1], points[i + 2]);
          for (final axis in _unitAxes) {
            line(v - axis * 0.02, v + axis * 0.02, color: color);
          }
        }
      case sim.CompoundShape(:final children):
        for (final child in children) {
          DebugDraw.shape(
            child.shape,
            transform.multiplied(child.localPose),
            color: color,
            segments: segments,
          );
        }
      case sim.HeightFieldShape():
        // TODO(debug-draw): stride the heightfield grid into a wire mesh.
        break;
    }
  }

  /// Draws the wireframe of every [Collider] in the [root] subtree, posed the
  /// way the simulation sees it.
  ///
  /// Triggers draw in [triggerColor] so they stand apart from solid volumes.
  static void colliders(
    Node root, {
    vm.Vector4? color,
    vm.Vector4? triggerColor,
    int segments = 16,
  }) {
    final solid = color ?? vm.Vector4(0.2, 1.0, 0.4, 0.9);
    final trigger = triggerColor ?? vm.Vector4(1.0, 0.85, 0.2, 0.9);

    for (final collider in root.getComponents<Collider>()) {
      shape(
        collider.shape,
        root.globalTransform.multiplied(collider.localPose),
        color: collider.isTrigger ? trigger : solid,
        segments: segments,
      );
    }
    for (final child in root.children) {
      colliders(child, color: solid, triggerColor: trigger, segments: segments);
    }
  }

  /// The 12 box edges as index pairs into the 8 corners of a `(sx, sy, sz)`
  /// sign lattice, connecting the corners that differ in one sign.
  static const _boxEdges = [
    (0, 1), (0, 2), (0, 4), (1, 3), (1, 5), (2, 3), //
    (2, 6), (3, 7), (4, 5), (4, 6), (5, 7), (6, 7),
  ];

  static final _unitAxes = [
    vm.Vector3(1, 0, 0),
    vm.Vector3(0, 1, 0),
    vm.Vector3(0, 0, 1),
  ];

  /// Draws a circle of [radius] around [axis], offset along that axis.
  static void _ring(
    vm.Vector3 Function(double, double, double) at,
    double radius,
    double offset,
    int axis,
    int segments,
    vm.Vector4? color,
  ) {
    vm.Vector3 point(int i) {
      final a = (i / segments) * 2 * math.pi;
      final c = math.cos(a) * radius;
      final s = math.sin(a) * radius;
      return switch (axis) {
        0 => at(offset, c, s),
        1 => at(c, offset, s),
        _ => at(c, s, offset),
      };
    }

    for (var i = 0; i < segments; i++) {
      line(point(i), point(i + 1), color: color);
    }
  }

  /// Draws the two half arcs closing a capsule end, [dir] being the Y sign of
  /// the cap.
  static void _cap(
    vm.Vector3 Function(double, double, double) at,
    double radius,
    double offset,
    double dir,
    int segments,
    vm.Vector4? color,
  ) {
    final steps = math.max(2, segments ~/ 2);
    for (final acrossZ in const [false, true]) {
      vm.Vector3 point(int i) {
        final a = (i / steps) * math.pi;
        final r = math.cos(a) * radius;
        final y = offset + math.sin(a) * radius * dir;
        return acrossZ ? at(0, y, r) : at(r, y, 0);
      }

      for (var i = 0; i < steps; i++) {
        line(point(i), point(i + 1), color: color);
      }
    }
  }

  /// Draws the four vertical seams joining a capsule or cylinder's end rings.
  static void _sides(
    vm.Vector3 Function(double, double, double) at,
    double radius,
    double halfHeight,
    vm.Vector4? color,
  ) {
    for (final (dx, dz) in const [
      (1.0, 0.0),
      (-1.0, 0.0),
      (0.0, 1.0),
      (0.0, -1.0),
    ]) {
      line(
        at(dx * radius, halfHeight, dz * radius),
        at(dx * radius, -halfHeight, dz * radius),
        color: color,
      );
    }
  }

  /// Total number of line vertices accumulated for the current frame.
  static int get vertexCount => _positions.length ~/ 3;

  /// Creates an empty updatable line geometry for [flushInto].
  static MeshGeometry createGeometry() => MeshGeometry.fromArrays(
    positions: Float32List(0),
    primitiveType: gpu.PrimitiveType.line,
    storage: GeometryStorage.updatable,
  );

  /// Rebuilds [geometry] from the accumulated line segments and clears the
  /// buffer.
  ///
  /// [geometry] is an updatable, non-indexed line geometry, as returned by
  /// [createGeometry]. Its GPU buffers are reused frame to frame, so this is
  /// the path for debug lines redrawn every frame; [flushMesh] allocates a
  /// new geometry per call.
  static void flushInto(MeshGeometry geometry) {
    geometry.rebuild(
      positions: Float32List.fromList(_positions),
      colors: Float32List.fromList(_colors),
    );
    clear();
  }

  /// Builds a new [MeshGeometry] containing all accumulated line segments and
  /// clears the buffer. For lines redrawn every frame, prefer [flushInto].
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
