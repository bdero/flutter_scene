@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sized lights widen the lobe on both punctual paths', () {
    final source = File('shaders/material_lighting.glsl').readAsStringSync();
    expect(source, contains('highp float source_radius = l3.w;'));
    // The hooked and plain evaluations both take the widened roughness.
    expect(
      RegExp(r'metallic, light_roughness, reflectance').allMatches(source),
      hasLength(2),
    );
  });
}
