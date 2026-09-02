/// The six repeated shapes, and the density rules that keep them repeated.
///
/// These are the tests that stop the grammar drifting one panel at a time: a
/// header that is four pixels taller here, a row whose label column is its
/// own width, a card radius that creeps back into a docked panel. Each of
/// those is invisible in isolation and obvious across a window.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_scene_editor/src/shell/panel_chrome.dart';
import 'package:flutter_scene_editor/src/shell/editor_theme.dart';

Widget _host(Widget child) => MaterialApp(
  theme: editorDarkTheme(),
  home: Scaffold(body: child),
);

void main() {
  testWidgets('a region header is one band high and names itself in caps', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const EditorPanelHeader(label: 'Hierarchy')));

    expect(
      tester.getSize(find.byType(EditorPanelHeader)).height,
      editorHeaderHeight,
    );
    expect(find.text('HIERARCHY'), findsOneWidget);
  });

  testWidgets('header actions and the collapse control sit inline', (
    tester,
  ) async {
    var collapsed = 0;
    await tester.pumpWidget(
      _host(
        EditorPanelHeader(
          label: 'Inspector',
          actions: [
            EditorPanelIconButton(
              icon: Icons.add,
              tooltip: 'Add',
              onPressed: () {},
            ),
          ],
          onCollapse: () => collapsed++,
        ),
      ),
    );

    expect(find.byIcon(Icons.add), findsOneWidget);
    await tester.tap(find.byIcon(Icons.keyboard_arrow_up));
    expect(collapsed, 1);
  });

  testWidgets('an icon button is 20 and disables with its reason', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const EditorPanelIconButton(
          icon: Icons.delete_outline,
          tooltip: 'Select something to delete it',
          onPressed: null,
        ),
      ),
    );

    expect(
      tester.getSize(find.byType(EditorPanelIconButton)),
      const Size(editorPanelIconButtonSize, editorPanelIconButtonSize),
    );
    final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
    expect(tooltip.message, 'Select something to delete it');
  });

  testWidgets('every property row shares one label column and one height', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const Column(
          children: [
            EditorPropertyRow(label: 'Position', child: SizedBox()),
            EditorPropertyRow(label: 'Cast shadows', child: SizedBox()),
          ],
        ),
      ),
    );

    final rows = find.byType(EditorPropertyRow);
    expect(rows, findsNWidgets(2));
    for (var index = 0; index < 2; index++) {
      expect(tester.getSize(rows.at(index)).height, editorPropertyRowHeight);
    }
    // The controls start at the same x, which is what makes a column of them
    // read as a column.
    expect(
      tester.getTopLeft(find.byType(SizedBox).at(0)).dx,
      tester.getTopLeft(find.byType(SizedBox).at(1)).dx,
    );
  });

  testWidgets('a property label takes no colon', (tester) async {
    await tester.pumpWidget(
      _host(const EditorPropertyRow(label: 'Intensity', child: SizedBox())),
    );

    expect(find.text('Intensity'), findsOneWidget);
    expect(find.text('Intensity:'), findsNothing);
  });

  testWidgets('a section is a chevron and a rule, never a card', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const EditorPanelSection(
          title: 'Diffuse',
          children: [EditorPropertyRow(label: 'Color', child: SizedBox())],
        ),
      ),
    );

    expect(find.text('DIFFUSE'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_drop_down), findsOneWidget);
    await tester.tap(find.text('DIFFUSE'));
    await tester.pump();
    expect(find.byIcon(Icons.arrow_right), findsOneWidget);
    expect(find.byType(EditorPropertyRow), findsNothing);
  });

  testWidgets('docked chrome draws no radius and no shadow', (tester) async {
    // The density audit. A radius or a shadow in a docked panel is what turns
    // a dense list into a stack of cards, and it arrives one widget at a time.
    await tester.pumpWidget(
      _host(
        Column(
          children: [
            const EditorPanelHeader(label: 'Project'),
            const EditorPanelSection(title: 'Ambient', children: []),
            const EditorPropertyRow(label: 'Colour', child: SizedBox()),
            EditorPanelIconButton(
              icon: Icons.add,
              tooltip: 'Add',
              onPressed: () {},
            ),
            const EditorRegionDivider(axis: Axis.horizontal),
            const Expanded(child: EditorPanelBody(child: SizedBox())),
          ],
        ),
      ),
    );

    for (final container in tester.widgetList<Container>(
      find.byType(Container),
    )) {
      final decoration = container.decoration;
      if (decoration is! BoxDecoration) continue;
      expect(
        decoration.borderRadius,
        isNull,
        reason: 'docked chrome keeps square corners',
      );
      expect(
        decoration.boxShadow,
        anyOf(isNull, isEmpty),
        reason: 'docked chrome casts no shadow',
      );
    }
    expect(find.byType(Card), findsNothing);
  });

  testWidgets('chrome text stays on the four-step ramp', (tester) async {
    await tester.pumpWidget(
      _host(
        const Column(
          children: [
            EditorPanelHeader(label: 'Console'),
            EditorPanelSection(title: 'Fog', children: []),
            EditorPropertyRow(label: 'Density', child: SizedBox()),
          ],
        ),
      ),
    );

    final ramp = <double>[9, 10.5, 11, 12];
    for (final text in tester.widgetList<Text>(find.byType(Text))) {
      final size = text.style?.fontSize;
      if (size == null) continue;
      expect(ramp, contains(size), reason: '"${text.data}" is off the ramp');
    }
  });
}
