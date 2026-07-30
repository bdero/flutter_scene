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

/// The resolved offline shader compiler plus the include directory the
/// generated GLSL's framework includes resolve against.
final class FmatToolchain {
  FmatToolchain({required this.impellerc, required this.frameworkShaders});

  /// The impellerc binary (its sibling `shader_lib/` joins the include path).
  final Uri impellerc;

  /// flutter_scene's `shaders/` directory.
  final Uri frameworkShaders;
}

/// Locates the impellerc the editor compiles `.fmat` sources with, trying the
/// `IMPELLERC` environment variable, a tool bundled beside the executable,
/// the Flutter SDK cache under `FLUTTER_ROOT`, then the `flutter` command on
/// PATH. Throws a [StateError] naming every location tried.
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

  Uri? impellerc;

  final env = Platform.environment['IMPELLERC'];
  if (env != null && env.isNotEmpty) impellerc = probe(env);

  // TODO(editor-dist): read the bundle's tool_manifest.json and cover the
  // per-platform distribution layouts once packaged builds ship the tool.
  final exeDir = File(Platform.resolvedExecutable).parent.path;
  impellerc ??= probe('$exeDir/$exeName');
  impellerc ??= probe('$exeDir/../Helpers/$exeName');

  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (impellerc == null && flutterRoot != null && flutterRoot.isNotEmpty) {
    impellerc = probeSdkRoot(flutterRoot);
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

  final frameworkShaders = _findFrameworkShaders();
  if (frameworkShaders == null) {
    throw StateError(
      'The flutter_scene framework shaders could not be resolved, so .fmat '
      'materials cannot compile in this build. Set FLUTTER_SCENE_SHADERS to '
      "flutter_scene's shaders directory.",
    );
  }
  return FmatToolchain(impellerc: impellerc, frameworkShaders: frameworkShaders);
}

// Locates flutter_scene's shaders/ directory (the framework GLSL the
// generated material shaders include). Flutter apps cannot resolve package
// URIs at runtime, so this reads the package_config.json a dev-mode process
// can reach by walking up from the working directory (flutter run inherits
// the project directory).
// TODO(editor-dist): materialize the framework GLSL from bundled assets for
// packaged builds, which have no package config on disk.
Uri? _findFrameworkShaders() {
  bool valid(Directory dir) =>
      File('${dir.path}/pbr.glsl').existsSync() &&
      File('${dir.path}/material_inputs.glsl').existsSync();

  final override = Platform.environment['FLUTTER_SCENE_SHADERS'];
  if (override != null && override.isNotEmpty) {
    final dir = Directory(override);
    if (valid(dir)) return dir.absolute.uri;
  }

  var probe = Directory.current.absolute;
  for (var depth = 0; depth < 8; depth++) {
    final config = File('${probe.path}/.dart_tool/package_config.json');
    if (config.existsSync()) {
      try {
        final json =
            (jsonDecode(config.readAsStringSync()) as Map)
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
  String? _toolchainError;

  final Map<String, _FmatEntry> _entries = {};
  final Map<String, Future<_FmatEntry?>> _pending = {};
  final Map<String, StreamSubscription<FileSystemEvent>> _directoryWatches =
      {};
  // Watched file -> the .fmat sources to recompile when it changes (a shared
  // include maps to many; a source maps to itself).
  final Map<String, Set<String>> _fmatsByWatchedFile = {};
  final Set<String> _dirty = {};
  Timer? _debounce;
  bool _disposed = false;

  /// The last compile/load error for [key], or the toolchain error, or null.
  String? errorForKey(String key) {
    final path = resolvePath(key);
    return (path == null ? null : _entries[path]?.lastError) ??
        _toolchainError;
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
        ..metadata =
            (result.sidecar[result.entryName] as Map?)
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
    // A failed probe is terminal for the session (the environment will not
    // change under a running editor); report once and stop retrying.
    if (_toolchainError != null) return null;
    try {
      final toolchain = await findFmatToolchain();
      final cacheDir = Directory(
        '${Directory.systemTemp.path}/flutter_scene_editor/fmat_cache',
      )..createSync(recursive: true);
      _compiler = FmatRuntimeCompiler(
        impellerc: toolchain.impellerc,
        includeDirectories: [toolchain.frameworkShaders],
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
      _fail(entry, 'Could not read .fmat "$path"; keeping the last good '
          'shaders ($e)');
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
        ..metadata =
            (result.sidecar[result.entryName] as Map?)
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
      ..metadata =
          (result.sidecar[result.entryName] as Map?)?.cast<String, Object?>()
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
