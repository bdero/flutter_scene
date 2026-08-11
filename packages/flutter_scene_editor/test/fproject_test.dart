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
    // Run templates always carry the Flutter GPU flags and reference the
    // device and mode variables so the dropdowns change behavior.
    for (final config in project.buildConfigurations) {
      expect(config.runCommand, contains('--enable-flutter-gpu'));
      expect(config.runCommand, contains('--enable-impeller'));
      expect(config.runCommand, contains(r'${DEVICE}'));
      expect(config.runCommand, contains(r'--${MODE}'));
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
      runCommand: '',
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
      runCommand: '',
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
