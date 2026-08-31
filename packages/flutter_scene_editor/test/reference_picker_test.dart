import 'package:flutter/material.dart';
import 'package:flutter_scene_editor/src/inspector/reference_picker.dart';
import 'package:flutter_scene_editor/src/shell/editor_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:scene/scene.dart';

void main() {
  testWidgets('reference options stay lazy while closed', (tester) async {
    final allocator = IdAllocator();
    final entries = [
      for (var i = 0; i < 1000; i++) (id: allocator.mint(), label: 'Option $i'),
    ];
    await tester.pumpWidget(
      MaterialApp(
        theme: editorDarkTheme(),
        builder: (context, child) => EditorThemeScope(child: child!),
        home: Scaffold(
          body: SizedBox(
            width: 300,
            child: ReferencePicker(
              entries: entries,
              value: entries[500].id,
              emptyLabel: 'Empty',
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Option 500'), findsOneWidget);
    expect(find.text('Option 999'), findsNothing);
    expect(find.byType(DropdownMenuItem<LocalId>), findsNothing);
    expect(find.byType(FButton), findsOneWidget);
  });
}
