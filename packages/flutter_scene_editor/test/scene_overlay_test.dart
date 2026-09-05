// The overlay chrome. A setting that changes what a drag does belongs where
// you can see it, so the property worth pinning is that a segmented choice
// shows both options and which one is current -- that is the whole reason it
// is on the scene rather than behind a menu.

import 'package:flutter/material.dart';
import 'package:flutter_scene_editor/src/shell/editor_theme.dart';
import 'package:flutter_scene_editor/src/viewport/scene_overlay.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
    theme: editorDarkTheme(),
    home: Scaffold(body: Center(child: child)),
  );

  testWidgets('an overlay with a label shows it, in caps', (tester) async {
    await tester.pumpWidget(
      host(const SceneOverlay(label: 'Tool settings', child: Text('body'))),
    );
    expect(find.text('TOOL SETTINGS'), findsOneWidget);
    expect(find.text('body'), findsOneWidget);
  });

  testWidgets('an overlay without one is just its contents', (tester) async {
    await tester.pumpWidget(host(const SceneOverlay(child: Text('body'))));
    expect(find.byType(Column), findsNothing);
    expect(find.text('body'), findsOneWidget);
  });

  testWidgets('segments show every option, not just the current one', (
    tester,
  ) async {
    // A dropdown for two options hides one behind a click.
    await tester.pumpWidget(
      host(
        OverlaySegments<int>(
          options: const {0: 'Global', 1: 'Local'},
          value: 0,
          onChanged: (_) {},
        ),
      ),
    );
    expect(find.text('Global'), findsOneWidget);
    expect(find.text('Local'), findsOneWidget);
  });

  testWidgets('picking one reports it', (tester) async {
    int? picked;
    await tester.pumpWidget(
      host(
        OverlaySegments<int>(
          options: const {0: 'Global', 1: 'Local'},
          value: 0,
          onChanged: (value) => picked = value,
        ),
      ),
    );
    await tester.tap(find.text('Local'));
    expect(picked, 1);
  });

  testWidgets('picking the one already current still reports it', (
    tester,
  ) async {
    // Cheaper than making every caller guard, and a no-op setter already does.
    int? picked;
    await tester.pumpWidget(
      host(
        OverlaySegments<int>(
          options: const {0: 'Global', 1: 'Local'},
          value: 0,
          onChanged: (value) => picked = value,
        ),
      ),
    );
    await tester.tap(find.text('Global'));
    expect(picked, 0);
  });

  testWidgets('the overlay does not black out what is behind it', (
    tester,
  ) async {
    await tester.pumpWidget(host(const SceneOverlay(child: Text('body'))));
    final container = tester.widget<Container>(
      find
          .ancestor(of: find.text('body'), matching: find.byType(Container))
          .first,
    );
    final decoration = container.decoration! as BoxDecoration;
    expect(decoration.color!.a, lessThan(1.0));
  });
}
