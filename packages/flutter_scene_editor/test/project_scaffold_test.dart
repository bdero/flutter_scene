import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_scene_editor/flutter_scene_editor.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeProcess implements Process {
  _FakeProcess(int code, {String stdoutText = ''})
    : stdout = Stream.value(utf8.encode(stdoutText)),
      _exit = Completer<int>() {
    if (code >= 0) _exit.complete(code);
  }

  final Completer<int> _exit;
  bool killed = false;

  @override
  final Stream<List<int>> stdout;

  @override
  Stream<List<int>> get stderr => const Stream.empty();

  @override
  Future<int> get exitCode => _exit.future;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killed = true;
    if (!_exit.isCompleted) _exit.complete(-15);
    return true;
  }

  @override
  int get pid => 0;

  @override
  IOSink get stdin => throw UnimplementedError();
}

Future<void> _settle(ProjectScaffoldJob job) async {
  while (!job.done) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late Directory parent;
  const installation = FlutterInstallation(
    id: 'x',
    name: 'X',
    flutterBin: '/sdk/bin/flutter',
  );

  setUp(() => parent = Directory.systemTemp.createTempSync('scaffold_'));
  tearDown(() => parent.deleteSync(recursive: true));

  test('names follow Dart package rules', () {
    expect(validateProjectName('my_game2'), isNull);
    expect(validateProjectName(''), isNotNull);
    expect(validateProjectName('MyGame'), isNotNull);
    expect(validateProjectName('2game'), isNotNull);
    expect(validateProjectName('my-game'), isNotNull);
    expect(validateProjectName('class'), isNotNull);
    expect(validateProjectName('flutter_scene'), isNotNull);
  });

  test('only a missing or empty directory is accepted', () {
    final target = '${parent.path}/app';
    expect(validateProjectDirectory(target), isNull);
    Directory(target).createSync();
    expect(validateProjectDirectory(target), isNull);
    File('$target/notes.txt').writeAsStringSync('');
    expect(validateProjectDirectory(target), contains('not empty'));
    File('$target/pubspec.yaml').writeAsStringSync('name: app');
    expect(validateProjectDirectory(target), contains('Existing Flutter app'));
  });

  test('the dependency pins a release editor to its minor', () {
    expect(flutterSceneDependency('0.24.0'), 'flutter_scene:^0.24.0');
    expect(flutterSceneDependency('0.25.0-dev.1'), 'flutter_scene');
    expect(flutterSceneDependency(null), 'flutter_scene');
  });

  test(
    'creates, adds flutter_scene, runs init, and writes the fproject',
    () async {
      final commands = <List<String>>[];
      final scaffolder = ProjectScaffolder(
        installation: installation,
        flutterSceneVersion: '0.24.0',
        start:
            (
              executable,
              args, {
              workingDirectory,
              environment,
              includeParentEnvironment = true,
            }) async {
              commands.add([executable, ...args]);
              if (args.first == 'create') {
                Directory(args.last).createSync();
                File(
                  '${args.last}/pubspec.yaml',
                ).writeAsStringSync('name: game');
              }
              return _FakeProcess(0);
            },
      );
      final job = scaffolder.create(parentDirectory: parent.path, name: 'game');
      await _settle(job);

      expect(job.error, isNull);
      final dir = job.directory;
      expect(commands, [
        [
          '/sdk/bin/flutter',
          'create',
          '--empty',
          '--project-name',
          'game',
          dir,
        ],
        ['/sdk/bin/flutter', 'pub', 'add', 'flutter_scene:^0.24.0'],
        [installation.dartBin, 'run', 'flutter_scene:init', '--no-skills'],
      ]);
      expect(job.result!.path, endsWith('game.fproject'));
      expect(File(job.result!.path).existsSync(), isTrue);
    },
  );

  test('a failing step stops the job and keeps the partial app', () async {
    final scaffolder = ProjectScaffolder(
      installation: installation,
      start:
          (
            executable,
            args, {
            workingDirectory,
            environment,
            includeParentEnvironment = true,
          }) async {
            if (args.first == 'create') {
              Directory(args.last).createSync();
              return _FakeProcess(0);
            }
            return _FakeProcess(1, stdoutText: 'offline');
          },
    );
    final job = scaffolder.create(parentDirectory: parent.path, name: 'game');
    await _settle(job);

    expect(job.phase, ProjectScaffoldPhase.dependency);
    expect(job.error, contains('pub add exited with 1'));
    expect(job.log, contains('offline'));
    expect(job.result, isNull);
    expect(Directory(job.directory).existsSync(), isTrue);
  });

  test('cancelling removes the app the job created', () async {
    final running = _FakeProcess(-1);
    final scaffolder = ProjectScaffolder(
      installation: installation,
      start:
          (
            executable,
            args, {
            workingDirectory,
            environment,
            includeParentEnvironment = true,
          }) async {
            Directory(args.last).createSync();
            return running;
          },
    );
    final job = scaffolder.create(parentDirectory: parent.path, name: 'game');
    while (job.log.length < 2) {
      await Future<void>.delayed(Duration.zero);
    }
    job.cancel();
    await _settle(job);

    expect(running.killed, isTrue);
    expect(job.error, 'Cancelled.');
    expect(Directory(job.directory).existsSync(), isFalse);
  });

  test('cancelling keeps a directory that existed before', () async {
    final target = Directory('${parent.path}/game')..createSync();
    final running = _FakeProcess(-1);
    final scaffolder = ProjectScaffolder(
      installation: installation,
      start:
          (
            executable,
            args, {
            workingDirectory,
            environment,
            includeParentEnvironment = true,
          }) async {
            File('${args.last}/pubspec.yaml').writeAsStringSync('name: game');
            return running;
          },
    );
    final job = scaffolder.create(parentDirectory: parent.path, name: 'game');
    while (job.log.length < 2) {
      await Future<void>.delayed(Duration.zero);
    }
    job.cancel();
    await _settle(job);

    expect(target.existsSync(), isTrue);
    expect(target.listSync(), isEmpty);
  });

  test('an unusable name or directory throws before starting', () {
    final scaffolder = ProjectScaffolder(installation: installation);
    expect(
      () => scaffolder.create(parentDirectory: parent.path, name: 'Bad'),
      throwsFormatException,
    );
    File('${parent.path}/game').writeAsStringSync('');
    expect(
      () => scaffolder.create(parentDirectory: parent.path, name: 'game'),
      throwsFormatException,
    );
  });
}
