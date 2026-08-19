import 'dart:io';

import 'package:flutter_scene/src/fmat/init_command.dart';

/// Installs, updates, or checks the flutter_scene agent skill, without touching
/// the build hook or pubspec the way `flutter_scene:init` does. Running this is
/// itself the consent to write into the project's agent skill homes.
Future<void> main(List<String> args) async {
  if (args.contains('-h') || args.contains('--help')) {
    stdout.writeln('Usage: dart run flutter_scene:skills [--check]');
    stdout.writeln('');
    stdout.writeln(
      'Installs or updates the flutter_scene agent skills (correct-usage '
      'guidance for coding agents) into this project. Unlike '
      'flutter_scene:init it does not modify hook/build.dart or pubspec.yaml, '
      'so it is safe to run after customizing those.',
    );
    stdout.writeln('');
    stdout.writeln(
      '--check  report the installed and bundled skill versions and whether an '
      'update is available, without writing. Exits non-zero when an install or '
      'update is available.',
    );
    return;
  }

  final plan = await planFlutterSceneSkillInstall();

  if (args.contains('--check')) {
    stdout.writeln(describeSkillPlan(plan));
    if (plan.action == SkillInstallAction.install ||
        plan.action == SkillInstallAction.update) {
      exitCode = 1;
    }
    return;
  }

  switch (plan.action) {
    case SkillInstallAction.sourceMissing:
      stderr.writeln(describeSkillPlan(plan));
      exitCode = 1;
    case SkillInstallAction.upToDate:
      stdout.writeln(describeSkillPlan(plan));
    case SkillInstallAction.install:
    case SkillInstallAction.update:
      final result = await installFlutterSceneSkills();
      stdout.writeln(result.message);
  }
}
