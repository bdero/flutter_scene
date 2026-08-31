import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_scene_editor/src/assets/environment_thumbnail.dart';
import 'package:flutter_scene_editor/src/inspector/live_fields.dart';
import 'package:flutter_scene_editor/src/panels/inspector_panel.dart';
import 'package:flutter_scene_editor/src/inspector/property_editors.dart';
import 'package:flutter_scene_editor/src/shell/editor_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

void main() {
  Widget themed(Widget child) => FTheme(
    data: editorForuiDarkTheme,
    child: MaterialApp(
      theme: editorDarkTheme(),
      home: Scaffold(body: child),
    ),
  );

  testWidgets('inspector slider uses Forui', (tester) async {
    await tester.pumpWidget(
      themed(
        LiveSlider(
          label: 'Roughness',
          value: 0.5,
          onPreview: (_) {},
          onCommit: (_) {},
        ),
      ),
    );

    expect(find.byType(FSlider), findsOneWidget);
    expect(find.byType(Slider), findsNothing);
  });

  testWidgets('slider number field supports direct numeric entry', (
    tester,
  ) async {
    final commits = <double>[];
    await tester.pumpWidget(
      themed(
        SizedBox(
          width: 360,
          child: SliderNumberField(
            label: 'Exposure',
            value: 1,
            min: 0,
            max: 8,
            onPreview: (_) {},
            onCommit: commits.add,
            enableInfiniteDrag: false,
          ),
        ),
      ),
    );

    expect(find.byType(InspectorSlider), findsOneWidget);
    expect(find.byType(ScrubbableNumberField), findsOneWidget);
    await tester.tap(find.byType(ScrubbableNumberField));
    await tester.pump();
    final editable = tester.widget<EditableText>(find.byType(EditableText));
    editable.controller.text = '2.5';
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(commits, [2.5]);
  });

  testWidgets('slider number field commits typed values past the slider max', (
    tester,
  ) async {
    final commits = <double>[];
    await tester.pumpWidget(
      themed(
        SizedBox(
          width: 360,
          child: SliderNumberField(
            label: 'Emissive strength',
            value: 1,
            min: 0,
            max: 10,
            onPreview: (_) {},
            onCommit: commits.add,
            enableInfiniteDrag: false,
          ),
        ),
      ),
    );

    await tester.tap(find.byType(ScrubbableNumberField));
    await tester.pump();
    final editable = tester.widget<EditableText>(find.byType(EditableText));
    editable.controller.text = '1000';
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    // The slider track is bounded; the committed value must not be.
    expect(commits, [1000.0]);
    expect(find.text('1000.000'), findsOneWidget);
  });

  testWidgets('slider number field rejects non-finite typed values', (
    tester,
  ) async {
    final commits = <double>[];
    await tester.pumpWidget(
      themed(
        SizedBox(
          width: 360,
          child: SliderNumberField(
            label: 'Emissive strength',
            value: 1,
            min: 0,
            max: 10,
            onPreview: (_) {},
            onCommit: commits.add,
            enableInfiniteDrag: false,
          ),
        ),
      ),
    );

    // tryParse accepts all three spellings; a committed non-finite value
    // would poison the document (canonical JSON refuses it on save).
    for (final text in ['NaN', 'Infinity', '1e999']) {
      await tester.tap(find.byType(ScrubbableNumberField));
      await tester.pump();
      final editable = tester.widget<EditableText>(find.byType(EditableText));
      editable.controller.text = text;
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
    }
    expect(commits, isEmpty);
    expect(find.text('1.000'), findsOneWidget);
  });

  testWidgets('inspector switch uses Forui', (tester) async {
    await tester.pumpWidget(
      themed(
        InspectorSwitch(label: 'Double sided', value: true, onChanged: (_) {}),
      ),
    );

    expect(
      find.byWidgetPredicate((widget) => widget is FTappable),
      findsOneWidget,
    );
    expect(find.byType(FSwitch), findsNothing);
    expect(find.byType(Switch), findsNothing);
    expect(find.byType(SwitchListTile), findsNothing);
  });

  testWidgets('environment effect toggle keeps its section expanded', (
    tester,
  ) async {
    await tester.pumpWidget(
      themed(const SizedBox(width: 420, child: _AccordionRebuildHarness())),
    );

    expect(find.text('Enabled'), findsNothing);
    await tester.tap(find.text('Effect OFF'));
    await tester.pumpAndSettle();
    expect(find.text('Enabled'), findsOneWidget);
    final switchFinder = find.byType(InspectorToggleSwitch);
    await tester.tap(switchFinder);
    await tester.pumpAndSettle();
    expect(find.text('Effect ON'), findsOneWidget);
    expect(find.text('Enabled'), findsOneWidget);

    await tester.tap(find.text('Effect ON'));
    await tester.pumpAndSettle();
    expect(find.text('Enabled'), findsNothing);
    await tester.tap(find.text('Effect ON'));
    await tester.pumpAndSettle();
    expect(find.text('Enabled'), findsOneWidget);
  });

  testWidgets('inspector text stays on one line by default', (tester) async {
    await tester.pumpWidget(
      themed(
        const SizedBox(
          width: 80,
          child: InspectorTextScope(
            child: Text('A property value that is too wide for the row'),
          ),
        ),
      ),
    );

    final paragraph = tester.renderObject<RenderParagraph>(
      find.text('A property value that is too wide for the row'),
    );
    expect(paragraph.maxLines, 1);
  });

  testWidgets('inspector descriptions may wrap', (tester) async {
    await tester.pumpWidget(
      themed(
        const SizedBox(
          width: 80,
          child: InspectorTextScope(
            child: InspectorDescriptionText(
              'A longer explanation that needs multiple lines.',
            ),
          ),
        ),
      ),
    );

    final paragraph = tester.renderObject<RenderParagraph>(
      find.text('A longer explanation that needs multiple lines.'),
    );
    expect(paragraph.maxLines, isNull);
    expect(paragraph.size.height, greaterThan(20));
  });

  testWidgets('scrubbable number field waits for drag threshold', (
    tester,
  ) async {
    final previews = <double>[];
    final commits = <double>[];
    await tester.pumpWidget(
      themed(
        Center(
          child: SizedBox(
            width: 140,
            child: ScrubbableNumberField(
              label: 'X',
              color: editorAxisColors[0],
              value: 1,
              scrubStep: 0.01,
              snapStep: 1,
              onPreview: previews.add,
              onCommit: commits.add,
              enableInfiniteDrag: false,
            ),
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(ScrubbableNumberField)),
    );
    await gesture.moveBy(const Offset(3, 0));
    await tester.pump();
    expect(previews, isEmpty);

    await gesture.moveBy(const Offset(7, 0));
    await tester.pump();
    expect(previews.single, closeTo(1.1, 0.0001));

    await gesture.moveBy(const Offset(10, 0));
    await gesture.up();
    await tester.pump();
    expect(previews.last, closeTo(1.2, 0.0001));
    expect(commits, hasLength(1));
    expect(commits.single, closeTo(1.2, 0.0001));
  });

  testWidgets('scrubbable number field clicks through to text editing', (
    tester,
  ) async {
    final commits = <double>[];
    await tester.pumpWidget(
      themed(
        Center(
          child: SizedBox(
            width: 140,
            child: ScrubbableNumberField(
              label: 'Y',
              color: editorAxisColors[1],
              value: 2,
              scrubStep: 0.01,
              snapStep: 1,
              onCommit: commits.add,
              enableInfiniteDrag: false,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(ScrubbableNumberField));
    await tester.pump();
    final editable = tester.widget<EditableText>(find.byType(EditableText));
    expect(editable.focusNode.hasFocus, isTrue);
    expect(commits, isEmpty);

    editable.controller.text = '2.5';
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(commits, [2.5]);
  });

  testWidgets('escape restores a scrub without committing', (tester) async {
    final previews = <double>[];
    final commits = <double>[];
    await tester.pumpWidget(
      themed(
        Center(
          child: SizedBox(
            width: 140,
            child: ScrubbableNumberField(
              label: 'Z',
              color: editorAxisColors[2],
              value: 3,
              scrubStep: 0.01,
              snapStep: 1,
              onPreview: previews.add,
              onCommit: commits.add,
              enableInfiniteDrag: false,
            ),
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(ScrubbableNumberField)),
    );
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(previews.last, 3);
    expect(commits, isEmpty);
  });

  testWidgets('shift makes transform scrubbing ten times finer', (
    tester,
  ) async {
    final previews = <double>[];
    await tester.pumpWidget(
      themed(
        Center(
          child: SizedBox(
            width: 140,
            child: ScrubbableNumberField(
              label: 'X',
              color: editorAxisColors[0],
              value: 0,
              scrubStep: 0.1,
              snapStep: 1,
              onPreview: previews.add,
              onCommit: (_) {},
              enableInfiniteDrag: false,
            ),
          ),
        ),
      ),
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(ScrubbableNumberField)),
    );
    await gesture.moveBy(const Offset(20, 0));
    await gesture.up();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();

    expect(previews.last, closeTo(0.2, 0.0001));
  });

  test('the editor palette is one palette, named in one place', () {
    // The accent and the ground are picked in editor_theme.dart; this pins
    // that the two themes agree rather than pinning the colours themselves,
    // so a deliberate repaint changes one file and not this test as well.
    expect(editorForuiDarkTheme.colors.primary, editorAccentColor);
    expect(editorDarkTheme().colorScheme.primary, editorAccentColor);
    expect(editorForuiDarkTheme.colors.background, editorSurfaceColor);
  });

  test('HDR and EXR environment thumbnails decode to display pixels', () {
    for (final name in ['rgb_4x2.hdr', 'rgb_4x2.exr']) {
      final candidates = [
        File('packages/flutter_scene/test/fixtures/$name'),
        File('../flutter_scene/test/fixtures/$name'),
      ];
      final fixture = candidates.firstWhere((file) => file.existsSync());
      final result = decodeEnvironmentPreviewForTesting(
        fixture.readAsBytesSync(),
      );
      expect(result[1], 4, reason: name);
      expect(result[2], 2, reason: name);
      expect((result[0] as Uint8List).length, 4 * 2 * 4, reason: name);
    }
  });

  // Regression: FSelect takes Map<String, T> keyed by DISPLAY LABEL. Building
  // it the other way round (option keys, label values) leaves the control
  // unable to resolve its current value, which threw and blanked the whole
  // node inspector behind an error box.
  testWidgets('enum row maps display labels to option values', (tester) async {
    await tester.pumpWidget(
      themed(
        EnumRow(
          label: 'Shadows',
          value: 'shadowsOnly',
          options: const ['on', 'off', 'shadowsOnly'],
          labels: const {
            'on': 'Cast',
            'off': 'Do not cast',
            'shadowsOnly': 'Shadows only',
          },
          onChanged: (_) {},
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    // The selection shows its human label, never the raw identifier.
    expect(find.text('Shadows only'), findsOneWidget);
    expect(find.text('shadowsOnly'), findsNothing);
  });

  testWidgets('enum row without labels shows the raw option', (tester) async {
    await tester.pumpWidget(
      themed(
        EnumRow(
          label: 'Quality',
          value: 'medium',
          options: const ['low', 'medium', 'high'],
          onChanged: (_) {},
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('medium'), findsOneWidget);
  });
}

class _AccordionRebuildHarness extends StatefulWidget {
  const _AccordionRebuildHarness();

  @override
  State<_AccordionRebuildHarness> createState() =>
      _AccordionRebuildHarnessState();
}

class _AccordionRebuildHarnessState extends State<_AccordionRebuildHarness> {
  bool _enabled = false;

  @override
  Widget build(BuildContext context) => InspectorAccordion(
    children: [
      InspectorAccordionItem(
        title: Text(_enabled ? 'Effect ON' : 'Effect OFF'),
        child: InspectorSwitch(
          label: 'Enabled',
          value: _enabled,
          onChanged: (value) => setState(() => _enabled = value),
        ),
      ),
    ],
  );
}
