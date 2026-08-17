/// The `flutter_scene_generated/` layout shared by the build hooks (which
/// write it) and the runtime registries (which read it).
///
/// The hooks convert sources (`.glb`, `.fscene`, images, `.fmat`, shader
/// manifests) into engine-ready assets. Those outputs land in this directory at
/// the app's root, listed once in the app's `flutter.assets`, and a manifest
/// maps each source path to the asset key built from it, so `loadScene`,
/// `loadTexture`, and `loadFmatMaterial` resolve by source path.
///
/// Pure Dart on purpose: hooks run on the plain VM and the registries run on
/// web, so nothing here may touch `dart:io` or Flutter.
library;

import 'dart:convert';

/// The persistent generated-asset directory at the app root, relative to the
/// app's package root. Not under `build/`, so it survives `flutter clean` and
/// stays listed in `flutter.assets`.
const String generatedAssetsDirectory = 'flutter_scene_generated';

/// The manifest file name inside [generatedAssetsDirectory].
const String generatedManifestFileName = 'manifest.json';

/// The one `flutter.assets` entry an app needs to ship the generated tree.
///
/// Flutter's directory entries are not recursive, so the tree is flat and one
/// entry covers every family.
const String generatedAssetsEntry = '$generatedAssetsDirectory/';

/// The `.gitignore` written inside the tree, so generated outputs are ignored
/// without editing the app's own `.gitignore`.
const String generatedAssetsGitignoreFileName = '.gitignore';

/// Contents of the tree's `.gitignore`. Ignores everything but itself, so the
/// directory stays in version control while its contents do not.
const String generatedAssetsGitignore =
    '''
# Written by flutter_scene's build hook. Generated assets are tied to the
# Flutter engine that built them, so they are never committed.
*
!$generatedAssetsGitignoreFileName
''';

/// One family of generated assets. The name prefixes every output file, so
/// families share one flat directory without colliding.
enum GeneratedAssetFamily {
  scene('scene'),
  material('material'),
  texture('texture'),
  shaderBundle('shaderbundle');

  const GeneratedAssetFamily(this.prefix);

  /// The generated file-name prefix for this family.
  final String prefix;

  static GeneratedAssetFamily? byName(String name) {
    for (final family in values) {
      if (family.name == name) return family;
    }
    return null;
  }
}

/// One generated output recorded in a [GeneratedAssetManifest].
final class GeneratedAssetEntry {
  const GeneratedAssetEntry({
    required this.family,
    required this.id,
    required this.owner,
    required this.file,
    required this.stamp,
    this.source,
  });

  /// Which builder produced this output.
  final GeneratedAssetFamily family;

  /// The lookup key within [family]. Source-derived families (scenes,
  /// textures) use the source path relative to [owner]'s root without its
  /// extension; bundle families use the bundle name.
  final String id;

  /// The package the asset belongs to, which is what `package:` disambiguates
  /// on. Assets of a dependency (flutter_scene's own shaders) live in the app's
  /// tree but are owned by that dependency.
  final String owner;

  /// The output path relative to [generatedAssetsDirectory].
  final String file;

  /// The build stamp of the inputs that produced [file]. A rerun whose stamp
  /// matches skips the conversion.
  final String stamp;

  /// The source path relative to [owner]'s root, for families that have one.
  /// An app-owned entry whose source no longer exists is pruned.
  final String? source;

  Map<String, Object?> toJson(String manifestPackage) => {
    'family': family.name,
    'id': id,
    if (owner != manifestPackage) 'owner': owner,
    'file': file,
    'stamp': stamp,
    if (source != null) 'source': source,
  };

  static GeneratedAssetEntry? fromJson(
    Map<String, Object?> json,
    String manifestPackage,
  ) {
    final family = GeneratedAssetFamily.byName(json['family'] as String? ?? '');
    final id = json['id'];
    final file = json['file'];
    if (family == null || id is! String || file is! String) return null;
    return GeneratedAssetEntry(
      family: family,
      id: id,
      owner: json['owner'] as String? ?? manifestPackage,
      file: file,
      stamp: json['stamp'] as String? ?? '',
      source: json['source'] as String?,
    );
  }
}

/// The manifest written to `flutter_scene_generated/manifest.json`, mapping
/// each source path to the generated asset built from it plus the build stamp
/// that produced it.
final class GeneratedAssetManifest {
  GeneratedAssetManifest({
    required this.package,
    List<GeneratedAssetEntry>? entries,
  }) : entries = entries ?? <GeneratedAssetEntry>[];

  /// The manifest schema this build of flutter_scene writes. A manifest with
  /// any other schema is discarded and rebuilt.
  static const int schema = 2;

  /// The app package the tree belongs to.
  final String package;

  final List<GeneratedAssetEntry> entries;

  GeneratedAssetEntry? find(GeneratedAssetFamily family, String id) {
    for (final entry in entries) {
      if (entry.family == family && entry.id == id) return entry;
    }
    return null;
  }

  /// Replaces (or adds) the entry for [entry]'s family and id.
  void put(GeneratedAssetEntry entry) {
    entries.removeWhere((e) => e.family == entry.family && e.id == entry.id);
    entries.add(entry);
  }

  /// Removes the entry for [family]/[id], returning it.
  GeneratedAssetEntry? remove(GeneratedAssetFamily family, String id) {
    final entry = find(family, id);
    if (entry != null) entries.remove(entry);
    return entry;
  }

  Iterable<GeneratedAssetEntry> ofFamily(GeneratedAssetFamily family) =>
      entries.where((entry) => entry.family == family);

  String encode() {
    final sorted = [...entries]
      ..sort((a, b) {
        final byFamily = a.family.index.compareTo(b.family.index);
        return byFamily != 0 ? byFamily : a.id.compareTo(b.id);
      });
    final json = const JsonEncoder.withIndent('  ').convert({
      'schema': schema,
      'package': package,
      'entries': [for (final entry in sorted) entry.toJson(package)],
    });
    return '$json\n';
  }

  /// Parses [contents], returning null when it is unreadable or was written by
  /// an incompatible flutter_scene.
  static GeneratedAssetManifest? decode(String contents) {
    try {
      final json = (jsonDecode(contents) as Map).cast<String, Object?>();
      if (json['schema'] != schema) return null;
      final package = json['package'] as String? ?? '';
      final entries = <GeneratedAssetEntry>[];
      for (final raw in (json['entries'] as List? ?? const [])) {
        final entry = GeneratedAssetEntry.fromJson(
          (raw as Map).cast<String, Object?>(),
          package,
        );
        if (entry != null) entries.add(entry);
      }
      return GeneratedAssetManifest(package: package, entries: entries);
    } catch (_) {
      return null;
    }
  }
}
