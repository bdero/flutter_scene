import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_scene_editor/flutter_scene_editor.dart';
// ignore: implementation_imports
import 'package:flutter_scene_editor/src/project/vm_service_link.dart';
import 'package:flutter_test/flutter_test.dart';

/// A scripted daemon endpoint standing in for `flutter run --machine`.
class FakeRunProcess implements Process {
  final _stdout = StreamController<List<int>>();
  final _stderr = StreamController<List<int>>();
  final _exit = Completer<int>();
  final List<Map<String, Object?>> requests = [];
  late final IOSink _stdin;

  FakeRunProcess() {
    final controller = StreamController<List<int>>();
    controller.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          final decoded = jsonDecode(line) as List;
          requests.add((decoded.first as Map).cast<String, Object?>());
        });
    _stdin = IOSink(controller.sink);
  }

  void emitEvent(String event, Map<String, Object?> params) {
    _stdout.add(
      utf8.encode(
        '${jsonEncode([
          {'event': event, 'params': params},
        ])}\n',
      ),
    );
  }

  void emitResponse(int id, Object? result) {
    _stdout.add(
      utf8.encode(
        '${jsonEncode([
          {'id': id, 'result': result},
        ])}\n',
      ),
    );
  }

  void emitRaw(String line) => _stdout.add(utf8.encode('$line\n'));

  void exit(int code) {
    if (!_exit.isCompleted) _exit.complete(code);
    _stdout.close();
    _stderr.close();
  }

  @override
  Stream<List<int>> get stdout => _stdout.stream;
  @override
  Stream<List<int>> get stderr => _stderr.stream;
  @override
  IOSink get stdin => _stdin;
  @override
  Future<int> get exitCode => _exit.future;
  @override
  int get pid => 4242;
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    exit(-15);
    return true;
  }
}

/// A scripted VM Service endpoint answering JSON-RPC by method name.
class FakeVmSocket implements VmServiceSocket {
  FakeVmSocket(this.handlers);

  final Map<String, Object? Function(Map<String, Object?> params)> handlers;
  final List<Map<String, Object?>> calls = [];
  final _controller = StreamController<dynamic>();
  bool closed = false;

  @override
  Stream<dynamic> get messages => _controller.stream;

  @override
  void send(String text) {
    final message = (jsonDecode(text) as Map).cast<String, Object?>();
    calls.add(message);
    final handler = handlers[message['method']];
    _controller.add(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': message['id'],
        if (handler == null)
          'error': {'code': -32601, 'message': 'method not found'}
        else
          'result': handler(
            ((message['params'] as Map?) ?? const {}).cast<String, Object?>(),
          ),
      }),
    );
  }

  @override
  Future<void> close() async {
    closed = true;
    await _controller.close();
  }
}

void main() {
  late FakeRunProcess process;
  late AppSession session;
  late List<(String, ConsoleLineKind)> lines;
  List<String>? launchedArgv;

  const installation = FlutterInstallation(
    id: 'sdk',
    name: 'SDK',
    flutterBin: '/sdk/bin/flutter',
  );
  const device = FlutterDevice(
    id: 'macos',
    name: 'macOS',
    targetPlatform: 'darwin',
  );

  setUp(() {
    process = FakeRunProcess();
    lines = [];
    launchedArgv = null;
    session = AppSession(
      log: (text, kind) => lines.add((text, kind)),
      processStarter:
          (
            executable,
            arguments, {
            required workingDirectory,
            required environment,
          }) async {
            launchedArgv = [executable, ...arguments];
            return process;
          },
    );
  });

  FProject project(Directory root) => FProject(
    path: '${root.path}/x.fproject',
    flutterProjectRoot: '.',
    buildConfigurations: defaultBuildConfigurations(root.path),
  );

  Future<Directory> tempRoot() async {
    final root = Directory.systemTemp.createTempSync('app_session_');
    addTearDown(() => root.deleteSync(recursive: true));
    return root;
  }

  test('launch composes the machine invocation and tracks state', () async {
    final root = await tempRoot();
    final launched = project(root);
    final ok = await session.launch(
      installation: installation,
      project: launched,
      configuration: buildConfigurationTemplate('debug'),
      device: device,
    );
    expect(ok, isTrue);
    expect(session.state, AppSessionState.launching);
    expect(launchedArgv, [
      '/sdk/bin/flutter',
      'run',
      '--machine',
      '-d',
      'macos',
      '--debug',
      '--dart-define=FLUTTER_SCENE_SOURCE_ROOT='
          '${launched.resolvedProjectRoot}',
      '--target',
      'lib/main.dart',
      '--enable-flutter-gpu',
      '--enable-impeller',
    ]);

    process.emitEvent('app.start', {'appId': 'app-1'});
    process.emitEvent('app.debugPort', {'wsUri': 'ws://127.0.0.1:1/ws'});
    process.emitEvent('app.progress', {
      'message': 'Launching lib/main.dart on macOS...',
      'finished': false,
    });
    process.emitEvent('app.started', {});
    await pumpEventQueue();

    expect(session.state, AppSessionState.running);
    expect(session.appId, 'app-1');
    expect(session.vmServiceUri, 'ws://127.0.0.1:1/ws');
    expect(session.supportsHotReload, isTrue);
    expect(session.supportsHotRestart, isTrue);
    expect(
      lines,
      contains(('Launching lib/main.dart on macOS...', ConsoleLineKind.status)),
    );

    process.emitEvent('app.log', {'log': 'hello from the app'});
    process.emitEvent('app.log', {'log': 'boom', 'error': true});
    process.emitRaw('plain non-JSON output');
    await pumpEventQueue();
    expect(lines, contains(('hello from the app', ConsoleLineKind.output)));
    expect(lines, contains(('boom', ConsoleLineKind.error)));
    expect(lines, contains(('plain non-JSON output', ConsoleLineKind.output)));

    process.exit(0);
    await pumpEventQueue();
    expect(session.state, AppSessionState.idle);
    expect(session.appId, isNull);
  });

  test('restart round trips an app.restart request', () async {
    final root = await tempRoot();
    await session.launch(
      installation: installation,
      project: project(root),
      configuration: buildConfigurationTemplate('debug'),
      device: device,
    );
    process.emitEvent('app.start', {'appId': 'app-1'});
    process.emitEvent('app.started', {});
    await pumpEventQueue();

    final restarted = session.restart(reason: 'save');
    await pumpEventQueue();
    expect(session.state, AppSessionState.restarting);
    final request = process.requests.single;
    expect(request['method'], 'app.restart');
    final params = (request['params'] as Map).cast<String, Object?>();
    expect(params['appId'], 'app-1');
    expect(params['fullRestart'], isTrue);
    process.emitResponse(request['id'] as int, {'code': 0, 'message': 'ok'});
    expect(await restarted, isTrue);
    expect(session.state, AppSessionState.running);

    process.exit(0);
    await pumpEventQueue();
  });

  test('hot reload is refused outside debug mode', () async {
    final root = await tempRoot();
    await session.launch(
      installation: installation,
      project: project(root),
      configuration: buildConfigurationTemplate('profile'),
      device: device,
    );
    process.emitEvent('app.start', {'appId': 'app-1'});
    process.emitEvent('app.started', {});
    await pumpEventQueue();

    expect(session.supportsHotReload, isFalse);
    expect(session.supportsHotRestart, isTrue);
    expect(await session.restart(fullRestart: false), isFalse);
    expect(process.requests, isEmpty);

    process.exit(0);
    await pumpEventQueue();
  });

  test('stop sends app.stop and settles on process exit', () async {
    final root = await tempRoot();
    await session.launch(
      installation: installation,
      project: project(root),
      configuration: buildConfigurationTemplate('debug'),
      device: device,
    );
    process.emitEvent('app.start', {'appId': 'app-1'});
    process.emitEvent('app.started', {});
    await pumpEventQueue();

    final stopping = session.stop();
    await pumpEventQueue();
    expect(session.state, AppSessionState.stopping);
    final request = process.requests.single;
    expect(request['method'], 'app.stop');
    process.emitResponse(request['id'] as int, true);
    process.exit(0);
    await stopping;
    await pumpEventQueue();
    expect(session.state, AppSessionState.idle);
  });

  test('a second launch while active is refused', () async {
    final root = await tempRoot();
    await session.launch(
      installation: installation,
      project: project(root),
      configuration: buildConfigurationTemplate('debug'),
      device: device,
    );
    expect(
      await session.launch(
        installation: installation,
        project: project(root),
        configuration: buildConfigurationTemplate('debug'),
        device: device,
      ),
      isFalse,
    );
    process.exit(0);
    await pumpEventQueue();
  });

  /// Launches a running debug session whose VM service is [socket].
  Future<AppSession> runningSession(FakeVmSocket socket) async {
    var connections = 0;
    final vmSession = AppSession(
      log: (text, kind) => lines.add((text, kind)),
      processStarter:
          (
            executable,
            arguments, {
            required workingDirectory,
            required environment,
          }) async => process,
      vmSocketConnector: (wsUri) async {
        connections++;
        expect(wsUri, 'ws://127.0.0.1:1/ws');
        expect(connections, 1, reason: 'the link is cached per session');
        return socket;
      },
    );
    addTearDown(vmSession.dispose);
    final root = await tempRoot();
    await vmSession.launch(
      installation: installation,
      project: project(root),
      configuration: buildConfigurationTemplate('debug'),
      device: device,
    );
    process.emitEvent('app.start', {'appId': 'app-1'});
    process.emitEvent('app.debugPort', {'wsUri': 'ws://127.0.0.1:1/ws'});
    process.emitEvent('app.started', {});
    await pumpEventQueue();
    return vmSession;
  }

  test('reloadScenes drives the flutter_scene extension', () async {
    final socket = FakeVmSocket({
      'getVM': (_) => {
        'isolates': [
          {'id': 'isolates/1'},
        ],
      },
      'getIsolate': (params) {
        expect(params['isolateId'], 'isolates/1');
        return {
          'extensionRPCs': ['ext.flutter_scene.reloadScene'],
        };
      },
      'ext.flutter_scene.reloadScene': (params) {
        expect(params['isolateId'], 'isolates/1');
        return {'type': 'Success', 'sourceLoading': true};
      },
    });
    final vmSession = await runningSession(socket);

    expect(await vmSession.reloadScenes(), isTrue);
    expect(await vmSession.reloadScenes(), isTrue);
    expect(
      lines.where((line) => line.$1.startsWith('Reloaded scenes in place')),
      hasLength(2),
    );

    process.exit(0);
    await pumpEventQueue();
    expect(socket.closed, isTrue, reason: 'exit disposes the link');
  });

  test(
    'reloadScenes reports false when no isolate has the extension',
    () async {
      final socket = FakeVmSocket({
        'getVM': (_) => {
          'isolates': [
            {'id': 'isolates/1'},
          ],
        },
        'getIsolate': (_) => {'extensionRPCs': <String>[]},
      });
      final vmSession = await runningSession(socket);

      expect(await vmSession.reloadScenes(), isFalse);
      expect(
        lines.any((line) => line.$1.startsWith('Scene reload unavailable')),
        isTrue,
      );

      process.exit(0);
      await pumpEventQueue();
    },
  );

  test('reloadScenes reports false without source-direct loading', () async {
    final socket = FakeVmSocket({
      'getVM': (_) => {
        'isolates': [
          {'id': 'isolates/1'},
        ],
      },
      'getIsolate': (_) => {
        'extensionRPCs': ['ext.flutter_scene.reloadScene'],
      },
      'ext.flutter_scene.reloadScene': (_) => {
        'type': 'Success',
        'sourceLoading': false,
      },
    });
    final vmSession = await runningSession(socket);

    expect(await vmSession.reloadScenes(), isFalse);

    process.exit(0);
    await pumpEventQueue();
  });

  test('setPaused holds and releases every isolate', () async {
    final paused = <String>[];
    final resumed = <String>[];
    final socket = FakeVmSocket({
      'getVM': (_) => {
        'isolates': [
          {'id': 'isolates/1'},
          {'id': 'isolates/2'},
        ],
      },
      'pause': (params) {
        paused.add(params['isolateId']! as String);
        return {'type': 'Success'};
      },
      'resume': (params) {
        resumed.add(params['isolateId']! as String);
        return {'type': 'Success'};
      },
    });
    final vmSession = await runningSession(socket);

    expect(vmSession.paused, isFalse);
    expect(await vmSession.setPaused(true), isTrue);
    expect(vmSession.paused, isTrue);
    // Every isolate, not just the main one: a background isolate that kept
    // running would mutate state behind a frozen frame.
    expect(paused, ['isolates/1', 'isolates/2']);

    // Asking for the state it is already in is a no-op, not a second call.
    expect(await vmSession.setPaused(true), isTrue);
    expect(paused, hasLength(2));

    expect(await vmSession.setPaused(false), isTrue);
    expect(vmSession.paused, isFalse);
    expect(resumed, ['isolates/1', 'isolates/2']);
  });

  test('setPaused reports failure when the VM refuses', () async {
    final socket = FakeVmSocket({
      'getVM': (_) => {
        'isolates': [
          {'id': 'isolates/1'},
        ],
      },
      // No 'pause' handler: the fake answers unknown methods with an error,
      // which is what a VM that will not hold looks like.
    });
    final vmSession = await runningSession(socket);

    expect(await vmSession.setPaused(true), isFalse);
    expect(vmSession.paused, isFalse, reason: 'a refused hold is not a hold');
    expect(
      lines.where((line) => line.$1.contains('Could not hold')),
      hasLength(1),
    );
  });

  test('a hold does not survive the app leaving the running state', () async {
    final socket = FakeVmSocket({
      'getVM': (_) => {
        'isolates': [
          {'id': 'isolates/1'},
        ],
      },
      'pause': (_) => {'type': 'Success'},
    });
    final vmSession = await runningSession(socket);
    expect(await vmSession.setPaused(true), isTrue);
    expect(vmSession.paused, isTrue);

    // The isolates it applied to are gone, so the flag cannot outlive them.
    process.exit(0);
    await pumpEventQueue();
    expect(vmSession.paused, isFalse);
  });
}
