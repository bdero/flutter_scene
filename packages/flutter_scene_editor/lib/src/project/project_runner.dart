/// Runs a project's build/run commands as streamed subprocesses feeding the
/// Console panel. At most one build and one run live at a time; commands run
/// argv-style (no shell) from the project root with SDK-management variables
/// scrubbed from the child environment.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../toolchains/flutter_installation.dart';
import 'fproject.dart';

/// One console line, tagged with its origin for styling.
class ConsoleLine {
  const ConsoleLine(this.text, {this.kind = ConsoleLineKind.output});

  final String text;
  final ConsoleLineKind kind;
}

enum ConsoleLineKind { command, output, error, status }

/// The editor's build/run process owner. Listen for console and state
/// changes.
class ProjectRunner extends ChangeNotifier {
  static const int maxConsoleLines = 2000;

  final List<ConsoleLine> console = [];
  Process? _build;
  Process? _run;

  bool get building => _build != null;
  bool get running => _run != null;

  void clearConsole() {
    console.clear();
    notifyListeners();
  }

  void _line(String text, ConsoleLineKind kind) {
    console.add(ConsoleLine(text, kind: kind));
    if (console.length > maxConsoleLines) {
      console.removeRange(0, console.length - maxConsoleLines);
    }
    notifyListeners();
  }

  /// Starts the configuration's build command. Returns the exit code, or
  /// null when a build is already running or the command is malformed.
  Future<int?> startBuild({
    required FlutterInstallation installation,
    required FProject project,
    required BuildConfiguration configuration,
  }) => _start(
    installation: installation,
    project: project,
    configuration: configuration,
    command: configuration.buildCommand,
    isRun: false,
  );

  /// Starts the configuration's run command (the Play button).
  Future<int?> startRun({
    required FlutterInstallation installation,
    required FProject project,
    required BuildConfiguration configuration,
  }) => _start(
    installation: installation,
    project: project,
    configuration: configuration,
    command: configuration.runCommand,
    isRun: true,
  );

  Future<int?> _start({
    required FlutterInstallation installation,
    required FProject project,
    required BuildConfiguration configuration,
    required String command,
    required bool isRun,
  }) async {
    if (isRun ? running : building) {
      _line(
        'A ${isRun ? 'run' : 'build'} is already in progress.',
        ConsoleLineKind.error,
      );
      return null;
    }
    final List<String> argv;
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
      );
      argv = [
        for (final token in tokenizeCommand(command))
          substituteCommandVariables(token, variables),
      ];
    } on FormatException catch (e) {
      _line(e.message, ConsoleLineKind.error);
      return null;
    }
    if (argv.isEmpty) {
      _line('The command is empty.', ConsoleLineKind.error);
      return null;
    }

    // The child environment is the editor's minus SDK-management variables
    // (they can break flutter run on some versions when inherited).
    final environment = Map.of(Platform.environment)
      ..remove('FLUTTER_GIT_URL')
      ..remove('FLUTTER_PREBUILT_ENGINE_VERSION')
      ..remove('IMPELLERC');

    _line('[${configuration.name}] ${argv.join(' ')}', ConsoleLineKind.command);
    final Process process;
    try {
      process = await Process.start(
        argv.first,
        argv.sublist(1),
        workingDirectory: project.resolvedProjectRoot,
        environment: environment,
        includeParentEnvironment: false,
      );
    } on ProcessException catch (e) {
      _line('Failed to start, ${e.message}', ConsoleLineKind.error);
      return null;
    }
    if (isRun) {
      _run = process;
    } else {
      _build = process;
    }
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
    if (isRun) {
      _run = null;
    } else {
      _build = null;
    }
    _line(
      '[${configuration.name}] exited with $exitCode',
      exitCode == 0 ? ConsoleLineKind.status : ConsoleLineKind.error,
    );
    return exitCode;
  }

  /// Stops the running app (SIGTERM, then SIGKILL after a grace period).
  void stopRun() => _stop(_run);

  /// Stops the running build.
  void stopBuild() => _stop(_build);

  void _stop(Process? process) {
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
    stopRun();
    stopBuild();
    super.dispose();
  }
}
