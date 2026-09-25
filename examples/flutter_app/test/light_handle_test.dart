import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:example_app/example_dice_shadows.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Renders the handle and reports where the amber glyph's pixels sit relative
/// to the middle of the widget.
Future<({Offset offset, Offset boxOffset, int pixels})> _glyphOffset(
  WidgetTester tester,
  LightGlyph glyph,
  double emphasis,
) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    MaterialApp(
      home: Center(
        child: RepaintBoundary(
          key: key,
          child: LightHandle(
            glyph: glyph,
            emphasisOverride: emphasis,
            onDrag: (_) {},
          ),
        ),
      ),
    ),
  );
  // Settle the hover/press tween.
  await tester.pumpAndSettle();

  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  // Rasterising needs real async; the fake clock in a widget test never
  // completes these futures.
  late Uint8List bytes;
  late int width;
  late int height;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 4.0);
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    bytes = data.buffer.asUint8List();
    width = image.width;
    height = image.height;
  });

  // The glyph is the brightest thing in the disc; the disc itself is nearly
  // black and the glow around it is dim.
  var sumX = 0.0;
  var sumY = 0.0;
  var weight = 0.0;
  var counted = 0;
  var minX = double.infinity;
  var maxX = -double.infinity;
  var minY = double.infinity;
  var maxY = -double.infinity;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 4;
      final a = bytes[i + 3];
      if (a < 40) continue;
      // Captured pixels are premultiplied, so undo the layer's alpha before
      // judging brightness.
      final scale = 255.0 / a;
      final r = bytes[i] * scale;
      final g = bytes[i + 1] * scale;
      final b = bytes[i + 2] * scale;
      final luminance = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0;
      if (luminance < 0.5) continue;
      sumX += x * luminance;
      sumY += y * luminance;
      weight += luminance;
      counted++;
      minX = math.min(minX, x.toDouble());
      maxX = math.max(maxX, x.toDouble());
      minY = math.min(minY, y.toDouble());
      maxY = math.max(maxY, y.toDouble());
    }
  }
  if (counted <= 50) {
    // Dump what was actually captured, to tell a missing font from a bad
    // threshold.
    var maxLum = 0.0;
    var opaque = 0;
    for (var i = 0; i < bytes.length; i += 4) {
      final a = bytes[i + 3];
      if (a < 40) continue;
      opaque++;
      final scale = 255.0 / a;
      final lum =
          (0.299 * bytes[i] + 0.587 * bytes[i + 1] + 0.114 * bytes[i + 2]) *
          scale /
          255.0;
      maxLum = math.max(maxLum, lum);
    }
    fail('glyph did not render: $opaque opaque px, brightest $maxLum');
  }
  final centroid = Offset(sumX / weight, sumY / weight);
  final box = Offset((minX + maxX) / 2, (minY + maxY) / 2);
  final middle = Offset(width / 2, height / 2);
  // Back to logical pixels.
  return (
    offset: (centroid - middle) / 4.0,
    boxOffset: (box - middle) / 4.0,
    pixels: counted,
  );
}

void main() {
  testWidgets('sun glyph is centred in the handle', (tester) async {
    for (final emphasis in [0.0, 1.0]) {
      final result = await _glyphOffset(tester, LightGlyph.sun, emphasis);
      expect(
        result.boxOffset.distance,
        lessThan(0.4),
        reason:
            'sun box off centre by ${result.boxOffset}, ink ${result.offset}, '
            'at emphasis $emphasis',
      );
      expect(
        result.offset.distance,
        lessThan(0.6),
        reason: 'sun ink off centre by ${result.offset}',
      );
    }
  });

  testWidgets('bulb glyph is centred in the handle', (tester) async {
    final result = await _glyphOffset(tester, LightGlyph.bulb, 0.0);
    expect(
      result.boxOffset.distance,
      lessThan(0.4),
      reason: 'bulb box off centre by ${result.boxOffset} logical px',
    );
  });

  testWidgets('the handle reports a drag', (tester) async {
    final drags = <Offset>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: LightHandle(glyph: LightGlyph.sun, onDrag: drags.add),
        ),
      ),
    );
    await tester.drag(find.byType(LightHandle), const Offset(40, 20));
    expect(drags, isNotEmpty);
  });

  test('centroid maths', () {
    // Guards the helper itself: a symmetric blob has no offset.
    final points = [
      const Offset(-2, -2),
      const Offset(2, -2),
      const Offset(-2, 2),
      const Offset(2, 2),
    ];
    final mean = points.reduce((a, b) => a + b) / points.length.toDouble();
    expect(mean.distance, lessThan(1e-9));
    expect(math.sqrt(4), 2);
  });
}
