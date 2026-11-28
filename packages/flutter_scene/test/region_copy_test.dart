import 'dart:ui' as ui;

import 'package:flutter_scene/src/render/region_copy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a fractional region inside the target stays inside it', () {
    final r = regionPixels(const ui.Rect.fromLTWH(10.5, 20.5, 89.5, 79.5));
    expect(r.x + r.width, 100);
    expect(r.y + r.height, 100);
  });

  test('adjacent fractional regions tile without overlap or gap', () {
    final left = regionPixels(const ui.Rect.fromLTRB(0, 0, 33.5, 10));
    final right = regionPixels(const ui.Rect.fromLTRB(33.5, 0, 67, 10));
    expect(left.x + left.width, right.x);
  });
}
