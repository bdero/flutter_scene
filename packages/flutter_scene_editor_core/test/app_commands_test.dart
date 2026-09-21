// Everything around the document is a command too, so a script opens, saves,
// runs, and switches tools exactly the way the menus do.
import 'package:flutter_scene_editor_core/flutter_scene_editor_core.dart';
import 'package:test/test.dart';

class _Host implements EditorHost {
  _Host({this.unsupported = const {}});

  final Set<String> unsupported;
  final List<String> calls = [];

  @override
  bool supports(String command) => !unsupported.contains(command);

  Future<void> _record(String call) async => calls.add(call);

  @override
  Future<void> newDocument() => _record('newDocument');
  @override
  Future<void> openDocument(String path) => _record('openDocument $path');
  @override
  Future<void> saveDocument({String? path}) => _record('saveDocument $path');
  @override
  Future<void> openProject(String path) => _record('openProject $path');
  @override
  Future<void> closeProject() => _record('closeProject');
  @override
  Future<void> selectBuildConfiguration(String id) => _record('config $id');
  @override
  Future<void> selectDevice(String id) => _record('device $id');
  @override
  Future<void> buildProject() => _record('buildProject');
  @override
  Future<void> runProject() => _record('runProject');
  @override
  Future<void> stopProject() => _record('stopProject');
  @override
  Future<void> hotReload() => _record('hotReload');
  @override
  Future<void> hotRestart() => _record('hotRestart');
  @override
  Future<void> reloadScene() => _record('reloadScene');
  @override
  Future<void> importModel(String path, {String? parentId, double scale = 1}) =>
      _record('importModel $path $parentId $scale');
  @override
  Future<void> importEnvironment(String path) => _record('importEnv $path');

  @override
  String toolMode = 'translate';
  @override
  List<String> get toolModes => const ['translate', 'rotate', 'scale'];
  @override
  void setToolMode(String mode) {
    toolMode = mode;
    calls.add('setToolMode $mode');
  }

  @override
  List<String> get panels => const ['viewport', 'inspector'];
  @override
  void showPanel(String id) => calls.add('showPanel $id');
  @override
  void focusPanel(String id) => calls.add('focusPanel $id');

  @override
  List<String> get viewportDebugModes => const ['none', 'normals'];
  @override
  void setViewportDebugMode(String mode) => calls.add('debug $mode');
}

void main() {
  test('application commands drive the host and stay out of history', () async {
    final session = EditorSession.empty();
    final host = _Host();
    session.host = host;

    await session.invoke('openDocument', {'path': 'scenes/level.fscene'});
    await session.invoke('saveDocument');
    await session.invoke('runProject');
    await session.invoke('importModel', {'path': 'a.glb', 'scale': 2.0});

    expect(host.calls, [
      'openDocument scenes/level.fscene',
      'saveDocument null',
      'runProject',
      'importModel a.glb null 2.0',
    ]);
    expect(session.history.transactions, isEmpty);
  });

  test('an application command refuses to run synchronously', () {
    final session = EditorSession.empty()..host = _Host();
    expect(
      () => session.run('runProject'),
      throwsA(
        isA<CommandException>().having(
          (e) => e.message,
          'message',
          contains('asynchronous'),
        ),
      ),
    );
  });

  test('a host decides what applies right now', () async {
    final session = EditorSession.empty();
    expect(session.canRun('runProject'), isFalse, reason: 'no host');

    session.host = _Host(unsupported: {'runProject'});
    expect(session.canRun('runProject'), isFalse);
    expect(session.canRun('stopProject'), isTrue);
    await expectLater(
      session.invoke('runProject'),
      throwsA(isA<CommandException>()),
    );
  });

  test('a host failure reads as a command error', () async {
    final session = EditorSession.empty()..host = _FailingHost();
    await expectLater(
      session.invoke('saveDocument'),
      throwsA(
        isA<CommandException>().having(
          (e) => e.message,
          'message',
          allOf(contains('saveDocument failed'), contains('never been saved')),
        ),
      ),
    );
  });

  test('tool and panel commands leave the document clean', () async {
    final session = EditorSession.empty();
    final host = _Host();
    session.host = host;

    expect(session.registry.lookup('setToolMode')!.kind, CommandKind.ui);
    expect(session.registry.lookup('showPanel')!.kind, CommandKind.ui);

    await session.invoke('setToolMode', {'mode': 'rotate'});
    await session.invoke('focusPanel', {'panel': 'inspector'});
    expect(host.calls, ['setToolMode rotate', 'focusPanel inspector']);
    expect(host.toolMode, 'rotate');
    expect(session.history.transactions, isEmpty);
    expect(
      session.isDirty,
      isFalse,
      reason: 'the tool and the panels are not part of the document',
    );

    expect(
      () => session.run('setToolMode', {'mode': 'nope'}),
      throwsA(
        isA<CommandException>().having(
          (e) => e.message,
          'message',
          contains('Unknown tool'),
        ),
      ),
    );
  });
}

class _FailingHost extends _Host {
  @override
  Future<void> saveDocument({String? path}) async =>
      throw const FormatException('The document has never been saved');
}
