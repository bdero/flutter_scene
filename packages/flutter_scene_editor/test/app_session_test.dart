import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_scene_editor/flutter_scene_editor.dart';
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
    final ok = await session.launch(
      installation: installation,
      project: project(root),
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
}
