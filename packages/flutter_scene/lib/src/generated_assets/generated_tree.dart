/// The build-hook half of `flutter_scene_generated/`: writes the generated
/// tree, its manifest, and checks that the app actually ships it.
///
/// Used only from `hook/build.dart`, so `dart:io` is fine here. The layout and
/// the manifest model live in `generated_assets.dart`, which the runtime
/// registries share.
library;

import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

import '../importer/build_cache.dart';
import 'generated_assets.dart';
import 'generated_file_names.dart';

/// The `flutter.assets` YAML the app needs, ready to paste.
const String generatedAssetsPubspecSnippet =
    'flutter:\n'
    '  assets:\n'
    '    - $generatedAssetsEntry';

/// Thrown when the hook generated assets the app does not list in
/// `flutter.assets`, so the build fails instead of producing an app that dies
/// at the first load.
final class MissingGeneratedAssetEntryException implements Exception {
  MissingGeneratedAssetEntryException(this.package);

  /// The package whose pubspec is missing the entry.
  final String package;

  @override
  String toString() {
    final buffer = StringBuffer(
      'flutter_scene: the build hook writes generated assets into '
      '$generatedAssetsEntry, but "$package"\'s pubspec.yaml does not list that '
      'directory under `flutter: assets:`. Run `dart run flutter_scene:init` in '
      'the app, or add these lines to pubspec.yaml by hand:\n\n'
      '$generatedAssetsPubspecSnippet\n',
    );
    // TODO(package-generated-assets): a third-party package that generates
    // assets for its consumers has no supported path yet. flutter_scene builds
    // its own engine shaders into its own tree (its pubspec lists the
    // directory, and only a keeper file is published), which another package
    // could copy, but nothing packages that as reusable API.
    buffer.write(
      '\nA package that generates assets for its consumers must list its own '
      'generated directory the same way, or use a DataAssets asset mode.\n',
    );
    return buffer.toString();
  }
}

/// Thrown when the generated tree cannot be written, which for flutter_scene's
/// own tree means a read-only package directory (a locked-down pub cache).
final class GeneratedAssetsNotWritableException implements Exception {
  GeneratedAssetsNotWritableException(this.path, this.cause);

  final String path;
  final Object cause;

  @override
  String toString() =>
      'flutter_scene: could not write generated assets into $path ($cause). '
      'Make that directory writable, or enable Dart data assets '
      '(`flutter config --enable-dart-data-assets`), or call buildEngineAssets '
      'from the app\'s own hook/build.dart (`dart run flutter_scene:init`) so '
      'the engine shaders are built into the app instead.';
}

/// Runs [write], reporting a read-only destination as an actionable failure
/// rather than a raw filesystem error.
T guardGeneratedWrite<T>(Uri target, T Function() write) {
  try {
    return write();
  } on FileSystemException catch (e) {
    throw GeneratedAssetsNotWritableException(
      target.toFilePath(),
      e.osError ?? e.message,
    );
  }
}

/// Writes [bytes] to [uri] through a temporary sibling.
///
/// Two builds can share one generated tree (the same pub cache backs every
/// project), so a file must never be visible half-written. The rename is
/// last-writer-wins, and the loser's next build finds a stamp that does not
/// match and rewrites it.
void writeGeneratedBytes(Uri uri, List<int> bytes) =>
    guardGeneratedWrite(uri, () {
      final temp = File.fromUri(Uri.file('${uri.toFilePath()}.$pid.tmp'))
        ..writeAsBytesSync(bytes);
      temp.renameSync(uri.toFilePath());
    });

/// [writeGeneratedBytes] for text.
void writeGeneratedString(Uri uri, String contents) =>
    writeGeneratedBytes(uri, utf8.encode(contents));

/// Creates the generated tree under [packageRoot] and writes its `.gitignore`,
/// so the listed asset directory is present in a fresh clone whose contents are
/// ignored. Writes no manifest.
void createGeneratedAssetsDirectory(Uri packageRoot) {
  final root = packageRoot.resolve('$generatedAssetsDirectory/');
  guardGeneratedWrite(root, () {
    Directory.fromUri(root).createSync(recursive: true);
  });
  final gitignore = File.fromUri(
    root.resolve(generatedAssetsGitignoreFileName),
  );
  if (gitignore.existsSync() &&
      gitignore.readAsStringSync() == generatedAssetsGitignore) {
    return;
  }
  writeGeneratedString(gitignore.uri, generatedAssetsGitignore);
}

/// The app's generated tree, opened for a hook run.
///
/// Each builder opens it, records what it wrote, and saves; the manifest
/// accumulates across builders within a run and persists across runs, so it
/// doubles as the incremental-build stamp store.
/// How long an unreferenced variant of a live output is kept, covering a build
/// racing this one without keeping a variant from an engine long retired.
const Duration variantRetention = Duration(hours: 1);

final class GeneratedAssetTree {
  GeneratedAssetTree._(
    this.packageRoot,
    this.packageName,
    this._manifest,
    this.options,
  );

  /// Opens (or starts) the generated tree of the package rooted at
  /// [packageRoot], creating the directory and its `.gitignore`.
  factory GeneratedAssetTree.open(
    Uri packageRoot,
    String packageName, {
    HookOptions options = const HookOptions(),
  }) {
    final tree = GeneratedAssetTree._(
      packageRoot,
      packageName,
      _readManifest(packageRoot, packageName) ??
          GeneratedAssetManifest(package: packageName),
      options,
    );
    tree._createDirectory();
    return tree;
  }

  /// Opens the tree only when one already exists, so a build that registers data
  /// assets can prune a tree left by an earlier build without creating one.
  static GeneratedAssetTree? openExisting(Uri packageRoot, String packageName) {
    final manifest = _readManifest(packageRoot, packageName);
    if (manifest == null) return null;
    return GeneratedAssetTree._(
      packageRoot,
      packageName,
      manifest,
      const HookOptions(),
    );
  }

  static GeneratedAssetManifest? _readManifest(
    Uri packageRoot,
    String packageName,
  ) {
    final file = File.fromUri(
      packageRoot.resolve(
        '$generatedAssetsDirectory/$generatedManifestFileName',
      ),
    );
    if (!file.existsSync()) return null;
    GeneratedAssetManifest? manifest;
    try {
      manifest = GeneratedAssetManifest.decode(file.readAsStringSync());
    } catch (_) {
      // An unreadable manifest is rebuilt from scratch.
    }
    if (manifest == null || manifest.package != packageName) return null;
    return manifest;
  }

  final Uri packageRoot;
  final String packageName;
  final GeneratedAssetManifest _manifest;
  final HookOptions options;

  Uri get _root => packageRoot.resolve('$generatedAssetsDirectory/');

  void _createDirectory() => createGeneratedAssetsDirectory(packageRoot);

  /// Whether the tree already holds outputs of [family], so a run that now
  /// discovers no sources still has stale outputs to prune.
  bool hasFamily(GeneratedAssetFamily family) =>
      _manifest.ofFamily(family).isNotEmpty;

  /// Fails the build unless the app lists [generatedAssetsEntry] under
  /// `flutter: assets:`. Without it the outputs never reach the app bundle.
  void requireAssetEntry() {
    final assets = readPubspecAssets(
      File.fromUri(packageRoot.resolve('pubspec.yaml')),
    );
    if (assets.contains(normalizeAssetEntry(generatedAssetsEntry))) return;
    throw MissingGeneratedAssetEntryException(packageName);
  }

  /// The absolute location [family]/[nameId] is written to. [extension]
  /// includes the leading dot.
  ///
  /// [target] names the build target an output is only valid for, and separates
  /// the file names of two builds sharing this tree the same way [variant] does
  /// for two engines.
  Uri fileUri(
    GeneratedAssetFamily family, {
    required String nameId,
    required String extension,
    String? variant,
    String? target,
  }) => _root.resolve(
    generatedFileName(
      family,
      nameId,
      extension,
      variant: _variantKey(variant, target),
    ),
  );

  /// Whether the recorded stamp for [family]/[id] on [target] matches [stamp]
  /// and every file in [outputs] still exists, meaning the conversion can be
  /// skipped.
  bool isFresh(
    GeneratedAssetFamily family,
    String id,
    String stamp,
    List<Uri> outputs, {
    String? target,
  }) {
    if (options.rebuildEverything) return false;
    final entry = _manifest.find(family, id, target: target);
    if (entry == null || entry.stamp != _digest(stamp)) return false;
    return outputs.every((uri) => File.fromUri(uri).existsSync());
  }

  /// Records [family]/[id] as built from [source] into [file] (relative to
  /// `flutter_scene_generated/`).
  void record({
    required GeneratedAssetFamily family,
    required String id,
    required String file,
    required String stamp,
    String? owner,
    String? source,
    String? target,
  }) => _manifest.put(
    GeneratedAssetEntry(
      family: family,
      id: id,
      owner: owner ?? packageName,
      file: file,
      // Digested, not stored verbatim: a stamp naming every input runs to
      // kilobytes, and the manifest ships in the app bundle.
      stamp: _digest(stamp),
      source: source,
      target: target,
    ),
  );

  /// Records the output at [uri] (which must be inside the generated tree).
  void recordFile({
    required GeneratedAssetFamily family,
    required String id,
    required Uri uri,
    required String stamp,
    String? owner,
    String? source,
    String? target,
  }) {
    final rootPath = _root.toFilePath(windows: false);
    final path = uri.toFilePath(windows: false);
    record(
      family: family,
      id: id,
      file: path.startsWith(rootPath) ? path.substring(rootPath.length) : path,
      stamp: stamp,
      owner: owner,
      source: source,
      target: target,
    );
  }

  /// Drops entries whose source file is gone and deletes their outputs, so a
  /// deleted `.glb` cannot keep loading from a stale `.fsceneb`.
  ///
  /// Only entries this package owns are considered; a dependency's sources
  /// resolve against that package's root, not the app's.
  ///
  /// TODO(legacy-prune): an entry outlives the builder that wrote it, whether
  /// its family's builder left the hook or a `buildEngineAssets` call did.
  /// A foreign-owned leftover is the one that bites, since the app's tree
  /// resolves ahead of the owning package's, so a stale engine bundle keeps
  /// winning after a Flutter switch. Dropping foreign entries a run did not
  /// re-record needs a per-process run marker rather than per-instance
  /// tracking (each builder opens its own tree), and it must not fire while
  /// the run emits data assets, since one `flutter run` invokes the hook under
  /// several asset-type configs and the data-asset invocation records nothing
  /// into the tree.
  void pruneMissingSources() {
    for (final entry in [..._manifest.entries]) {
      final source = entry.source;
      if (source == null || entry.owner != packageName) continue;
      if (File.fromUri(packageRoot.resolve(source)).existsSync()) continue;
      _manifest.entries.remove(entry);
      _deleteIfPresent(_root.resolve(entry.file));
      stdout.writeln(
        'flutter_scene: dropped the generated ${entry.family.prefix} for '
        'removed source $source',
      );
    }
  }

  /// Drops every [family] entry owned by [owner] and deletes its outputs, for
  /// a build that now registers those assets as DataAssets instead. Reports
  /// once when anything was dropped, so a mode switch is never silent.
  void dropOwned(GeneratedAssetFamily family, {required String owner}) {
    var dropped = 0;
    for (final entry in _manifest.ofFamily(family).toList()) {
      if (entry.owner != owner) continue;
      _manifest.entries.remove(entry);
      _deleteIfPresent(_root.resolve(entry.file));
      dropped++;
    }
    if (dropped == 0) return;
    stdout.writeln(
      'flutter_scene: removed $dropped generated ${family.prefix} '
      '${dropped == 1 ? 'asset' : 'assets'} from $generatedAssetsEntry; this '
      'build registers them as data assets instead.',
    );
  }

  /// Writes the manifest and removes generated files no entry references (an
  /// output renamed by a source move, or left by an older flutter_scene).
  ///
  /// A recently written file that is another variant of a referenced name is
  /// kept, since a concurrent build on a different engine is named by it and
  /// would otherwise lose its asset between its hook and asset bundling. The
  /// window bounds that, because a build racing this one wrote its file moments
  /// ago while a variant left by a Flutter version retired weeks back is only
  /// weight in a directory that ships, survives `flutter clean`, and for a
  /// pub-cache consumer is shared with every project on the machine.
  void save() {
    final referenced = {for (final entry in _manifest.entries) entry.file};
    final variantsOfReferenced = referenced
        .map(generatedNameWithoutTag)
        .nonNulls
        .toSet();
    final directory = Directory.fromUri(_root);
    if (directory.existsSync()) {
      final keepAfter = DateTime.now().subtract(variantRetention);
      for (final file in directory.listSync(followLinks: false)) {
        if (file is! File) continue;
        final name = file.uri.pathSegments.last;
        // Only ever delete files matching the generated naming scheme, so a
        // keeper file in the tree survives.
        if (!isGeneratedFileName(name)) continue;
        if (referenced.contains(name)) continue;
        if (variantsOfReferenced.contains(generatedNameWithoutTag(name)) &&
            file.statSync().modified.isAfter(keepAfter)) {
          continue;
        }
        file.deleteSync();
      }
    }
    if (_manifest.entries.isEmpty && !directory.existsSync()) return;
    final manifestFile = File.fromUri(_root.resolve(generatedManifestFileName));
    guardGeneratedWrite(manifestFile.uri, () {
      manifestFile.parent.createSync(recursive: true);
    });
    final contents = _manifest.encode();
    // Rewriting an identical manifest changes its timestamp, which the tool
    // reads as a modified file and reruns the build for.
    if (manifestFile.existsSync() &&
        manifestFile.readAsStringSync() == contents) {
      return;
    }
    writeGeneratedString(manifestFile.uri, contents);
  }

  static String _digest(String stamp) => fnv1aHex(utf8.encode(stamp));

  static String? _variantKey(String? variant, String? target) {
    if (target == null) return variant;
    return variant == null ? 'target=$target' : '$variant target=$target';
  }

  void _deleteIfPresent(Uri uri) {
    final file = File.fromUri(uri);
    if (file.existsSync()) file.deleteSync();
  }
}

/// A directory entry compares equal with or without its trailing slash.
String normalizeAssetEntry(String entry) =>
    entry.endsWith('/') ? entry.substring(0, entry.length - 1) : entry;

/// The `flutter: assets:` entries of [pubspec], normalized by
/// [normalizeAssetEntry]. A missing or unparseable pubspec reads as none.
List<String> readPubspecAssets(File pubspec) {
  if (!pubspec.existsSync()) return const <String>[];
  return parsePubspecAssets(pubspec.readAsStringSync());
}

/// [readPubspecAssets] over already-read [contents].
List<String> parsePubspecAssets(String contents) {
  final Object? document;
  try {
    document = loadYaml(contents);
  } on YamlException {
    return const <String>[];
  }
  if (document is! YamlMap) return const <String>[];
  final flutter = document['flutter'];
  if (flutter is! YamlMap) return const <String>[];
  final assets = flutter['assets'];
  if (assets is! YamlList) return const <String>[];
  return <String>[
    for (final entry in assets)
      // An entry is either a path or a map whose `path` key holds one (the
      // form that also declares asset transformers).
      if (entry is String)
        normalizeAssetEntry(entry)
      else if (entry is YamlMap && entry['path'] is String)
        normalizeAssetEntry(entry['path'] as String),
  ];
}

/// What [ensureGeneratedAssetsEntry] did to a pubspec.
enum PubspecEditStatus { added, alreadyPresent, unsupported, missingPubspec }

/// The outcome of [ensureGeneratedAssetsEntry].
final class PubspecEditResult {
  const PubspecEditResult(this.status, this.message);

  final PubspecEditStatus status;
  final String message;
}

/// Adds [generatedAssetsEntry] to [pubspec]'s `flutter: assets:` list, keeping
/// every comment and the surrounding order. Idempotent.
PubspecEditResult ensureGeneratedAssetsEntry(File pubspec) {
  if (!pubspec.existsSync()) {
    return const PubspecEditResult(
      PubspecEditStatus.missingPubspec,
      'No pubspec.yaml here. Run this from the app directory.',
    );
  }
  final contents = pubspec.readAsStringSync();
  if (parsePubspecAssets(
    contents,
  ).contains(normalizeAssetEntry(generatedAssetsEntry))) {
    return const PubspecEditResult(
      PubspecEditStatus.alreadyPresent,
      'pubspec.yaml already lists $generatedAssetsEntry under `flutter: '
      'assets:`.',
    );
  }

  final YamlEditor editor;
  try {
    editor = YamlEditor(contents);
    if (editor.parseAt(<Object>[]) is! YamlMap) {
      return const PubspecEditResult(
        PubspecEditStatus.unsupported,
        'pubspec.yaml is not a YAML mapping, so it cannot be edited '
        'automatically. Add these lines by hand:\n\n'
        '$generatedAssetsPubspecSnippet',
      );
    }
    final flutter = editor.parseAt(<Object>[
      'flutter',
    ], orElse: () => wrapAsYamlNode(null));
    if (flutter.value == null) {
      // Appended as text: an inserted mapping key lands at the top of the
      // document, above `name:`.
      final separator = contents.endsWith('\n') ? '' : '\n';
      pubspec.writeAsStringSync(
        '$contents$separator\n$generatedAssetsPubspecSnippet\n',
      );
      return const PubspecEditResult(
        PubspecEditStatus.added,
        'Added a `flutter: assets:` section listing $generatedAssetsEntry to '
        'pubspec.yaml.',
      );
    } else if (editor.parseAt(<Object>[
          'flutter',
          'assets',
        ], orElse: () => wrapAsYamlNode(null))
        is YamlList) {
      editor.appendToList(<Object>['flutter', 'assets'], generatedAssetsEntry);
    } else {
      editor.update(
        <Object>['flutter', 'assets'],
        <String>[generatedAssetsEntry],
      );
    }
  } on YamlException catch (error) {
    return PubspecEditResult(
      PubspecEditStatus.unsupported,
      'pubspec.yaml could not be parsed ($error), so it cannot be edited '
      'automatically. Add these lines by hand:\n\n'
      '$generatedAssetsPubspecSnippet',
    );
  }

  pubspec.writeAsStringSync(editor.toString());
  return const PubspecEditResult(
    PubspecEditStatus.added,
    'Added $generatedAssetsEntry to `flutter: assets:` in pubspec.yaml.',
  );
}
