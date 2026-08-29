// The toolbar. The load-bearing property is that the transport sits on the
// window's midpoint whatever is beside it: that is where every editor this
// one is measured against puts it, and it is why people find it without
// looking.

import 'package:flutter/material.dart';
import 'package:flutter_scene_editor/src/shell/editor_theme.dart';
import 'package:flutter_scene_editor/src/shell/editor_toolbar_row.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// The transport's centre against the toolbar's own centre, which is the
  /// invariant regardless of how wide the test surface happens to be.
  void expectCentred(WidgetTester tester) {
    final row = find
        .descendant(
          of: find.byType(EditorToolbarRow),
          matching: find.byType(Row),
        )
        .first;
    expect(
      tester.getCenter(find.text('transport')).dx,
      closeTo(tester.getCenter(row).dx, 0.5),
    );
  }

  Widget bar(double width, {List<Widget> leading = const []}) => MaterialApp(
    theme: editorDarkTheme(),
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          child: EditorToolbarRow(
            leading: leading,
            centre: const [
              SizedBox(width: 90, height: 20, child: Text('transport')),
            ],
            namedLayouts: const {},
            onApplyLayout: (_) {},
            onSaveCurrentLayout: () {},
            onManageLayouts: () {},
          ),
        ),
      ),
    ),
  );

  testWidgets('the transport sits on the window centre', (tester) async {
    await tester.pumpWidget(bar(700));
    expectCentred(tester);
  });

  testWidgets('a wide left group does not push it off centre', (tester) async {
    // The reason this is a row of its own: a bar whose left half is five
    // menus cannot centre anything by putting it after them.
    await tester.pumpWidget(
      bar(
        700,
        leading: [
          for (var i = 0; i < 6; i++)
            const SizedBox(width: 70, height: 20, child: Text('sel')),
        ],
      ),
    );
    expectCentred(tester);
  });

  testWidgets('it stays centred as the window changes width', (tester) async {
    for (final width in [420.0, 600.0, 780.0]) {
      await tester.pumpWidget(bar(width));
      expectCentred(tester);
    }
  });

  testWidgets('a side group too wide for its half scrolls, and does not '
      'overflow', (tester) async {
    await tester.pumpWidget(
      bar(
        400,
        leading: [
          for (var i = 0; i < 10; i++)
            const SizedBox(width: 80, height: 20, child: Text('sel')),
        ],
      ),
    );
    expect(tester.takeException(), isNull);
    expectCentred(tester);
  });

  testWidgets('the layout menu is on the right', (tester) async {
    await tester.pumpWidget(bar(700));
    expect(find.text('Layout'), findsOneWidget);
    expect(
      tester.getCenter(find.text('Layout')).dx,
      greaterThan(tester.getCenter(find.text('transport')).dx),
    );
  });
}
