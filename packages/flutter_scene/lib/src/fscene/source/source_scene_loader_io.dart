/// Native implementation of debug source-direct scene loading.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:scene/scene.dart';

import '../../hot_reload/fingerprinted_bundle.dart';

/// The project directory scene sources load from, set by the launcher (the
/// editor's Play session passes the open project's root).
const String _sourceRootDefine = String.fromEnvironment(
  'FLUTTER_SCENE_SOURCE_ROOT',
);

String? _debugRootOverride;
SceneSourceLoader? _active;
bool _resolved = false;

/// The process-wide source loader, or null when source-direct loading is
/// inactive (release builds, web, no define, or the directory is gone).
SceneSourceLoader? activeSceneSourceLoader() {
  if (!kDebugMode) return null;
  if (!_resolved) {
    _resolved = true;
    final root = _debugRootOverride ?? _sourceRootDefine;
    if (root.isNotEmpty && Directory(root).existsSync()) {
      _active = SceneSourceLoader._(
        root.endsWith('/') ? root.substring(0, root.length - 1) : root,
      );
      debugPrint('flutter_scene: loading scene sources from $root');
    }
  }
  return _active;
}

/// Whether scenes are loading straight from project sources (reported to the
/// editor by `ext.flutter_scene.reloadScene`).
bool get sceneSourceLoadingActive => activeSceneSourceLoader() != null;

/// Points source-direct loading at [root] (null deactivates), replacing the
/// dart-define for tests.
@visibleForTesting
void debugSetSceneSourceRoot(String? root) {
  _debugRootOverride = root;
  _active = null;
  _resolved = false;
}

/// Reads scene documents from files under the project [root], preparing them
/// the way `buildScenes` would: payload-sidecar bytes attached, and image and
/// prefab references rebased from document-relative to project-relative keys
/// that [bundle] serves.
final class SceneSourceLoader {
  SceneSourceLoader._(this.root) : bundle = _SourceOverlayBundle(root);

  /// The absolute project root (no trailing separator).
  final String root;

  /// Serves project-relative keys from files under [root], delegating
  /// anything else (bundled DataAssets, the asset manifest) to [rootBundle].
  final AssetBundle bundle;

  /// Resolves a `loadScene` source path to a project-relative document key,
  /// or null when no source file exists under the root.
  String? resolveScene(String sourcePath) =>
      _probeDocument(_normalizeKey(sourcePath));

  /// Resolves a prefab reference (relative to the referencing document at
  /// [hostKey], or project-relative) to a document key, or null.
  String? resolveRef(String hostKey, String refKey) =>
      _resolveFromDir(_dirOf(hostKey), refKey);

  String? _resolveFromDir(String dir, String refKey) {
    if (dir.isNotEmpty) {
      final joined = _probeDocument(_joinKey(dir, refKey));
      if (joined != null) return joined;
    }
    return _probeDocument(_normalizeKey(refKey));
  }

  /// Whether [key] is a project-relative document key this loader reads.
  bool isSourceKey(String key) =>
      (key.endsWith('.fscene') || key.endsWith('.fsceneb')) &&
      _fileFor(key).existsSync();

  /// When [error] is a filesystem failure, returns true so this load falls
  /// back to the bundled DataAssets. A permission denial (the macOS App
  /// Sandbox being the common one; stat can succeed where open is refused)
  /// additionally deactivates source loading for the rest of the run; a
  /// transient failure (a sidecar mid-rewrite during a save, a file deleted
  /// between stat and read) keeps it active so the next load retries the
  /// sources. Anything else returns false.
  bool deactivateOnAccessError(Object error, String key) {
    if (error is! FileSystemException) return false;
    final errno = error.osError?.errorCode;
    // POSIX EPERM/EACCES; Windows OSError carries Win32 codes, where 1/13
    // mean something unrelated and denial is ERROR_ACCESS_DENIED.
    final denied = Platform.isWindows ? errno == 5 : errno == 1 || errno == 13;
    if (!denied) {
      debugPrint(
        'flutter_scene: failed reading scene source "$key" '
        '(${error.message}); using the bundled asset for this load.',
      );
      return true;
    }
    _active = null;
    debugPrint(
      'flutter_scene: cannot read scene sources under $root '
      '("$key": ${error.message}); falling back to bundled assets. On macOS '
      'this is usually the App Sandbox; allow file access in '
      'DebugProfile.entitlements to load sources directly.',
    );
    return true;
  }

  /// Reads and prepares the document at project-relative [key], recording
  /// every file consumed (the document, plus its payload sidecar) into
  /// [dependencies] as keys [bundle] can hash for hot reload.
  ///
  /// TODO(source-textures): content edits to a referenced external image are
  /// invisible here (the document is unchanged); track referenced image files
  /// and refresh their textures on reload.
  /// TODO(source-prefab-cache): a re-read `.fsceneb` prefab allocates fresh
  /// payload buffers each reload, so its resources fail the identity check in
  /// ResourceRealizer.adoptUnchanged and rebuild; cache parsed prefab
  /// documents by mtime+size the way the payload sidecar is.
  Future<SceneDocument> readDocument(
    String key,
    Set<String> dependencies,
  ) async {
    dependencies.add(key);
    final file = _fileFor(key);
    final SceneDocument document;
    if (key.endsWith('.fsceneb')) {
      document = readFsceneb(await file.readAsBytes());
    } else {
      document = readFscene(await file.readAsString());
      final sidecar = document.payloadSource;
      if (sidecar != null) {
        await _attachPayloadSidecar(document, key, sidecar, dependencies);
      }
    }
    _rebaseDocumentAssets(document, _dirOf(key));
    return document;
  }

  /// Copies payload bytes from the sidecar `.fsceneb` beside the document
  /// into matching manifest-only entries. A missing or mismatched sidecar
  /// entry degrades to the realizer's placeholder instead of failing the
  /// reload loop.
  Future<void> _attachPayloadSidecar(
    SceneDocument document,
    String documentKey,
    String sidecarRef,
    Set<String> dependencies,
  ) async {
    final sidecarKey = _joinKey(_dirOf(documentKey), sidecarRef);
    final file = _fileFor(sidecarKey);
    if (!await file.exists()) {
      debugPrint(
        'flutter_scene: payload source "$sidecarRef" of "$documentKey" was '
        'not found under $root',
      );
      return;
    }
    dependencies.add(sidecarKey);
    // A sidecar can be huge (bistro's is ~900MB, ~0.9s to read and parse);
    // cache the parsed payloads by mtime+size so the repeated reloads of an
    // edit session re-attach the same byte buffers instead of re-reading.
    final stat = file.statSync();
    var cached = _sidecarCache[sidecarKey];
    if (cached == null ||
        cached.mtimeUs != stat.modified.microsecondsSinceEpoch ||
        cached.length != stat.size) {
      final Map<LocalId, PayloadSpec> payloads;
      try {
        payloads = readFsceneb(await file.readAsBytes()).payloads;
      } on Exception catch (e) {
        debugPrint(
          'flutter_scene: payload source "$sidecarKey" failed to read: $e',
        );
        return;
      }
      cached = _SidecarCache(
        stat.modified.microsecondsSinceEpoch,
        stat.size,
        payloads,
      );
      _sidecarCache[sidecarKey] = cached;
    }
    for (final entry in document.payloads.entries) {
      if (entry.value.bytes != null) continue;
      final supplied = cached.payloads[entry.key];
      final bytes = supplied?.bytes;
      if (supplied == null ||
          bytes == null ||
          !_samePayloadDescriptor(entry.value, supplied)) {
        debugPrint(
          'flutter_scene: payload source "$sidecarKey" has no matching bytes '
          'for ${entry.key}',
        );
        continue;
      }
      entry.value.bytes = bytes;
    }
  }

  final Map<String, _SidecarCache> _sidecarCache = {};

  /// Rewrites document-relative image, environment, and prefab references to
  /// project-relative keys when the referenced file exists, mirroring how the
  /// build inlines them (references are authored relative to the document's
  /// directory). Unresolved references are left for the bundled-asset
  /// fallback.
  void _rebaseDocumentAssets(SceneDocument document, String dir) {
    String? rebase(String key) {
      if (dir.isEmpty) return null;
      final joined = _joinKey(dir, key);
      if (joined == key || !_fileFor(joined).existsSync()) return null;
      return joined;
    }

    // The DataAssets material registry keys `.fmat` sources (materials and
    // shader skies) by their project-relative path, so document-relative
    // refs rebase like the other asset kinds. An absolute path under the
    // root (written by older editor saves) heals to project-relative.
    String? rebaseFmat(String rawKey) {
      final key = rawKey.replaceAll('\\', '/');
      final rootPrefix = '${root.replaceAll('\\', '/')}/';
      final rebased = key.startsWith(rootPrefix)
          ? key.substring(rootPrefix.length)
          : rebase(key);
      return rebased == null || rebased == rawKey ? null : rebased;
    }

    for (final node in document.nodes.values) {
      final instance = node.instance;
      if (instance == null) continue;
      final rebased = _resolveFromDir(dir, instance.source.key);
      if (rebased == null || rebased == instance.source.key) continue;
      node.instance = instance.copyWith(source: AssetRef(rebased));
    }
    for (final entry in document.resources.entries.toList()) {
      final resource = entry.value;
      if (resource is TextureResource && resource.asset != null) {
        final rebased = rebase(resource.asset!.key);
        if (rebased == null) continue;
        document.resources[entry.key] = TextureResource(
          resource.id,
          asset: AssetRef(rebased),
          content: resource.content,
        );
      } else if (resource is MaterialResource &&
          resource.type == 'fmat' &&
          resource.asset != null) {
        final rebased = rebaseFmat(resource.asset!.key);
        if (rebased != null) {
          document.resources[entry.key] = resource.copyWith(
            asset: AssetRef(rebased),
          );
        }
      } else if (resource is EnvironmentResource) {
        if (resource.environment is AssetEnvironment) {
          final environment = resource.environment as AssetEnvironment;
          final rebased = rebase(environment.asset.key);
          if (rebased != null) {
            resource.environment = AssetEnvironment(AssetRef(rebased));
          }
        }
        final lut = resource.effects.colorGradingLut;
        if (lut != null) {
          final rebased = rebase(lut.key);
          if (rebased != null) {
            resource.effects.colorGradingLut = AssetRef(rebased);
          }
        }
        // Shader skies reference `.fmat` sources the same way materials do.
        final skybox = resource.skybox;
        if (skybox != null && skybox.source is FmatSkySpec) {
          final sky = skybox.source as FmatSkySpec;
          final rebased = rebaseFmat(sky.asset.key);
          if (rebased != null) {
            skybox.source = FmatSkySpec(
              AssetRef(rebased),
              properties: sky.properties,
            );
          }
        }
        final skyEnvironment = resource.skyEnvironment;
        if (skyEnvironment != null && skyEnvironment.source is FmatSkySpec) {
          final sky = skyEnvironment.source as FmatSkySpec;
          final rebased = rebaseFmat(sky.asset.key);
          if (rebased != null) {
            skyEnvironment.source = FmatSkySpec(
              AssetRef(rebased),
              properties: sky.properties,
            );
          }
        }
      }
    }
  }

  /// A document key for [key] when its source exists: the key as given, then
  /// sibling `.fscene`/`.fsceneb` spellings (a built app references prefabs
  /// by their converted `.fsceneb` name even when the project holds the
  /// `.fscene` source). `.glb` references stay on the built DataAsset (the
  /// runtime cannot compose a glTF into a document).
  String? _probeDocument(String key) {
    final base = _stripDocumentExtension(key);
    for (final candidate in ['$base.fscene', '$base.fsceneb']) {
      if (_fileFor(candidate).existsSync()) return candidate;
    }
    return null;
  }

  static String _stripDocumentExtension(String key) {
    for (final extension in ['.fscene', '.fsceneb', '.glb']) {
      if (key.endsWith(extension)) {
        return key.substring(0, key.length - extension.length);
      }
    }
    return key;
  }

  File _fileFor(String key) => File('$root/$key');

  static bool _samePayloadDescriptor(PayloadSpec a, PayloadSpec b) =>
      a.encoding == b.encoding &&
      a.layout == b.layout &&
      a.format == b.format &&
      a.width == b.width &&
      a.height == b.height &&
      a.length == b.length;
}

class _SidecarCache {
  _SidecarCache(this.mtimeUs, this.length, this.payloads);

  final int mtimeUs;
  final int length;
  final Map<LocalId, PayloadSpec> payloads;
}

// The directory part of a project-relative key, or empty.
String _dirOf(String key) {
  final slash = key.lastIndexOf('/');
  return slash < 0 ? '' : key.substring(0, slash);
}

// Joins [rel] onto [dir] and normalizes `.`/`..` segments (both
// `/`-separated, project-relative).
String _joinKey(String dir, String rel) {
  final out = <String>[];
  for (final segment in [...dir.split('/'), ..._normalizeKey(rel).split('/')]) {
    if (segment.isEmpty || segment == '.') continue;
    if (segment == '..') {
      if (out.isNotEmpty) out.removeLast();
      continue;
    }
    out.add(segment);
  }
  return out.join('/');
}

String _normalizeKey(String path) => path.replaceAll('\\', '/');

/// Serves project files by project-relative key, falling back to the real
/// bundle for everything else (DataAssets, `AssetManifest.bin`). Byte loads
/// are never cached, so hot-reload re-reads see the changed file, and
/// file-backed keys fingerprint by stat so change scans never read them.
final class _SourceOverlayBundle extends CachingAssetBundle
    implements FingerprintedAssetBundle {
  _SourceOverlayBundle(this.root);

  final String root;

  @override
  Future<ByteData> load(String key) async {
    final file = File('$root/$key');
    if (await file.exists()) {
      return ByteData.sublistView(await file.readAsBytes());
    }
    return rootBundle.load(key);
  }

  @override
  int? fingerprintFor(String key) {
    final stat = File('$root/$key').statSync();
    if (stat.type == FileSystemEntityType.notFound) return null;
    return Object.hash(stat.modified.microsecondsSinceEpoch, stat.size);
  }

  @override
  void evict(String key) {
    super.evict(key);
    rootBundle.evict(key);
  }
}
