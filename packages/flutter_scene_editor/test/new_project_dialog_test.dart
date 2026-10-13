import 'dart:io';

import 'package:flutter_scene_editor/flutter_scene_editor.dart';
import 'package:flutter_scene_editor/src/shell/editor_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

class _ExitedProcess implements Process {
  @override
  Stream<List<int>> get stdout => const Stream.empty();

  @override
  Stream<List<int>> get stderr => const Stream.empty();

  @override
  Future<int> get exitCode => Future.value(0);

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) => true;

  @override
  int get pid => 0;

  @override
  IOSink get stdin => throw UnimplementedError();
}

const _custom = FlutterInstallation(
  id: 'custom',
  name: 'My Flutter',
  flutterBin: '/sdk/bin/flutter',
);
const _other = FlutterInstallation(
  id: 'other',
  name: 'Other Flutter',
  flutterBin: '/other/bin/flutter',
);

void main() {
  Future<void> open(
    WidgetTester tester, {
    required List<FlutterInstallation> installations,
    FlutterInstallation? initial,
    FlutterInstallation? recommended,
    bool canInstall = true,
    void Function(FlutterInstallation)? onUsed,
    ProjectScaffolder Function(FlutterInstallation)? scaffolderFor,
    String? location,
  }) async {
    await tester.pumpWidget(
      FTheme(
        data: editorForuiDarkTheme,
        child: MaterialApp(
          theme: editorDarkTheme(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showNewProjectDialog(
                  context,
                  installations: installations,
                  initialInstallation: initial,
                  recommended: recommended,
                  // Never started; the tests stop before any download.
                  installManaged: canInstall
                      ? () => throw StateError('no install in tests')
                      : null,
                  onInstallationUsed: onUsed,
                  managedVersion: '3.47.1',
                  initialLocation: location,
                  scaffolderFor: scaffolderFor,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  bool createEnabled(WidgetTester tester) =>
      tester.widget<FButton>(find.widgetWithText(FButton, 'Create')).onPress !=
      null;

  testWidgets('with no installations it defaults to installing one', (
    tester,
  ) async {
    await open(tester, installations: const []);
    expect(find.text('Install Flutter 3.47.1 (managed)'), findsOneWidget);
    expect(find.textContaining('one-time download'), findsOneWidget);
    expect(createEnabled(tester), isTrue);
  });

  testWidgets('it starts on the matching installation', (tester) async {
    await open(
      tester,
      installations: const [_other, _custom],
      initial: _custom,
      recommended: _custom,
    );
    expect(find.text('My Flutter (matches the editor)'), findsOneWidget);
    expect(find.textContaining('one-time download'), findsNothing);
    expect(createEnabled(tester), isTrue);
  });

  testWidgets('without an initial pick it offers the managed install', (
    tester,
  ) async {
    await open(tester, installations: const [_other]);
    expect(find.text('Install Flutter 3.47.1 (managed)'), findsOneWidget);
    expect(createEnabled(tester), isTrue);
  });

  testWidgets('it falls back to a configured installation', (tester) async {
    await open(tester, installations: const [_other], canInstall: false);
    expect(find.text('Other Flutter'), findsOneWidget);
    expect(createEnabled(tester), isTrue);
  });

  testWidgets('only with nothing to pick is Create disabled', (tester) async {
    await open(tester, installations: const [], canInstall: false);
    expect(find.textContaining('No Flutter installation'), findsOneWidget);
    expect(createEnabled(tester), isFalse);
  });

  testWidgets('a bad name fails before any install starts', (tester) async {
    await open(tester, installations: const []);
    await tester.enterText(find.byType(TextField).last, 'MyGame');
    await tester.tap(find.widgetWithText(FButton, 'Create'));
    await tester.pumpAndSettle();
    expect(find.textContaining('lowercase letters'), findsOneWidget);
  });

  testWidgets('Create scaffolds with the picked installation', (tester) async {
    final parent = Directory.systemTemp.createTempSync('new_project_dialog_');
    addTearDown(() => parent.deleteSync(recursive: true));
    FlutterInstallation? used;
    FlutterInstallation? scaffoldedWith;
    await open(
      tester,
      installations: const [_custom],
      initial: _custom,
      location: parent.path,
      onUsed: (installation) => used = installation,
      scaffolderFor: (installation) {
        scaffoldedWith = installation;
        return ProjectScaffolder(
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
                  File(
                    '${args.last}/pubspec.yaml',
                  ).writeAsStringSync('name: my_scene');
                }
                return _ExitedProcess();
              },
        );
      },
    );
    await tester.tap(find.widgetWithText(FButton, 'Create'));
    await tester.runAsync(() async {
      final project = File('${parent.path}/my_scene/my_scene.fproject');
      for (var i = 0; i < 200 && !project.existsSync(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });
    await tester.pumpAndSettle();
    expect(used, _custom);
    expect(scaffoldedWith, _custom);
    expect(find.text('New project'), findsNothing);
  });
}
