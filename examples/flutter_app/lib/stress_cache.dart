// Resource cache for the stress-test downloads. Backed by the on-disk
// application support directory on native platforms, and by an in-memory map
// on web (which has no filesystem). Both expose, keyed by the resource URL:
//
//   Future<Uint8List?> loadCachedResource(String key);
//   Future<void> storeCachedResource(String key, Uint8List bytes);
export 'stress_cache_io.dart'
    if (dart.library.js_interop) 'stress_cache_web.dart';
