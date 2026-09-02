/// The picker itself: grouped, searchable, and readable.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart' as forui show FTheme;

import 'package:flutter_scene_editor/src/panels/inspector_panel.dart';
import 'package:flutter_scene_editor/src/shell/editor_theme.dart';

const Map<String, ComponentTypeInfo> _types = {
  'directionalLight': (
    category: 'Rendering',
    icon: null,
    provenance: null,
  ),
  'pointLight': (category: 'Rendering', icon: null, provenance: null),
  'rigidBody': (category: 'Physics', icon: null, provenance: null),
  'playerController': (category: null, icon: null, provenance: 'live'),
};

Future<void> _pump(WidgetTester tester) => tester.pumpWidget(
  forui.FTheme(
    data: editorForuiDarkTheme,
    child: MaterialApp(
    theme: editorDarkTheme(),
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 460,
          height: 520,
          child: AddComponentPicker(
            types: _types,
            docFor: (type) =>
                type == 'rigidBody' ? 'Moves under forces.' : null,
          ),
        ),
      ),
      ),
    ),
  ),
);

void main() {
  testWidgets('components arrive grouped, named as words, with their doc', (
    tester,
  ) async {
    await _pump(tester);

    // The categories are headings, and a project's own component is filed
    // under Scripts rather than lost in one long list.
    expect(find.text('PHYSICS'), findsOneWidget);
    expect(find.text('RENDERING'), findsOneWidget);
    expect(find.text('SCRIPTS'), findsOneWidget);

    expect(find.text('Directional Light'), findsOneWidget);
    expect(find.text('Player Controller'), findsOneWidget);
    expect(find.text('Moves under forces.'), findsOneWidget);
  });

  testWidgets('search narrows by name and by category', (tester) async {
    await _pump(tester);

    await tester.enterText(find.byType(TextField), 'point');
    await tester.pump();
    expect(find.text('Point Light'), findsOneWidget);
    expect(find.text('Rigid Body'), findsNothing);

    // A category matches too, so "phys" finds every physics component and not
    // only the one spelled that way.
    await tester.enterText(find.byType(TextField), 'phys');
    await tester.pump();
    expect(find.text('Rigid Body'), findsOneWidget);
    expect(find.text('Point Light'), findsNothing);

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump();
    expect(find.text('No component matches that.'), findsOneWidget);
  });
}
