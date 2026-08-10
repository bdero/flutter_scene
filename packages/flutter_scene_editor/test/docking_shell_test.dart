import 'package:flutter/material.dart';
import 'package:flutter_scene_editor/src/shell/dock_layout.dart';
import 'package:flutter_scene_editor/src/shell/docking_shell.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a new layout instance replaces the active arrangement', (
    tester,
  ) async {
    final panels = [
      const DockPanel(id: 'first', title: 'First', child: Text('First panel')),
      const DockPanel(
        id: 'second',
        title: 'Second',
        child: Text('Second panel'),
      ),
    ];

    Widget shell(DockLayout layout) => MaterialApp(
      home: Scaffold(
        body: DockingShell(panels: panels, layout: layout),
      ),
    );

    await tester.pumpWidget(shell(DockLayout(DockTabs(['first']))));
    expect(find.text('First panel'), findsOneWidget);
    expect(find.text('Second panel'), findsNothing);

    await tester.pumpWidget(shell(DockLayout(DockTabs(['second']))));
    await tester.pump();
    expect(find.text('First panel'), findsNothing);
    expect(find.text('Second panel'), findsOneWidget);
  });
}
