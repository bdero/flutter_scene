/// The build-hook half of `flutter_scene_generated/`: writes the generated
/// tree, its manifest, and checks that the app actually ships it.
///
/// Used only from `hook/build.dart`, so `dart:io` is fine here. The layout and
/// the manifest model live in `generated_assets.dart`, which the runtime
/// registries share.
library;

import 'dart:convert';
import 'dart:io';

import 'generated_assets.dart';

/// The `flutter.assets` YAML the app needs, ready to paste.
const String generatedAssetsPubspecSnippet =
    'flutter:\n'
    '  assets:\n'
    '    - $generatedAssetsEntry';

/// Thrown when the hook generated assets the app does not list in
/// `flutter.assets`, so the build fails instead of producing an app that dies
/// at the first load.
final class MissingGeneratedAssetEntryException implements Exception {
  MissingGeneratedAssetEntryException(
    this.package, {
    this.flowStyleAssets = false,
  });

  /// The package whose pubspec is missing the entry.
  final String package;

  /// Whether the pubspec has a flow-style `assets: [...]` list, which the
  /// line-based reader cannot see into.
  final bool flowStyleAssets;

  @override
  String toString() {
    final buffer = StringBuffer(
      'flutter_scene: the build hook writes generated assets into '
      '$generatedAssetsEntry, but "$package"\'s pubspec.yaml does not list that '
      'directory under `flutter: assets:`. Run `dart run flutter_scene:init` in '
      'the app, or add these lines to pubspec.yaml by hand:\n\n'
      '$generatedAssetsPubspecSnippet\n',
    );
    if (flowStyleAssets) {
      buffer.write(
        '\nThe pubspec writes its assets as an inline list '
        '(`assets: [ ... ]`), which cannot be read or edited automatically. '
        'Add the entry by hand, or rewrite the list one item per line.\n',
      );
    }
    // TODO(legacy-package-assets): a package that is not the app cannot ship
    // generated assets this way (its tree would be published to pub.dev and
    // shared across projects through the pub cache). Such a package needs the
    // DataAssets opt-in modes until the app-side hook can convert a
    // dependency's declared sources into the app tree.
    buffer.write(
      '\nOnly the app can ship generated assets this way. A package that '
      'generates assets for its consumers needs a DataAssets asset mode.\n',
    );
    return buffer.toString();
  }
}

/// Creates the generated tree under [packageRoot] and writes its `.gitignore`,
/// so the listed asset directory is present in a fresh clone whose contents are
/// ignored. Writes no manifest.
void createGeneratedAssetsDirectory(Uri packageRoot) {
  final root = packageRoot.resolve('$generatedAssetsDirectory/');
  Directory.fromUri(root).createSync(recursive: true);
  final gitignore = File.fromUri(
    root.resolve(generatedAssetsGitignoreFileName),
  );
  if (gitignore.existsSync() &&
      gitignore.readAsStringSync() == generatedAssetsGitignore) {
    return;
  }
  gitignore.writeAsStringSync(generatedAssetsGitignore);
}

/// The app's generated tree, opened for a hook run.
///
/// Each builder opens it, records what it wrote, and saves; the manifest
/// accumulates across builders within a run and persists across runs, so it
/// doubles as the incremental-build stamp store.
final class GeneratedAssetTree {
  GeneratedAssetTree._(this.packageRoot, this.packageName, this._manifest);

  /// Opens (or starts) the generated tree of the package rooted at
  /// [packageRoot], creating the directory and its `.gitignore`.
  factory GeneratedAssetTree.open(Uri packageRoot, String packageName) {
    final tree = GeneratedAssetTree._(
      packageRoot,
      packageName,
      _readManifest(packageRoot, packageName) ??
          GeneratedAssetManifest(package: packageName),
    );
    tree._createDirectory();
    return tree;
  }

  /// Opens the tree only when one already exists, so a build that emits
  /// DataAssets can prune a tree left by an earlier build without creating one.
  static GeneratedAssetTree? openExisting(Uri packageRoot, String packageName) {
    final manifest = _readManifest(packageRoot, packageName);
    if (manifest == null) return null;
    return GeneratedAssetTree._(packageRoot, packageName, manifest);
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
    if (assets.entries.contains(normalizeAssetEntry(generatedAssetsEntry))) {
      return;
    }
    throw MissingGeneratedAssetEntryException(
      packageName,
      flowStyleAssets: assets.style == PubspecAssetsStyle.flow,
    );
  }

  /// The absolute location [family]/[nameId] is written to. [extension]
  /// includes the leading dot.
  Uri fileUri(
    GeneratedAssetFamily family, {
    required String nameId,
    required String extension,
  }) => _root.resolve(generatedFileName(family, nameId, extension));

  /// Whether the recorded stamp for [family]/[id] matches [stamp] and every
  /// file in [outputs] still exists, meaning the conversion can be skipped.
  bool isFresh(
    GeneratedAssetFamily family,
    String id,
    String stamp,
    List<Uri> outputs,
  ) {
    if (Platform.environment.containsKey('FLUTTER_SCENE_DISABLE_BUILD_CACHE')) {
      return false;
    }
    final entry = _manifest.find(family, id);
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
    );
  }

  /// Drops entries whose source file is gone and deletes their outputs, so a
  /// deleted `.glb` cannot keep loading from a stale `.fsceneb`.
  ///
  /// Only entries this package owns are considered; a dependency's sources
  /// resolve against that package's root, not the app's.
  ///
  /// TODO(legacy-prune): entries of a family whose builder was removed from
  /// the hook outlive it as long as their sources exist. Recording the set of
  /// builders that ran would let a save prune those too.
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
  void save() {
    final referenced = {for (final entry in _manifest.entries) entry.file};
    final directory = Directory.fromUri(_root);
    if (directory.existsSync()) {
      for (final file in directory.listSync(followLinks: false)) {
        if (file is! File) continue;
        final name = file.uri.pathSegments.last;
        // Only ever delete files matching the generated naming scheme, so a
        // keeper file in the tree survives.
        if (!isGeneratedFileName(name)) continue;
        if (referenced.contains(name)) continue;
        file.deleteSync();
      }
    }
    if (_manifest.entries.isEmpty && !directory.existsSync()) return;
    final manifestFile = File.fromUri(_root.resolve(generatedManifestFileName));
    manifestFile.parent.createSync(recursive: true);
    final contents = _manifest.encode();
    // Rewriting an identical manifest changes its timestamp, which the tool
    // reads as a modified file and reruns the build for.
    if (manifestFile.existsSync() &&
        manifestFile.readAsStringSync() == contents) {
      return;
    }
    manifestFile.writeAsStringSync(contents);
  }

  static String _digest(String stamp) => fnv1aHex(utf8.encode(stamp));

  void _deleteIfPresent(Uri uri) {
    final file = File.fromUri(uri);
    if (file.existsSync()) file.deleteSync();
  }
}

/// How a pubspec writes its `flutter: assets:` list.
enum PubspecAssetsStyle {
  /// No `assets:` key under the top-level `flutter:` key.
  absent,

  /// One `- entry` per line, the form this package reads and edits.
  block,

  /// An inline `assets: [a, b]` list, which the line-based reader cannot see
  /// into and reports rather than treating as empty.
  flow,
}

/// The `flutter: assets:` list of a pubspec, as written.
final class PubspecAssets {
  const PubspecAssets(this.style, this.entries);

  static const PubspecAssets none = PubspecAssets(
    PubspecAssetsStyle.absent,
    <String>[],
  );

  final PubspecAssetsStyle style;

  /// The listed paths, normalized by [normalizeAssetEntry]. Always empty for
  /// [PubspecAssetsStyle.flow].
  final List<String> entries;
}

/// Reads the `flutter: assets:` list of [pubspec].
///
/// Line-based so a hand-maintained pubspec keeps its comments and ordering;
/// `dart run flutter_scene:init` edits it the same way.
PubspecAssets readPubspecAssets(File pubspec) {
  if (!pubspec.existsSync()) return PubspecAssets.none;
  return parsePubspecAssets(pubspec.readAsLinesSync());
}

/// [readPubspecAssets] over already-read [lines].
PubspecAssets parsePubspecAssets(List<String> lines) {
  final flutter = pubspecFlutterBlock(lines);
  if (flutter == null) return PubspecAssets.none;
  final assets = _assetsKeyLine(lines, flutter);
  if (assets == null) return PubspecAssets.none;
  if (assets.flow) {
    return const PubspecAssets(PubspecAssetsStyle.flow, <String>[]);
  }
  final entries = <String>[];
  for (var i = assets.line + 1; i < flutter.end; i++) {
    final trimmed = lines[i].trimLeft();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    final indent = lines[i].length - trimmed.length;
    if (indent <= flutter.childIndent) break;
    if (!trimmed.startsWith('- ')) continue;
    final value = _stripInlineComment(trimmed.substring(2)).trim();
    final unquoted = value.replaceAll('"', '').replaceAll("'", '');
    if (unquoted.isNotEmpty) entries.add(normalizeAssetEntry(unquoted));
  }
  return PubspecAssets(PubspecAssetsStyle.block, entries);
}

/// A directory entry compares equal with or without its trailing slash.
String normalizeAssetEntry(String entry) =>
    entry.endsWith('/') ? entry.substring(0, entry.length - 1) : entry;

/// The extent of the top-level `flutter:` mapping in [lines].
///
/// [start] is its key line, [end] is one past its block, and [childIndent] is
/// the indent of its direct children (2 when the block is empty).
final class PubspecFlutterBlock {
  const PubspecFlutterBlock(this.start, this.end, this.childIndent);

  final int start;
  final int end;
  final int childIndent;
}

/// Locates the top-level `flutter:` mapping in [lines], or null when absent.
PubspecFlutterBlock? pubspecFlutterBlock(List<String> lines) {
  for (var i = 0; i < lines.length; i++) {
    if (lines[i] != 'flutter:') continue;
    var end = lines.length;
    var childIndent = -1;
    for (var j = i + 1; j < lines.length; j++) {
      final trimmed = lines[j].trimLeft();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      final indent = lines[j].length - trimmed.length;
      if (indent == 0) {
        end = j;
        break;
      }
      if (childIndent < 0) childIndent = indent;
    }
    return PubspecFlutterBlock(i, end, childIndent < 0 ? 2 : childIndent);
  }
  return null;
}

/// The `assets:` key line inside [flutter], and whether it holds an inline
/// list.
({int line, bool flow})? _assetsKeyLine(
  List<String> lines,
  PubspecFlutterBlock flutter,
) {
  for (var i = flutter.start + 1; i < flutter.end; i++) {
    final trimmed = lines[i].trimLeft();
    if (!trimmed.startsWith('assets:')) continue;
    // Only a direct child of `flutter:` is the asset list; a deeper `assets:`
    // belongs to something else (a deferred component, another tool's block).
    if (lines[i].length - trimmed.length != flutter.childIndent) continue;
    final rest = _stripInlineComment(
      trimmed.substring('assets:'.length),
    ).trim();
    return (line: i, flow: rest.isNotEmpty);
  }
  return null;
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
    return PubspecEditResult(
      PubspecEditStatus.missingPubspec,
      'No pubspec.yaml here. Run this from the app directory.',
    );
  }
  final lines = pubspec.readAsStringSync().split('\n');
  final assets = parsePubspecAssets(lines);
  if (assets.entries.contains(normalizeAssetEntry(generatedAssetsEntry))) {
    return PubspecEditResult(
      PubspecEditStatus.alreadyPresent,
      'pubspec.yaml already lists $generatedAssetsEntry under `flutter: '
      'assets:`.',
    );
  }
  if (assets.style == PubspecAssetsStyle.flow) {
    return PubspecEditResult(
      PubspecEditStatus.unsupported,
      'pubspec.yaml writes its assets as an inline list (`assets: [ ... ]`), '
      'which cannot be edited automatically. Add "$generatedAssetsEntry" to '
      'that list by hand.',
    );
  }

  final flutter = pubspecFlutterBlock(lines);
  if (flutter == null) {
    final trailing = lines.isNotEmpty && lines.last.trim().isEmpty ? '' : '\n';
    pubspec.writeAsStringSync(
      '${lines.join('\n')}$trailing\n$generatedAssetsPubspecSnippet\n',
    );
    return PubspecEditResult(
      PubspecEditStatus.added,
      'Added a `flutter: assets:` section listing $generatedAssetsEntry to '
      'pubspec.yaml.',
    );
  }

  final assetsKey = _assetsKeyLine(lines, flutter);
  final int insertAt;
  final List<String> inserted;
  if (assetsKey == null) {
    insertAt = _lastContentLine(lines, flutter.start + 1, flutter.end) + 1;
    inserted = [
      '${' ' * flutter.childIndent}assets:',
      '${' ' * (flutter.childIndent + 2)}- $generatedAssetsEntry',
    ];
  } else {
    // Stop at the next key of the same depth, so the entry lands inside the
    // asset list rather than after whatever follows it.
    final assetsEnd = _blockEnd(
      lines,
      assetsKey.line,
      flutter.end,
      flutter.childIndent,
    );
    insertAt = _lastContentLine(lines, assetsKey.line + 1, assetsEnd) + 1;
    final itemIndent = _firstItemIndent(lines, assetsKey.line + 1, assetsEnd);
    inserted = [
      '${' ' * (itemIndent ?? flutter.childIndent + 2)}'
          '- $generatedAssetsEntry',
    ];
  }
  lines.insertAll(insertAt, inserted);
  pubspec.writeAsStringSync(lines.join('\n'));
  return PubspecEditResult(
    PubspecEditStatus.added,
    'Added $generatedAssetsEntry to `flutter: assets:` in pubspec.yaml.',
  );
}

/// One past the block opened at [start], the first line in `[start, limit)`
/// whose indent is at most [indent].
int _blockEnd(List<String> lines, int start, int limit, int indent) {
  for (var i = start + 1; i < limit && i < lines.length; i++) {
    final trimmed = lines[i].trimLeft();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    if (lines[i].length - trimmed.length <= indent) return i;
  }
  return limit;
}

/// The last non-blank, non-comment line index in `[from, end)`, or [from] - 1
/// when the range holds none.
int _lastContentLine(List<String> lines, int from, int end) {
  var last = from - 1;
  for (var i = from; i < end && i < lines.length; i++) {
    final trimmed = lines[i].trimLeft();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    last = i;
  }
  return last;
}

/// The indent of the first `- ` item in `[from, end)`, or null when there is
/// none.
int? _firstItemIndent(List<String> lines, int from, int end) {
  for (var i = from; i < end && i < lines.length; i++) {
    final trimmed = lines[i].trimLeft();
    if (!trimmed.startsWith('- ')) continue;
    return lines[i].length - trimmed.length;
  }
  return null;
}

/// [text] up to its first `#` outside a quoted run.
String _stripInlineComment(String text) {
  var quote = '';
  for (var i = 0; i < text.length; i++) {
    final char = text[i];
    if (quote.isEmpty && (char == '"' || char == "'")) {
      quote = char;
      continue;
    }
    if (quote == char) {
      quote = '';
      continue;
    }
    if (quote.isEmpty && char == '#') return text.substring(0, i);
  }
  return text;
}
