// ignore_for_file: implementation_imports
import 'dart:ui' show Color;

import 'package:flutter_scene/src/render/region_copy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('packExternalOutputInfo', () {
    test('packs nothing for a plain copy', () {
      final info = packExternalOutputInfo(background: null, decodeSrgb: false);
      expect(info, hasLength(8));
      expect(info.every((value) => value == 0.0), isTrue);
    });

    test('premultiplies the background', () {
      final info = packExternalOutputInfo(
        background: const Color.from(alpha: 0.5, red: 1.0, green: 0.5, blue: 0),
        decodeSrgb: false,
      );
      expect(info[0], closeTo(0.5, 1e-6));
      expect(info[1], closeTo(0.25, 1e-6));
      expect(info[2], 0.0);
      expect(info[3], closeTo(0.5, 1e-6));
      expect(info[4], 0.0);
    });

    test('flags the sRGB decode in the second row', () {
      final info = packExternalOutputInfo(background: null, decodeSrgb: true);
      expect(info.sublist(0, 4).every((value) => value == 0.0), isTrue);
      expect(info[4], 1.0);
    });
  });
}
