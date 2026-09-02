/// The six repeated shapes, and the density rules that keep them repeated.
///
/// These are the tests that stop the grammar drifting one panel at a time: a
/// header that is four pixels taller here, a row whose label column is its
/// own width, a card radius that creeps back into a docked panel. Each of
/// those is invisible in isolation and obvious across a window.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_scene_editor/src/inspector/property_editors.dart';
import 'package:flutter_scene_editor/src/shell/panel_chrome.dart';
import 'package:flutter_scene_editor/src/shell/editor_theme.dart';

/// The accent an active input borders itself with.
const editorAccentButtonColorForTest = editorAccentColor;

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

  testWidgets('an input is one shape, and shows its border when used', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const Column(
          children: [
            EditorFieldSurface(child: SizedBox()),
            EditorFieldSurface(active: true, child: SizedBox()),
          ],
        ),
      ),
    );

    final fields = find.byType(EditorFieldSurface);
    expect(tester.getSize(fields.at(0)).height, editorFieldHeight);
    expect(tester.getSize(fields.at(1)).height, editorFieldHeight);

    BoxDecoration decorationAt(int index) =>
        tester
                .widgetList<AnimatedContainer>(
                  find.descendant(
                    of: fields.at(index),
                    matching: find.byType(AnimatedContainer),
                  ),
                )
                .first
                .decoration!
            as BoxDecoration;

    // Resting: a fill and nothing else. Active: the accent says where you are.
    expect(decorationAt(0).border!.top.color, Colors.transparent);
    expect(decorationAt(1).border!.top.color, editorAccentButtonColorForTest);
  });

  testWidgets('a text field commits on submit and on losing focus', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'Cube');
    addTearDown(controller.dispose);
    final commits = <String>[];
    await tester.pumpWidget(
      _host(
        Column(
          children: [
            EditorTextField(controller: controller, onSubmit: commits.add),
            const TextField(),
          ],
        ),
      ),
    );

    await tester.enterText(find.byType(EditorTextField), 'Crate');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    expect(commits, ['Crate']);

    // Submitting drops focus behind it, and that must not commit a second
    // time for one edit.
    await tester.pump();
    expect(commits, ['Crate']);

    // Clicking away is a commit too: a half-typed name that vanishes because
    // you looked at something else is the oldest bug in property panels.
    await tester.tap(find.byType(EditorTextField));
    await tester.enterText(find.byType(EditorTextField), 'Barrel');
    await tester.tap(find.byType(TextField).last);
    await tester.pump();
    expect(commits, ['Crate', 'Barrel']);
  });

  testWidgets('a full-width action states why it is unavailable', (
    tester,
  ) async {
    var pressed = 0;
    await tester.pumpWidget(
      _host(
        Column(
          children: [
            EditorActionButton(
              label: 'Add Component',
              icon: Icons.add,
              onPressed: () => pressed++,
            ),
            const EditorActionButton(
              label: 'Download',
              onPressed: null,
              tooltip: 'Nothing is selected',
            ),
          ],
        ),
      ),
    );

    expect(find.text('ADD COMPONENT'), findsOneWidget);
    await tester.tap(find.text('ADD COMPONENT'));
    expect(pressed, 1);

    await tester.tap(find.text('DOWNLOAD'));
    expect(pressed, 1);
    expect(
      tester.widget<Tooltip>(find.byType(Tooltip)).message,
      'Nothing is selected',
    );
  });

  test('identifiers are shown as words', () {
    expect(humanizeIdentifier('castsShadows'), 'Casts Shadows');
    expect(humanizeIdentifier('directionalLight'), 'Directional Light');
    expect(humanizeIdentifier('localDirection'), 'Local Direction');
    expect(humanizeIdentifier('color'), 'Color');
    expect(humanizeIdentifier('nav_mesh_surface'), 'Nav mesh surface');
    expect(humanizeIdentifier('uv0'), 'Uv0');
    expect(humanizeIdentifier(''), '');
  });

  testWidgets('rows keep one pitch, and a heading keeps its air', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const Column(
          children: [
            EditorSectionHeader(label: 'Shadows'),
            LabeledControlRow(label: 'Casts Shadow', control: SizedBox()),
            LabeledControlRow(label: 'Shadow Softness', control: SizedBox()),
          ],
        ),
      ),
    );

    final rows = find.byType(LabeledControlRow);
    const pitch = editorPropertyRowHeight + editorRowGap * 2;
    expect(tester.getSize(rows.at(0)).height, pitch);
    expect(
      tester.getTopLeft(rows.at(1)).dy - tester.getTopLeft(rows.at(0)).dy,
      pitch,
    );

    // The rule under a heading must not sit on the first row it covers.
    // Measured from the painted box rather than the widget, whose bounds
    // include the very margin under test.
    final rule = tester.getRect(
      find
          .descendant(
            of: find.byType(EditorSectionHeader),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    expect(
      tester.getTopLeft(rows.at(0)).dy - rule.bottom,
      greaterThanOrEqualTo(editorHeadingGapBelow),
    );
  });

  testWidgets('a long property name is readable on hover', (tester) async {
    await tester.pumpWidget(
      _host(
        const LabeledControlRow(
          label: 'Shadow Cascade Distribution Exponent',
          control: SizedBox(),
        ),
      ),
    );

    expect(
      tester.widget<Tooltip>(find.byType(Tooltip)).message,
      'Shadow Cascade Distribution Exponent',
    );
  });

  testWidgets('a dropdown survives being measured against unbounded width', (
    tester,
  ) async {
    // The trap this editor has fallen into twice: a control laid out inside a
    // horizontally scrolling strip is offered infinite width, and anything
    // that asks to fill it throws from inside layout -- which abandons the
    // rest of the frame, not just this widget.
    await tester.pumpWidget(
      _host(
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              EditorDropdown<String>(
                value: 'one',
                items: const [
                  DropdownMenuItem(value: 'one', child: Text('One')),
                  DropdownMenuItem(value: 'two', child: Text('Two')),
                ],
                onChanged: (_) {},
              ),
            ],
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('One'), findsOneWidget);

    // And in a row that does have a width, it fills it.
    await tester.pumpWidget(
      _host(
        SizedBox(
          width: 240,
          child: EditorDropdown<String>(
            value: 'one',
            items: const [DropdownMenuItem(value: 'one', child: Text('One'))],
            onChanged: (_) {},
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(EditorFieldSurface)).width, 240);
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
