// The panel toolbar strip. A docked panel can be dragged narrower than its
// own controls, and the strip has to survive that without painting the
// framework's overflow stripes over itself.
import 'package:flutter/material.dart';
import 'package:flutter_scene_editor/src/shell/editor_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

void main() {
  Widget strip(double width, List<Widget> children) => FTheme(
    data: editorForuiDarkTheme,
    child: MaterialApp(
      theme: editorDarkTheme(),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: EditorToolbar(children: children),
          ),
        ),
      ),
    ),
  );

  // What the Animation strip is: a run of fixed-width buttons, a Spacer, and
  // a couple more pinned right.
  List<Widget> transport() => [
    for (var i = 0; i < 8; i++)
      const SizedBox(
        width: 24,
        height: 24,
        child: Icon(Icons.circle, size: 12),
      ),
    const Spacer(),
    const SizedBox(width: 140, height: 24, child: Text('Dopesheet')),
  ];

  testWidgets('a strip narrower than its contents scrolls instead of '
      'overflowing', (tester) async {
    await tester.pumpWidget(strip(200, transport()));
    expect(tester.takeException(), isNull);
    // The row kept its full width rather than being squeezed into the strip.
    expect(tester.getSize(find.byType(Row).first).width, greaterThan(200));
    // And that width is reachable by scrolling.
    final view = tester.widget<SingleChildScrollView>(
      find.byType(SingleChildScrollView),
    );
    expect(view.scrollDirection, Axis.horizontal);
  });

  testWidgets('a strip wider than its contents still pins a Spacer right', (
    tester,
  ) async {
    await tester.pumpWidget(strip(600, transport()));
    expect(tester.takeException(), isNull);
    // 600 wide less 8 of padding at each end.
    expect(tester.getSize(find.byType(Row).first).width, 584);
    // The trailing child sits against the right edge.
    expect(tester.getBottomRight(find.text('Dopesheet')).dx, 592);
  });

  testWidgets('an Expanded child lays out at both widths', (tester) async {
    // The Assets and Effects strips give their search field the leftover
    // room, which is a flex child in a scroll view that offers none.
    List<Widget> withField() => [
      const Text('Assets'),
      const SizedBox(width: 12),
      const Expanded(
        child: FTextField(size: .sm, hint: 'Filter'),
      ),
      const SizedBox(width: 26, height: 24),
    ];
    await tester.pumpWidget(strip(600, withField()));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(strip(120, withField()));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the strip is tall enough for the field it carries', (
    tester,
  ) async {
    // The Assets filter is a forui small text field; at 30 it overflowed the
    // strip by the two pixels between them.
    await tester.pumpWidget(
      FTheme(
        data: editorForuiDarkTheme,
        child: MaterialApp(
          theme: editorDarkTheme(),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 300,
                child: FTextField(size: .sm, hint: 'Filter'),
              ),
            ),
          ),
        ),
      ),
    );
    final fieldHeight = tester.getSize(find.byType(FTextField)).height;
    expect(editorToolbarHeight, greaterThanOrEqualTo(fieldHeight));
  });

  testWidgets('every control the six strips carry survives being measured', (
    tester,
  ) async {
    // Making the strip scrollable means asking the row for its own width
    // first, and a widget that refuses to be measured throws there rather
    // than laying out. This is one of each control the panels put in a strip.
    for (final width in [600.0, 140.0]) {
      await tester.pumpWidget(
        strip(width, [
          const Icon(Icons.folder_open, size: 14),
          const SizedBox(width: 6),
          const Text(
            'a label long enough to want ellipsis',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(
            width: 160,
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: 1,
                isDense: true,
                isExpanded: true,
                items: const [DropdownMenuItem(value: 1, child: Text('clip'))],
                onChanged: (_) {},
              ),
            ),
          ),
          const SizedBox(
            width: 54,
            height: 20,
            child: TextField(decoration: InputDecoration(isDense: true)),
          ),
          const Expanded(
            child: FTextField(size: .sm, hint: 'Filter'),
          ),
          Tooltip(
            message: 'Rescan',
            child: IconButton(
              icon: const Icon(Icons.refresh, size: 16),
              visualDensity: VisualDensity.compact,
              onPressed: () {},
            ),
          ),
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const Spacer(),
          TextButton(onPressed: () {}, child: const Text('Stop')),
        ]),
      );
      expect(tester.takeException(), isNull, reason: 'at width $width');
    }
  });

  testWidgets('a strip with nothing to scroll leaves drags to its parent', (
    tester,
  ) async {
    // The menu bar is the window's drag handle where the host hides the
    // native title bar, so a strip that fits must not take the gesture.
    var panned = 0;
    Widget bar(double width) => FTheme(
      data: editorForuiDarkTheme,
      child: MaterialApp(
        theme: editorDarkTheme(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onPanStart: (_) => panned++,
                child: EditorToolbar(
                  height: 28,
                  horizontalPadding: 0,
                  children: [
                    for (var i = 0; i < 6; i++)
                      const SizedBox(
                        width: 60,
                        height: 20,
                        child: Text('menu'),
                      ),
                    const Spacer(),
                    const SizedBox(width: 80, height: 20),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpWidget(bar(900));
    await tester.drag(find.byType(EditorToolbar), const Offset(60, 0));
    await tester.pumpAndSettle();
    expect(
      panned,
      1,
      reason: 'a bar with room to spare still drags the window',
    );

    // Too narrow for its own contents: the drag scrolls the strip instead,
    // which is the only way to reach what no longer fits.
    panned = 0;
    await tester.pumpWidget(bar(200));
    await tester.drag(find.byType(EditorToolbar), const Offset(-60, 0));
    await tester.pumpAndSettle();
    expect(panned, 0);
    expect(tester.takeException(), isNull);
  });
}
