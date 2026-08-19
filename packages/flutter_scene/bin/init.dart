import 'dart:io';

import 'package:flutter_scene/src/fmat/init_command.dart';

Future<void> main(List<String> args) async {
  if (args.contains('-h') || args.contains('--help')) {
    stdout.writeln('Usage: dart run flutter_scene:init [--skills|--no-skills]');
    stdout.writeln('');
    stdout.writeln(
      'Sets this project up for flutter_scene: installs hook/build.dart, '
      'creates flutter_scene_generated/, and lists it in pubspec.yaml.',
    );
    stdout.writeln('');
    stdout.writeln(
      'By default it also offers to install the flutter_scene agent skills '
      '(correct-usage guidance for coding agents) into this project. It asks '
      'first at a terminal. Pass --skills to install or update without asking '
      '(for CI), or --no-skills to skip it. To manage the skill on its own '
      '(after customizing your hook or pubspec), use dart run '
      'flutter_scene:skills instead.',
    );
    stdout.writeln('');
    stdout.writeln(manualInstallInstructions);
    return;
  }

  final result = await installFlutterSceneBuildHook();
  final sink = result.status == InitHookStatus.needsManualInstall
      ? stderr
      : stdout;
  sink.writeln(result.message);
  if (result.status == InitHookStatus.needsManualInstall) {
    exitCode = 1;
    return;
  }

  await _handleSkill(args);

  stdout.writeln('');
  stdout.writeln(
    'The hook converts .glb and .fscene models, .fmat materials, and loose '
    'images under assets/ at build time. Load them by source path with '
    'loadScene / loadFmatMaterial / loadTexture, render with SceneView, and '
    'edits hot reload in place.',
  );
}

// Installs the agent skill only with consent: an explicit flag, or a yes at an
// interactive prompt. With no flag and no terminal (CI), it does nothing.
Future<void> _handleSkill(List<String> args) async {
  if (args.contains('--no-skills')) return;
  final forced = args.contains('--skills');

  final plan = await planFlutterSceneSkillInstall();
  switch (plan.action) {
    case SkillInstallAction.sourceMissing:
      if (forced) {
        stdout.writeln(
          'Could not locate the bundled flutter_scene skills to install.',
        );
      }
      return;
    case SkillInstallAction.upToDate:
      if (forced) {
        stdout.writeln('The flutter_scene agent skills are up to date.');
      }
      return;
    case SkillInstallAction.install:
    case SkillInstallAction.update:
      break;
  }

  final update = plan.action == SkillInstallAction.update;
  var go = forced;
  if (!go) {
    void skip() => stdout.writeln(
      'Skipping the flutter_scene agent skills. Run with --skills to install '
      'or update them, or --no-skills to silence this.',
    );
    if (!stdin.hasTerminal) {
      skip();
      return;
    }
    final where = plan.homes.join(', ');
    stdout.write(
      update
          ? 'Update the flutter_scene agent skills in $where? [Y/n] '
          : 'Install the flutter_scene agent skills (correct-usage guidance '
                'for coding agents) into $where? [y/N] ',
    );
    // Closed stdin (a misdetected terminal, or piped input in CI) reads as
    // null; treat that as no so nothing installs unattended. An empty line is
    // a deliberate enter, which takes the default (yes for an update the user
    // already opted into, no for a fresh install).
    final answer = stdin.readLineSync();
    if (answer == null) {
      skip();
      return;
    }
    final normalized = answer.trim().toLowerCase();
    go = update
        ? normalized != 'n' && normalized != 'no'
        : normalized == 'y' || normalized == 'yes';
  }
  if (!go) return;

  final skill = await installFlutterSceneSkills();
  stdout.writeln(skill.message);
}
