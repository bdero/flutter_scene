import 'package:flutter/material.dart';
import 'package:flutter_scene_editor/src/shell/editor_theme.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget app(Widget child) => MaterialApp(
    theme: editorDarkTheme(),
    home: Scaffold(body: child),
  );

  testWidgets('menu items render at the shared editor height', (tester) async {
    final controller = MenuController();
    await tester.pumpWidget(
      app(
        MenuAnchor(
          controller: controller,
          menuChildren: [
            MenuItemButton(onPressed: () {}, child: const Text('First')),
            MenuItemButton(
              onPressed: () {},
              leadingIcon: editorMenuCheckmark(true),
              child: const Text('Second'),
            ),
            SubmenuButton(
              menuChildren: [
                MenuItemButton(onPressed: () {}, child: const Text('Nested')),
              ],
              child: const Text('Submenu'),
            ),
          ],
          child: const Text('Open'),
        ),
      ),
    );
    controller.open();
    await tester.pumpAndSettle();

    for (final label in ['First', 'Second', 'Submenu']) {
      final size = tester.getSize(
        find.ancestor(
          of: find.text(label),
          matching: find.byWidgetPredicate(
            (w) => w is MenuItemButton || w is SubmenuButton,
          ),
        ),
      );
      expect(
        size.height,
        editorMenuItemHeight,
        reason: '$label should be $editorMenuItemHeight tall',
      );
    }

    // The global compact visual density must not shrink menu rows below the
    // shared height (the button theme pins them to standard density).
    final first = tester.getSize(
      find.ancestor(
        of: find.text('First'),
        matching: find.byType(MenuItemButton),
      ),
    );
    final second = tester.getSize(
      find.ancestor(
        of: find.text('Second'),
        matching: find.byType(MenuItemButton),
      ),
    );
    expect(first.height, second.height);
  });

  testWidgets('menu item text inherits the shared 12px style', (tester) async {
    final controller = MenuController();
    await tester.pumpWidget(
      app(
        MenuAnchor(
          controller: controller,
          menuChildren: [
            MenuItemButton(onPressed: () {}, child: const Text('Item')),
          ],
          child: const Text('Open'),
        ),
      ),
    );
    controller.open();
    await tester.pumpAndSettle();

    final style = DefaultTextStyle.of(tester.element(find.text('Item'))).style;
    expect(style.fontSize, editorMenuItemText.fontSize);
  });
}
