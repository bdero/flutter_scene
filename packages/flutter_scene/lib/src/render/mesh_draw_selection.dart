import 'dart:collection';

import 'package:flutter_scene/src/geometry/geometry.dart';
import 'package:flutter_scene/src/mesh_draw.dart';
import 'package:flutter_scene/src/render/render_scene.dart';
import 'package:vector_math/vector_math.dart';

final MeshDrawContext _context = MeshDrawContext(
  pass: MeshDrawPass.color,
  cameraPosition: Vector3.zero(),
  primaryView: true,
);

/// Runs [item]'s [MeshDrawSelector] for one draw and applies its index range
/// to [geometry]. Pair with [endMeshDraw].
MeshDrawSelection beginMeshDraw(
  RenderItem item,
  Geometry geometry,
  MeshDrawPass pass,
  Vector3 cameraPosition,
  bool primaryView,
) {
  final selector = item.drawSource?.drawSelector;
  if (selector == null) return MeshDrawSelection.all;
  _context
    ..pass = pass
    ..cameraPosition = cameraPosition
    ..primaryView = primaryView;
  final selection = selector(_context);
  if (selection.firstIndex != 0 || selection.indexCount != null) {
    geometry.setDrawWindow(selection.firstIndex, selection.indexCount);
  }
  return selection;
}

/// Restores [geometry] to its full range after [beginMeshDraw].
void endMeshDraw(Geometry geometry) => geometry.clearDrawWindow();

/// Whether [item] has a selector, which keeps it out of cross-node batching.
bool hasMeshDrawSelector(RenderItem item) =>
    item.drawSource?.drawSelector != null;

/// [indices] (ascending instance indices, or null for all [count]) limited
/// to instances below [limit]. Returns [indices] itself when nothing is cut.
List<int>? limitInstanceIndices(List<int>? indices, int count, int? limit) {
  if (limit == null || limit >= count) return indices;
  if (indices == null) return _Prefix(limit);
  // Binary search the first index at or past the limit.
  var lo = 0, hi = indices.length;
  while (lo < hi) {
    final mid = (lo + hi) >> 1;
    if (indices[mid] < limit) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  return lo == indices.length ? indices : _Head(indices, lo);
}

/// The integers `0 .. length - 1`, without storing them.
class _Prefix extends ListBase<int> {
  _Prefix(this._length);
  final int _length;

  @override
  int get length => _length;
  @override
  set length(int value) => throw UnsupportedError('fixed length');
  @override
  int operator [](int index) => index;
  @override
  void operator []=(int index, int value) =>
      throw UnsupportedError('read only');
}

/// The first [length] entries of a list, without copying.
class _Head extends ListBase<int> {
  _Head(this._source, this._length);
  final List<int> _source;
  final int _length;

  @override
  int get length => _length;
  @override
  set length(int value) => throw UnsupportedError('fixed length');
  @override
  int operator [](int index) => _source[index];
  @override
  void operator []=(int index, int value) =>
      throw UnsupportedError('read only');
}
