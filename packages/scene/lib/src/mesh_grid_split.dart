/// Grid splitting for triangle meshes: bins whole triangles by world-space
/// centroid into cells of a world-aligned grid and emits one vertex/index
/// buffer pair per cell, attribute data copied verbatim through a per-cell
/// remap. Shared by the editor's `splitMeshByGrid` command and the importer's
/// `-split<N>` name hint, so both produce identical, deterministic output
/// (stable cell names like `Ground_x0_z3` across re-imports).
library;

import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'id.dart';
import 'log.dart';
import 'property_value.dart';
import 'scene_document.dart';
import 'specs.dart';

class _VertexLayout {
  const _VertexLayout(this.bytesPerVertex, this.soaStreams);

  final int bytesPerVertex;

  /// Per-vertex byte widths of the concatenated attribute streams, or null
  /// for an interleaved layout.
  final List<int>? soaStreams;
}

// Skinned and morph-target layouts are excluded; splitting them would also
// need joint and delta-slab re-binning.
const Map<String, _VertexLayout> _layouts = {
  'unskinned_soa_uv1_tangent': _VertexLayout(72, [12, 12, 8, 8, 16, 16]),
  'unskinned_soa': _VertexLayout(48, [12, 12, 8, 16]),
  'unskinned_uv1_tangent': _VertexLayout(72, null),
  'unskinned': _VertexLayout(48, null),
};

/// The vertex-buffer payload `layout` values [splitTriangleMeshByGrid] can
/// slice (the unskinned interleaved and structure-of-arrays forms).
/// {@category Documents}
Set<String> get splittableVertexLayouts => _layouts.keys.toSet();

/// One output cell of a grid split: the cell's grid coordinates (zero on axes
/// the grid does not span), a deterministic name [suffix] such as `x0_z-3`,
/// the sliced vertex and index buffers, and local-space bounds computed from
/// the cell's actual triangles.
/// {@category Documents}
class MeshGridCell {
  MeshGridCell({
    required this.x,
    required this.y,
    required this.z,
    required this.suffix,
    required this.vertexBytes,
    required this.indexBytes,
    required this.indexFormat,
    required this.boundsMin,
    required this.boundsMax,
  });

  final int x, y, z;
  final String suffix;
  final Uint8List vertexBytes;
  final Uint8List indexBytes;

  /// `uint16`, or `uint32` when the cell holds more than 65535 vertices.
  final String indexFormat;

  final Vector3 boundsMin;
  final Vector3 boundsMax;
}

/// Splits a triangle mesh into per-cell buffers on a world-aligned grid.
///
/// [vertexBytes] holds vertices in [layout] (one of
/// [splittableVertexLayouts]); [indices] is the triangle list, or null for
/// non-indexed consecutive triples. Each triangle bins whole into the cell
/// its [worldTransform]-space centroid lands in (`floor((p - origin) /
/// cellSize)` on each axis of [axes], a subset of `xyz`); triangles are never
/// clipped, so the total triangle count is unchanged and shared border
/// vertices duplicate bit-identically into both cells. Returns the cells in
/// deterministic coordinate order; a single-cell result means the mesh did
/// not span the grid. Throws [ArgumentError] on an unsupported layout or
/// malformed buffer.
/// {@category Documents}
List<MeshGridCell> splitTriangleMeshByGrid({
  required Uint8List vertexBytes,
  required String layout,
  List<int>? indices,
  required Matrix4 worldTransform,
  required double cellSize,
  String axes = 'xz',
  Vector3? origin,
}) {
  if (cellSize <= 0) {
    throw ArgumentError.value(cellSize, 'cellSize', 'must be positive');
  }
  final layoutInfo = _layouts[layout];
  if (layoutInfo == null) {
    throw ArgumentError.value(layout, 'layout', 'cannot be split');
  }
  final axisList = <int>[];
  for (final ch in axes.split('')) {
    final axis = 'xyz'.indexOf(ch);
    if (axis < 0 || axisList.contains(axis)) {
      throw ArgumentError.value(axes, 'axes', 'must be a subset of "xyz"');
    }
    axisList.add(axis);
  }
  if (axisList.isEmpty) {
    throw ArgumentError.value(axes, 'axes', 'must name at least one axis');
  }
  final gridOrigin = origin ?? Vector3.zero();

  final vertexCount = vertexBytes.length ~/ layoutInfo.bytesPerVertex;
  if (vertexCount * layoutInfo.bytesPerVertex != vertexBytes.length) {
    throw ArgumentError(
      'vertex data is not a whole number of ${layoutInfo.bytesPerVertex}-byte '
      'vertices',
    );
  }
  final triangleIndices = indices ?? List<int>.generate(vertexCount, (i) => i);
  if (triangleIndices.length % 3 != 0) {
    throw ArgumentError('index data is not a whole number of triangles');
  }

  // Positions: the SoA position stream leads the buffer; the interleaved
  // record also starts with position, so both read as float triples at a
  // per-layout stride.
  final floats = Float32List.sublistView(vertexBytes);
  final positionStride = layoutInfo.soaStreams == null
      ? layoutInfo.bytesPerVertex ~/ 4
      : 3;

  final cells = <(int, int, int), List<int>>{};
  final local = Vector3.zero();
  final centroid = Vector3.zero();
  for (var tri = 0; tri < triangleIndices.length; tri += 3) {
    centroid.setZero();
    for (var corner = 0; corner < 3; corner++) {
      final v = triangleIndices[tri + corner] * positionStride;
      local.setValues(floats[v], floats[v + 1], floats[v + 2]);
      centroid.add(worldTransform.transformed3(local));
    }
    centroid.scale(1 / 3);
    var cx = 0, cy = 0, cz = 0;
    for (final axis in axisList) {
      final c = ((centroid[axis] - gridOrigin[axis]) / cellSize).floor();
      if (axis == 0) cx = c;
      if (axis == 1) cy = c;
      if (axis == 2) cz = c;
    }
    (cells[(cx, cy, cz)] ??= []).add(tri);
  }

  final cellKeys = cells.keys.toList()
    ..sort((a, b) {
      if (a.$1 != b.$1) return a.$1.compareTo(b.$1);
      if (a.$2 != b.$2) return a.$2.compareTo(b.$2);
      return a.$3.compareTo(b.$3);
    });

  final out = <MeshGridCell>[];
  for (final key in cellKeys) {
    final triangles = cells[key]!;
    final remap = <int, int>{};
    final cellIndices = <int>[];
    for (final tri in triangles) {
      for (var corner = 0; corner < 3; corner++) {
        final old = triangleIndices[tri + corner];
        cellIndices.add(remap.putIfAbsent(old, () => remap.length));
      }
    }
    final cellVertexCount = remap.length;
    final oldByNew = List<int>.filled(cellVertexCount, 0);
    remap.forEach((old, fresh) => oldByNew[fresh] = old);

    final cellVertexBytes = Uint8List(
      cellVertexCount * layoutInfo.bytesPerVertex,
    );
    final streams = layoutInfo.soaStreams;
    if (streams == null) {
      final stride = layoutInfo.bytesPerVertex;
      for (var fresh = 0; fresh < cellVertexCount; fresh++) {
        cellVertexBytes.setRange(
          fresh * stride,
          (fresh + 1) * stride,
          vertexBytes,
          oldByNew[fresh] * stride,
        );
      }
    } else {
      var srcBase = 0, dstBase = 0;
      for (final streamBytes in streams) {
        for (var fresh = 0; fresh < cellVertexCount; fresh++) {
          cellVertexBytes.setRange(
            dstBase + fresh * streamBytes,
            dstBase + (fresh + 1) * streamBytes,
            vertexBytes,
            srcBase + oldByNew[fresh] * streamBytes,
          );
        }
        srcBase += vertexCount * streamBytes;
        dstBase += cellVertexCount * streamBytes;
      }
    }

    final min = Vector3.all(double.infinity);
    final max = Vector3.all(double.negativeInfinity);
    for (final old in oldByNew) {
      final v = old * positionStride;
      for (var c = 0; c < 3; c++) {
        final value = floats[v + c];
        if (value < min[c]) min[c] = value;
        if (value > max[c]) max[c] = value;
      }
    }

    final wide = cellVertexCount > 0xFFFF;
    final indexBytes = wide
        ? Uint32List.fromList(cellIndices).buffer.asUint8List()
        : Uint16List.fromList(cellIndices).buffer.asUint8List();
    final suffix = [
      for (final axis in axisList)
        '${'xyz'[axis]}${[key.$1, key.$2, key.$3][axis]}',
    ].join('_');
    out.add(
      MeshGridCell(
        x: key.$1,
        y: key.$2,
        z: key.$3,
        suffix: suffix,
        vertexBytes: cellVertexBytes,
        indexBytes: indexBytes,
        indexFormat: wide ? 'uint32' : 'uint16',
        boundsMin: min,
        boundsMax: max,
      ),
    );
  }
  return out;
}

// The name hint: `Ground-split16` or `Ground-split7.5` splits at that cell
// size on the ground (xz) plane, world-anchored. Matches at end of name only.
final RegExp _splitHint = RegExp(r'-split(\d+(?:\.\d+)?)$');

/// Applies `-split<N>` name-suffix hints across [document]: each hinted
/// node's triangle mesh splits in place into per-cell child nodes on an
/// `xz` world grid of `N`-unit cells (world-anchored, so cell assignment is
/// stable across re-imports), the hint is stripped from the node's name, the
/// mesh component moves to the children, and the now-unreferenced source
/// geometry and payloads are removed. A hinted node the splitter cannot
/// handle (skinned, morphed, procedural, unsupported layout) keeps its mesh
/// and logs why. Returns the number of hinted nodes processed (a mesh whose
/// triangles all land in one cell keeps its mesh but still loses the hint).
///
/// Import pipelines call this after building the document, which is what
/// makes the split reapply on every re-import. Pick cell sizes that nest
/// with streaming grids (powers of two are a good default).
/// {@category Documents}
int applyMeshSplitHints(SceneDocument document) {
  var split = 0;
  // Snapshot: splitting mutates the node pool.
  for (final node in document.nodes.values.toList()) {
    final hint = _splitHint.firstMatch(node.name);
    if (hint == null) continue;
    final cellSize = double.parse(hint.group(1)!);
    final baseName = node.name.substring(0, hint.start);
    final why = _splitNodeInPlace(document, node, cellSize, baseName);
    if (why == null) {
      node.name = baseName;
      split++;
    } else {
      sceneLog('mesh split hint on "${node.name}" skipped, $why');
    }
  }
  return split;
}

/// Splits [node]'s mesh in place, or returns why it cannot be split.
String? _splitNodeInPlace(
  SceneDocument document,
  NodeSpec node,
  double cellSize,
  String baseName,
) {
  if (cellSize <= 0) return 'cell size must be positive';
  if (node.skin != null) return 'the node is skinned';
  final meshIndex = node.components.indexWhere((c) => c.type == 'mesh');
  if (meshIndex < 0) return 'the node has no mesh component';
  final mesh = node.components[meshIndex];
  final geometryRef = mesh.properties['geometry'];
  if (geometryRef is! ResourceRefValue) {
    return 'the mesh has no geometry reference';
  }
  final geometry = document.resources[geometryRef.id];
  if (geometry is! GeometryResource) return 'the geometry resource is missing';
  if (geometry.procedural != null) return 'the geometry is procedural';
  if (geometry.morphTargets != null) return 'the geometry has morph targets';
  if (geometry.topology != 'triangle') {
    return 'the topology is ${geometry.topology}';
  }
  final vertexPayload = document.payloads[geometry.vertices];
  final vertexBytes = vertexPayload?.bytes;
  if (vertexPayload == null || vertexBytes == null) {
    return 'the vertex payload bytes are not loaded';
  }
  final layout = vertexPayload.layout;
  if (layout == null || !_layouts.containsKey(layout)) {
    return 'the vertex layout "$layout" cannot be split';
  }
  List<int>? indices;
  PayloadSpec? indexPayload;
  if (geometry.indices != null) {
    indexPayload = document.payloads[geometry.indices];
    final indexBytes = indexPayload?.bytes;
    if (indexPayload == null || indexBytes == null) {
      return 'the index payload bytes are not loaded';
    }
    indices = indexPayload.format == 'uint32'
        ? Uint32List.sublistView(indexBytes)
        : Uint16List.sublistView(indexBytes);
  }

  final List<MeshGridCell> cells;
  try {
    cells = splitTriangleMeshByGrid(
      vertexBytes: vertexBytes,
      layout: layout,
      indices: indices,
      worldTransform: documentWorldMatrix(document, node.id),
      cellSize: cellSize,
    );
  } on ArgumentError catch (e) {
    return '$e';
  }
  if (cells.length <= 1) return null; // One cell; nothing to split.

  for (final cell in cells) {
    final newVertexPayload = document.addPayload(
      PayloadSpec(
        document.newId(),
        encoding: PayloadEncoding.vertexBuffer,
        layout: layout,
        length: cell.vertexBytes.length,
        bytes: cell.vertexBytes,
      ),
    );
    final newIndexPayload = document.addPayload(
      PayloadSpec(
        document.newId(),
        encoding: PayloadEncoding.indexBuffer,
        format: cell.indexFormat,
        length: cell.indexBytes.length,
        bytes: cell.indexBytes,
      ),
    );
    final newGeometry = GeometryResource(
      document.newId(),
      vertices: newVertexPayload.id,
      indices: newIndexPayload.id,
      bounds: BoundsSpec(min: cell.boundsMin, max: cell.boundsMax),
      legacyWinding: geometry.legacyWinding,
    );
    document.resources[newGeometry.id] = newGeometry;
    final child = NodeSpec(
      id: document.newId(),
      name: '${baseName}_${cell.suffix}',
      components: [
        ComponentSpec(
          'mesh',
          properties: {
            ...mesh.properties,
            'geometry': ResourceRefValue(newGeometry.id),
          },
        ),
      ],
    );
    document.nodes[child.id] = child;
    node.children.add(child.id);
  }
  node.components.removeAt(meshIndex);

  if (countResourceReferences(document, geometry.id) == 0) {
    document.resources.remove(geometry.id);
    for (final payload in [vertexPayload, indexPayload]) {
      if (payload == null) continue;
      if (!isPayloadReferenced(document, payload.id)) {
        document.payloads.remove(payload.id);
      }
    }
  }
  return null;
}

/// The world-space matrix of node [id] in [document], composed from local
/// transforms up the hierarchy (identity for a missing node).
/// {@category Documents}
Matrix4 documentWorldMatrix(SceneDocument document, LocalId id) {
  final node = document.nodes[id];
  if (node == null) return Matrix4.identity();
  final local = node.transform.toMatrix4();
  for (final parent in document.nodes.values) {
    if (parent.children.contains(id)) {
      return documentWorldMatrix(document, parent.id).multiplied(local);
    }
  }
  return local;
}

/// How many times [resourceId] is referenced from component properties and
/// prefab-instance override values across [document].
/// {@category Documents}
int countResourceReferences(SceneDocument document, LocalId resourceId) {
  var count = 0;
  int inValue(PropertyValue value) => switch (value) {
    ResourceRefValue(:final id) => id == resourceId ? 1 : 0,
    ListValue(:final values) => values.fold(0, (n, v) => n + inValue(v)),
    MapValue(:final values) => values.values.fold(0, (n, v) => n + inValue(v)),
    _ => 0,
  };
  for (final node in document.nodes.values) {
    for (final component in node.components) {
      count += component.properties.values.fold(0, (n, v) => n + inValue(v));
    }
    final instance = node.instance;
    if (instance != null) {
      for (final override in instance.overrides) {
        count += inValue(override.value);
      }
      for (final mc in instance.memberComponents) {
        count += mc.component.properties.values.fold(
          0,
          (n, v) => n + inValue(v),
        );
      }
    }
  }
  return count;
}

/// Whether any resource in [document] references payload [id]. A resource
/// about to be removed passes itself as [excluding] so its own references do
/// not count.
/// {@category Documents}
bool isPayloadReferenced(
  SceneDocument document,
  LocalId id, {
  LocalId? excluding,
}) {
  for (final resource in document.resources.values) {
    if (resource.id == excluding) continue;
    switch (resource) {
      case GeometryResource():
        if (resource.vertices == id ||
            resource.indices == id ||
            resource.morphTargets?.deltas == id) {
          return true;
        }
      case TextureResource():
        if (resource.payload == id) return true;
      case EnvironmentResource():
        final env = resource.environment;
        if (env is PayloadEnvironment && env.payload == id) return true;
      default:
        break;
    }
  }
  return false;
}
