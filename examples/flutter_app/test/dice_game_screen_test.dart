import 'dart:io';
import 'dart:ui' as ui;

import 'package:example_app/dice/dice_celebration.dart';
import 'package:example_app/example_dice_shadows.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Renders the game screen at [frame] and returns its pixels, also writing a
/// PNG next to the test when `DICE_SCREEN_PNG` is set, for eyeballing.
Future<({Uint8List bytes, int width, int height})> _render(
  WidgetTester tester,
  CelebrationFrame frame, {
  String? png,
}) async {
  final key = GlobalKey();
  await tester.binding.setSurfaceSize(const Size(1280, 800));
  await tester.pumpWidget(
    MaterialApp(
      home: RepaintBoundary(
        key: key,
        child: DiceGameScreen(
          onRoll: () {},
          lastRoll: ValueNotifier<List<int>?>([3, 5, 3]),
          history: ValueNotifier<List<RollRecord>>([
            (faces: [3, 5, 3], multiplier: 2, scored: 22),
            (faces: [6, 2, 1], multiplier: 1, scored: 9),
          ]),
          frame: ValueNotifier(frame),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  late Uint8List bytes;
  late int width;
  late int height;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1.5);
    width = image.width;
    height = image.height;
    bytes = (await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!.buffer.asUint8List();
    if (png != null) {
      final encoded = await image.toByteData(format: ui.ImageByteFormat.png);
      File(png).writeAsBytesSync(encoded!.buffer.asUint8List());
    }
    image.dispose();
  });
  return (bytes: bytes, width: width, height: height);
}

/// How many pixels sit within [tolerance] of [color] per channel.
int _count(Uint8List bytes, Color color, {int tolerance = 12}) {
  var n = 0;
  final r = (color.r * 255).round();
  final g = (color.g * 255).round();
  final b = (color.b * 255).round();
  for (var i = 0; i < bytes.length; i += 4) {
    if ((bytes[i] - r).abs() <= tolerance &&
        (bytes[i + 1] - g).abs() <= tolerance &&
        (bytes[i + 2] - b).abs() <= tolerance) {
      n++;
    }
  }
  return n;
}

void main() {
  final png = Platform.environment['DICE_SCREEN_PNG'];

  testWidgets('the screen paints stripes in every palette color', (
    tester,
  ) async {
    final shot = await _render(
      tester,
      const CelebrationFrame(total: 1240),
      png: png == null ? null : '$png/idle.png',
    );
    final total = shot.width * shot.height;
    // Each stripe color covers a real share of the screen, and ink outlines
    // are present but not dominant.
    for (final color in const [
      Color(0xFFF4845F),
      Color(0xFF2A9D8F),
      Color(0xFFE9C46A),
      Color(0xFF8ED2C6),
    ]) {
      expect(_count(shot.bytes, color) / total, greaterThan(0.03));
    }
    final ink = _count(shot.bytes, const Color(0xFF1F1B1A)) / total;
    expect(ink, greaterThan(0.01));
    expect(ink, lessThan(0.2));
  });

  testWidgets('the counter and badge draw mid-celebration', (tester) async {
    final before = await _render(
      tester,
      const CelebrationFrame(total: 1240),
      png: png == null ? null : '$png/before.png',
    );
    final during = await _render(
      tester,
      const CelebrationFrame(
        phase: CelebrationPhase.multiplier,
        counter: 22,
        multiplier: 2,
        multiplierReveal: 1.0,
        counterAlpha: 1.0,
        punch: 0.0,
        total: 1240,
      ),
      png: png == null ? null : '$png/multiplier.png',
    );
    // The big mustard number and its ink outline add their colors; the
    // badge is too small to count against the stripes it covers.
    expect(
      _count(during.bytes, const Color(0xFFE9C46A)),
      greaterThan(_count(before.bytes, const Color(0xFFE9C46A)) + 20000),
    );
    expect(
      _count(during.bytes, const Color(0xFF1F1B1A)),
      greaterThan(_count(before.bytes, const Color(0xFF1F1B1A)) + 5000),
    );
  });
}
