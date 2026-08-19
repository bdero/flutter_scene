import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_scene_editor/src/shell/editor_dialog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('showEditorDialog shows content and returns the popped value', (
    tester,
  ) async {
    Future<String?>? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () {
              result = showEditorDialog<String>(
                context,
                builder: (context) => TextButton(
                  onPressed: () => Navigator.of(context).pop('picked'),
                  child: const Text('inside'),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('inside'), findsOneWidget);
    await tester.tap(find.text('inside'));
    await tester.pumpAndSettle();
    expect(await result, 'picked');
    expect(find.text('inside'), findsNothing);
  });

  test('editor dialogs never call showDialog directly', () {
    // showDialog hosts dialogs in their own OS window when windowing is
    // enabled, which breaks modally on the pinned stable (a 0x0 window blocks
    // the whole app). Everything must route through showEditorDialog.
    final offenders = <String>[];
    for (final root in ['lib', '../../apps/flutter_scene_editor_app/lib']) {
      final dir = Directory(root);
      if (!dir.existsSync()) continue;
      for (final file in dir.listSync(recursive: true)) {
        if (file is! File || !file.path.endsWith('.dart')) continue;
        if (file.path.endsWith('shell/editor_dialog.dart')) continue;
        if (file.readAsStringSync().contains('showDialog')) {
          offenders.add(file.path);
        }
      }
    }
    expect(offenders, isEmpty, reason: 'use showEditorDialog instead');
  });
}
