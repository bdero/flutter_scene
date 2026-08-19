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

// The bundled agent skills teaching correct flutter_scene usage each live at
// `skills/<name>/` with a SKILL.md. When you change a skill's content, bump the
// `version:` field in its SKILL.md, or an already-installed copy is not detected
// as stale and never offered an update.
//
// Each skill installs under `<parent>/skills/<name>/` for every agent parent
// already present in the project, defaulting to `.claude` when none is.
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
    this.skillNames = const [],
    this.homes = const [],
    this.installCount = 0,
    this.updateCount = 0,
  });

  final SkillInstallAction action;

  /// The bundled skill names, sorted.
  final List<String> skillNames;

  /// The agent skill-home dirs a write touches (e.g. `.claude/skills`).
  final List<String> homes;

  /// Bundled skills missing from at least one home.
  final int installCount;

  /// Bundled skills with an older copy in at least one home.
  final int updateCount;
}

/// Inspects the skill state without writing. Callers use [SkillInstallPlan.action]
/// to decide whether to prompt (install vs update vs nothing) before calling
/// [installFlutterSceneSkills].
Future<SkillInstallPlan> planFlutterSceneSkillInstall({
  Directory? projectRoot,
  Uri? skillsRoot,
}) async {
  final root = projectRoot ?? Directory.current;
  final rootUri = skillsRoot ?? await _resolveBundledSkillsRoot();
  final bundled = rootUri == null
      ? const <({String name, Uri dir})>[]
      : _bundledSkills(rootUri);
  if (bundled.isEmpty) {
    return const SkillInstallPlan(SkillInstallAction.sourceMissing);
  }

  final homes = _presentSkillHomes(root);
  var installCount = 0;
  var updateCount = 0;
  for (final skill in bundled) {
    final bundledVersion = _skillVersion(
      File.fromUri(skill.dir.resolve('SKILL.md')),
    );
    var missingSomewhere = false;
    var staleSomewhere = false;
    for (final home in homes) {
      final file = File.fromUri(
        root.uri.resolve('$home/${skill.name}/SKILL.md'),
      );
      if (!file.existsSync()) {
        missingSomewhere = true;
      } else if (_skillVersion(file) < bundledVersion) {
        staleSomewhere = true;
      }
    }
    if (missingSomewhere) {
      installCount++;
    } else if (staleSomewhere) {
      updateCount++;
    }
  }

  final action = installCount > 0
      ? SkillInstallAction.install
      : (updateCount > 0
            ? SkillInstallAction.update
            : SkillInstallAction.upToDate);
  return SkillInstallPlan(
    action,
    skillNames: [for (final s in bundled) s.name],
    homes: homes,
    installCount: installCount,
    updateCount: updateCount,
  );
}

/// A human-readable status line for [plan], shared by `flutter_scene:init` and
/// the `flutter_scene:skills` command so both describe the state the same way.
String describeSkillPlan(SkillInstallPlan plan) {
  switch (plan.action) {
    case SkillInstallAction.sourceMissing:
      return 'Could not locate the bundled flutter_scene skills. This package '
          'version may predate them, or it is a git dependency published '
          'without them.';
    case SkillInstallAction.upToDate:
      return 'The flutter_scene agent skills are up to date '
          '(${plan.skillNames.length} installed).';
    case SkillInstallAction.install:
      return '${plan.installCount} of the flutter_scene agent skills '
          '(${plan.skillNames.length} total) are not installed. Install them '
          'with: dart run flutter_scene:skills';
    case SkillInstallAction.update:
      return '${plan.updateCount} flutter_scene agent skill(s) have a newer '
          'version available. Update with: dart run flutter_scene:skills';
  }
}

enum InitSkillStatus { installed, sourceMissing }

final class InitSkillResult {
  const InitSkillResult(this.status, this.message);

  final InitSkillStatus status;
  final String message;
}

/// Copies every bundled skill into the project's agent skill homes. Writes
/// `<home>/skills/<skill>/` into every known agent home already present, or
/// `.claude` by default, and overwrites so an upgrade refreshes each skill.
/// Never called without the caller having established consent (a prompt or a
/// flag).
Future<InitSkillResult> installFlutterSceneSkills({
  Directory? projectRoot,
  Uri? skillsRoot,
}) async {
  final root = projectRoot ?? Directory.current;
  final rootUri = skillsRoot ?? await _resolveBundledSkillsRoot();
  final bundled = rootUri == null
      ? const <({String name, Uri dir})>[]
      : _bundledSkills(rootUri);
  if (bundled.isEmpty) {
    return const InitSkillResult(
      InitSkillStatus.sourceMissing,
      'Could not locate the bundled flutter_scene skills; skipped skill '
      'install.',
    );
  }

  final homes = _presentSkillHomes(root);
  for (final home in homes) {
    for (final skill in bundled) {
      _copyDirectory(skill.dir, root.uri.resolve('$home/${skill.name}/'));
    }
  }
  final count = bundled.length;
  return InitSkillResult(
    InitSkillStatus.installed,
    'Installed $count flutter_scene agent skill${count == 1 ? '' : 's'} into '
    '${homes.join(', ')}.',
  );
}

// The agent skill-home dirs to write into: `<parent>/skills` for every known
// parent already present, or `.claude/skills` when none is. Each bundled skill
// lands in a `<name>/` subdirectory under one of these.
List<String> _presentSkillHomes(Directory root) {
  final present = _agentSkillParents
      .where((p) => Directory.fromUri(root.uri.resolve('$p/')).existsSync())
      .toList();
  if (present.isEmpty) present.add('.claude');
  return [for (final p in present) '$p/skills'];
}

// The bundled skills: every `skills/<name>/` directory holding a SKILL.md,
// sorted by name.
List<({String name, Uri dir})> _bundledSkills(Uri skillsRoot) {
  final dir = Directory.fromUri(skillsRoot);
  if (!dir.existsSync()) return const [];
  final skills = <({String name, Uri dir})>[];
  for (final entity in dir.listSync()) {
    if (entity is! Directory) continue;
    final skillDir = Uri.directory(entity.path);
    if (!File.fromUri(skillDir.resolve('SKILL.md')).existsSync()) continue;
    final segments = skillDir.pathSegments;
    skills.add((name: segments[segments.length - 2], dir: skillDir));
  }
  skills.sort((a, b) => a.name.compareTo(b.name));
  return skills;
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

// The bundled skills live at the package root next to lib/, so resolve a
// library file and step up out of lib/.
Future<Uri?> _resolveBundledSkillsRoot() async {
  final lib = await Isolate.resolvePackageUri(
    Uri.parse('package:flutter_scene/scene.dart'),
  );
  return lib?.resolve('../skills/');
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
