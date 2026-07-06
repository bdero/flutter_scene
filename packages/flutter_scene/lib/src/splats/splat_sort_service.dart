import 'dart:typed_data';

import 'package:flutter_scene/src/splats/splat_sort_service_native.dart'
    if (dart.library.js_interop) 'package:flutter_scene/src/splats/splat_sort_service_web.dart'
    as impl;

/// A long-lived background sorter for one splat set.
///
/// The positions array is copied to the worker once at construction, so a
/// re-sort only ships the tiny direction request and the sorted order back
/// (transferred, not copied). The per-sort `compute` alternative re-copies
/// the whole positions array on the UI thread every time, which shows as a
/// rhythmic stutter while the camera orbits a large set.
///
/// On the web there are no isolates; the fallback sorts synchronously on
/// the main thread. TODO(splats): move the web path into a web worker.
abstract interface class SplatSortService {
  /// Creates the platform sorter over [positions] (`x, y, z` per splat).
  factory SplatSortService(Float32List positions, int count) =>
      impl.createSplatSortService(positions, count);

  /// Resolves with the splat indices in back-to-front order along the given
  /// local-space view-depth direction (ready to upload as the instance
  /// stream), or null if the service was disposed first.
  ///
  /// Callers must not issue a new sort until the previous one resolves.
  Future<Float32List?> sort(double dirX, double dirY, double dirZ);

  /// Shuts down the worker. In-flight sorts resolve null.
  void dispose();
}
