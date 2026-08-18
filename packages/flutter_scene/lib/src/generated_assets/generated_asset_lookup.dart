/// The runtime half of `flutter_scene_generated/`: resolves a source path to a
/// bundled asset key through the manifest the build hooks wrote.
///
/// The registries scan for DataAssets keys first and come here for everything
/// else, so an app behaves identically whichever asset mode built it, with no
/// app-code change.
library;

import 'package:flutter/foundation.dart' show internal, kDebugMode;
import 'package:flutter/services.dart';

import 'generated_assets.dart';
import 'runtime_target.dart';

/// The [shaderTargetKey] this build's outputs were compiled for. Generated
/// outputs recorded for any other target belong to a build for a different
/// platform that shared the same tree, and are skipped.
final String currentShaderTarget = shaderTargetKey(
  shaderBundleBackendsForOS(runtimeOperatingSystem),
);

/// One generated manifest, plus where its assets are keyed from.
final class GeneratedAssetSource {
  GeneratedAssetSource({required this.keyPrefix, required this.manifest});

  /// The asset-key prefix the manifest's `file` paths hang off, i.e.
  /// `flutter_scene_generated/`.
  final String keyPrefix;

  final GeneratedAssetManifest manifest;

  /// The asset key of [entry]'s output.
  String keyOf(GeneratedAssetEntry entry) => '$keyPrefix${entry.file}';

  /// Whether this tree belongs to a dependency rather than the app. A package's
  /// keys are prefixed `packages/<name>/`, which an app's own tree cannot be.
  bool get isPackageOwned => keyPrefix.startsWith('packages/');
}

/// The generated manifests reachable from an asset bundle, resolved by source
/// path.
final class GeneratedAssetIndex {
  GeneratedAssetIndex(this.sources);

  final List<GeneratedAssetSource> sources;

  static final GeneratedAssetIndex empty = GeneratedAssetIndex(const []);

  bool get isEmpty => sources.isEmpty;

  /// Every match for [id] in [family] usable on this build's target, optionally
  /// narrowed to the assets [package] owns.
  List<({GeneratedAssetSource source, GeneratedAssetEntry entry})> lookup(
    GeneratedAssetFamily family,
    String id, {
    String? package,
  }) => [
    for (final source in sources)
      if (source.manifest.findForTarget(family, id, currentShaderTarget)
          case final entry?)
        if (package == null || entry.owner == package)
          (source: source, entry: entry),
  ];

  /// Every target [family]/[id] was built for, whether or not this build can
  /// use it, so a "not found" can say a bundle is present but for another
  /// platform.
  List<String> targetsOf(
    GeneratedAssetFamily family,
    String id, {
    String? package,
  }) => [
    for (final source in sources)
      for (final entry in source.manifest.entries)
        if (entry.family == family && entry.id == id)
          if (package == null || entry.owner == package) entry.target ?? 'any',
  ];

  /// Every entry of [family] usable on this build's target, with the key its
  /// output is bundled under.
  List<({String key, GeneratedAssetEntry entry})> entriesOf(
    GeneratedAssetFamily family,
  ) => [
    for (final source in sources)
      for (final entry in source.manifest.ofFamilyForTarget(
        family,
        currentShaderTarget,
      ))
        (key: source.keyOf(entry), entry: entry),
  ];

  /// The asset key for [family]/[id] from the first tree that has it, or null.
  ///
  /// Sources are ordered app tree first, so an app that builds flutter_scene's
  /// engine shaders itself gets its own copy and the one in flutter_scene's
  /// package directory is ignored. Only assets a package and the app can both
  /// provide use this; everything else goes through [resolveKey], which reports
  /// the ambiguity instead of picking.
  String? resolveFirstKey(
    GeneratedAssetFamily family,
    String id, {
    String? package,
  }) {
    final matches = lookup(family, id, package: package);
    if (matches.isEmpty) return null;
    return matches.first.source.keyOf(matches.first.entry);
  }

  /// The single asset key for [family]/[id], or null when it is absent.
  /// Throws when more than one package provides it and [package] does not
  /// disambiguate.
  String? resolveKey(
    GeneratedAssetFamily family,
    String id, {
    String? package,
  }) {
    final matches = lookup(family, id, package: package);
    if (matches.isEmpty) return null;
    if (matches.length > 1) {
      final choices = matches.map((m) => m.entry.owner).join(', ');
      throw StateError(
        'Multiple generated ${family.name} assets for source "$id" were found '
        'in packages: $choices. Pass package to disambiguate.',
      );
    }
    return matches.single.source.keyOf(matches.single.entry);
  }
}

const String _manifestSuffix =
    '$generatedAssetsDirectory/$generatedManifestFileName';

final Expando<Future<GeneratedAssetIndex>> _cache =
    Expando<Future<GeneratedAssetIndex>>('flutter_scene generated manifests');

/// Loads (and caches per bundle) every `flutter_scene_generated/manifest.json`
/// the bundle carries.
///
/// A build that registered everything as DataAssets ships no manifest, so this
/// is an empty index there and every lookup falls straight through.
Future<GeneratedAssetIndex> loadGeneratedAssetIndex([AssetBundle? bundle]) {
  final assetBundle = bundle ?? rootBundle;
  return _cache[assetBundle] ??= _load(assetBundle);
}

/// Drops the cached manifests so the next lookup re-reads them.
///
/// Called on hot reload: regenerating a source can add or repoint a manifest
/// entry, and a cached index would keep resolving the old mapping.
@internal
void clearGeneratedAssetIndexCache([AssetBundle? bundle]) {
  _cache[bundle ?? rootBundle] = null;
}

Future<GeneratedAssetIndex> _load(AssetBundle bundle) async {
  List<String> keys;
  try {
    keys = (await AssetManifest.loadFromAssetBundle(bundle)).listAssets();
  } catch (_) {
    return GeneratedAssetIndex.empty;
  }
  final sources = <GeneratedAssetSource>[];
  for (final key in keys.where((key) => key.endsWith(_manifestSuffix))) {
    try {
      if (kDebugMode) bundle.evict(key);
      final manifest = GeneratedAssetManifest.decode(
        await bundle.loadString(key),
      );
      if (manifest == null) continue;
      sources.add(
        GeneratedAssetSource(
          keyPrefix: key.substring(
            0,
            key.length - generatedManifestFileName.length,
          ),
          manifest: manifest,
        ),
      );
    } catch (_) {
      // A manifest that cannot be read contributes nothing.
    }
  }
  // The app's own tree first, so it wins over a dependency's copy of the same
  // asset; alphabetical within each group for a stable order.
  sources.sort((a, b) {
    final byOwner = (a.isPackageOwned ? 1 : 0).compareTo(
      b.isPackageOwned ? 1 : 0,
    );
    return byOwner != 0 ? byOwner : a.keyPrefix.compareTo(b.keyPrefix);
  });
  return GeneratedAssetIndex(sources);
}

/// The tail every registry appends to its "not found" error, naming the fix.
String generatedAssetFixHint(String what) =>
    'Make sure the build hook builds it (`dart run flutter_scene:init` installs '
    'and configures the hook), then rebuild the app. The hook writes $what into '
    '$generatedAssetsDirectory/, which the app lists once under '
    '`flutter: assets:`.';

/// Resolves the asset key of a shader bundle built by
/// `buildTargetShaderBundleJson` (or `flutter_gpu_shaders`'
/// `buildShaderBundleJson`), by its bundle name.
///
/// Hand the result to `loadShaderLibraryAsync`. Pass [package] to disambiguate
/// when more than one package in the app builds a bundle of the same name.
///
/// ```dart
/// final key = await resolveShaderBundleKey('my', package: 'my_app');
/// final library = await gpu.loadShaderLibraryAsync(key);
/// ```
/// {@category Assets and loading}
Future<String> resolveShaderBundleKey(
  String bundleName, {
  String? package,
  AssetBundle? bundle,
}) async {
  final name = bundleName.endsWith('.shaderbundle')
      ? bundleName.substring(0, bundleName.length - '.shaderbundle'.length)
      : bundleName;
  final dataAssetSuffix =
      '/flutter_gpu_shaders/shaderbundles/$name.shaderbundle';
  // Collected inside the guard, judged outside it, so an ambiguity is reported
  // rather than swallowed by the missing-manifest fallback.
  var matches = const <String>[];
  try {
    final keys = (await AssetManifest.loadFromAssetBundle(
      bundle ?? rootBundle,
    )).listAssets();
    matches = keys
        .where(
          (key) =>
              key.endsWith(dataAssetSuffix) &&
              (package == null || key.startsWith('packages/$package/')),
        )
        .toList();
  } catch (_) {
    // No manifest here; the generated index below is the only source.
  }
  if (matches.length == 1) return matches.single;
  if (matches.length > 1) {
    throw StateError(
      'Multiple shader bundles named "$name" were found: '
      '${matches.join(', ')}. Pass package to disambiguate.',
    );
  }
  final index = await loadGeneratedAssetIndex(bundle);
  final key = index.resolveKey(
    GeneratedAssetFamily.shaderBundle,
    name,
    package: package,
  );
  if (key != null) return key;
  throw StateError(
    'No shader bundle named "$name" was found. '
    '${generatedAssetFixHint('shader bundles')}',
  );
}
