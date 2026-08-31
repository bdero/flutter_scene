// Covers the theme reachability a floating dock panel depends on.
//
// Floating panels are real OS windows, which is the same situation that broke
// dialogs in issue #344: a window-hosted route mounted above the app's
// MaterialApp.builder lost EditorThemeScope/FTheme and forui's accessibility
// InheritedModel, so every FButton threw "Null check operator used on a null
// value" on mount. Floating panels avoid that only because they are built
// inside the shell, below the builder, and FloatWindowScaffold's nested
// MaterialApp does not cut off inherited lookups. This pins that property.
//
// The real RegularWindow cannot be created under flutter_test, so this covers
// the widget-tree half (the scaffold and its nested MaterialApp) rather than
// the embedder half.

import 'package:flutter/material.dart';
import 'package:flutter_scene_editor/src/shell/docking_shell.dart';
import 'package:flutter_scene_editor/src/shell/editor_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

void main() {
  // Mirrors the app: EditorThemeScope installed in MaterialApp.builder, with
  // the shell's content below it.
  Widget app(Widget child) => MaterialApp(
    theme: editorDarkTheme(),
    debugShowCheckedModeBanner: false,
    builder: (context, built) => EditorThemeScope(child: built!),
    home: Scaffold(body: child),
  );

  testWidgets('a floating panel keeps the forui theme scopes', (tester) async {
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => FloatWindowScaffold(
            theme: Theme.of(context),
            child: FButton(
              size: .xs,
              mainAxisSize: .min,
              onPress: () {},
              child: const Text('Floating action'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // A missing FTheme or accessibility scope throws while mounting FButton,
    // which is the failure this guards against.
    expect(tester.takeException(), isNull);
    expect(find.text('Floating action'), findsOneWidget);
  });

  testWidgets('the panel resolves the editor FTheme, not a forui default', (
    tester,
  ) async {
    FThemeData? resolved;
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => FloatWindowScaffold(
            theme: Theme.of(context),
            child: Builder(
              builder: (context) {
                resolved = FTheme.of(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    // The editor's palette, so the scope crossing the nested MaterialApp is
    // the editor's own and not a fallback.
    expect(resolved, isNotNull);
    expect(resolved!.colors.primary, editorForuiDarkTheme.colors.primary);
  });
}
