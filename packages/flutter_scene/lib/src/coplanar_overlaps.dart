import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show internal, visibleForTesting;
import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/geometry/geometry.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/importer/constants.dart'
    show kSkinnedPerVertexSize, kUnskinnedPerVertexSize;
import 'package:flutter_scene/src/node.dart';
import 'package:flutter_scene/src/node_path.dart';
import 'package:flutter_scene/src/render/render_scene.dart';

/// Two surfaces that overlap in one plane (or so nearly that the depth buffer
/// cannot tell them apart from where they are seen), so they flicker against
/// each other (z-fighting).
/// {@category Rendering}
class CoplanarOverlap {
  const CoplanarOverlap({
    required this.nodeA,
    required this.nodeB,
    required this.instanceA,
    required this.instanceB,
    required this.area,
    required this.separation,
    required this.center,
    required this.normal,
    this.hint,
  });

  /// The node owning one surface, or null when its item has no node.
  final Node? nodeA;

  /// The node owning the other surface.
  final Node? nodeB;

  /// The instance index within [nodeA]'s instanced mesh, or null.
  final int? instanceA;

  /// The instance index within [nodeB]'s instanced mesh, or null.
  final int? instanceB;

  /// The overlapping area, in square world units.
  final double area;

  /// The distance between the two planes, zero for an exact overlap.
  final double separation;

  /// The middle of the overlap, in world space.
  final Vector3 center;

  /// The shared plane's normal (the direction the surfaces face).
  final Vector3 normal;

  /// A fix for the common shape this overlap has, when one is recognized
  /// (a repeated piece longer than the spacing between pieces).
  final String? hint;

  /// Whether the surfaces lie in exactly one plane, so they fight at any
  /// distance and no depth setting separates them.
  bool get exact => separation < kCoplanarExactTolerance;

  /// One line naming the pair, the overlap, and the fix.
  String describe() {
    String label(Node? node, int? instance) {
      final name = node == null ? '(unnamed)' : "'${debugNodePath(node)}'";
      return instance == null ? name : '$name #$instance';
    }

    final where =
        '(${center.x.toStringAsFixed(1)}, ${center.y.toStringAsFixed(1)}, '
        '${center.z.toStringAsFixed(1)})';
    final gap = exact
        ? 'in one plane'
        : '${(separation * 1000).toStringAsFixed(1)} mm apart';
    return '${label(nodeA, instanceA)} and ${label(nodeB, instanceB)} '
        'overlap ${area.toStringAsFixed(2)} m² $gap at $where'
        '${hint == null ? '' : '. $hint'}';
  }
}

/// Planes closer than this (world units) count as one plane.
const double kCoplanarExactTolerance = 0.001;

/// Faces whose normals differ by more than this many degrees are not
/// parallel.
const double kCoplanarAngleDegrees = 2.0;

/// Overlaps smaller than this (square world units) are not reported.
const double kCoplanarMinArea = 0.01;

/// Triangles one item may contribute; denser meshes are skipped.
const int _kMaxTrianglesPerItem = 20000;

/// Triangle pairs one plane pair may test exactly before its area is
/// estimated from bounds.
const int _kMaxTrianglePairs = 4096;

/// Finds faces from different items (or instances) that overlap in one plane,
/// or that sit closer than [separationAt] allows at their distance from
/// [eye]. Pairs whose `Material.depthLayer` differs are skipped, since the
/// layer resolves them.
@internal
List<CoplanarOverlap> findCoplanarOverlaps(
  Iterable<RenderItem> items, {
  Vector3? eye,
  double Function(double distance)? separationAt,
}) {
  final scan = CoplanarOverlapScan(items, eye: eye, separationAt: separationAt);
  scan.advance();
  return scan.result!;
}

/// [findCoplanarOverlaps] in slices, so a caller on the UI isolate can spread
/// a large scene's scan over frames. It works on the items as they stand at
/// each slice; [result] holds the overlaps once [advance] reports the end.
@internal
class CoplanarOverlapScan {
  CoplanarOverlapScan(
    Iterable<RenderItem> items, {
    Vector3? eye,
    double Function(double distance)? separationAt,
  }) {
    _steps = _scan(
      List.of(items),
      eye == null ? null : Vector3.copy(eye),
      separationAt,
    ).iterator;
  }

  late final Iterator<void> _steps;
  List<CoplanarOverlap>? _result;

  /// The overlaps, largest first, once the scan has finished.
  List<CoplanarOverlap>? get result => _result;

  /// Runs the scan for about [budget] (to the end without one) and returns
  /// whether it has finished.
  bool advance([Duration? budget]) {
    final watch = budget == null ? null : (Stopwatch()..start());
    while (_result == null && _steps.moveNext()) {
      if (watch != null && watch.elapsed >= budget!) break;
    }
    return _result != null;
  }

  // Yields between slices of work small enough to stay well inside a frame.
  Iterable<void> _scan(
    List<RenderItem> items,
    Vector3? eye,
    double Function(double distance)? separationAt,
  ) sync* {
    final groups = <_PlaneGroup>[];
    for (final item in items) {
      if (!item.drawsColor || item.material.drawsNothing) continue;
      if (item.material.depthCompare == gpu.CompareFunction.always) continue;
      final geometry = item.geometry;
      if (geometry.primitiveType != gpu.PrimitiveType.triangle) continue;
      final triangles = _localTriangles(geometry);
      if (triangles == null) continue;
      yield null;
      final instances = item.instanceTransforms;
      if (instances == null) {
        yield* _collectGroups(
          groups,
          item,
          null,
          item.worldTransform,
          triangles,
        );
      } else {
        final world = Matrix4.zero();
        for (var i = 0; i < instances.length; i++) {
          world
            ..setFrom(item.worldTransform)
            ..multiply(instances[i]);
          yield* _collectGroups(groups, item, i, world, triangles);
        }
      }
    }

    // Sort and sweep along x for groups whose bounds overlap.
    groups.sort((a, b) => a.min.x.compareTo(b.min.x));
    final cosAngle = math.cos(kCoplanarAngleDegrees * degrees2Radians);
    final limit = eye == null ? null : separationAt;
    final overlaps = <CoplanarOverlap>[];
    var work = 0;
    for (var i = 0; i < groups.length; i++) {
      final a = groups[i];
      // Bounds are apart by at most the planes' separation where faces
      // overlap, and the separation that still fights shrinks toward the
      // eye, so a's own distance bounds the sweep.
      final slack = limit == null
          ? kCoplanarExactTolerance
          : math.max(kCoplanarExactTolerance, limit(a.distanceTo(eye!)));
      for (var j = i + 1; j < groups.length; j++) {
        if (++work % 1024 == 0) yield null;
        final b = groups[j];
        if (b.min.x > a.max.x + slack) break;
        if (identical(a.item, b.item) && a.instance == b.instance) continue;
        if (a.normal.dot(b.normal) < cosAngle) continue;
        final separation = (a.offset - b.offset).abs();
        if (separation >= slack) continue;
        final pad = separation + kCoplanarExactTolerance;
        if (b.min.y > a.max.y + pad || b.max.y < a.min.y - pad) continue;
        if (b.min.z > a.max.z + pad || b.max.z < a.min.z - pad) continue;
        if (separation >= kCoplanarExactTolerance) {
          final distance = math.min(a.distanceTo(eye!), b.distanceTo(eye));
          if (separation >= limit!(distance)) continue;
        }
        if (a.item.material.depthLayer != b.item.material.depthLayer) continue;
        final overlap = _overlapArea(a, b);
        yield null;
        if (overlap.area < kCoplanarMinArea) continue;
        overlaps.add(
          CoplanarOverlap(
            nodeA: a.item.sourceNode is Node ? a.item.sourceNode as Node : null,
            nodeB: b.item.sourceNode is Node ? b.item.sourceNode as Node : null,
            instanceA: a.instance,
            instanceB: b.instance,
            area: overlap.area,
            separation: separation,
            center: overlap.center,
            normal: a.normal.clone(),
            hint: _pitchHint(a, b),
          ),
        );
      }
    }
    overlaps.sort((x, y) => y.area.compareTo(x.area));
    _result = overlaps;
  }
}

/// A summary of [overlaps] for the debug log, grouped by node pair, or null
/// when there are none.
@internal
String? describeCoplanarOverlaps(List<CoplanarOverlap> overlaps) {
  if (overlaps.isEmpty) return null;
  final byPair = <String, List<CoplanarOverlap>>{};
  for (final overlap in overlaps) {
    String name(Node? node) => node == null ? '(unnamed)' : debugNodePath(node);
    final key = [name(overlap.nodeA), name(overlap.nodeB)]..sort();
    byPair.putIfAbsent(key.join(' and '), () => []).add(overlap);
  }
  final pairs = byPair.entries.toList()
    ..sort((x, y) => y.value.length.compareTo(x.value.length));
  final lines = [
    'flutter_scene: ${overlaps.length} surface overlap'
        '${overlaps.length == 1 ? '' : 's'} in one plane will flicker '
        '(z-fighting) at any distance. Separate the surfaces, make repeated '
        'pieces abut, or give the one that belongs on top a higher '
        'Material.depthLayer.',
  ];
  for (final pair in pairs.take(5)) {
    final first = pair.value.first;
    final count = pair.value.length;
    lines.add(
      "  '${pair.key}': $count overlap${count == 1 ? '' : 's'}, "
      'largest ${first.area.toStringAsFixed(2)} m²'
      '${first.hint == null ? '' : '. ${first.hint}'}',
    );
  }
  if (pairs.length > 5) lines.add('  and ${pairs.length - 5} more pairs');
  lines.add('  Scene.findCoplanarOverlaps() lists every overlap.');
  return lines.join('\n');
}

// One item-instance's triangles that share one plane, in world space.
class _PlaneGroup {
  _PlaneGroup(this.item, this.instance, this.normal, this.offset);

  final RenderItem item;
  final int? instance;
  final Vector3 normal;
  final double offset;
  final Vector3 min = Vector3.all(double.infinity);
  final Vector3 max = Vector3.all(double.negativeInfinity);
  // World-space triangle corners, nine floats per triangle.
  final List<double> corners = [];
  // The instance transform's translation and the item's geometry, for the
  // spacing hint.
  Vector3 origin = Vector3.zero();
  Matrix4 transform = Matrix4.identity();

  double distanceTo(Vector3 eye) {
    final dx = eye.x < min.x
        ? min.x - eye.x
        : (eye.x > max.x ? eye.x - max.x : 0.0);
    final dy = eye.y < min.y
        ? min.y - eye.y
        : (eye.y > max.y ? eye.y - max.y : 0.0);
    final dz = eye.z < min.z
        ? min.z - eye.z
        : (eye.z > max.z ? eye.z - max.z : 0.0);
    return math.sqrt(dx * dx + dy * dy + dz * dz);
  }
}

// Local-space triangle corners of [geometry], nine floats per triangle, or
// null when it keeps no CPU data or is too dense to check.
Float32List? _localTriangles(Geometry geometry) {
  final data = geometry.cpuMeshData;
  if (data.vertexCount == 0) return null;
  final positions = data.positions;
  final vertices = data.vertices;
  int? stride;
  if (positions == null) {
    if (vertices == null) return null;
    stride = vertices.lengthInBytes ~/ data.vertexCount;
    if (stride != kUnskinnedPerVertexSize && stride != kSkinnedPerVertexSize) {
      return null;
    }
  }
  final indices = data.indices;
  final count = indices == null ? data.vertexCount : data.indexCount;
  final triangleCount = count ~/ 3;
  if (triangleCount == 0 || triangleCount > _kMaxTrianglesPerItem) return null;
  int indexAt(int i) {
    if (indices == null) return i;
    return data.indexType == gpu.IndexType.int16
        ? indices.getUint16(i * 2, Endian.little)
        : indices.getUint32(i * 4, Endian.little);
  }

  final out = Float32List(triangleCount * 9);
  for (var i = 0; i < triangleCount * 3; i++) {
    final v = indexAt(i);
    if (positions != null) {
      out[i * 3] = positions[v * 3];
      out[i * 3 + 1] = positions[v * 3 + 1];
      out[i * 3 + 2] = positions[v * 3 + 2];
    } else {
      final o = v * stride!;
      out[i * 3] = vertices!.getFloat32(o, Endian.little);
      out[i * 3 + 1] = vertices.getFloat32(o + 4, Endian.little);
      out[i * 3 + 2] = vertices.getFloat32(o + 8, Endian.little);
    }
  }
  return out;
}

// Plane cells for grouping, over twice the grouping tolerances so a value
// is near at most one cell edge: unit normals within kCoplanarAngleDegrees
// differ by under 0.035 per component, and grouped offsets by under
// kCoplanarExactTolerance.
const double _kNormalCell = 1.0 / 8.0;
const double _kNormalTolerance = 0.035;
const double _kOffsetCell = 0.01;

/// Plane comparisons the grouping has made, for tests that check it stays
/// linear in triangles.
@visibleForTesting
int debugCoplanarPlaneComparisons = 0;

// One key per cell: normal indices span [-9, 9], offsets any integer.
int _cellKey(int x, int y, int z, int offset) =>
    ((offset * 19 + x + 9) * 19 + y + 9) * 19 + z + 9;

// Groups [triangles] (local space) of one item-instance by world plane,
// yielding every few hundred triangles. Each plane lives in the cell of its
// first triangle; a triangle searches its own cell, and the neighbor across
// any cell edge it sits within tolerance of, so the search stays local
// without splitting a plane at a cell edge.
Iterable<void> _collectGroups(
  List<_PlaneGroup> groups,
  RenderItem item,
  int? instance,
  Matrix4 world,
  Float32List triangles,
) sync* {
  final cells = <int, List<_PlaneGroup>>{};
  final p0 = Vector3.zero(), p1 = Vector3.zero(), p2 = Vector3.zero();
  final cosAngle = math.cos(kCoplanarAngleDegrees * degrees2Radians);
  // A mirroring transform flips the winding; keep the facing it renders.
  final mirrored = world.determinant() < 0;
  final index = Int32List(4);
  final reach = Int32List(4);
  // Shared by this item-instance's groups, for the spacing hint.
  Matrix4? transform;
  Vector3? origin;
  for (var t = 0; t < triangles.length; t += 9) {
    if (t % 2304 == 0) yield null;
    p0.setValues(triangles[t], triangles[t + 1], triangles[t + 2]);
    p1.setValues(triangles[t + 3], triangles[t + 4], triangles[t + 5]);
    p2.setValues(triangles[t + 6], triangles[t + 7], triangles[t + 8]);
    world
      ..transform3(p0)
      ..transform3(p1)
      ..transform3(p2);
    final normal = (p1 - p0).cross(p2 - p0);
    final length = normal.length;
    // Also skips a degenerate transform's non-finite positions.
    if (!(length >= 1e-9)) continue;
    normal.scale(1.0 / length);
    if (mirrored) normal.negate();
    final offset = normal.dot(p0);
    if (!offset.isFinite) continue;
    final values = [normal.x, normal.y, normal.z, offset];
    for (var d = 0; d < 4; d++) {
      final cell = d < 3 ? _kNormalCell : _kOffsetCell;
      final tolerance = d < 3 ? _kNormalTolerance : kCoplanarExactTolerance;
      final position = values[d] / cell;
      index[d] = position.floor();
      final fraction = position - index[d];
      reach[d] = fraction * cell < tolerance
          ? -1
          : ((1 - fraction) * cell < tolerance ? 1 : 0);
    }
    _PlaneGroup? group;
    search:
    for (var dx = 0; dx < (reach[0] == 0 ? 1 : 2); dx++) {
      for (var dy = 0; dy < (reach[1] == 0 ? 1 : 2); dy++) {
        for (var dz = 0; dz < (reach[2] == 0 ? 1 : 2); dz++) {
          for (var dO = 0; dO < (reach[3] == 0 ? 1 : 2); dO++) {
            final candidates =
                cells[_cellKey(
                  index[0] + dx * reach[0],
                  index[1] + dy * reach[1],
                  index[2] + dz * reach[2],
                  index[3] + dO * reach[3],
                )];
            if (candidates == null) continue;
            for (final candidate in candidates) {
              debugCoplanarPlaneComparisons++;
              if (candidate.normal.dot(normal) >= cosAngle &&
                  (candidate.offset - offset).abs() < kCoplanarExactTolerance) {
                group = candidate;
                break search;
              }
            }
          }
        }
      }
    }
    if (group == null) {
      group = _PlaneGroup(item, instance, normal, offset)
        ..origin = (origin ??= world.getTranslation())
        ..transform = (transform ??= Matrix4.copy(world));
      cells
          .putIfAbsent(
            _cellKey(index[0], index[1], index[2], index[3]),
            () => [],
          )
          .add(group);
      groups.add(group);
    }
    for (final p in [p0, p1, p2]) {
      group.corners
        ..add(p.x)
        ..add(p.y)
        ..add(p.z);
      group.min.setValues(
        math.min(group.min.x, p.x),
        math.min(group.min.y, p.y),
        math.min(group.min.z, p.z),
      );
      group.max.setValues(
        math.max(group.max.x, p.x),
        math.max(group.max.y, p.y),
        math.max(group.max.z, p.z),
      );
    }
  }
}

// The area where [a] and [b] overlap in [a]'s plane, and its center.
({double area, Vector3 center}) _overlapArea(_PlaneGroup a, _PlaneGroup b) {
  final n = a.normal;
  // A basis in the plane.
  final helper = n.x.abs() < 0.9 ? Vector3(1, 0, 0) : Vector3(0, 1, 0);
  final u = n.cross(helper)..normalize();
  final v = n.cross(u)..normalize();
  List<List<double>> project(_PlaneGroup g) {
    final out = <List<double>>[];
    for (var t = 0; t < g.corners.length; t += 9) {
      final tri = <double>[];
      for (var k = 0; k < 9; k += 3) {
        final x = g.corners[t + k], y = g.corners[t + k + 1];
        final z = g.corners[t + k + 2];
        tri
          ..add(x * u.x + y * u.y + z * u.z)
          ..add(x * v.x + y * v.y + z * v.z);
      }
      out.add(tri);
    }
    return out;
  }

  final trisA = project(a);
  final trisB = project(b);
  var area = 0.0;
  var cx = 0.0, cy = 0.0;
  if (trisA.length * trisB.length <= _kMaxTrianglePairs) {
    for (final ta in trisA) {
      for (final tb in trisB) {
        final clipped = clipConvexPolygons(ta, tb);
        final polygonArea = polygonAreaAndCentroid(clipped);
        area += polygonArea.area;
        cx += polygonArea.cx * polygonArea.area;
        cy += polygonArea.cy * polygonArea.area;
      }
    }
  } else {
    // Too dense to clip pairwise; take the overlap of the projected bounds.
    double minOf(List<List<double>> tris, int axis) => tris
        .expand((t) => [t[axis], t[axis + 2], t[axis + 4]])
        .reduce(math.min);
    double maxOf(List<List<double>> tris, int axis) => tris
        .expand((t) => [t[axis], t[axis + 2], t[axis + 4]])
        .reduce(math.max);
    final x0 = math.max(minOf(trisA, 0), minOf(trisB, 0));
    final x1 = math.min(maxOf(trisA, 0), maxOf(trisB, 0));
    final y0 = math.max(minOf(trisA, 1), minOf(trisB, 1));
    final y1 = math.min(maxOf(trisA, 1), maxOf(trisB, 1));
    if (x1 > x0 && y1 > y0) {
      area = (x1 - x0) * (y1 - y0);
      cx = (x0 + x1) * 0.5 * area;
      cy = (y0 + y1) * 0.5 * area;
    }
  }
  if (area <= 0) return (area: 0.0, center: Vector3.zero());
  cx /= area;
  cy /= area;
  return (area: area, center: u * cx + v * cy + n * a.offset);
}

// "Pieces 8.4 m long placed 8.0 m apart": two instances of one geometry whose
// overlap is their length past their spacing.
String? _pitchHint(_PlaneGroup a, _PlaneGroup b) {
  if (!identical(a.item.geometry, b.item.geometry)) return null;
  final bounds = a.item.geometry.localBounds;
  if (bounds == null) return null;
  final step = b.origin - a.origin;
  final spacing = step.length;
  if (spacing < 1e-6) return null;
  // The piece's length along the step, from its world-space axes.
  final m = a.transform.storage;
  final extent = bounds.max - bounds.min;
  final axes = [
    Vector3(m[0], m[1], m[2])..scale(extent.x),
    Vector3(m[4], m[5], m[6])..scale(extent.y),
    Vector3(m[8], m[9], m[10])..scale(extent.z),
  ];
  final direction = step / spacing;
  var length = 0.0;
  for (final axis in axes) {
    length += axis.dot(direction).abs();
  }
  if (length <= spacing + kCoplanarExactTolerance) return null;
  String metres(double value) => value.toStringAsFixed(value < 10 ? 2 : 1);
  return 'Pieces ${metres(length)} m long are placed ${metres(spacing)} m '
      'apart, so neighbors overlap ${metres(length - spacing)} m; make them '
      '${metres(spacing)} m long';
}

/// The intersection of two convex polygons given as flat `x, y` lists
/// (Sutherland-Hodgman), as a flat list.
@visibleForTesting
List<double> clipConvexPolygons(List<double> subject, List<double> clip) {
  var output = List<double>.of(subject);
  // Orient the clip polygon counterclockwise.
  var clipPoints = List<double>.of(clip);
  if (_signedArea(clipPoints) < 0) {
    final reversed = <double>[];
    for (var i = clipPoints.length - 2; i >= 0; i -= 2) {
      reversed
        ..add(clipPoints[i])
        ..add(clipPoints[i + 1]);
    }
    clipPoints = reversed;
  }
  final n = clipPoints.length ~/ 2;
  for (var e = 0; e < n && output.isNotEmpty; e++) {
    final ax = clipPoints[e * 2], ay = clipPoints[e * 2 + 1];
    final bx = clipPoints[((e + 1) % n) * 2];
    final by = clipPoints[((e + 1) % n) * 2 + 1];
    bool inside(double x, double y) =>
        (bx - ax) * (y - ay) - (by - ay) * (x - ax) >= -1e-12;
    final input = output;
    output = <double>[];
    final m = input.length ~/ 2;
    for (var i = 0; i < m; i++) {
      final px = input[i * 2], py = input[i * 2 + 1];
      final qx = input[((i + 1) % m) * 2], qy = input[((i + 1) % m) * 2 + 1];
      final pIn = inside(px, py), qIn = inside(qx, qy);
      if (pIn) output.addAll([px, py]);
      if (pIn != qIn) {
        // Intersect segment pq with the clip edge's line.
        final dx = qx - px, dy = qy - py;
        final ex = bx - ax, ey = by - ay;
        final denominator = ex * dy - ey * dx;
        if (denominator.abs() > 1e-18) {
          final t = (ey * (px - ax) - ex * (py - ay)) / denominator;
          output.addAll([px + dx * t, py + dy * t]);
        }
      }
    }
  }
  return output;
}

double _signedArea(List<double> points) {
  var sum = 0.0;
  final n = points.length ~/ 2;
  for (var i = 0; i < n; i++) {
    final j = (i + 1) % n;
    sum +=
        points[i * 2] * points[j * 2 + 1] - points[j * 2] * points[i * 2 + 1];
  }
  return sum * 0.5;
}

/// The area and centroid of a simple polygon given as a flat `x, y` list.
@visibleForTesting
({double area, double cx, double cy}) polygonAreaAndCentroid(
  List<double> points,
) {
  final n = points.length ~/ 2;
  if (n < 3) return (area: 0.0, cx: 0.0, cy: 0.0);
  var area2 = 0.0, cx = 0.0, cy = 0.0;
  for (var i = 0; i < n; i++) {
    final j = (i + 1) % n;
    final cross =
        points[i * 2] * points[j * 2 + 1] - points[j * 2] * points[i * 2 + 1];
    area2 += cross;
    cx += (points[i * 2] + points[j * 2]) * cross;
    cy += (points[i * 2 + 1] + points[j * 2 + 1]) * cross;
  }
  if (area2.abs() < 1e-18) return (area: 0.0, cx: 0.0, cy: 0.0);
  return (area: area2.abs() * 0.5, cx: cx / (3 * area2), cy: cy / (3 * area2));
}
