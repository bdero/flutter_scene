import 'dart:io';

import 'package:flutter_scene_editor/flutter_scene_editor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('fproject_');
    File('${root.path}/pubspec.yaml').writeAsStringSync('''
name: game
dependencies:
  flutter_scene: ^0.21.0
''');
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('createDefault writes an fproject with mode defaults, round trips', () {
    final project = FProject.createDefault(root.path);
    expect(File(project.path).existsSync(), isTrue);
    // One variable-driven configuration per mode; the device is toolbar
    // session state, not part of the configuration.
    expect(project.buildConfigurations.length, 3);
    expect(project.buildConfigurations.map((config) => config.mode), [
      'debug',
      'profile',
      'release',
    ]);
    // Run parameters always carry the Flutter GPU flags; the device and mode
    // are session state the editor composes into the invocation.
    for (final config in project.buildConfigurations) {
      expect(config.run.args, contains('--enable-flutter-gpu'));
      expect(config.run.args, contains('--enable-impeller'));
      expect(config.run.target, RunParameters.defaultTarget);
      expect(config.buildCommand, contains(r'${BUILD_TARGET}'));
    }

    final loaded = FProject.load(project.path);
    expect(loaded.name, project.name);
    expect(
      loaded.buildConfigurations.length,
      project.buildConfigurations.length,
    );
    expect(loaded.resolvedProjectRoot, Directory(root.path).absolute.path);
  });

  test('loading a v1 fproject migrates a default-shaped runCommand', () {
    File('${root.path}/game.fproject').writeAsStringSync('''
{
  "version": 1,
  "flutterProjectRoot": ".",
  "buildConfigurations": [
    {
      "id": "debug",
      "name": "Debug",
      "mode": "debug",
      "buildCommand": "\${FLUTTER_CLI} build \${BUILD_TARGET} --\${MODE}",
      "runCommand": "\${FLUTTER_CLI} run -d \${DEVICE} --\${MODE} --enable-flutter-gpu --enable-impeller --target lib/game.dart"
    }
  ]
}
''');
    final project = FProject.load('${root.path}/game.fproject');
    expect(project.tasks, isEmpty);
    final config = project.buildConfigurations.single;
    expect(config.run.target, 'lib/game.dart');
    expect(config.run.args, ['--enable-flutter-gpu', '--enable-impeller']);
  });

  test('loading a v1 fproject preserves a custom runCommand as a task', () {
    File('${root.path}/game.fproject').writeAsStringSync('''
{
  "version": 1,
  "flutterProjectRoot": ".",
  "buildConfigurations": [
    {
      "id": "echo",
      "name": "Echo",
      "mode": "debug",
      "buildCommand": "",
      "runCommand": "/bin/echo hello \${PROJECT_ROOT}"
    }
  ]
}
''');
    final project = FProject.load('${root.path}/game.fproject');
    final task = project.tasks.single;
    expect(task.command, r'/bin/echo hello ${PROJECT_ROOT}');
    expect(task.name, contains('Echo'));
    // The configuration falls back to default run parameters.
    expect(
      project.buildConfigurations.single.run.args,
      contains('--enable-flutter-gpu'),
    );

    // Saving persists v2 with the migrated task; a reload is stable.
    project.save();
    final reloaded = FProject.load(project.path);
    expect(reloaded.tasks.single.command, task.command);
    expect(reloaded.buildConfigurations.single.run.args, isNotEmpty);
  });

  test('a hardcoded device keeps the whole runCommand as a task', () {
    const command = r'${FLUTTER_CLI} run -d chrome --${MODE}';
    final migrated = migrateV1RunCommand(
      command,
      configId: 'web',
      configName: 'Web',
    );
    expect(migrated.task, isNotNull);
    expect(migrated.task!.command, command);
  });

  test('run parameters round trip through json', () {
    const params = RunParameters(
      target: 'lib/other.dart',
      args: ['--dart-define=A=1'],
    );
    expect(RunParameters.fromJson(params.toJson()).target, 'lib/other.dart');
    expect(RunParameters.fromJson(params.toJson()).args, ['--dart-define=A=1']);
    // Defaults serialize to nothing.
    expect(const RunParameters().toJson(), isEmpty);
  });

  test('ancestor discovery finds the nearest fproject or pubspec', () {
    final scenes = Directory('${root.path}/assets/levels')
      ..createSync(recursive: true);
    final scenePath = '${scenes.path}/town.fscene';
    File(scenePath).writeAsStringSync('{}');

    // Only a pubspec above; discovery offers it for initialization.
    var context = findSceneProjectContext(
      scenePath,
      stopAtDirectory: root.path,
    );
    expect(context.fprojectPath, isNull);
    expect(context.pubspecDirectory, Directory(root.path).absolute.path);

    // With a project file, the nearest one wins and the pubspec offer clears.
    final project = FProject.createDefault(root.path);
    context = findSceneProjectContext(scenePath, stopAtDirectory: root.path);
    expect(context.fprojectPath, project.path);
    expect(context.pubspecDirectory, isNull);

    // Several project files in one directory; the directory-named one wins.
    File('${root.path}/aaa.fproject').writeAsStringSync('{"version": 2}');
    context = findSceneProjectContext(scenePath, stopAtDirectory: root.path);
    expect(context.fprojectPath, project.path);

    // The walk does not ascend past the stop directory.
    context = findSceneProjectContext(scenePath, stopAtDirectory: scenes.path);
    expect(context.fprojectPath, isNull);
    expect(context.pubspecDirectory, isNull);
  });

  test('defaultScene round trips and resolves against the root', () {
    final project = FProject.createDefault(root.path);
    project.defaultScene = 'assets/main.fscene';
    project.save();
    final reloaded = FProject.load(project.path);
    expect(reloaded.defaultScene, 'assets/main.fscene');
    expect(
      reloaded.resolvedDefaultScene,
      '${Directory(root.path).absolute.path}/assets/main.fscene',
    );
  });

  test('createDefault requires a pubspec', () {
    final empty = Directory.systemTemp.createTempSync('not_flutter_');
    addTearDown(() => empty.deleteSync(recursive: true));
    expect(() => FProject.createDefault(empty.path), throwsFormatException);
  });

  test('command variables substitute and unknown names throw', () {
    const config = BuildConfiguration(
      id: 'x',
      name: 'X',
      mode: 'profile',
      buildCommand: '',
    );
    final variables = commandVariables(
      flutterBin: '/sdk/bin/flutter',
      dartBin: '/sdk/bin/dart',
      sdkRoot: '/sdk',
      impellerc: '/sdk/impellerc',
      projectRoot: '/proj',
      configuration: config,
      deviceId: 'macos',
      buildTarget: 'macos',
    );
    expect(
      substituteCommandVariables(
        r'${FLUTTER_CLI} run -d ${DEVICE} --${MODE}',
        variables,
      ),
      '/sdk/bin/flutter run -d macos --profile',
    );
    expect(
      () => substituteCommandVariables(r'${NOPE}', variables),
      throwsFormatException,
    );
    // Without a device, referencing it names the missing variable.
    final deviceless = commandVariables(
      flutterBin: '/sdk/bin/flutter',
      dartBin: '/sdk/bin/dart',
      sdkRoot: '/sdk',
      impellerc: null,
      projectRoot: '/proj',
      configuration: config,
    );
    expect(
      () => substituteCommandVariables(r'-d ${DEVICE}', deviceless),
      throwsFormatException,
    );
  });

  test('tokenize-then-substitute keeps spaced expansions as one token', () {
    // The runner's order (tokenize the template, substitute per token) must
    // keep a variable expanding to a spaced path as a single argument.
    const config = BuildConfiguration(
      id: 'x',
      name: 'X',
      mode: 'debug',
      buildCommand: '',
    );
    final variables = commandVariables(
      flutterBin: '/Users/x/Library/Application Support/Editor/bin/flutter',
      dartBin: '/sdk/bin/dart',
      sdkRoot: '/sdk',
      impellerc: null,
      projectRoot: '/proj',
      configuration: config,
    );
    final argv = [
      for (final token in tokenizeCommand(r'${FLUTTER_CLI} --version'))
        substituteCommandVariables(token, variables),
    ];
    expect(argv, [
      '/Users/x/Library/Application Support/Editor/bin/flutter',
      '--version',
    ]);
  });

  test('tokenizeCommand splits argv with quote grouping', () {
    expect(tokenizeCommand('a b  c'), ['a', 'b', 'c']);
    expect(tokenizeCommand('run "-d my device" --x'), [
      'run',
      '-d my device',
      '--x',
    ]);
    expect(tokenizeCommand('a ""'), ['a', '']);
  });

  test('version check warns on minor mismatch and info on patch', () {
    final project = FProject.createDefault(root.path);
    const editor = EditorBuildInfo(flutterSceneVersion: '0.21.0');

    // Constraint path (no lockfile), matching minor, ok.
    expect(
      checkFlutterSceneVersion(project, editor).severity,
      VersionCheckSeverity.ok,
    );

    // Lockfile with a different minor, warning.
    File('${root.path}/pubspec.lock').writeAsStringSync('''
packages:
  flutter_scene:
    dependency: "direct main"
    description:
      name: flutter_scene
      url: "https://pub.dev"
    source: hosted
    version: "0.20.1"
''');
    final mismatch = checkFlutterSceneVersion(project, editor);
    expect(mismatch.severity, VersionCheckSeverity.warning);
    expect(mismatch.message, contains('0.20.1'));
    expect(mismatch.message, contains('0.21.0'));

    // Patch difference only, informational.
    File('${root.path}/pubspec.lock').writeAsStringSync('''
packages:
  flutter_scene:
    dependency: "direct main"
    source: hosted
    version: "0.21.3"
''');
    expect(
      checkFlutterSceneVersion(project, editor).severity,
      VersionCheckSeverity.info,
    );
  });

  test('version check warns when flutter_scene is absent', () {
    File('${root.path}/pubspec.yaml').writeAsStringSync('''
name: game
dependencies:
  http: ^1.0.0
''');
    final project = FProject.createDefault(root.path);
    final check = checkFlutterSceneVersion(
      project,
      const EditorBuildInfo(flutterSceneVersion: '0.21.0'),
    );
    expect(check.severity, VersionCheckSeverity.warning);
    expect(check.message, contains('no flutter_scene dependency'));
  });

  test('version check resolves a path dependency', () {
    final dep = Directory('${root.path}/pkgs/flutter_scene')
      ..createSync(recursive: true);
    File('${dep.path}/pubspec.yaml').writeAsStringSync('''
name: flutter_scene
version: 0.22.0
''');
    File('${root.path}/pubspec.yaml').writeAsStringSync('''
name: game
dependencies:
  flutter_scene:
    path: pkgs/flutter_scene
''');
    final project = FProject.createDefault(root.path);
    final check = checkFlutterSceneVersion(
      project,
      const EditorBuildInfo(flutterSceneVersion: '0.21.0'),
    );
    expect(check.severity, VersionCheckSeverity.warning);
    expect(check.message, contains('0.22.0'));
  });
}
