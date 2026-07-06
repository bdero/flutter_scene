import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_scene/src/splats/splat_sort_service.dart';
import 'package:flutter_scene/src/splats/splat_sorter.dart';

/// Creates the web sorter, which runs synchronously on the main thread
/// (the web platform has no shared-memory isolates).
/// TODO(splats): move this into a web worker for large sets.
SplatSortService createSplatSortService(Float32List positions, int count) =>
    _SynchronousSplatSortService(positions, count);

class _SynchronousSplatSortService implements SplatSortService {
  _SynchronousSplatSortService(this._positions, this._count);

  final Float32List _positions;
  final int _count;
  bool _disposed = false;

  @override
  Future<Float32List?> sort(double dirX, double dirY, double dirZ) =>
      Future(() {
        if (_disposed) return null;
        return sortSplatsBackToFront(_positions, _count, dirX, dirY, dirZ);
      });

  @override
  void dispose() {
    _disposed = true;
  }
}
