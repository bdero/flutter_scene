/// The `checkDepthLayering` query: faces of different meshes that overlap in
/// one plane, which flicker against each other (z-fighting) at any distance.
///
/// The document-side counterpart of the engine's `Scene.findCoplanarOverlaps`,
/// over procedural cuboids and planes and unskinned triangle payloads, so a
/// tool can check a scene it built without a renderer.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:scene/scene.dart';
import 'package:vector_math/vector_math.dart';

import 'command.dart';
import 'queries.dart';

// Planes closer than this (meters) count as one plane.
const double _kPlaneTolerance = 0.001;

// Faces whose normals differ by more than this many degrees are not parallel.
const double _kAngleDegrees = 2.0;

// Triangles one primitive may contribute; denser meshes are skipped.
const int _kMaxTriangles = 20000;

// Triangle pairs one plane pair may clip before its overlap is estimated from
// bounds.
const int _kMaxTrianglePairs = 4096;

// Interleaved (true) or structure-of-arrays (false) unskinned layouts and
// their vertex sizes in bytes; position is the first attribute in each.
const Map<String, (int, bool)> _layouts = {
  'unskinned': (48, true),
  'unskinned_uv1_tangent': (72, true),
  'unskinned_soa': (48, false),
  'unskinned_soa_uv1_tangent': (72, false),
};

/// Faces of different meshes that overlap in one plane.
final checkDepthLayering = QueryEntry(
  name: 'checkDepthLayering',
  doc:
      'Find faces of different meshes that overlap in one plane, which '
      'flicker against each other (z-fighting) at any distance. Covers '
      'procedural cuboids and planes and unskinned triangle meshes. Each '
      'overlap names its nodes, area, and center, and for repeated pieces '
      'longer than their spacing, the length that fixes them. Pairs whose '
      'materials set different depthLayer values are left out, since the '
      'layer resolves them.',
  category: 'Scene',
  paramSchema: const [
    ParamSpec(
      name: 'minArea',
      type: ParamType.number,
      label: 'Minimum area',
      description: 'The smallest overlap to report, in square meters',
      required: false,
      defaultValue: 0.01,
    ),
    ParamSpec(
      name: 'limit',
      type: ParamType.integer,
      label: 'Limit',
      description: 'The most overlaps to list',
      required: false,
      defaultValue: 50,
    ),
  ],
  read: (ctx, params) {
    final minArea = params['minArea'];
    if (minArea != null && minArea is! num) {
      throw const QueryException('"minArea" must be a number');
    }
    final limit = params['limit'];
    if (limit != null && limit is! int) {
      throw const QueryException('"limit" must be an integer');
    }
    final overlaps = findDocumentCoplanarOverlaps(
      ctx.document,
      minArea: (minArea as num?)?.toDouble() ?? 0.01,
    );
    String? path(LocalId id) => ctx.query.namePathOf(id);
    Map<String, double> vector(Vector3 v) => {'x': v.x, 'y': v.y, 'z': v.z};
    return QueryResult({
      'overlapCount': overlaps.length,
      'overlaps': [
        for (final overlap in overlaps.take((limit as int?) ?? 50))
          {
            'nodeA': overlap.nodeA.toToken(),
            'nodeB': overlap.nodeB.toToken(),
            'pathA': path(overlap.nodeA),
            'pathB': path(overlap.nodeB),
            'area': overlap.area,
            'center': vector(overlap.center),
            'normal': vector(overlap.normal),
            if (overlap.hint != null) 'hint': overlap.hint,
          },
      ],
      'summary': _summary(overlaps, path),
    });
  },
);

/// Two faces of different meshes in [SceneDocument] that overlap in one
/// plane.
class DocumentCoplanarOverlap {
  /// Creates an overlap record.
  const DocumentCoplanarOverlap({
    required this.nodeA,
    required this.nodeB,
    required this.area,
    required this.center,
    required this.normal,
    this.hint,
  });

  /// The node owning one face.
  final LocalId nodeA;

  /// The node owning the other.
  final LocalId nodeB;

  /// The overlapping area, in square meters.
  final double area;

  /// The middle of the overlap, in world space.
  final Vector3 center;

  /// The shared plane's normal.
  final Vector3 normal;

  /// The fix for a repeated piece longer than its spacing, when recognized.
  final String? hint;
}

/// Every pair of faces of different meshes in [document] that overlap in one
/// plane by at least [minArea] square meters, largest first. Pairs whose
/// materials set different `depthLayer` values, and hidden nodes, are left
/// out. Meshes sharing a material still count, since vertex colors, texture
/// coordinates, or normals can still tell their pixels apart.
List<DocumentCoplanarOverlap> findDocumentCoplanarOverlaps(
  SceneDocument document, {
  double minArea = 0.01,
}) {
  final parents = <LocalId, LocalId>{};
  for (final node in document.nodes.values) {
    for (final child in node.children) {
      parents[child] = node.id;
    }
  }
  final worlds = <LocalId, Matrix4>{};
  Matrix4 worldOf(LocalId id) {
    final cached = worlds[id];
    if (cached != null) return cached;
    final node = document.nodes[id];
    if (node == null) return Matrix4.identity();
    final local = node.transform.toMatrix4();
    final parent = parents[id];
    return worlds[id] = parent == null
        ? local
        : worldOf(parent).multiplied(local);
  }

  bool visible(LocalId id) {
    for (LocalId? current = id; current != null; current = parents[current]) {
      if (document.nodes[current]?.visible == false) return false;
    }
    return true;
  }

  final groups = <_PlaneGroup>[];
  for (final node in document.nodes.values) {
    if (!visible(node.id)) continue;
    for (final component in node.components) {
      if (component.type != 'mesh') continue;
      for (final (geometryId, materialId) in _primitives(component)) {
        final geometry = document.resources[geometryId];
        if (geometry is! GeometryResource) continue;
        final triangles = _localTriangles(document, geometry);
        if (triangles == null) continue;
        final material = document.resources[materialId];
        final layer = material is MaterialResource
            ? switch (material.properties['depthLayer']) {
                IntValue(:final value) => value,
                _ => 0,
              }
            : 0;
        _collectGroups(
          groups,
          _Source(node.id, geometryId, materialId, layer, geometry),
          worldOf(node.id),
          triangles,
        );
      }
    }
  }

  groups.sort((a, b) => a.min.x.compareTo(b.min.x));
  final cosAngle = math.cos(_kAngleDegrees * degrees2Radians);
  final overlaps = <DocumentCoplanarOverlap>[];
  for (var i = 0; i < groups.length; i++) {
    final a = groups[i];
    for (var j = i + 1; j < groups.length; j++) {
      final b = groups[j];
      if (b.min.x > a.max.x + _kPlaneTolerance) break;
      if (identical(a.source, b.source)) continue;
      if (a.source.node == b.source.node) continue;
      if (a.source.layer != b.source.layer) continue;
      if (a.normal.dot(b.normal) < cosAngle) continue;
      if ((a.offset - b.offset).abs() >= _kPlaneTolerance) continue;
      if (b.min.y > a.max.y + _kPlaneTolerance ||
          b.max.y < a.min.y - _kPlaneTolerance ||
          b.min.z > a.max.z + _kPlaneTolerance ||
          b.max.z < a.min.z - _kPlaneTolerance) {
        continue;
      }
      final overlap = _overlapArea(a, b);
      if (overlap.area < minArea) continue;
      overlaps.add(
        DocumentCoplanarOverlap(
          nodeA: a.source.node,
          nodeB: b.source.node,
          area: overlap.area,
          center: overlap.center,
          normal: a.normal.clone(),
          hint: _pitchHint(a, b),
        ),
      );
    }
  }
  overlaps.sort((x, y) => y.area.compareTo(x.area));
  return overlaps;
}

String? _summary(
  List<DocumentCoplanarOverlap> overlaps,
  String? Function(LocalId id) path,
) {
  if (overlaps.isEmpty) return null;
  final byPair = <String, List<DocumentCoplanarOverlap>>{};
  for (final overlap in overlaps) {
    final key = [
      path(overlap.nodeA) ?? overlap.nodeA.toToken(),
      path(overlap.nodeB) ?? overlap.nodeB.toToken(),
    ]..sort();
    byPair.putIfAbsent(key.join(' and '), () => []).add(overlap);
  }
  final pairs = byPair.entries.toList()
    ..sort((x, y) => y.value.length.compareTo(x.value.length));
  return [
    '${overlaps.length} surface overlap${overlaps.length == 1 ? '' : 's'} in '
        'one plane will flicker (z-fighting) at any distance. Separate the '
        'surfaces, make repeated pieces abut, or give the one that belongs on '
        'top a higher depthLayer.',
    for (final pair in pairs.take(5))
      "  '${pair.key}': ${pair.value.length} overlap"
          "${pair.value.length == 1 ? '' : 's'}, largest "
          '${pair.value.first.area.toStringAsFixed(2)} m²'
          '${pair.value.first.hint == null ? '' : '. ${pair.value.first.hint}'}',
    if (pairs.length > 5) '  and ${pairs.length - 5} more pairs',
  ].join('\n');
}

// The (geometry, material) pairs a mesh component draws.
List<(LocalId, LocalId)> _primitives(ComponentSpec component) {
  final list = component.properties['primitives'];
  if (list is ListValue) {
    return [
      for (final entry in list.values)
        if (entry is MapValue &&
            entry.values['geometry'] is ResourceRefValue &&
            entry.values['material'] is ResourceRefValue)
          (
            (entry.values['geometry']! as ResourceRefValue).id,
            (entry.values['material']! as ResourceRefValue).id,
          ),
    ];
  }
  final geometry = component.properties['geometry'];
  final material = component.properties['material'];
  if (geometry is! ResourceRefValue || material is! ResourceRefValue) {
    return const [];
  }
  return [(geometry.id, material.id)];
}

// Local-space triangle corners of [geometry], nine floats per triangle, or
// null when it is curved, skinned, too dense, or its bytes are not loaded.
Float64List? _localTriangles(
  SceneDocument document,
  GeometryResource geometry,
) {
  final procedural = geometry.procedural;
  if (procedural is CuboidGeometrySpec) {
    final h = procedural.extents / 2;
    final corners = [
      for (final z in [-h.z, h.z])
        for (final y in [-h.y, h.y])
          for (final x in [-h.x, h.x]) Vector3(x, y, z),
    ];
    // Faces as quads of corner indices, counterclockwise seen from outside.
    const faces = [
      [0, 2, 3, 1],
      [4, 5, 7, 6],
      [0, 4, 6, 2],
      [1, 3, 7, 5],
      [0, 1, 5, 4],
      [2, 6, 7, 3],
    ];
    return Float64List.fromList([
      for (final f in faces)
        for (final i in [f[0], f[1], f[2], f[0], f[2], f[3]]) ...[
          corners[i].x,
          corners[i].y,
          corners[i].z,
        ],
    ]);
  }
  if (procedural is PlaneGeometrySpec) {
    final w = procedural.width / 2;
    final d = procedural.depth / 2;
    // Facing +Y, counterclockwise seen from above.
    return Float64List.fromList([
      ...[-w, 0.0, -d, -w, 0.0, d, w, 0.0, d],
      ...[-w, 0.0, -d, w, 0.0, d, w, 0.0, -d],
    ]);
  }
  if (procedural != null || geometry.topology != 'triangle') return null;
  final vertexPayload = document.payloads[geometry.vertices];
  final bytes = vertexPayload?.bytes;
  final layout = _layouts[vertexPayload?.layout];
  if (bytes == null || layout == null) return null;
  final (stride, interleaved) = layout;
  final vertexCount = bytes.lengthInBytes ~/ stride;
  final data = ByteData.sublistView(bytes);
  List<int>? indices;
  if (geometry.indices != null) {
    final indexPayload = document.payloads[geometry.indices];
    final indexBytes = indexPayload?.bytes;
    if (indexBytes == null) return null;
    indices = indexPayload!.format == 'uint32'
        ? Uint32List.sublistView(indexBytes)
        : Uint16List.sublistView(indexBytes);
  }
  final count = indices?.length ?? vertexCount;
  final triangleCount = count ~/ 3;
  if (triangleCount == 0 || triangleCount > _kMaxTriangles) return null;
  final out = Float64List(triangleCount * 9);
  for (var i = 0; i < triangleCount * 3; i++) {
    final v = indices?[i] ?? i;
    if (v >= vertexCount) return null;
    final offset = interleaved ? v * stride : v * 12;
    for (var k = 0; k < 3; k++) {
      out[i * 3 + k] = data.getFloat32(offset + k * 4, Endian.little);
    }
  }
  return out;
}

// What a plane group came from.
class _Source {
  _Source(this.node, this.geometry, this.material, this.layer, this.spec);

  final LocalId node;
  final LocalId geometry;
  final LocalId material;
  final int layer;
  final GeometryResource spec;
}

// One primitive's triangles that share one plane, in world space.
class _PlaneGroup {
  _PlaneGroup(this.source, this.normal, this.offset, this.transform);

  final _Source source;
  final Vector3 normal;
  final double offset;
  final Matrix4 transform;
  final Vector3 min = Vector3.all(double.infinity);
  final Vector3 max = Vector3.all(double.negativeInfinity);
  // World-space triangle corners, nine floats per triangle.
  final List<double> corners = [];
}

// Plane cells for grouping, over twice the grouping tolerances so a value
// is near at most one cell edge: unit normals within _kAngleDegrees differ by
// under 0.035 per component, and grouped offsets by under _kPlaneTolerance.
const double _kNormalCell = 1.0 / 8.0;
const double _kNormalTolerance = 0.035;
const double _kOffsetCell = 0.01;

// One key per cell: normal indices span [-9, 9], offsets any integer.
int _cellKey(int x, int y, int z, int offset) =>
    ((offset * 19 + x + 9) * 19 + y + 9) * 19 + z + 9;

// Groups one primitive's triangles by world plane. Each plane lives in the
// cell of its first triangle; a triangle searches its own cell, and the
// neighbor across any cell edge it sits within tolerance of, so the search
// stays local without splitting a plane at a cell edge.
void _collectGroups(
  List<_PlaneGroup> groups,
  _Source source,
  Matrix4 world,
  Float64List triangles,
) {
  final cells = <int, List<_PlaneGroup>>{};
  final cosAngle = math.cos(_kAngleDegrees * degrees2Radians);
  final mirrored = world.determinant() < 0;
  final p = [Vector3.zero(), Vector3.zero(), Vector3.zero()];
  final index = Int32List(4);
  final reach = Int32List(4);
  for (var t = 0; t < triangles.length; t += 9) {
    for (var k = 0; k < 3; k++) {
      p[k]
        ..setValues(
          triangles[t + k * 3],
          triangles[t + k * 3 + 1],
          triangles[t + k * 3 + 2],
        )
        ..applyMatrix4(world);
    }
    final normal = (p[1] - p[0]).cross(p[2] - p[0]);
    final length = normal.length;
    // Also skips a degenerate transform's non-finite positions.
    if (!(length >= 1e-9)) continue;
    normal.scale(mirrored ? -1.0 / length : 1.0 / length);
    final offset = normal.dot(p[0]);
    if (!offset.isFinite) continue;
    final values = [normal.x, normal.y, normal.z, offset];
    for (var d = 0; d < 4; d++) {
      final cell = d < 3 ? _kNormalCell : _kOffsetCell;
      final tolerance = d < 3 ? _kNormalTolerance : _kPlaneTolerance;
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
              if (candidate.normal.dot(normal) >= cosAngle &&
                  (candidate.offset - offset).abs() < _kPlaneTolerance) {
                group = candidate;
                break search;
              }
            }
          }
        }
      }
    }
    if (group == null) {
      group = _PlaneGroup(source, normal, offset, world);
      cells
          .putIfAbsent(
            _cellKey(index[0], index[1], index[2], index[3]),
            () => [],
          )
          .add(group);
      groups.add(group);
    }
    for (final corner in p) {
      group.corners
        ..add(corner.x)
        ..add(corner.y)
        ..add(corner.z);
      Vector3.min(group.min, corner, group.min);
      Vector3.max(group.max, corner, group.max);
    }
  }
}

// The area where [a] and [b] overlap in [a]'s plane, and its center.
({double area, Vector3 center}) _overlapArea(_PlaneGroup a, _PlaneGroup b) {
  final n = a.normal;
  final helper = n.x.abs() < 0.9 ? Vector3(1, 0, 0) : Vector3(0, 1, 0);
  final u = n.cross(helper)..normalize();
  final v = n.cross(u)..normalize();
  List<List<double>> project(_PlaneGroup g) => [
    for (var t = 0; t < g.corners.length; t += 9)
      [
        for (var k = 0; k < 9; k += 3) ...[
          g.corners[t + k] * u.x +
              g.corners[t + k + 1] * u.y +
              g.corners[t + k + 2] * u.z,
          g.corners[t + k] * v.x +
              g.corners[t + k + 1] * v.y +
              g.corners[t + k + 2] * v.z,
        ],
      ],
  ];

  final trisA = project(a);
  final trisB = project(b);
  var area = 0.0, cx = 0.0, cy = 0.0;
  if (trisA.length * trisB.length <= _kMaxTrianglePairs) {
    for (final ta in trisA) {
      for (final tb in trisB) {
        final piece = _areaAndCentroid(_clip(ta, tb));
        area += piece.area;
        cx += piece.cx * piece.area;
        cy += piece.cy * piece.area;
      }
    }
  } else {
    // Too dense to clip pairwise; take the overlap of the projected bounds.
    double bound(List<List<double>> tris, int axis, bool upper) {
      var value = upper ? double.negativeInfinity : double.infinity;
      for (final t in tris) {
        for (var k = axis; k < 6; k += 2) {
          value = upper ? math.max(value, t[k]) : math.min(value, t[k]);
        }
      }
      return value;
    }

    final x0 = math.max(bound(trisA, 0, false), bound(trisB, 0, false));
    final x1 = math.min(bound(trisA, 0, true), bound(trisB, 0, true));
    final y0 = math.max(bound(trisA, 1, false), bound(trisB, 1, false));
    final y1 = math.min(bound(trisA, 1, true), bound(trisB, 1, true));
    if (x1 > x0 && y1 > y0) {
      area = (x1 - x0) * (y1 - y0);
      cx = (x0 + x1) * 0.5 * area;
      cy = (y0 + y1) * 0.5 * area;
    }
  }
  if (area <= 0) return (area: 0.0, center: Vector3.zero());
  return (area: area, center: u * (cx / area) + v * (cy / area) + n * a.offset);
}

// The intersection of two convex polygons given as flat x, y lists
// (Sutherland-Hodgman), as a flat list.
List<double> _clip(List<double> subject, List<double> clip) {
  var output = List<double>.of(subject);
  var edges = List<double>.of(clip);
  if (_signedArea(edges) < 0) {
    edges = [
      for (var i = edges.length - 2; i >= 0; i -= 2) ...[
        edges[i],
        edges[i + 1],
      ],
    ];
  }
  final n = edges.length ~/ 2;
  for (var e = 0; e < n && output.isNotEmpty; e++) {
    final ax = edges[e * 2], ay = edges[e * 2 + 1];
    final bx = edges[((e + 1) % n) * 2], by = edges[((e + 1) % n) * 2 + 1];
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

({double area, double cx, double cy}) _areaAndCentroid(List<double> points) {
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

// "Pieces 8.40 m long are placed 8.00 m apart": two placements of one
// procedural geometry whose overlap is their length past their spacing.
String? _pitchHint(_PlaneGroup a, _PlaneGroup b) {
  if (a.source.geometry != b.source.geometry) return null;
  final procedural = a.source.spec.procedural;
  final Vector3 extent;
  if (procedural is CuboidGeometrySpec) {
    extent = procedural.extents;
  } else if (procedural is PlaneGeometrySpec) {
    extent = Vector3(procedural.width, 0, procedural.depth);
  } else {
    return null;
  }
  final step = b.transform.getTranslation() - a.transform.getTranslation();
  final spacing = step.length;
  if (spacing < 1e-6) return null;
  final m = a.transform.storage;
  final direction = step / spacing;
  final length =
      (Vector3(m[0], m[1], m[2])..scale(extent.x)).dot(direction).abs() +
      (Vector3(m[4], m[5], m[6])..scale(extent.y)).dot(direction).abs() +
      (Vector3(m[8], m[9], m[10])..scale(extent.z)).dot(direction).abs();
  if (length <= spacing + _kPlaneTolerance) return null;
  String meters(double value) => value.toStringAsFixed(value < 10 ? 2 : 1);
  return 'Pieces ${meters(length)} m long are placed ${meters(spacing)} m '
      'apart, so neighbors overlap ${meters(length - spacing)} m; make them '
      '${meters(spacing)} m long';
}
