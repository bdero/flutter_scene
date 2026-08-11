/// Runtime `.fmat` loading for the editor.
///
/// Resolves a material resource's `.fmat` source on disk, compiles it with
/// the Flutter SDK's impellerc, loads the bytes as live shaders (entirely
/// outside the asset bundle), and watches the source plus its GLSL includes
/// to hot swap the compiled shaders in place as the user edits them. A failed
/// compile keeps the last good shaders and surfaces the error.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_scene/scene.dart'
    show PreprocessedMaterial, PreprocessedSky;
import 'package:flutter_scene/src/fmat/fmat_bytes_library.dart';
import 'package:flutter_scene/src/fmat/runtime_compile.dart';
import 'package:scene/scene.dart' show AssetRef;

import '../toolchains/flutter_installation.dart';

/// The resolved offline shader compiler and the directories the generated
/// GLSL's includes resolve against, plus provenance for diagnostics.
final class FmatToolchain {
  FmatToolchain({
    required this.impellerc,
    required this.frameworkShaders,
    required this.source,
    this.shaderLib,
    this.manifest,
  });

  /// The impellerc binary.
  final Uri impellerc;

  /// flutter_scene's `shaders/` directory.
  final Uri frameworkShaders;

  /// impellerc's `shader_lib/` include directory, or null for the binary's
  /// sibling (the SDK cache layout).
  final Uri? shaderLib;

  /// Where the toolchain came from (`bundled`, `IMPELLERC`, `FLUTTER_ROOT`,
  /// or `PATH`), for the diagnostics surface.
  final String source;

  /// The packaged bundle's `tool_manifest.json` contents (the Flutter
  /// revision the tools were built from), or null outside a packaged build.
  final Map<String, Object?>? manifest;

  /// A short human-readable description for the diagnostics surface.
  String describe() {
    final buffer = StringBuffer()
      ..writeln('impellerc ($source): ${impellerc.toFilePath()}')
      ..writeln('framework shaders: ${frameworkShaders.toFilePath()}');
    final info = manifest;
    if (info != null) {
      buffer.writeln(
        'built from Flutter ${info['flutterVersion']} '
        '(engine ${info['engineRevision']})',
      );
    }
    return buffer.toString().trimRight();
  }
}

// The packaged bundle's tool and data locations, resolved relative to the
// executable. macOS keeps the tool in Contents/Helpers and the data in
// Contents/Resources; Linux and Windows use bin/ and data/ next to the
// binary (the layout tool/package_editor.dart produces).
({Uri impellerc, String dataDir})? _bundledLayout() {
  final exeDir = File(Platform.resolvedExecutable).parent.path;
  final exeName = Platform.isWindows ? 'impellerc.exe' : 'impellerc';
  final candidates = [
    (tool: '$exeDir/../Helpers/$exeName', data: '$exeDir/../Resources'),
    (tool: '$exeDir/bin/$exeName', data: '$exeDir/data'),
  ];
  for (final candidate in candidates) {
    if (File(candidate.tool).existsSync() &&
        Directory('${candidate.data}/flutter_scene_shaders').existsSync()) {
      return (
        impellerc: File(candidate.tool).absolute.uri,
        dataDir: Directory(candidate.data).absolute.path,
      );
    }
  }
  return null;
}

/// Locates the toolchain the editor compiles `.fmat` sources with.
///
/// A packaged bundle (impellerc, shader_lib, and the framework shaders laid
/// out by the packaging script) wins after an explicit `IMPELLERC` override;
/// a dev-mode process falls back to the Flutter SDK cache (via `FLUTTER_ROOT`
/// or the `flutter` on PATH) and the workspace's package config. Throws a
/// [StateError] naming every location tried.
Future<FmatToolchain> findFmatToolchain() async {
  final tried = <String>[];
  final exeName = Platform.isWindows ? 'impellerc.exe' : 'impellerc';

  Uri? probe(String path) {
    tried.add(path);
    return File(path).existsSync() ? Uri.file(path) : null;
  }

  // The SDK cache keeps macOS host artifacts under darwin-x64 on every Mac;
  // other hosts get their own directory (same probe set flutter_gpu_shaders
  // uses).
  Uri? probeSdkRoot(String root) {
    for (final host in const [
      'darwin-x64',
      'linux-x64',
      'linux-arm64',
      'windows-x64',
      'windows-arm64',
    ]) {
      final found = probe('$root/bin/cache/artifacts/engine/$host/$exeName');
      if (found != null) return found;
    }
    return null;
  }

  final bundled = _bundledLayout();

  Uri? impellerc;
  String source = 'bundled';
  final env = Platform.environment['IMPELLERC'];
  if (env != null && env.isNotEmpty) {
    impellerc = probe(env);
    source = 'IMPELLERC';
  }
  if (impellerc == null && bundled != null) {
    impellerc = bundled.impellerc;
    source = 'bundled';
  }

  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (impellerc == null && flutterRoot != null && flutterRoot.isNotEmpty) {
    impellerc = probeSdkRoot(flutterRoot);
    source = 'FLUTTER_ROOT';
  }

  if (impellerc == null) {
    final which = await Process.run(Platform.isWindows ? 'where' : 'which', [
      'flutter',
    ]);
    if (which.exitCode == 0) {
      final path = '${which.stdout}'.trim().split('\n').first.trim();
      if (path.isNotEmpty) {
        try {
          // <flutter root>/bin/flutter, following a PATH symlink.
          final script = File(path).resolveSymbolicLinksSync();
          impellerc = probeSdkRoot(File(script).parent.parent.path);
          source = 'PATH';
        } on FileSystemException {
          tried.add('$path (unresolvable symlink)');
        }
      }
    } else {
      tried.add('flutter on PATH (not found)');
    }
  }

  if (impellerc == null) {
    throw StateError(
      'impellerc could not be located, so .fmat materials cannot compile. '
      'Set the IMPELLERC environment variable or install a Flutter SDK. '
      'Tried\n  ${tried.join('\n  ')}',
    );
  }

  final frameworkShaders = _findFrameworkShaders(bundled?.dataDir);
  if (frameworkShaders == null) {
    throw StateError(
      'The flutter_scene framework shaders could not be resolved, so .fmat '
      'materials cannot compile in this build. Set FLUTTER_SCENE_SHADERS to '
      "flutter_scene's shaders directory.",
    );
  }

  Uri? shaderLib;
  Map<String, Object?>? manifest;
  if (bundled != null) {
    final bundledShaderLib = Directory('${bundled.dataDir}/shader_lib');
    if (bundledShaderLib.existsSync()) shaderLib = bundledShaderLib.uri;
    final manifestFile = File('${bundled.dataDir}/tool_manifest.json');
    if (manifestFile.existsSync()) {
      try {
        manifest = (jsonDecode(manifestFile.readAsStringSync()) as Map)
            .cast<String, Object?>();
      } catch (_) {
        // A malformed manifest only degrades diagnostics.
      }
    }
  }

  return FmatToolchain(
    impellerc: impellerc,
    frameworkShaders: frameworkShaders,
    shaderLib: shaderLib,
    source: source,
    manifest: manifest,
  );
}

/// Builds the toolchain for a selected Flutter [installation], the compiler
/// coming from the installation and the framework shaders from the editor's
/// own resolution (they must match the editor's flutter_scene, not the SDK).
/// Throws a [StateError] when the installation's impellerc is unresolved.
Future<FmatToolchain> fmatToolchainForInstallation(
  FlutterInstallation installation,
) async {
  final impellerc = installation.resolvedImpellerc;
  if (impellerc == null) {
    throw StateError(
      'The installation "${installation.name}" has no impellerc. Bootstrap '
      'the SDK (flutter precache) or set an explicit impellerc path in '
      'Settings.',
    );
  }
  final bundled = _bundledLayout();
  final frameworkShaders = _findFrameworkShaders(bundled?.dataDir);
  if (frameworkShaders == null) {
    throw StateError(
      'The flutter_scene framework shaders could not be resolved, so .fmat '
      'materials cannot compile in this build. Set FLUTTER_SCENE_SHADERS to '
      "flutter_scene's shaders directory.",
    );
  }
  // shader_lib sits beside impellerc both in the SDK artifact cache and in
  // engine out directories, so the compiler's sibling default applies.
  return FmatToolchain(
    impellerc: Uri.file(impellerc),
    frameworkShaders: frameworkShaders,
    shaderLib: null,
    source: 'installation "${installation.name}"',
    manifest: null,
  );
}

// Locates flutter_scene's shaders/ directory (the framework GLSL the
// generated material shaders include). A packaged bundle ships them under
// its data directory; a dev-mode process reads the package_config.json it
// can reach by walking up from the working directory (flutter run inherits
// the project directory).
Uri? _findFrameworkShaders(String? bundledDataDir) {
  bool valid(Directory dir) =>
      File('${dir.path}/pbr.glsl').existsSync() &&
      File('${dir.path}/material_inputs.glsl').existsSync();

  final override = Platform.environment['FLUTTER_SCENE_SHADERS'];
  if (override != null && override.isNotEmpty) {
    final dir = Directory(override);
    if (valid(dir)) return dir.absolute.uri;
  }

  if (bundledDataDir != null) {
    final dir = Directory('$bundledDataDir/flutter_scene_shaders');
    if (valid(dir)) return dir.absolute.uri;
  }

  var probe = Directory.current.absolute;
  for (var depth = 0; depth < 8; depth++) {
    final config = File('${probe.path}/.dart_tool/package_config.json');
    if (config.existsSync()) {
      try {
        final json = (jsonDecode(config.readAsStringSync()) as Map)
            .cast<String, Object?>();
        for (final entry in (json['packages'] as List? ?? const [])) {
          final package = (entry as Map).cast<String, Object?>();
          if (package['name'] != 'flutter_scene') continue;
          var root = config.parent.uri.resolveUri(
            Uri.parse(package['rootUri'] as String),
          );
          if (!root.path.endsWith('/')) {
            root = root.replace(path: '${root.path}/');
          }
          final dir = Directory.fromUri(root.resolve('shaders/'));
          if (valid(dir)) return dir.uri;
        }
      } catch (_) {
        // An unreadable config falls through to the parent directory.
      }
    }
    final parent = probe.parent;
    if (parent.path == probe.path) break;
    probe = parent;
  }
  return null;
}

class _FmatEntry {
  _FmatEntry(this.path);

  final String path;
  FmatBytesLibrary? library;
  String? entryName;
  Map<String, Object?>? metadata;
  String? lastError;
}

/// Compiles, serves, and hot swaps `.fmat` materials for one editor session.
///
/// Handed to the realizer as its fmat loaders; each loaded source is watched
/// (with its transitive GLSL includes) and recompiled on change, refreshing
/// every live instance in place with no scene rebuild.
class EditorFmatLibrary {
  EditorFmatLibrary({
    required this.resolvePath,
    this.onReload,
    this.onError,
    this.onStructuralChange,
  });

  /// Resolves a document asset key to an absolute path (a relative key
  /// resolves against the scene's base directory), or null when it cannot.
  final String? Function(String key) resolvePath;

  /// Called after a watched `.fmat` recompiled and its live instances were
  /// refreshed in place, so the owner repaints.
  final void Function()? onReload;

  /// Called with a human-readable message when locating the toolchain, a
  /// compile, or a load fails. The last good shaders stay live.
  final void Function(String message)? onError;

  /// Called when a watched change cannot refresh in place (the material was
  /// renamed, changing its bundle entry), so the owner re-realizes the scene.
  final Future<void> Function()? onStructuralChange;

  FmatRuntimeCompiler? _compiler;
  FmatToolchain? _toolchain;
  String? _toolchainError;

  /// Overrides how the toolchain resolves (the host routes the selected
  /// Flutter installation through this); null falls back to
  /// [findFmatToolchain]'s environment probing.
  Future<FmatToolchain> Function()? toolchainResolver;

  /// The resolved toolchain, or null before the first fmat load (or when
  /// resolution failed; see [toolchainError]).
  FmatToolchain? get toolchain => _toolchain;

  /// Why toolchain resolution failed, or null.
  String? get toolchainError => _toolchainError;

  /// Forgets the resolved toolchain and every compiled entry so the next load
  /// re-resolves and recompiles (the selected installation changed). Watches
  /// are torn down; the owner re-realizes to reload and rewatch.
  void invalidateToolchain() {
    _compiler = null;
    _toolchain = null;
    _toolchainError = null;
    _entries.clear();
    _pending.clear();
    for (final subscription in _directoryWatches.values) {
      subscription.cancel();
    }
    _directoryWatches.clear();
    _fmatsByWatchedFile.clear();
    _dirty.clear();
    _debounce?.cancel();
  }

  final Map<String, _FmatEntry> _entries = {};
  final Map<String, Future<_FmatEntry?>> _pending = {};
  final Map<String, StreamSubscription<FileSystemEvent>> _directoryWatches = {};
  // Watched file -> the .fmat sources to recompile when it changes (a shared
  // include maps to many; a source maps to itself).
  final Map<String, Set<String>> _fmatsByWatchedFile = {};
  final Set<String> _dirty = {};
  Timer? _debounce;
  bool _disposed = false;

  /// The last compile/load error for [key], or the toolchain error, or null.
  String? errorForKey(String key) {
    final path = resolvePath(key);
    return (path == null ? null : _entries[path]?.lastError) ?? _toolchainError;
  }

  /// The loaded sidecar metadata for [key] (parameter and sampler schemas for
  /// the inspector), or null when it has not compiled yet.
  Map<String, Object?>? metadataForKey(String key) {
    final path = resolvePath(key);
    return path == null ? null : _entries[path]?.metadata;
  }

  /// Loads (compiling on demand) the surface material for [asset], or null
  /// when the toolchain is unavailable or the source does not compile; the
  /// failure is recorded and surfaced through [onError].
  Future<PreprocessedMaterial?> loadMaterial(AssetRef asset) async {
    final entry = await _ensure(asset);
    final library = entry?.library;
    if (entry == null || library == null) return null;
    try {
      return library.createMaterial(entry.entryName!, sourcePath: asset.key);
    } on StateError catch (e) {
      _fail(entry, '$e');
      return null;
    }
  }

  /// Loads (compiling on demand) the sky for [asset]; null on failure, like
  /// [loadMaterial].
  Future<PreprocessedSky?> loadSky(AssetRef asset) async {
    final entry = await _ensure(asset);
    final library = entry?.library;
    if (entry == null || library == null) return null;
    try {
      return library.createSky(entry.entryName!, sourcePath: asset.key);
    } on StateError catch (e) {
      _fail(entry, '$e');
      return null;
    }
  }

  Future<_FmatEntry?> _ensure(AssetRef asset) {
    final path = resolvePath(asset.key);
    if (path == null) {
      _report(
        'Cannot resolve .fmat "${asset.key}" without a base directory; save '
        'the scene first.',
      );
      return Future.value(null);
    }
    final loaded = _entries[path];
    if (loaded != null && loaded.library != null) return Future.value(loaded);
    final inFlight = _pending[path];
    if (inFlight != null) return inFlight;
    final future = _load(path);
    _pending[path] = future;
    future.whenComplete(() => _pending.remove(path));
    return future;
  }

  Future<_FmatEntry?> _load(String path) async {
    final compiler = await _ensureCompiler();
    if (compiler == null) return null;
    final entry = _entries[path] ??= _FmatEntry(path);
    final String source;
    try {
      source = File(path).readAsStringSync();
    } catch (e) {
      _fail(entry, 'Could not read .fmat "$path" ($e)');
      return null;
    }
    try {
      final result = await compiler.compile(source, fileName: path);
      entry
        ..library = await FmatBytesLibrary.load(
          result.shaderBundle,
          result.sidecar,
        )
        ..entryName = result.entryName
        ..metadata = (result.sidecar[result.entryName] as Map?)
            ?.cast<String, Object?>()
        ..lastError = null;
      _watch(path, result.includeDependencies);
      return entry;
    } on Exception catch (e) {
      _fail(entry, '$e');
      // Watch the broken source too, so fixing it triggers a reload even
      // though nothing loaded yet.
      _watch(path, const []);
      return null;
    }
  }

  Future<FmatRuntimeCompiler?> _ensureCompiler() async {
    if (_compiler != null) return _compiler;
    // A failed probe is terminal until the toolchain is invalidated (the
    // environment will not change under a running editor, but the selected
    // installation can); report once and stop retrying.
    if (_toolchainError != null) return null;
    try {
      final toolchain =
          await (toolchainResolver?.call() ?? findFmatToolchain());
      _toolchain = toolchain;
      final cacheDir = Directory(
        '${Directory.systemTemp.path}/flutter_scene_editor/fmat_cache',
      )..createSync(recursive: true);
      _compiler = FmatRuntimeCompiler(
        impellerc: toolchain.impellerc,
        includeDirectories: [toolchain.frameworkShaders],
        shaderLibDirectory: toolchain.shaderLib,
        cacheDirectory: cacheDir,
      );
      return _compiler;
    } on Exception catch (e) {
      _toolchainError = '$e';
      _report('$e');
      return null;
    }
  }

  void _watch(String fmatPath, List<String> dependencies) {
    for (final watchers in _fmatsByWatchedFile.values) {
      watchers.remove(fmatPath);
    }
    for (final file in {fmatPath, ...dependencies}) {
      _fmatsByWatchedFile.putIfAbsent(file, () => {}).add(fmatPath);
      // Watch the parent directory rather than the file, so editors that save
      // through an atomic rename (which replaces the inode) stay watched.
      final dir = File(file).parent.path;
      _directoryWatches[dir] ??= Directory(dir).watch().listen(_onFsEvent);
    }
  }

  void _onFsEvent(FileSystemEvent event) {
    if (_disposed) return;
    final paths = <String>{
      event.path,
      if (event is FileSystemMoveEvent && event.destination != null)
        event.destination!,
    };
    var hit = false;
    for (final path in paths) {
      final fmats = _fmatsByWatchedFile[path];
      if (fmats != null) {
        _dirty.addAll(fmats);
        hit = true;
      }
    }
    if (!hit) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), () {
      unawaited(_flushDirty());
    });
  }

  Future<void> _flushDirty() async {
    if (_disposed) return;
    final paths = _dirty.toList();
    _dirty.clear();
    for (final path in paths) {
      await _recompile(path);
    }
  }

  Future<void> _recompile(String path) async {
    final entry = _entries[path];
    final compiler = await _ensureCompiler();
    if (entry == null || compiler == null) return;
    final String source;
    try {
      source = File(path).readAsStringSync();
    } catch (e) {
      _fail(
        entry,
        'Could not read .fmat "$path"; keeping the last good '
        'shaders ($e)',
      );
      return;
    }
    final FmatCompileResult result;
    try {
      result = await compiler.compile(source, fileName: path);
    } on Exception catch (e) {
      _fail(entry, '$e');
      return;
    }
    final library = entry.library;
    if (library == null || result.entryName != entry.entryName) {
      // First successful compile of a previously broken source, or a renamed
      // material (whose bundle entry changed, which an in-place refresh
      // cannot follow). Load fresh and rebuild the scene's materials.
      entry
        ..library = await FmatBytesLibrary.load(
          result.shaderBundle,
          result.sidecar,
        )
        ..entryName = result.entryName
        ..metadata = (result.sidecar[result.entryName] as Map?)
            ?.cast<String, Object?>()
        ..lastError = null;
      _watch(path, result.includeDependencies);
      await onStructuralChange?.call();
      return;
    }
    final error = await library.refresh(result.shaderBundle, result.sidecar);
    if (error != null) {
      _fail(entry, error);
      return;
    }
    entry
      ..metadata = (result.sidecar[result.entryName] as Map?)
          ?.cast<String, Object?>()
      ..lastError = null;
    _watch(path, result.includeDependencies);
    onReload?.call();
  }

  void _fail(_FmatEntry entry, String message) {
    entry.lastError = message;
    _report(message);
  }

  void _report(String message) => onError?.call(message);

  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    for (final subscription in _directoryWatches.values) {
      unawaited(subscription.cancel());
    }
    _directoryWatches.clear();
    _fmatsByWatchedFile.clear();
    _entries.clear();
  }
}
