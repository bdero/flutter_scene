// Layout tests for the cloth panels in the overlay slots that host them.
//
// The slots differ in what they constrain: the side panels hand the child a
// width, the top-right slot does not. A panel that does not account for that
// throws during layout, and an example whose subtree failed to lay out stops
// hit-testing, which reads to the user as the mouse going dead everywhere.

import 'package:example_app/cloth/cloth_controls.dart';
import 'package:example_app/cloth/cloth_settings.dart';
import 'package:example_app/cloth/cloth_wind.dart';
import 'package:example_app/example_overlay.dart';
import 'package:example_app/example_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pumpInSlot(WidgetTester tester, Widget slot, Size window) async {
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: window),
        child: SizedBox(
          width: window.width,
          height: window.height,
          child: Stack(children: [slot]),
        ),
      ),
    ),
  );
}

void main() {
  const windows = [
    Size(1280, 800),
    Size(800, 600),
    // A phone in portrait, the tightest the panels ever get.
    Size(390, 844),
  ];

  for (final window in windows) {
    testWidgets('the cloth panel lays out in the bottom-left slot at $window', (
      tester,
    ) async {
      await _pumpInSlot(
        tester,
        ExampleOverlay.bottomLeftPanel(
          child: ClothControlPanel(
            settings: ClothSettings(),
            stats: '2400 particles, 7000 constraints, 6.1 ms',
            onChanged: () {},
            onQualityChanged: () {},
            onReset: () {},
          ),
        ),
        window,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the wind panel lays out in the top-right slot at $window', (
      tester,
    ) async {
      await _pumpInSlot(
        tester,
        ExampleOverlay.topRightPanel(
          child: ExamplePanelCard(
            icon: Icons.air,
            title: 'Wind',
            width: 300,
            maxBodyHeight: 220,
            bodyPadding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            body: ClothWindControls(wind: ClothWind(), onChanged: () {}),
          ),
        ),
        window,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
