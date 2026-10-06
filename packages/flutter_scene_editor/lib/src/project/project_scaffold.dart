/// New project scaffolding. Creates a Flutter app set up for flutter_scene
/// with the selected installation's tools (`flutter create`, `flutter pub
/// add flutter_scene`, `dart run flutter_scene:init`), then wraps it in an
/// fproject. Runs as a cancellable job with a live log.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../toolchains/flutter_installation.dart';
import 'fproject.dart';

enum ProjectScaffoldPhase {
  create('Creating the Flutter app'),
  dependency('Adding flutter_scene'),
  init('Installing the flutter_scene build hook'),
  register('Writing the project file');

  const ProjectScaffoldPhase(this.label);

  final String label;
}

/// Starts a subprocess; [Process.start] by default, a fake in tests.
typedef ScaffoldProcessStarter =
    Future<Process> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
      Map<String, String>? environment,
      bool includeParentEnvironment,
    });

// Names `flutter create` rejects, plus the packages the scaffold depends on
// (a package cannot depend on a package of its own name).
const _reservedNames = {
  'abstract',
  'as',
  'assert',
  'async',
  'await',
  'break',
  'case',
  'catch',
  'class',
  'const',
  'continue',
  'covariant',
  'default',
  'deferred',
  'do',
  'dynamic',
  'else',
  'enum',
  'export',
  'extends',
  'extension',
  'external',
  'factory',
  'false',
  'final',
  'finally',
  'for',
  'function',
  'get',
  'if',
  'implements',
  'import',
  'in',
  'interface',
  'is',
  'late',
  'library',
  'mixin',
  'new',
  'null',
  'operator',
  'part',
  'required',
  'rethrow',
  'return',
  'set',
  'static',
  'super',
  'switch',
  'sync',
  'this',
  'throw',
  'true',
  'try',
  'typedef',
  'var',
  'void',
  'while',
  'with',
  'yield',
  'flutter',
  'flutter_test',
  'flutter_scene',
  'scene',
};

/// Why [name] is not a usable app name, or null when it is. The name becomes
/// the Dart package name and the app's directory.
String? validateProjectName(String name) {
  if (name.isEmpty) return 'Enter a name.';
  if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(name)) {
    return 'Use lowercase letters, digits, and underscores, starting with a '
        'letter.';
  }
  if (_reservedNames.contains(name)) return '"$name" is a reserved name.';
  return null;
}

/// Why the app cannot be created at [directory], or null when it can. A
/// missing or empty directory is fine; anything else would mix the new app
/// into existing files.
String? validateProjectDirectory(String directory) {
  final dir = Directory(directory);
  if (FileSystemEntity.isFileSync(directory)) {
    return 'A file already exists at $directory.';
  }
  if (!dir.existsSync()) return null;
  if (dir.listSync().isEmpty) return null;
  if (File('${dir.path}/pubspec.yaml').existsSync()) {
    return '$directory is already a Flutter project. Use "Existing Flutter '
        'app" to open it.';
  }
  return '$directory is not empty.';
}

/// The `pub add` descriptor for flutter_scene, pinned to the editor's minor
/// when the editor is a release build so the scenes it writes load in the
/// app. A prerelease or unknown editor version takes the latest release.
String flutterSceneDependency(String? editorVersion) {
  final release = RegExp(
    r'^(\d+)\.(\d+)\.(\d+)$',
  ).firstMatch(editorVersion ?? '');
  if (release == null) return 'flutter_scene';
  return 'flutter_scene:^${release.group(0)}';
}

/// A running (or finished) scaffold. Listen for progress; [result] is set on
/// success.
class ProjectScaffoldJob extends ChangeNotifier {
  ProjectScaffoldJob._(this.directory);

  static const int _maxLogLines = 500;
  static const int _trimSlack = 128;

  /// The app's directory.
  final String directory;

  ProjectScaffoldPhase _phase = ProjectScaffoldPhase.create;
  final List<String> log = [];
  String? error;
  bool done = false;
  bool cancelled = false;
  FProject? result;
  Process? _current;
  bool _disposed = false;
  bool _notifyScheduled = false;

  ProjectScaffoldPhase get phase => _phase;

  void _setPhase(ProjectScaffoldPhase phase) {
    _phase = phase;
    _line('== ${phase.label}');
  }

  void _line(String message) {
    log.add(message);
    if (log.length > _maxLogLines + _trimSlack) {
      log.removeRange(0, log.length - _maxLogLines);
    }
    if (_notifyScheduled || _disposed) return;
    _notifyScheduled = true;
    scheduleMicrotask(() {
      _notifyScheduled = false;
      if (!_disposed) notifyListeners();
    });
  }

  void _finish({String? error, FProject? result}) {
    this.error = error;
    this.result = result;
    done = true;
    if (!_disposed) notifyListeners();
  }

  /// Stops the job. A directory the job created is removed.
  void cancel() {
    if (done) return;
    cancelled = true;
    _current?.kill();
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Creates new flutter_scene apps with one installation's tools.
class ProjectScaffolder {
  ProjectScaffolder({
    required this.installation,
    this.flutterSceneVersion,
    ScaffoldProcessStarter? start,
  }) : _start = start ?? Process.start;

  final FlutterInstallation installation;

  /// The flutter_scene version the editor was built with, if known.
  final String? flutterSceneVersion;

  final ScaffoldProcessStarter _start;

  /// Starts creating app [name] in `<parentDirectory>/<name>`. Throws a
  /// [FormatException] when the name or directory is unusable; every later
  /// failure lands on the returned job.
  ProjectScaffoldJob create({
    required String parentDirectory,
    required String name,
  }) {
    final nameError = validateProjectName(name);
    if (nameError != null) throw FormatException(nameError);
    final parent = Directory(
      parentDirectory,
    ).absolute.path.replaceAll(RegExp(r'[/\\]$'), '');
    final directory = '$parent${Platform.pathSeparator}$name';
    final directoryError = validateProjectDirectory(directory);
    if (directoryError != null) throw FormatException(directoryError);
    final job = ProjectScaffoldJob._(directory);
    unawaited(_run(job, parent, name));
    return job;
  }

  Future<void> _run(ProjectScaffoldJob job, String parent, String name) async {
    final directory = job.directory;
    final existed = Directory(directory).existsSync();
    try {
      job._setPhase(ProjectScaffoldPhase.create);
      Directory(parent).createSync(recursive: true);
      await _step(job, installation.flutterBin, [
        'create',
        '--empty',
        '--project-name',
        name,
        directory,
      ], parent);
      if (job.cancelled) return _abort(job, existed);

      job._setPhase(ProjectScaffoldPhase.dependency);
      await _step(job, installation.flutterBin, [
        'pub',
        'add',
        flutterSceneDependency(flutterSceneVersion),
      ], directory);
      if (job.cancelled) return _abort(job, existed);

      job._setPhase(ProjectScaffoldPhase.init);
      // TODO(editor-new-project): offer the agent skill install as a dialog
      // option; init cannot prompt without a terminal, so it is skipped.
      await _step(job, installation.dartBin, [
        'run',
        'flutter_scene:init',
        '--no-skills',
      ], directory);
      if (job.cancelled) return _abort(job, existed);

      job._setPhase(ProjectScaffoldPhase.register);
      final project = FProject.createDefault(directory);
      job._line('Created ${project.path}');
      job._finish(result: project);
    } catch (e) {
      if (job.cancelled) return _abort(job, existed);
      job._finish(
        error:
            '$e\nThe partial app is at $directory. Fix the error above, then '
            'open it with "Existing Flutter app".',
      );
    }
  }

  Future<void> _step(
    ProjectScaffoldJob job,
    String executable,
    List<String> args,
    String workingDirectory,
  ) async {
    job._line('+ $executable ${args.join(' ')}');
    final Process process;
    try {
      process = await _start(
        executable,
        args,
        workingDirectory: workingDirectory,
        environment: projectChildEnvironment(),
        includeParentEnvironment: false,
      );
    } on ProcessException catch (e) {
      throw _StepFailure('Failed to start $executable, ${e.message}');
    }
    job._current = process;
    // A cancel that landed while the process was starting had nothing to
    // kill yet.
    if (job.cancelled) process.kill();
    Future<void> tail(Stream<List<int>> stream) => stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .forEach((line) {
          if (line.trim().isNotEmpty) job._line(line);
        });
    final drained = Future.wait([tail(process.stdout), tail(process.stderr)]);
    final exitCode = await process.exitCode;
    await drained;
    job._current = null;
    if (exitCode != 0 && !job.cancelled) {
      throw _StepFailure('${args.take(2).join(' ')} exited with $exitCode.');
    }
  }

  void _abort(ProjectScaffoldJob job, bool existed) {
    // Everything inside was written by this job (the directory was missing or
    // empty). A pre-existing directory itself stays, the user may have made it
    // for the app.
    final dir = Directory(job.directory);
    try {
      if (!existed && dir.existsSync()) {
        dir.deleteSync(recursive: true);
      } else if (dir.existsSync()) {
        for (final entry in dir.listSync()) {
          entry.deleteSync(recursive: true);
        }
      }
    } on FileSystemException catch (e) {
      job._line('Could not remove ${job.directory}, $e');
    }
    job._finish(error: 'Cancelled.');
  }
}

class _StepFailure implements Exception {
  const _StepFailure(this.message);

  final String message;

  @override
  String toString() => message;
}
