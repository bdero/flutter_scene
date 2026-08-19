import 'dart:io';

import 'package:flutter_scene/src/fmat/init_command.dart';
import 'package:flutter_scene/src/generated_assets/generated_assets.dart';
import 'package:flutter_scene/src/generated_assets/generated_tree.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('flutter_scene_init');
    File.fromUri(temp.uri.resolve('pubspec.yaml')).writeAsStringSync(
      'name: app\n\nflutter:\n  uses-material-design: true\n',
    );
  });
  tearDown(() => temp.deleteSync(recursive: true));

  File hookFile() => File.fromUri(temp.uri.resolve('hook/build.dart'));

  test('sets up a project that has nothing yet', () async {
    final result = await installFlutterSceneBuildHook(projectRoot: temp);

    expect(result.status, InitHookStatus.created);
    final contents = hookFile().readAsStringSync();
    expect(contents, contains(hookStartMarker));
    expect(contents, contains('buildScenes('));
    expect(contents, contains('buildMaterials('));
    // flutter_scene's own hook builds the engine's shaders, so an app's hook
    // does not have to.
    expect(contents, isNot(contains('buildEngineAssets(')));
    // Nothing in the normal path mentions data assets.
    expect(contents.toLowerCase(), isNot(contains('dataassets')));
    expect(contents, isNot(contains('enable-dart-data-assets')));

    expect(
      File.fromUri(
        temp.uri.resolve(
          '$generatedAssetsDirectory/$generatedAssetsGitignoreFileName',
        ),
      ).existsSync(),
      isTrue,
    );
    expect(
      parsePubspecAssets(
        File.fromUri(temp.uri.resolve('pubspec.yaml')).readAsStringSync(),
      ),
      contains(normalizeAssetEntry(generatedAssetsEntry)),
    );
  });

  test('is idempotent', () async {
    await installFlutterSceneBuildHook(projectRoot: temp);
    final hook = hookFile().readAsStringSync();
    final pubspec = File.fromUri(
      temp.uri.resolve('pubspec.yaml'),
    ).readAsStringSync();

    final again = await installFlutterSceneBuildHook(projectRoot: temp);

    expect(again.status, InitHookStatus.alreadyConfigured);
    expect(hookFile().readAsStringSync(), hook);
    expect(
      File.fromUri(temp.uri.resolve('pubspec.yaml')).readAsStringSync(),
      pubspec,
    );
  });

  test('keeps pubspec comments when adding the entry', () async {
    File.fromUri(temp.uri.resolve('pubspec.yaml')).writeAsStringSync('''
name: app

flutter:
  assets:
    # my own assets
    - assets/logo.png
''');
    await installFlutterSceneBuildHook(projectRoot: temp);
    expect(
      File.fromUri(temp.uri.resolve('pubspec.yaml')).readAsStringSync(),
      '''
name: app

flutter:
  assets:
    # my own assets
    - assets/logo.png
    - $generatedAssetsEntry
''',
    );
  });

  test('refreshes the managed block in a generated hook', () async {
    hookFile()
      ..createSync(recursive: true)
      ..writeAsStringSync('''
import 'package:flutter_scene/build_hooks.dart';
import 'package:hooks/hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
$hookStartMarker
    // stale contents
$hookEndMarker
  });
}
''');

    final result = await installFlutterSceneBuildHook(projectRoot: temp);

    expect(result.status, InitHookStatus.updated);
    final contents = hookFile().readAsStringSync();
    expect(contents, isNot(contains('stale contents')));
    expect(contents, contains('buildScenes('));
  });

  test('leaves a foreign hook alone and prints what to paste', () async {
    hookFile()
      ..createSync(recursive: true)
      ..writeAsStringSync('void main() {}\n');

    final result = await installFlutterSceneBuildHook(projectRoot: temp);

    expect(result.status, InitHookStatus.needsManualInstall);
    expect(hookFile().readAsStringSync(), 'void main() {}\n');
    expect(
      result.message,
      allOf(
        contains('Add this call to your existing hook/build.dart'),
        contains(generatedAssetsEntry),
      ),
    );
  });

  test(
    'recognizes a hand-written hook that already calls the builders',
    () async {
      hookFile()
        ..createSync(recursive: true)
        ..writeAsStringSync(
          "import 'package:flutter_scene/build_hooks.dart';\n"
          'void main(List<String> args) async {\n'
          '  await buildEngineAssets(buildInput: i, buildOutput: o);\n'
          '}\n',
        );

      final result = await installFlutterSceneBuildHook(projectRoot: temp);

      expect(result.status, InitHookStatus.alreadyConfigured);
    },
  );

  test('adds the entry to an inline assets list', () async {
    File.fromUri(
      temp.uri.resolve('pubspec.yaml'),
    ).writeAsStringSync('name: app\nflutter:\n  assets: [assets/logo.png]\n');

    final result = await installFlutterSceneBuildHook(projectRoot: temp);

    expect(result.status, InitHookStatus.created);
    expect(
      parsePubspecAssets(
        File.fromUri(temp.uri.resolve('pubspec.yaml')).readAsStringSync(),
      ),
      contains(normalizeAssetEntry(generatedAssetsEntry)),
    );
  });

  group('skill install', () {
    late Uri skillSource;

    // Writes a fake bundled skill (versioned frontmatter plus a reference) to
    // [dir] and returns its uri.
    Uri writeSkill(String dir, int version) {
      final src = Directory.fromUri(temp.uri.resolve('$dir/'))
        ..createSync(recursive: true);
      File.fromUri(src.uri.resolve('SKILL.md')).writeAsStringSync(
        '---\nname: $flutterSceneSkillName\nversion: $version\n---\n# skill\n',
      );
      Directory.fromUri(src.uri.resolve('references/')).createSync();
      File.fromUri(
        src.uri.resolve('references/what-exists.md'),
      ).writeAsStringSync('x\n');
      return src.uri;
    }

    setUp(() => skillSource = writeSkill('_src/$flutterSceneSkillName', 1));

    File installed(String parent) => File.fromUri(
      temp.uri.resolve('$parent/skills/$flutterSceneSkillName/SKILL.md'),
    );

    test('defaults to .claude when no agent home is present', () async {
      final plan = await planFlutterSceneSkillInstall(
        projectRoot: temp,
        skillSource: skillSource,
      );
      expect(plan.action, SkillInstallAction.install);
      expect(plan.bundledVersion, 1);
      expect(plan.installedVersion, isNull);

      final result = await installFlutterSceneSkills(
        projectRoot: temp,
        skillSource: skillSource,
      );

      expect(result.status, InitSkillStatus.installed);
      expect(installed('.claude').existsSync(), isTrue);
      // The references subtree comes along.
      expect(
        File.fromUri(
          temp.uri.resolve(
            '.claude/skills/$flutterSceneSkillName/references/what-exists.md',
          ),
        ).existsSync(),
        isTrue,
      );
    });

    test('installs into every agent home already present', () async {
      Directory.fromUri(temp.uri.resolve('.cursor/')).createSync();
      Directory.fromUri(temp.uri.resolve('.codex/')).createSync();

      await installFlutterSceneSkills(
        projectRoot: temp,
        skillSource: skillSource,
      );

      expect(installed('.cursor').existsSync(), isTrue);
      expect(installed('.codex').existsSync(), isTrue);
      // No .claude home existed, so it is not created when others are.
      expect(installed('.claude').existsSync(), isFalse);
    });

    test('an installed matching version reports up to date', () async {
      await installFlutterSceneSkills(
        projectRoot: temp,
        skillSource: skillSource,
      );

      final plan = await planFlutterSceneSkillInstall(
        projectRoot: temp,
        skillSource: skillSource,
      );
      expect(plan.action, SkillInstallAction.upToDate);
      expect(plan.installedVersion, 1);
    });

    test('a newer bundled version reports an update', () async {
      // Install v1, then point at a v2 source.
      await installFlutterSceneSkills(
        projectRoot: temp,
        skillSource: skillSource,
      );
      final v2 = writeSkill('_src2/$flutterSceneSkillName', 2);

      final plan = await planFlutterSceneSkillInstall(
        projectRoot: temp,
        skillSource: v2,
      );
      expect(plan.action, SkillInstallAction.update);
      expect(plan.installedVersion, 1);
      expect(plan.bundledVersion, 2);

      await installFlutterSceneSkills(projectRoot: temp, skillSource: v2);
      expect(
        await planFlutterSceneSkillInstall(projectRoot: temp, skillSource: v2),
        isA<SkillInstallPlan>().having(
          (p) => p.action,
          'action',
          SkillInstallAction.upToDate,
        ),
      );
    });

    test('a pre-versioning install reads as stale', () async {
      // A skill with no version frontmatter counts as 0, below any bundle.
      final home = Directory.fromUri(
        temp.uri.resolve('.claude/skills/$flutterSceneSkillName/'),
      )..createSync(recursive: true);
      File.fromUri(home.uri.resolve('SKILL.md')).writeAsStringSync('# old\n');

      final plan = await planFlutterSceneSkillInstall(
        projectRoot: temp,
        skillSource: skillSource,
      );
      expect(plan.action, SkillInstallAction.update);
      expect(plan.installedVersion, 0);
    });

    test('reports a missing source instead of throwing', () async {
      final plan = await planFlutterSceneSkillInstall(
        projectRoot: temp,
        skillSource: temp.uri.resolve('_nope/'),
      );
      expect(plan.action, SkillInstallAction.sourceMissing);

      final result = await installFlutterSceneSkills(
        projectRoot: temp,
        skillSource: temp.uri.resolve('_nope/'),
      );
      expect(result.status, InitSkillStatus.sourceMissing);
    });

    test('describeSkillPlan names the action and how to act', () {
      expect(
        describeSkillPlan(
          const SkillInstallPlan(
            SkillInstallAction.update,
            installedVersion: 1,
            bundledVersion: 3,
          ),
        ),
        allOf(contains('v1'), contains('v3'), contains('flutter_scene:skills')),
      );
      expect(
        describeSkillPlan(
          const SkillInstallPlan(SkillInstallAction.install, bundledVersion: 3),
        ),
        contains('not installed'),
      );
      expect(
        describeSkillPlan(
          const SkillInstallPlan(
            SkillInstallAction.upToDate,
            bundledVersion: 3,
          ),
        ),
        contains('up to date'),
      );
    });
  });
}
