/// What flutter_scene is currently keeping resident on the GPU, and what is
/// holding it.
library;

import 'package:flutter/foundation.dart';

import 'importer/scene_registry.dart';
import 'texture/texture_registry.dart';

/// One category of resident GPU memory.
/// {@category Assets and loading}
@immutable
class MemoryCategory {
  const MemoryCategory({
    required this.name,
    required this.bytes,
    required this.count,
  });

  /// What this category holds (`textures`, `scene templates`).
  final String name;

  /// Resident bytes, or null where the size is not knowable from Dart.
  final int? bytes;

  /// How many resources the category holds.
  final int count;

  @override
  String toString() =>
      '$name: $count${bytes == null ? '' : ' (${_mib(bytes!)} MiB)'}';
}

/// A snapshot of what flutter_scene is keeping resident.
///
/// Covers what the engine's shared caches pin, which is the memory an app has
/// no other way to see or release. It does not cover resources the app holds
/// itself (a [Texture2D] you constructed and kept), and it is a measure of
/// what is *pinned*, not of what the GPU has actually reclaimed. Dropping the
/// last reference to a resource makes it collectable, but the reclaim happens
/// on the engine's schedule.
/// {@category Assets and loading}
@immutable
class MemoryReport {
  const MemoryReport(this.categories);

  /// Every category, in a stable order.
  final List<MemoryCategory> categories;

  /// Total resident bytes across the categories that can report a size.
  int get totalBytes =>
      categories.fold(0, (sum, category) => sum + (category.bytes ?? 0));

  @override
  String toString() =>
      'MemoryReport(${_mib(totalBytes)} MiB)\n'
      '${categories.map((c) => '  $c').join('\n')}';
}

/// Takes a [MemoryReport] of what the engine's shared caches are holding.
///
/// Cheap enough to poll (it walks the cache maps and reads each texture's
/// reflected size), so it is reasonable to surface in a debug overlay.
/// {@category Assets and loading}
MemoryReport takeMemoryReport() {
  final textures = textureCacheFootprint();
  return MemoryReport([
    MemoryCategory(
      name: 'textures',
      bytes: textures.bytes,
      count: textures.count,
    ),
    // A template's footprint is spread across the geometry, materials, and
    // textures it realized, which are not individually measurable from here
    // yet, so only the count is reported.
    MemoryCategory(
      name: 'scene templates',
      bytes: null,
      count: sceneTemplateCacheCount(),
    ),
  ]);
}

String _mib(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(2);
