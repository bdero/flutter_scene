/// The editor-owned Play session, one `flutter run --machine` process driven
/// over the daemon protocol. The editor composes the invocation (device,
/// mode, target, extra args) so it can parse structured events, hot
/// reload/restart over stdin, and stop cleanly; free-form commands stay in
/// ProjectRunner tasks.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:scene/schema.dart';

import '../toolchains/device_catalog.dart';
import '../toolchains/flutter_installation.dart';
import 'fproject.dart';
import 'project_runner.dart';
import 'vm_service_link.dart';

enum AppSessionState { idle, launching, running, restarting, stopping }

/// Injectable process launcher, so tests drive the protocol with a fake.
typedef SessionProcessStarter =
    Future<Process> Function(
      String executable,
      List<String> arguments, {
      required String workingDirectory,
      required Map<String, String> environment,
    });

Future<Process> _startProcess(
  String executable,
  List<String> arguments, {
  required String workingDirectory,
  required Map<String, String> environment,
}) => Process.start(
  executable,
  arguments,
  workingDirectory: workingDirectory,
  environment: environment,
  includeParentEnvironment: false,
);

/// Owns at most one running app. Listen for state changes; output flows into
/// the shared Console through [log].
class AppSession extends ChangeNotifier {
  AppSession({
    required this.log,
    SessionProcessStarter? processStarter,
    VmSocketConnector? vmSocketConnector,
  }) : _startProcess0 = processStarter ?? _startProcess,
       _vmSocketConnector = vmSocketConnector;

  final void Function(String text, ConsoleLineKind kind) log;
  final SessionProcessStarter _startProcess0;
  final VmSocketConnector? _vmSocketConnector;

  AppSessionState _state = AppSessionState.idle;
  Process? _process;
  HookLogTailer? _hookLogs;
  String? _appId;
  String? _vmServiceUri;
  Future<VmServiceLink>? _vmLink;
  String _mode = '';
  String? _deviceId;
  int _requestId = 0;
  final Map<int, Completer<Map<String, Object?>>> _pending = {};

  AppSessionState get state => _state;
  bool get active => _state != AppSessionState.idle;
  String? get appId => _appId;

  /// The VM Service websocket URI from `app.debugPort`, when the mode has one.
  String? get vmServiceUri => _vmServiceUri;

  /// The launched configuration's mode (debug/profile/release).
  String get mode => _mode;
  String? get deviceId => _deviceId;

  /// Hot reload needs a debug VM.
  bool get supportsHotReload => _mode == 'debug';

  /// Hot restart needs a VM (debug or profile).
  bool get supportsHotRestart => _mode == 'debug' || _mode == 'profile';

  /// Whether the editor has asked the running app to hold.
  ///
  /// This reflects the last hold or release this session issued, not a live
  /// query of the VM: an app stopped at a breakpoint by another client reads
  /// as running here. It clears whenever the app leaves the running state or
  /// is restarted, since both replace the isolates it applied to.
  bool get paused => _paused;
  bool _paused = false;

  /// Whether the running app can be held. Needs a VM service, which a release
  /// build does not carry.
  bool get supportsPause => _vmServiceUri != null;

  bool _disposed = false;

  void _setState(AppSessionState state) {
    // The process outlives dispose by however long it takes to die, and its
    // exit still runs through here. Notifying then trips ChangeNotifier's
    // use-after-dispose assertion, so stop at the door.
    if (_disposed || _state == state) return;
    _state = state;
    // Holding applies to isolates that no longer exist once the app leaves
    // the running state, so the flag cannot outlive it.
    if (state != AppSessionState.running) _paused = false;
    notifyListeners();
  }

  /// Launches `flutter run --machine` for [configuration] on [device].
  /// Returns false (with a console line) when a session is already active.
  Future<bool> launch({
    required FlutterInstallation installation,
    required FProject project,
    required BuildConfiguration configuration,
    required FlutterDevice device,
  }) async {
    if (active) {
      log(
        'A session is already running; stop it first.',
        ConsoleLineKind.error,
      );
      return false;
    }
    // Claim the session before the first await; overlapping launch() calls
    // (double-click Play, UI plus MCP) would otherwise both pass the guard
    // and spawn two processes.
    _setState(AppSessionState.launching);
    final List<String> argv;
    final String workingDirectory;
    try {
      final variables = commandVariables(
        flutterBin: installation.flutterBin,
        dartBin: installation.dartBin,
        sdkRoot: installation.sdkRoot,
        impellerc: installation.resolvedImpellerc,
        projectRoot: project.resolvedProjectRoot,
        configuration: configuration,
        deviceId: device.id,
        buildTarget: device.targetPlatform.isEmpty ? null : device.buildTarget,
      );
      argv = [
        installation.flutterBin,
        'run',
        '--machine',
        '-d',
        device.id,
        '--${configuration.mode}',
        // Debug sessions read scene sources straight from the project, so an
        // editor save is visible to ext.flutter_scene.reloadScene without a
        // rebuild (flutter_scene ignores the define outside debug).
        if (configuration.mode == 'debug')
          '--dart-define=FLUTTER_SCENE_SOURCE_ROOT='
              '${project.resolvedProjectRoot}',
        '--target',
        substituteCommandVariables(configuration.run.target, variables),
        for (final arg in configuration.run.args)
          substituteCommandVariables(arg, variables),
      ];
      workingDirectory = resolveWorkingDirectory(
        project,
        configuration,
        variables,
      );
    } on FormatException catch (e) {
      log(e.message, ConsoleLineKind.error);
      _setState(AppSessionState.idle);
      return false;
    }

    log(
      '[${configuration.name}] ${argv.join(' ')}  (in $workingDirectory)',
      ConsoleLineKind.command,
    );
    final Process process;
    try {
      process = await _startProcess0(
        argv.first,
        argv.sublist(1),
        workingDirectory: workingDirectory,
        environment: projectChildEnvironment(),
      );
    } on ProcessException catch (e) {
      log('Failed to start, ${e.message}', ConsoleLineKind.error);
      _setState(AppSessionState.idle);
      return false;
    }
    _process = process;
    _mode = configuration.mode;
    _deviceId = device.id;
    _appId = null;
    _vmServiceUri = null;
    // Session launches build under the hood; surface hook progress the same
    // way task subprocesses do.
    _hookLogs = HookLogTailer(
      Directory('${project.resolvedProjectRoot}/.dart_tool/hooks_runner'),
      (line) => log(line, ConsoleLineKind.output),
    )..start();

    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_handleStdoutLine);
    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) => log(line, ConsoleLineKind.error));
    unawaited(process.exitCode.then(_onExited));
    return true;
  }

  void _onExited(int exitCode) {
    _hookLogs?.stop();
    _hookLogs = null;
    _process = null;
    _appId = null;
    _vmServiceUri = null;
    _disposeVmLink();
    for (final pending in _pending.values) {
      if (!pending.isCompleted) {
        pending.complete({'error': 'the app exited'});
      }
    }
    _pending.clear();
    log(
      'App session exited with $exitCode',
      exitCode == 0 ? ConsoleLineKind.status : ConsoleLineKind.error,
    );
    _setState(AppSessionState.idle);
  }

  // One daemon message per stdout line, a JSON array wrapping one object.
  // Anything else (early tool output, stray prints) passes through as plain
  // console output.
  void _handleStdoutLine(String line) {
    final trimmed = line.trim();
    if (trimmed.startsWith('[{') && trimmed.endsWith('}]')) {
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is List && decoded.length == 1 && decoded.first is Map) {
          _handleMessage((decoded.first as Map).cast<String, Object?>());
          return;
        }
      } on FormatException {
        // Fall through to plain output.
      }
    }
    if (trimmed.isNotEmpty) log(line, ConsoleLineKind.output);
  }

  void _handleMessage(Map<String, Object?> message) {
    final id = message['id'];
    if (id is int) {
      _pending.remove(id)?.complete(message);
      return;
    }
    final params = message['params'] is Map
        ? (message['params'] as Map).cast<String, Object?>()
        : const <String, Object?>{};
    switch (message['event']) {
      case 'app.start':
        _appId = params['appId'] as String?;
        notifyListeners();
      case 'app.debugPort':
        _vmServiceUri = params['wsUri'] as String?;
        notifyListeners();
      case 'app.started':
        log('App started', ConsoleLineKind.status);
        // The build is over; end the hook-log poll rather than scanning the
        // hooks_runner tree every tick for the rest of the session.
        _hookLogs?.stop();
        _hookLogs = null;
        _setState(AppSessionState.running);
      case 'app.progress':
        final progressMessage = params['message'];
        if (progressMessage is String &&
            progressMessage.isNotEmpty &&
            params['finished'] != true) {
          log(progressMessage, ConsoleLineKind.status);
        }
      case 'app.log':
        final text = params['log'];
        if (text is String && text.isNotEmpty) {
          log(
            text,
            params['error'] == true
                ? ConsoleLineKind.error
                : ConsoleLineKind.output,
          );
        }
      case 'daemon.logMessage':
        if (params['level'] == 'error' && params['message'] is String) {
          log(params['message'] as String, ConsoleLineKind.error);
        }
    }
  }

  Future<Map<String, Object?>> _request(
    String method,
    Map<String, Object?> params,
  ) {
    final process = _process;
    if (process == null) {
      return Future.value({'error': 'no session'});
    }
    final id = ++_requestId;
    final completer = Completer<Map<String, Object?>>();
    _pending[id] = completer;
    process.stdin.writeln(
      '[${jsonEncode({'id': id, 'method': method, 'params': params})}]',
    );
    return completer.future;
  }

  /// Hot restart (or with [fullRestart] false, hot reload). Returns whether
  /// the daemon reported success.
  Future<bool> restart({
    bool fullRestart = true,
    String reason = 'manual',
  }) async {
    final appId = _appId;
    if (_state != AppSessionState.running || appId == null) return false;
    if (fullRestart ? !supportsHotRestart : !supportsHotReload) {
      log(
        '${fullRestart ? 'Hot restart' : 'Hot reload'} is unavailable in '
        '$_mode mode.',
        ConsoleLineKind.error,
      );
      return false;
    }
    _setState(AppSessionState.restarting);
    final watch = Stopwatch()..start();
    final response = await _request('app.restart', {
      'appId': appId,
      'fullRestart': fullRestart,
      'pause': false,
      'reason': reason,
    });
    // The session may have exited mid-restart.
    if (_state == AppSessionState.restarting) {
      _setState(AppSessionState.running);
    }
    final result = response['result'];
    final ok = result is Map && result['code'] == 0;
    final label = fullRestart ? 'Hot restart' : 'Hot reload';
    if (ok) {
      log(
        '$label finished in ${(watch.elapsedMilliseconds / 1000).toStringAsFixed(1)}s',
        ConsoleLineKind.status,
      );
    } else {
      log(
        '$label failed, '
        '${result is Map ? result['message'] ?? response : response}',
        ConsoleLineKind.error,
      );
    }
    return ok;
  }

  void _disposeVmLink() {
    final pending = _vmLink;
    _vmLink = null;
    if (pending != null) {
      unawaited(
        pending.then((link) => link.dispose()).catchError((Object _) {}),
      );
    }
  }

  /// The cached VM service link, reconnecting when the cached one's socket
  /// has dropped (a dead link would swallow every later request). Null when
  /// connecting fails.
  Future<VmServiceLink?> _connectedVmLink(String wsUri) async {
    final cached = _vmLink;
    if (cached != null) {
      try {
        final link = await cached;
        if (link.isAlive) return link;
      } catch (_) {}
      _disposeVmLink();
    }
    try {
      final pending = _vmLink = VmServiceLink.connect(
        wsUri,
        connector: _vmSocketConnector,
      );
      return await pending;
    } catch (e) {
      _vmLink = null;
      log('VM service connection failed, $e', ConsoleLineKind.error);
      return null;
    }
  }

  /// Asks the running app to reload changed scene assets in place through
  /// flutter_scene's `ext.flutter_scene.reloadScene` debug extension.
  /// Returns whether the app refreshed from project sources (false means the
  /// caller should fall back to a hot restart, because the app is not
  /// running, has no VM service, does not register the extension, or was not
  /// launched with source-direct loading).
  Future<bool> reloadScenes() async {
    final wsUri = _vmServiceUri;
    if (_state != AppSessionState.running || wsUri == null) return false;
    final link = await _connectedVmLink(wsUri);
    if (link == null) return false;
    final watch = Stopwatch()..start();
    final result = await link.callExtension(
      'ext.flutter_scene.reloadScene',
      onError: (message) =>
          log('Scene reload unavailable, $message', ConsoleLineKind.status),
    );
    if (result == null || result['sourceLoading'] != true) return false;
    log(
      'Reloaded scenes in place in ${watch.elapsedMilliseconds}ms',
      ConsoleLineKind.status,
    );
    return true;
  }

  /// Fetches the running app's registered component schemas over the VM
  /// service (`ext.flutter_scene.componentSchemas`), the authoritative source
  /// for the editor's foreign-component support. Returns null when the app
  /// is not running, has no VM service, or does not register the extension.
  Future<List<ComponentSchema>?> fetchComponentSchemas() async {
    final wsUri = _vmServiceUri;
    if (_state != AppSessionState.running || wsUri == null) return null;
    final link = await _connectedVmLink(wsUri);
    if (link == null) return null;
    final result = await link.callExtension(
      'ext.flutter_scene.componentSchemas',
      onError: (message) => log(
        'Component schemas unavailable, $message',
        ConsoleLineKind.status,
      ),
    );
    if (result == null) return null;
    return decodeComponentSchemas(result['schemas']);
  }

  /// Holds ([hold] true) or releases every isolate in the running app.
  ///
  /// Every isolate rather than only the main one: holding the app means the
  /// whole thing stops advancing, and a background isolate that kept running
  /// would carry on mutating state behind a frozen frame.
  ///
  /// Returns whether the VM accepted it. Asking for the state it is already
  /// in succeeds without a call.
  Future<bool> setPaused(bool hold) async {
    if (_paused == hold) return true;
    final wsUri = _vmServiceUri;
    if (_state != AppSessionState.running || wsUri == null) return false;
    final link = await _connectedVmLink(wsUri);
    if (link == null) return false;

    final vm = await link.request('getVM');
    final isolates = ((vm['result'] as Map?)?['isolates'] as List?) ?? const [];
    final method = hold ? 'pause' : 'resume';
    var applied = 0;
    for (final ref in isolates) {
      if (ref is! Map) continue;
      final isolateId = ref['id'];
      if (isolateId is! String) continue;
      final response = await link.request(method, {'isolateId': isolateId});
      if (response['error'] == null) applied++;
    }
    if (applied == 0) {
      log(
        hold ? 'Could not hold the app' : 'Could not release the app',
        ConsoleLineKind.error,
      );
      return false;
    }
    _paused = hold;
    log(hold ? 'App held' : 'App released', ConsoleLineKind.status);
    notifyListeners();
    return true;
  }

  /// Stops the app (a daemon `app.stop`, escalating to killing the tool
  /// process when the daemon does not comply).
  Future<void> stop() async {
    final process = _process;
    if (process == null) return;
    _setState(AppSessionState.stopping);
    final appId = _appId;
    if (appId != null) {
      try {
        final response = await _request('app.stop', {
          'appId': appId,
        }).timeout(const Duration(seconds: 10));
        // An error reply means the app is not stopping; fall through to
        // killing the process rather than sticking in `stopping`.
        if (response['error'] == null) return;
      } on TimeoutException {
        // Fall through to killing the process.
      }
    }
    process.kill();
    unawaited(
      Future<void>.delayed(const Duration(seconds: 5)).then((_) {
        process.kill(ProcessSignal.sigkill);
      }),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _disposeVmLink();
    _process?.kill();
    super.dispose();
  }
}
