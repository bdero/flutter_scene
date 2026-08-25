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

import 'package:hooks/hooks.dart';

/// Bump when the hooks' generated output changes for the same inputs (the
/// importer, the scene emitter, or the material pipeline), so outputs cached
/// by an older flutter_scene revision are rebuilt.
const int buildCacheRevision = 8;

/// Disables the per-input build cache, so every source is reconverted. Only
/// reaches a builder driven directly; see [HookOptions] for the pubspec form a
/// `flutter build` respects.
const String kDisableBuildCacheEnv = 'FLUTTER_SCENE_DISABLE_BUILD_CACHE';

/// Content-hashes every source in a build stamp instead of taking its size and
/// modification time. Only reaches a builder driven directly; see [HookOptions]
/// for the pubspec form a `flutter build` respects.
///
/// Slower (roughly 5 s per GiB), and worth it in two cases: a filesystem whose
/// timestamps are too coarse to see a same-size rewrite, and CI that restores a
/// build cache across fresh checkouts, where every file has a new mtime and a
/// stat fingerprint invalidates everything.
const String kStrictHashEnv = 'FLUTTER_SCENE_STRICT_HASH';

/// Sources at or below this size are content-hashed whatever the mode. Reading
/// them costs nothing measurable, and it removes the whole class of timestamp
/// surprises for hand-edited `.fscene`, `.fmat`, and `.glsl` files.
const int kSmallSourceBytes = 1 << 20;

/// The two build-hook switches, read from the app's user defines with an
/// environment fallback.
///
/// The build system passes a hook a **filtered** environment (an allowlist for
/// compiler discovery), so an environment variable set on a `flutter build` never
/// reaches the hook. The switch that works there is the app pubspec:
///
/// ```yaml
/// hooks:
///   user_defines:
///     my_app:
///       flutter_scene_strict_hashing: true
/// ```
///
/// The environment forms still work when the builders are driven directly, from
/// a test or a script.
final class HookOptions {
  const HookOptions({
    this.strictHashing = false,
    this.rebuildEverything = false,
  });

  /// Reads the options declared for the package [input] is building.
  factory HookOptions.of(BuildInput input) => HookOptions(
    strictHashing: _flag(input, 'flutter_scene_strict_hashing', kStrictHashEnv),
    rebuildEverything: _flag(
      input,
      'flutter_scene_rebuild_assets',
      kDisableBuildCacheEnv,
    ),
  );

  static bool _flag(BuildInput input, String define, String environment) =>
      input.userDefines[define] == true ||
      Platform.environment.containsKey(environment);

  /// Content-hash every source, however large.
  final bool strictHashing;

  /// Redo every conversion, whatever the stamps say.
  final bool rebuildEverything;
}

/// Whether the cache is disabled via [kDisableBuildCacheEnv].
bool get buildCacheDisabled =>
    Platform.environment.containsKey(kDisableBuildCacheEnv);

/// A build-stamp fingerprint of [file]: its content hash when it is small (or
/// under strict hashing), and its size plus modification time otherwise.
///
/// Hashing a multi-gigabyte source costs seconds per build; a stat costs
/// microseconds. The stat form misses only a rewrite that keeps both the size
/// and the timestamp, which no ordinary tool produces (git and every editor move
/// the timestamp forward).
String sourceFingerprint(File file, {bool strict = false}) {
  final stat = file.statSync();
  if (strict || stat.size <= kSmallSourceBytes) {
    return contentHash(file.readAsBytesSync());
  }
  return '${stat.size}@${stat.modified.microsecondsSinceEpoch}';
}

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
