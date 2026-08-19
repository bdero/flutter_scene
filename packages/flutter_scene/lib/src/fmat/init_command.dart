import 'dart:io';
import 'dart:isolate';

import '../generated_assets/generated_assets.dart';
import '../generated_assets/generated_tree.dart';

const String hookStartMarker = '// flutter_scene:init:start';
const String hookEndMarker = '// flutter_scene:init:end';

const String _hookSnippet =
    '''
$hookStartMarker
    // Import .glb and .fscene sources under assets/, loadable by source path
    // with loadScene (and hot-reloadable). A no-op when there are no scenes.
    buildScenes(buildInput: input, buildOutput: output);
    // Compile .fmat materials under assets/, loadable by source path with
    // loadFmatMaterial (and hot-reloadable). A no-op when there are none.
    await buildMaterials(buildInput: input, buildOutput: output);
$hookEndMarker''';

const String generatedBuildHook =
    '''
import 'package:flutter_scene/build_hooks.dart';
import 'package:hooks/hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
$_hookSnippet
  });
}
''';

const String manualInstallInstructions =
    '''
Add this call to your existing hook/build.dart:

$_hookSnippet

Then list the generated directory in pubspec.yaml:

$generatedAssetsPubspecSnippet
''';

enum InitHookStatus { created, updated, alreadyConfigured, needsManualInstall }

final class InitHookResult {
  const InitHookResult(this.status, this.message);

  final InitHookStatus status;
  final String message;
}

/// Sets a project up for flutter_scene's build hook: installs (or refreshes)
/// `hook/build.dart`, creates `flutter_scene_generated/` with its `.gitignore`,
/// and lists that directory in `pubspec.yaml`. Idempotent.
Future<InitHookResult> installFlutterSceneBuildHook({
  Directory? projectRoot,
}) async {
  final root = projectRoot ?? Directory.current;
  final notes = <String>[];

  final hook = _installHook(root);
  notes.add(hook.message);

  // Creating the tree keeps the listed asset directory present in a fresh
  // clone, where its contents are ignored.
  createGeneratedAssetsDirectory(root.uri);
  notes.add('Created $generatedAssetsEntry with a .gitignore for its outputs.');

  final pubspec = ensureGeneratedAssetsEntry(
    File.fromUri(root.uri.resolve('pubspec.yaml')),
  );
  notes.add(pubspec.message);

  final needsHand =
      pubspec.status == PubspecEditStatus.unsupported ||
      pubspec.status == PubspecEditStatus.missingPubspec;
  return InitHookResult(
    needsHand ? InitHookStatus.needsManualInstall : hook.status,
    notes.join('\n'),
  );
}

/// The bundled agent skill teaching correct flutter_scene usage.
const String flutterSceneSkillName = 'flutter_scene-idioms';

// Agent skill homes. The skill installs under `<parent>/skills/` for every
// parent already present in the project, defaulting to `.claude` when none is.
const List<String> _agentSkillParents = <String>[
  '.claude',
  '.cursor',
  '.codex',
  '.opencode',
  '.cline',
  '.gemini',
  '.github',
  '.agents',
];

/// What re-running the skill install would do, given what is on disk.
enum SkillInstallAction {
  /// The skill is not in any target home yet.
  install,

  /// A target home has an older version than the bundled one.
  update,

  /// Every target home already has the bundled version.
  upToDate,

  /// The bundled skill could not be located (an old package, or a git dep
  /// published without it).
  sourceMissing,
}

/// The result of inspecting the skill state without writing anything.
final class SkillInstallPlan {
  const SkillInstallPlan(
    this.action, {
    this.bundledVersion,
    this.installedVersion,
    this.homes = const [],
  });

  final SkillInstallAction action;

  /// The version shipped with this package.
  final int? bundledVersion;

  /// The lowest version found across target homes, or null when absent.
  final int? installedVersion;

  /// The agent-home skill paths that a write would create or refresh.
  final List<String> homes;
}

/// Inspects the skill state without writing. Callers use [SkillInstallPlan.action]
/// to decide whether to prompt (install vs update vs nothing) before calling
/// [installFlutterSceneSkills].
Future<SkillInstallPlan> planFlutterSceneSkillInstall({
  Directory? projectRoot,
  Uri? skillSource,
}) async {
  final root = projectRoot ?? Directory.current;
  final source = skillSource ?? await _resolveBundledSkill();
  if (source == null || !Directory.fromUri(source).existsSync()) {
    return const SkillInstallPlan(SkillInstallAction.sourceMissing);
  }

  final bundled = _skillVersion(File.fromUri(source.resolve('SKILL.md')));
  final homes = _skillHomes(root);

  int? installed;
  for (final home in homes) {
    final file = File.fromUri(root.uri.resolve('$home/SKILL.md'));
    if (!file.existsSync()) continue;
    final version = _skillVersion(file);
    installed = installed == null
        ? version
        : (version < installed ? version : installed);
  }

  final action = installed == null
      ? SkillInstallAction.install
      : (bundled > installed
            ? SkillInstallAction.update
            : SkillInstallAction.upToDate);
  return SkillInstallPlan(
    action,
    bundledVersion: bundled,
    installedVersion: installed,
    homes: homes,
  );
}

/// A human-readable status line for [plan], shared by `flutter_scene:init` and
/// the `flutter_scene:skills` command so both describe the state the same way.
String describeSkillPlan(SkillInstallPlan plan) {
  switch (plan.action) {
    case SkillInstallAction.sourceMissing:
      return 'Could not locate the bundled flutter_scene skill. This package '
          'version may predate it, or it is a git dependency published '
          'without it.';
    case SkillInstallAction.upToDate:
      return 'The flutter_scene agent skill is up to date '
          '(v${plan.bundledVersion}).';
    case SkillInstallAction.install:
      return 'The flutter_scene agent skill (v${plan.bundledVersion}) is not '
          'installed. Install it with: dart run flutter_scene:skills';
    case SkillInstallAction.update:
      return 'A newer flutter_scene agent skill is available (installed '
          'v${plan.installedVersion}, this package ships '
          'v${plan.bundledVersion}). Update it with: '
          'dart run flutter_scene:skills';
  }
}

enum InitSkillStatus { installed, sourceMissing }

final class InitSkillResult {
  const InitSkillResult(this.status, this.message);

  final InitSkillStatus status;
  final String message;
}

/// Copies the bundled `flutter_scene-idioms` skill into the project's agent
/// skill homes. Writes into every known agent home already present, or `.claude`
/// by default, and overwrites so an upgrade refreshes the skill. Never called
/// without the caller having established consent (a prompt or a flag).
Future<InitSkillResult> installFlutterSceneSkills({
  Directory? projectRoot,
  Uri? skillSource,
}) async {
  final root = projectRoot ?? Directory.current;
  final source = skillSource ?? await _resolveBundledSkill();
  if (source == null || !Directory.fromUri(source).existsSync()) {
    return const InitSkillResult(
      InitSkillStatus.sourceMissing,
      'Could not locate the bundled flutter_scene skill; skipped skill install.',
    );
  }

  final homes = _skillHomes(root);
  for (final home in homes) {
    _copyDirectory(source, root.uri.resolve('$home/'));
  }
  return InitSkillResult(
    InitSkillStatus.installed,
    'Installed the flutter_scene agent skill into ${homes.join(', ')}.',
  );
}

// The agent-home skill paths to write to: `<parent>/skills/<skill>` for every
// known parent already present, or `.claude` when none is.
List<String> _skillHomes(Directory root) {
  final present = _agentSkillParents
      .where((p) => Directory.fromUri(root.uri.resolve('$p/')).existsSync())
      .toList();
  if (present.isEmpty) present.add('.claude');
  return [for (final p in present) '$p/skills/$flutterSceneSkillName'];
}

// Reads the `version:` field from a SKILL.md frontmatter. A skill installed
// before versioning, or a malformed one, reads as 0 so it is treated as stale.
int _skillVersion(File skill) {
  if (!skill.existsSync()) return 0;
  var inFrontmatter = false;
  for (final line in skill.readAsLinesSync()) {
    final trimmed = line.trim();
    if (trimmed == '---') {
      if (inFrontmatter) break; // Closing fence, no version found.
      inFrontmatter = true;
      continue;
    }
    if (!inFrontmatter) continue;
    final match = RegExp(r'^version:\s*(\d+)\s*$').firstMatch(trimmed);
    if (match != null) return int.parse(match.group(1)!);
  }
  return 0;
}

// The bundled skill lives at the package root next to lib/, so resolve a
// library file and step up out of lib/.
Future<Uri?> _resolveBundledSkill() async {
  final lib = await Isolate.resolvePackageUri(
    Uri.parse('package:flutter_scene/scene.dart'),
  );
  return lib?.resolve('../skills/$flutterSceneSkillName/');
}

void _copyDirectory(Uri from, Uri to) {
  final source = Directory.fromUri(from);
  final base = from.toFilePath();
  for (final entity in source.listSync(recursive: true)) {
    if (entity is! File) continue;
    final relative = entity.path.substring(base.length);
    final target = File.fromUri(to.resolve(relative));
    target.parent.createSync(recursive: true);
    entity.copySync(target.path);
  }
}

InitHookResult _installHook(Directory root) {
  final hookDirectory = Directory.fromUri(root.uri.resolve('hook/'));
  final hookFile = File.fromUri(hookDirectory.uri.resolve('build.dart'));

  if (!hookFile.existsSync()) {
    hookDirectory.createSync(recursive: true);
    hookFile.writeAsStringSync(generatedBuildHook);
    return const InitHookResult(
      InitHookStatus.created,
      'Created hook/build.dart, which converts your assets at build time.',
    );
  }

  final contents = hookFile.readAsStringSync();
  if (contents.contains(hookStartMarker) && contents.contains(hookEndMarker)) {
    final updated = contents.replaceRange(
      contents.indexOf(hookStartMarker),
      contents.indexOf(hookEndMarker) + hookEndMarker.length,
      _hookSnippet.trimRight(),
    );
    if (updated == contents) {
      return const InitHookResult(
        InitHookStatus.alreadyConfigured,
        'hook/build.dart is already set up.',
      );
    }
    hookFile.writeAsStringSync(updated);
    return const InitHookResult(
      InitHookStatus.updated,
      'Refreshed the flutter_scene block in hook/build.dart.',
    );
  }

  if (contents.contains('buildScenes(') ||
      contents.contains('buildMaterials(') ||
      contents.contains('buildEngineAssets(')) {
    return const InitHookResult(
      InitHookStatus.alreadyConfigured,
      'hook/build.dart already calls the flutter_scene builders.',
    );
  }

  return InitHookResult(
    InitHookStatus.needsManualInstall,
    'hook/build.dart already exists and was not written by flutter_scene.\n\n'
    '$manualInstallInstructions',
  );
}
