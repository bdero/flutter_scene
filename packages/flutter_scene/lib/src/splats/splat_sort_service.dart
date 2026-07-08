import 'dart:typed_data';

import 'package:flutter_scene/src/splats/splat_sort_service_native.dart'
    if (dart.library.js_interop) 'package:flutter_scene/src/splats/splat_sort_service_web.dart'
    as impl;

/// A long-lived background sorter for one splat set.
///
/// The positions are copied to the worker once at construction, so a re-sort
/// only ships the direction out and transfers the order back. A per-sort
/// `compute` would re-copy the whole positions array on the UI thread every
/// time, a rhythmic stutter while orbiting a large set.
///
/// The web has no isolates, so its fallback sorts synchronously on the main
/// thread. TODO(splats): move the web path into a web worker.
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
