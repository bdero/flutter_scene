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

/// Shader backends stored in a Flutter GPU shader bundle.
// TODO(shader-bundle): add desktop OpenGL selection when Flutter GPU exposes
// that target.
enum ShaderBundleBackend { metalIos, metalDesktop, openglEs, vulkan }

/// The backends an app running on [os] needs, spelled the way the hook protocol
/// spells `target_os` (build) and `Platform.operatingSystem` spells it
/// (runtime). Null is web, or a hook invocation whose config names no target
/// OS. A name with no arm here gets the portable set.
///
/// The build and the runtime both resolve through here, so what an output is
/// recorded as and what the app looks for cannot drift apart. Drift is silent,
/// it renders a black frame.
///
/// Every Apple platform but macOS shares the iOS arm, because `metalIos` names
/// a shader family rather than a product. impellerc's two Metal targets differ
/// only in the MSL platform they generate for, iOS or macOS, so the embedded
/// platforms all take the iOS variant. Naming them costs an arm each and keeps
/// an embedder that reports its own OS from asking for a bundle no build
/// produces, whether or not this package can build for it today.
// TODO(watchos-gpu): watchOS has no Metal in its SDK, on the device or the
// simulator, and its engine builds rasterize in software, so nothing renders
// there yet and this arm is inert. It is here so the key still agrees on both
// sides if a GPU path arrives. Revisit when one does.
Set<ShaderBundleBackend> shaderBundleBackendsForOS(String? os) => switch (os) {
  null => const {ShaderBundleBackend.openglEs},
  'ios' ||
  'tvos' ||
  'visionos' ||
  'watchos' => const {ShaderBundleBackend.metalIos},
  'macos' => const {ShaderBundleBackend.metalDesktop},
  'fuchsia' => const {ShaderBundleBackend.vulkan},
  _ => const {ShaderBundleBackend.openglEs, ShaderBundleBackend.vulkan},
};

/// The manifest target naming [backends], in enum order so two builds that pick
/// the same set write the same key.
String shaderTargetKey(Set<ShaderBundleBackend> backends) =>
    (backends.toList()..sort((a, b) => a.index.compareTo(b.index)))
        .map((backend) => backend.name)
        .join(',');

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
    this.target,
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

  /// The [shaderTargetKey] this output is only usable on, or null when it works
  /// everywhere. One tree holds an entry per target, because several builds
  /// share it (one `flutter run` invokes the hook both with and without a
  /// target OS, and a pub-cache tree is shared by every project on the
  /// machine). impellerc compiles every backend; the build then trims each
  /// bundle to its target's, so two targets' outputs are not interchangeable.
  final String? target;

  Map<String, Object?> toJson(String manifestPackage) => {
    'family': family.name,
    'id': id,
    if (owner != manifestPackage) 'owner': owner,
    'file': file,
    'stamp': stamp,
    if (source != null) 'source': source,
    if (target != null) 'target': target,
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
      target: json['target'] as String?,
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
  static const int schema = 3;

  /// The app package the tree belongs to.
  final String package;

  final List<GeneratedAssetEntry> entries;

  /// The entry recorded for [family]/[id] built for exactly [target]. Writers
  /// use this, so a build only ever replaces its own target's entry.
  GeneratedAssetEntry? find(
    GeneratedAssetFamily family,
    String id, {
    String? target,
  }) {
    for (final entry in entries) {
      if (entry.family == family && entry.id == id && entry.target == target) {
        return entry;
      }
    }
    return null;
  }

  /// The entry for [family]/[id] a build for [target] can load, preferring one
  /// compiled for it over a target-agnostic one. Readers use this.
  GeneratedAssetEntry? findForTarget(
    GeneratedAssetFamily family,
    String id,
    String target,
  ) => find(family, id, target: target) ?? find(family, id);

  /// Replaces (or adds) the entry for [entry]'s family, id, and target.
  void put(GeneratedAssetEntry entry) {
    entries.removeWhere(
      (e) =>
          e.family == entry.family &&
          e.id == entry.id &&
          e.target == entry.target,
    );
    entries.add(entry);
  }

  /// Removes the entry for [family]/[id] built for [target], returning it.
  GeneratedAssetEntry? remove(
    GeneratedAssetFamily family,
    String id, {
    String? target,
  }) {
    final entry = find(family, id, target: target);
    if (entry != null) entries.remove(entry);
    return entry;
  }

  Iterable<GeneratedAssetEntry> ofFamily(GeneratedAssetFamily family) =>
      entries.where((entry) => entry.family == family);

  /// [ofFamily] narrowed to what a build for [target] can load.
  Iterable<GeneratedAssetEntry> ofFamilyForTarget(
    GeneratedAssetFamily family,
    String target,
  ) => ofFamily(
    family,
  ).where((entry) => entry.target == null || entry.target == target);

  String encode() {
    final sorted = [...entries]
      ..sort((a, b) {
        final byFamily = a.family.index.compareTo(b.family.index);
        if (byFamily != 0) return byFamily;
        final byId = a.id.compareTo(b.id);
        return byId != 0 ? byId : (a.target ?? '').compareTo(b.target ?? '');
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

/// Thrown for the build-hook asset modes 0.21.0 removed, naming the fix rather
/// than leaving a hook that silently writes somewhere else.
Never throwRemovedAssetMode(String mode, String replacement) =>
    throw UnsupportedError(
      'flutter_scene: $mode was removed in 0.21.0. Generated assets now go '
      'into $generatedAssetsEntry and load by source path on every Flutter '
      'channel, so the mode that picked an output location no longer applies. '
      'Use $replacement, then run `dart run flutter_scene:init` to add the '
      'pubspec assets entry that directory needs. An app loading by explicit '
      'asset key (loadFscenebAsset and friends) reads its new keys from '
      "${generatedAssetsEntry}manifest.json.",
    );
