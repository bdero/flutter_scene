// Layout tests for the cloth control panel.
//
// A panel that fails layout takes the whole example subtree with it, and an
// unlaid-out subtree stops routing pointer events, so a control-panel layout
// error reads to the user as "the app stopped responding". These pump the
// panel at the sizes the overlay gives it and assert it lays out clean.

import 'package:example_app/cloth/cloth_controls.dart';
import 'package:example_app/cloth/cloth_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child, Size size) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox(width: size.width, height: size.height, child: child),
    ),
  ),
);

void main() {
  for (final size in const [
    Size(340, 800),
    Size(300, 520),
    // The narrow phone case, where the panel is squeezed hardest.
    Size(240, 420),
  ]) {
    testWidgets('the control panel lays out at $size', (tester) async {
      await tester.pumpWidget(
        _host(
          ClothControlPanel(
            settings: ClothSettings(),
            stats: ValueNotifier<String>(
              '1234 particles, 5678 constraints, 4.2 ms',
            ),
            onChanged: () {},
            onRebuild: () {},
            onReset: () {},
          ),
          size,
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Cloth'), findsOneWidget);
    });
  }

  testWidgets('the quality dropdown opens and reports a change', (
    tester,
  ) async {
    final settings = ClothSettings();
    var qualityChanges = 0;
    await tester.pumpWidget(
      _host(
        ClothControlPanel(
          settings: settings,
          stats: ValueNotifier<String>(''),
          onChanged: () {},
          onRebuild: () => qualityChanges++,
          onReset: () {},
        ),
        const Size(340, 800),
      ),
    );

    // Whatever the default tier is, pick a different one, so retuning the
    // defaults does not break this.
    final current = settings.quality;
    final other = ClothQuality.values.firstWhere((q) => q != current);

    // The panel is taller than the viewport, so scroll the row into view
    // before tapping it.
    await tester.scrollUntilVisible(find.text(current.label), 80);
    await tester.tap(find.text(current.label));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.text(other.label).last);
    await tester.pumpAndSettle();
    expect(settings.quality, other);
    expect(qualityChanges, 1);
  });

  testWidgets('the sliders write through to the settings', (tester) async {
    final settings = ClothSettings();
    var changes = 0;
    await tester.pumpWidget(
      _host(
        ClothControlPanel(
          settings: settings,
          stats: ValueNotifier<String>(''),
          onChanged: () => changes++,
          onRebuild: () {},
          onReset: () {},
        ),
        const Size(340, 800),
      ),
    );

    // Drag the wind speed slider to its maximum.
    await tester.drag(find.byType(Slider).first, const Offset(400, 0));
    await tester.pump();
    expect(settings.wind.speed, 18.0);
    expect(changes, greaterThan(0));
  });
}
