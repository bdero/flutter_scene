import 'dart:typed_data';

/// In-memory cache for stress-test downloads (web). The browser has no
/// filesystem, so downloaded resources are held in memory for the page
/// session; a full reload re-downloads them. Swap this for an IndexedDB
/// implementation if cross-reload persistence is wanted.
final Map<String, Uint8List> _cache = <String, Uint8List>{};

/// Returns the cached bytes for [key], or null if absent.
Future<Uint8List?> loadCachedResource(String key) async => _cache[key];

/// Stores [bytes] for [key].
Future<void> storeCachedResource(String key, Uint8List bytes) async {
  _cache[key] = bytes;
}
