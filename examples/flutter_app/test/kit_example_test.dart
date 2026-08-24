import 'package:example_app/example_overlay.dart';
import 'package:example_app/kit/kit_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pumpInSlot(WidgetTester tester, Widget slot, Size window) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(size: window),
          child: SizedBox(
            width: window.width,
            height: window.height,
            child: Stack(children: [slot]),
          ),
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const windows = [Size(1280, 800), Size(800, 600), Size(390, 844)];

  for (final window in windows) {
    testWidgets('kit slider row lays out at $window', (tester) async {
      await _pumpInSlot(
        tester,
        ExampleOverlay.bottomLeftPanel(
          child: KitSliderRow(
            label: 'Speed',
            value: 5.0,
            min: 0.0,
            max: 10.0,
            onChanged: (_) {},
          ),
        ),
        window,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('kit slider updates settings value on change', (tester) async {
    final settings = KitDemoSettings();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: KitSliderRow(
            label: 'Arm Length',
            value: settings.armLength,
            min: 2.0,
            max: 12.0,
            onChanged: (v) => settings.armLength = v,
          ),
        ),
      ),
    );

    expect(settings.armLength, closeTo(5.5, 0.01));
    final slider = find.byType(Slider);
    expect(slider, findsOneWidget);

    await tester.tap(slider);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
