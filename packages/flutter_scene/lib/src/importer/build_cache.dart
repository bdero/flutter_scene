/// Per-input caching for the build hooks.
///
/// A hook reruns whenever any of its declared dependencies changes, which
/// re-converts every model, scene, and material even when only one source
/// changed (an edited `.fmat` would re-import and re-compress every model).
/// Each conversion therefore records a stamp of its inputs next to its
/// outputs; when the stamp matches and the outputs exist, the conversion is
/// skipped and the existing outputs are registered as-is.
library;

import 'dart:io';

/// Bump when the hooks' generated output changes for the same inputs (the
/// importer, the scene emitter, or the material pipeline), so outputs cached
/// by an older flutter_scene revision are rebuilt.
const int buildCacheRevision = 1;

/// Setting this environment variable (to any value) disables the per-input
/// build cache, so every source is reconverted on each hook run.
const String kDisableBuildCacheEnv = 'FLUTTER_SCENE_DISABLE_BUILD_CACHE';

/// Whether the cache is disabled via [kDisableBuildCacheEnv].
bool get buildCacheDisabled =>
    Platform.environment.containsKey(kDisableBuildCacheEnv);

/// 64-bit FNV-1a over [bytes], as a hex string. Used to fingerprint source
/// contents in build stamps. Hooks always run on the native VM, where Dart
/// ints carry the full 64 bits.
String contentHash(List<int> bytes) {
  var hash = 0xcbf29ce484222325;
  for (final b in bytes) {
    hash ^= b;
    hash *= 0x100000001b3;
  }
  return hash.toRadixString(16);
}

/// True when [stampFile] records exactly [stamp] and every file in [outputs]
/// exists, meaning the conversion that produced them can be skipped.
bool isBuildCacheFresh(File stampFile, String stamp, List<File> outputs) {
  if (buildCacheDisabled) return false;
  if (!outputs.every((file) => file.existsSync())) return false;
  try {
    return stampFile.existsSync() && stampFile.readAsStringSync() == stamp;
  } catch (_) {
    return false;
  }
}
