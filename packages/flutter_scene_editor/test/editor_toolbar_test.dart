// The panel toolbar strip. A docked panel can be dragged narrower than its own
// controls, and the strip has to survive that -- without measuring the row,
// which is what broke it the first time.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_scene_editor/src/shell/editor_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

void main() {
  Widget strip(
    double width, {
    List<Widget> leading = const [],
    List<Widget> trailing = const [],
  }) => FTheme(
    data: editorForuiDarkTheme,
    child: MaterialApp(
      theme: editorDarkTheme(),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: EditorToolbar(leading: leading, trailing: trailing),
          ),
        ),
      ),
    ),
  );

  /// What the Animation strip is: a run of fixed-width buttons on the left and
  /// a couple of controls pinned right.
  List<Widget> buttons(int count) => [
    for (var i = 0; i < count; i++)
      const SizedBox(
        width: 24,
        height: 24,
        child: Icon(Icons.circle, size: 12),
      ),
  ];

  group('a child that cannot be measured', () {
    testWidgets('a LayoutBuilder in the strip does not throw', (tester) async {
      // This is the regression. The strip used to size its row with
      // IntrinsicWidth, and a LayoutBuilder cannot answer an intrinsic query:
      // it threw from inside layout, took the frame with it, and -- when the
      // layout was running inside a mouse-tracker update -- latched that
      // tracker's debug flag so every later pointer move asserted too.
      await tester.pumpWidget(
        strip(
          600,
          leading: [
            LayoutBuilder(
              builder: (context, _) =>
                  const SizedBox(width: 40, height: 20, child: Text('x')),
            ),
          ],
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('x'), findsOneWidget);
    });

    testWidgets('and neither does one in the trailing group', (tester) async {
      await tester.pumpWidget(
        strip(
          600,
          trailing: [
            LayoutBuilder(
              builder: (context, _) =>
                  const SizedBox(width: 40, height: 20, child: Text('y')),
            ),
          ],
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a menu, which is what the menu bar is made of', (
      tester,
    ) async {
      await tester.pumpWidget(
        strip(
          600,
          leading: [
            MenuAnchor(
              menuChildren: const [MenuItemButton(child: Text('New'))],
              builder: (context, controller, _) =>
                  TextButton(onPressed: () {}, child: const Text('File')),
            ),
          ],
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('File'), findsOneWidget);
    });

    testWidgets('moving the pointer over it keeps working afterwards', (
      tester,
    ) async {
      // The flood was pointer-driven, so the check is that a hover after the
      // layout still runs clean rather than asserting.
      await tester.pumpWidget(
        strip(
          400,
          leading: [
            LayoutBuilder(
              builder: (context, _) => const SizedBox(width: 40, height: 20),
            ),
            ...buttons(6),
          ],
        ),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      for (final dx in [20.0, 120.0, 260.0, 380.0]) {
        await mouse.moveTo(Offset(dx, 16));
        await tester.pump();
      }
      expect(tester.takeException(), isNull);
    });
  });

  group('layout', () {
    testWidgets('the trailing group sits against the right edge', (
      tester,
    ) async {
      await tester.pumpWidget(
        strip(
          600,
          leading: buttons(3),
          trailing: const [
            SizedBox(width: 140, height: 24, child: Text('Dopesheet')),
          ],
        ),
      );
      // 600 wide, less 8 of padding at the right.
      expect(tester.getBottomRight(find.text('Dopesheet')).dx, 592);
    });

    testWidgets('a strip narrower than its contents scrolls, not overflows', (
      tester,
    ) async {
      await tester.pumpWidget(strip(200, leading: buttons(12)));
      expect(tester.takeException(), isNull);
      final view = tester.widget<SingleChildScrollView>(
        find.byType(SingleChildScrollView).first,
      );
      expect(view.scrollDirection, Axis.horizontal);
    });

    testWidgets('an editable field in the strip lays out at both widths', (
      tester,
    ) async {
      // The Project strip gives its filter the leftover room.
      for (final width in [600.0, 120.0]) {
        await tester.pumpWidget(
          strip(
            width,
            leading: const [
              Text('Project'),
              SizedBox(width: 12),
              SizedBox(
                width: 150,
                child: FTextField(size: .sm, hint: 'Filter'),
              ),
            ],
          ),
        );
        expect(tester.takeException(), isNull, reason: 'at $width');
      }
    });

    testWidgets('every control the strips carry survives being laid out', (
      tester,
    ) async {
      for (final width in [600.0, 140.0]) {
        await tester.pumpWidget(
          strip(
            width,
            leading: [
              const Icon(Icons.folder_open, size: 14),
              const SizedBox(width: 6),
              const Text(
                'a label',
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
                    items: const [
                      DropdownMenuItem(value: 1, child: Text('clip')),
                    ],
                    onChanged: (_) {},
                  ),
                ),
              ),
              const SizedBox(
                width: 54,
                height: 20,
                child: TextField(decoration: InputDecoration(isDense: true)),
              ),
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ],
            trailing: [
              Tooltip(
                message: 'Rescan',
                child: IconButton(
                  icon: const Icon(Icons.refresh, size: 16),
                  visualDensity: VisualDensity.compact,
                  onPressed: () {},
                ),
              ),
              TextButton(onPressed: () {}, child: const Text('Stop')),
            ],
          ),
        );
        expect(tester.takeException(), isNull, reason: 'at width $width');
      }
    });

    testWidgets('the strip is tall enough for the field it carries', (
      tester,
    ) async {
      // The Project filter is a forui small text field; at 30 it overflowed
      // the strip by the two pixels between them.
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
  });

  testWidgets('a strip with nothing to scroll leaves drags to its parent', (
    tester,
  ) async {
    // The menu bar is the window's drag handle where the host hides the
    // native title bar, so a strip that fits must not take the gesture.
    var panned = 0;
    Widget bar(double width, int count) => MaterialApp(
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
                leading: [
                  for (var i = 0; i < count; i++)
                    const SizedBox(width: 60, height: 20, child: Text('menu')),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpWidget(bar(900, 4));
    await tester.drag(find.byType(EditorToolbar), const Offset(60, 0));
    await tester.pumpAndSettle();
    expect(
      panned,
      1,
      reason: 'a bar with room to spare still drags the window',
    );

    panned = 0;
    await tester.pumpWidget(bar(200, 10));
    await tester.drag(find.byType(EditorToolbar), const Offset(-60, 0));
    await tester.pumpAndSettle();
    expect(panned, 0);
    expect(tester.takeException(), isNull);
  });
}
