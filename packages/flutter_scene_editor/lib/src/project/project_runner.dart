/// Runs a project's build command and tasks as streamed subprocesses feeding
/// the Console panel. At most one subprocess lives at a time; commands run
/// argv-style (no shell) from the project root with SDK-management variables
/// scrubbed from the child environment. The Play session (flutter run under
/// the machine protocol) is AppSession's job, not this runner's.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../toolchains/device_catalog.dart';
import '../toolchains/flutter_installation.dart';
import 'fproject.dart';

/// One console line, tagged with its origin for styling.
class ConsoleLine {
  const ConsoleLine(this.text, {this.kind = ConsoleLineKind.output});

  final String text;
  final ConsoleLineKind kind;
}

enum ConsoleLineKind { command, output, error, status }

/// The editor's task subprocess owner. Listen for console and state changes.
class ProjectRunner extends ChangeNotifier {
  static const int maxConsoleLines = 2000;
  // Trim in chunks; trimming one line per append is O(length) every line
  // once the buffer is at capacity.
  static const int _trimSlack = 256;

  final List<ConsoleLine> console = [];
  Process? _build;
  bool _notifyScheduled = false;

  bool get building => _build != null;

  void clearConsole() {
    console.clear();
    notifyListeners();
  }

  /// Appends one console line (also the sink AppSession logs through, so
  /// session and task output share one Console).
  void addLine(String text, ConsoleLineKind kind) => _line(text, kind);

  void _line(String text, ConsoleLineKind kind) {
    console.add(ConsoleLine(text, kind: kind));
    if (console.length > maxConsoleLines + _trimSlack) {
      console.removeRange(0, console.length - maxConsoleLines);
    }
    // One stdout chunk can split into many lines; notify once per burst.
    if (_notifyScheduled) return;
    _notifyScheduled = true;
    scheduleMicrotask(() {
      _notifyScheduled = false;
      notifyListeners();
    });
  }

  /// Starts the configuration's build command. Returns the exit code, or
  /// null when a build is already running or the command is malformed.
  Future<int?> startBuild({
    required FlutterInstallation installation,
    required FProject project,
    required BuildConfiguration configuration,
    FlutterDevice? device,
  }) => _start(
    installation: installation,
    project: project,
    configuration: configuration,
    device: device,
    command: configuration.buildCommand,
    label: configuration.name,
  );

  /// Starts a free-form project task's command template.
  Future<int?> startTask({
    required FlutterInstallation installation,
    required FProject project,
    required BuildConfiguration configuration,
    required ProjectTask task,
    FlutterDevice? device,
  }) => _start(
    installation: installation,
    project: project,
    configuration: configuration,
    device: device,
    command: task.command,
    label: task.name,
  );

  Future<int?> _start({
    required FlutterInstallation installation,
    required FProject project,
    required BuildConfiguration configuration,
    required FlutterDevice? device,
    required String command,
    required String label,
  }) async {
    if (building) {
      _line('A command is already in progress.', ConsoleLineKind.error);
      return null;
    }
    final List<String> argv;
    final String workingDirectory;
    try {
      // Tokenize the template first, then substitute inside each token, so a
      // variable expanding to a path with spaces stays one argument.
      final variables = commandVariables(
        flutterBin: installation.flutterBin,
        dartBin: installation.dartBin,
        sdkRoot: installation.sdkRoot,
        impellerc: installation.resolvedImpellerc,
        projectRoot: project.resolvedProjectRoot,
        configuration: configuration,
        deviceId: device?.id,
        // A persisted device id whose platform is not yet known (the catalog
        // has not listed since launch) cannot derive a build target.
        buildTarget: device == null || device.targetPlatform.isEmpty
            ? null
            : device.buildTarget,
      );
      argv = [
        for (final token in tokenizeCommand(command))
          substituteCommandVariables(token, variables),
      ];
      workingDirectory = resolveWorkingDirectory(
        project,
        configuration,
        variables,
      );
    } on FormatException catch (e) {
      _line(
        e.message.contains('DEVICE') || e.message.contains('BUILD_TARGET')
            ? '${e.message}. Select a device in the toolbar.'
            : e.message,
        ConsoleLineKind.error,
      );
      return null;
    }
    if (argv.isEmpty) {
      _line('The command is empty.', ConsoleLineKind.error);
      return null;
    }

    final environment = projectChildEnvironment();

    _line(
      '[$label] ${argv.join(' ')}  (in $workingDirectory)',
      ConsoleLineKind.command,
    );
    // Build-hook progress is invisible in normal flutter output on macOS (the
    // assemble phase runs inside xcodebuild, which swallows it), so tail the
    // hook runner's stderr logs directly while the command runs.
    final hookLogs = HookLogTailer(
      Directory('${project.resolvedProjectRoot}/.dart_tool/hooks_runner'),
      (line) => _line(line, ConsoleLineKind.output),
    )..start();
    final Process process;
    try {
      process = await Process.start(
        argv.first,
        argv.sublist(1),
        workingDirectory: workingDirectory,
        environment: environment,
        includeParentEnvironment: false,
      );
    } on ProcessException catch (e) {
      hookLogs.stop();
      _line('Failed to start, ${e.message}', ConsoleLineKind.error);
      return null;
    }
    _build = process;
    notifyListeners();

    Future<void> tail(Stream<List<int>> stream, ConsoleLineKind kind) => stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .forEach((line) => _line(line, kind));
    final drained = Future.wait([
      tail(process.stdout, ConsoleLineKind.output),
      tail(process.stderr, ConsoleLineKind.error),
    ]);
    final exitCode = await process.exitCode;
    await drained;
    hookLogs.stop();
    _build = null;
    _line(
      '[$label] exited with $exitCode',
      exitCode == 0 ? ConsoleLineKind.status : ConsoleLineKind.error,
    );
    return exitCode;
  }

  /// Stops the running command (SIGTERM, then SIGKILL after a grace period).
  void stopBuild() {
    final process = _build;
    if (process == null) return;
    process.kill();
    unawaited(
      Future<void>.delayed(const Duration(seconds: 5)).then((_) {
        // A no-op when the process already exited.
        process.kill(ProcessSignal.sigkill);
      }),
    );
  }

  @override
  void dispose() {
    stopBuild();
    super.dispose();
  }
}

/// Streams new lines appended to hook runner `stderr.txt` logs while a build
/// or run command is active. Existing content is baselined at start so only
/// fresh output reaches the console; a shrunken file (the runner truncates
/// each log when its hook starts) is reread from the top.
class HookLogTailer {
  HookLogTailer(this.root, this.emit);

  final Directory root;
  final void Function(String line) emit;
  final Map<String, int> _offsets = {};
  Timer? _timer;

  void start() {
    _scan(baseline: true);
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) => _scan());
  }

  void stop() {
    if (_timer == null) return;
    _timer!.cancel();
    _timer = null;
    _scan();
  }

  void _scan({bool baseline = false}) {
    if (!root.existsSync()) return;
    final Iterable<File> logs;
    try {
      logs = root
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .where((f) => f.path.endsWith('stderr.txt'));
    } on FileSystemException {
      return;
    }
    for (final file in logs) {
      try {
        final length = file.lengthSync();
        final offset = _offsets[file.path] ?? 0;
        if (baseline) {
          _offsets[file.path] = length;
          continue;
        }
        if (length == offset) continue;
        final start = length < offset ? 0 : offset;
        final raf = file.openSync();
        try {
          raf.setPositionSync(start);
          final bytes = raf.readSync(length - start);
          _offsets[file.path] = length;
          for (final line in const LineSplitter().convert(
            utf8.decode(bytes, allowMalformed: true),
          )) {
            if (line.trim().isEmpty) continue;
            emit(line);
          }
        } finally {
          raf.closeSync();
        }
      } on FileSystemException {
        // The runner may be rewriting the file; catch up next tick.
      }
    }
  }
}
