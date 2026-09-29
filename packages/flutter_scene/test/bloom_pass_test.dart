import 'dart:io';

import 'package:flutter_scene/src/render/bloom_pass.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the default scatter weights every mip equally', () {
    expect(bloomLevelWeight(0.7), 1.0);
    expect(bloomLevelScale(1.0, 6), 1.0);
  });

  test('scatter widens monotonically at constant brightness', () {
    var previous = 0.0;
    for (var scatter = 0.0; scatter <= 1.0; scatter += 0.1) {
      final weight = bloomLevelWeight(scatter);
      expect(weight, greaterThan(previous));
      previous = weight;
      final scale = bloomLevelScale(weight, 6);
      var total = 0.0;
      for (var level = 0; level < 6; level++) {
        total += scale * _pow(weight, level);
      }
      expect(total, closeTo(6, 1e-9));
    }
  });

  test('prefilter taps overlap into an even box', () {
    expect(bloomThresholdTaps(1.0), 1);
    expect(bloomThresholdTaps(2.0), 2);
    expect(bloomThresholdTaps(9.4), 10);
    expect(bloomThresholdTaps(40), kMaxBloomThresholdTaps);
  });

  test('the threshold shader loop bound matches the Dart cap', () {
    final source = File(
      'shaders/flutter_scene_bloom_threshold.frag',
    ).readAsStringSync();
    expect(source, contains('const int kMaxTaps = $kMaxBloomThresholdTaps;'));
  });
}

double _pow(double x, int n) {
  var r = 1.0;
  for (var i = 0; i < n; i++) {
    r *= x;
  }
  return r;
}
