/// Per-input caching for the build hooks.
///
/// A hook reruns whenever any of its declared dependencies changes, which
/// re-converts every model, scene, and material even when only one source
/// changed (an edited `.fmat` would re-import and re-compress every model).
/// Each conversion therefore records a stamp of its inputs next to its
/// outputs; when the stamp matches and the outputs exist, the conversion is
/// skipped and the existing outputs are registered as-is.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:hooks/hooks.dart';

/// Bump when the hooks' generated output changes for the same inputs and the
/// code that caused it is not covered by a generator fingerprint (see
/// [sceneGeneratorFingerprint]), so outputs cached by an older flutter_scene
/// revision are rebuilt. A change to the importer, the texture encoder, the
/// `.fmat` compiler, or the `scene` format rebuilds on its own.
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

/// The code that writes `.fsceneb` scenes: the importer, the texture encoder it
/// embeds, and the `scene` package's format. Its fingerprint is part of every
/// scene's build stamp, so a change to any of it rebuilds the scene.
const List<String> _sceneGenerator = [
  'package:flutter_scene/src/importer/',
  'package:flutter_scene/src/texture/',
  'package:scene/',
];
const List<String> _textureGenerator = ['package:flutter_scene/src/texture/'];
const List<String> _materialCompiler = ['package:flutter_scene/src/fmat/'];

/// Fingerprint of the code that writes `.fsceneb` scenes.
String sceneGeneratorFingerprint() => _generator(_sceneGenerator).fingerprint;

/// Fingerprint of the code that writes `.fstex` textures.
String textureGeneratorFingerprint() =>
    _generator(_textureGenerator).fingerprint;

/// Fingerprint of the `.fmat` compiler.
String materialCompilerFingerprint() =>
    _generator(_materialCompiler).fingerprint;

/// The `.fmat` compiler's source files, declared as hook dependencies so an
/// edit to them reruns the hook.
List<Uri> materialCompilerSources() => _generator(_materialCompiler).files;

final Map<String, ({String fingerprint, List<Uri> files})> _generators = {};

// Hashes every Dart file under [packageDirectories]. A file that imports
// Flutter cannot run in a build hook, so it is runtime code and left out; any
// other file counts, so new generator code is covered without a list to keep.
// Unresolvable directories (a package missing from this isolate's config)
// contribute nothing, leaving [buildCacheRevision] as the backstop.
({String fingerprint, List<Uri> files}) _generator(
  List<String> packageDirectories,
) => _generators[packageDirectories.join(',')] ??= () {
  final entries = <String>[];
  final sources = <Uri>[];
  for (final directory in packageDirectories) {
    final resolved = _resolvePackageUri(Uri.parse(directory));
    if (resolved == null) continue;
    final root = Directory.fromUri(resolved);
    if (!root.existsSync()) continue;
    final files =
        root
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    for (final file in files) {
      final bytes = file.readAsBytesSync();
      if (_importsFlutter(bytes)) continue;
      final relative = file.path.substring(root.path.length);
      entries.add('$directory$relative=${contentHash(bytes)}');
      sources.add(file.uri);
    }
  }
  return (
    fingerprint: contentHash(entries.join('\n').codeUnits),
    files: sources,
  );
}();

// A hook's plain Dart VM resolves package URIs itself; the Flutter test VM
// does not, so fall back to the nearest package config above the working
// directory.
Uri? _resolvePackageUri(Uri packageUri) {
  try {
    return Isolate.resolvePackageUriSync(packageUri);
  } on UnsupportedError {
    return _resolveFromPackageConfig(packageUri);
  }
}

Uri? _resolveFromPackageConfig(Uri packageUri) {
  final name = packageUri.pathSegments.first;
  final rest = packageUri.pathSegments.skip(1).join('/');
  for (
    var dir = Directory.current.absolute;
    dir.parent.path != dir.path;
    dir = dir.parent
  ) {
    final config = File('${dir.path}/.dart_tool/package_config.json');
    if (!config.existsSync()) continue;
    final packages =
        (jsonDecode(config.readAsStringSync()) as Map)['packages'] as List;
    for (final entry in packages.cast<Map<String, Object?>>()) {
      if (entry['name'] != name) continue;
      final root = config.uri.resolve(_asDirectory(entry['rootUri'] as String));
      final lib = root.resolve(
        _asDirectory(entry['packageUri'] as String? ?? ''),
      );
      return lib.resolve(rest);
    }
    return null;
  }
  return null;
}

String _asDirectory(String path) =>
    path.isEmpty || path.endsWith('/') ? path : '$path/';

bool _importsFlutter(List<int> bytes) {
  final source = String.fromCharCodes(bytes);
  return source.contains("import 'dart:ui") ||
      source.contains("import 'package:flutter/");
}
