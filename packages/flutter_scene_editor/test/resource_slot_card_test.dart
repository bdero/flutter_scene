import 'package:flutter/material.dart';
import 'package:flutter_scene_editor/src/inspector/resource_origin.dart';
import 'package:flutter_scene_editor/src/inspector/resource_slot_card.dart';
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

  testWidgets('OriginBadge labels built-in and external', (tester) async {
    await tester.pumpWidget(
      themed(
        const Column(
          children: [
            OriginBadge(locality: ResourceLocality.builtIn),
            OriginBadge(
              locality: ResourceLocality.external,
              path: 'shaders/glow.fmat',
            ),
          ],
        ),
      ),
    );
    expect(find.text('Built-in'), findsOneWidget);
    expect(find.text('External'), findsOneWidget);
  });

  testWidgets('ResourceSlotCard shows title, kind, badge, and remove', (
    tester,
  ) async {
    var replaced = false;
    var removed = false;
    await tester.pumpWidget(
      themed(
        SizedBox(
          width: 320,
          child: ResourceSlotCard(
            title: 'bricks.png',
            kind: 'Base color · PNG image',
            locality: ResourceLocality.external,
            path: '/tmp/bricks.png',
            onReplace: () => replaced = true,
            onRemove: () => removed = true,
          ),
        ),
      ),
    );
    expect(find.text('bricks.png'), findsOneWidget);
    expect(find.text('Base color · PNG image'), findsOneWidget);
    expect(find.text('External'), findsOneWidget);
    expect(find.text('Replace'), findsOneWidget);

    await tester.tap(find.text('Replace'));
    await tester.pumpAndSettle();
    expect(replaced, isTrue);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(removed, isTrue);
  });

  testWidgets('ResourceSlotCard without onRemove hides the remove button', (
    tester,
  ) async {
    await tester.pumpWidget(
      themed(
        const SizedBox(
          width: 320,
          child: ResourceSlotCard(
            title: 'Physically based',
            kind: 'Physically based',
            locality: ResourceLocality.builtIn,
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.close), findsNothing);
    expect(find.text('Replace'), findsNothing);
    expect(find.text('Built-in'), findsOneWidget);
  });
}
