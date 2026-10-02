import 'dart:io';

import 'package:flutter_scene/src/render/bloom_pass.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the default scatter weights every mip equally', () {
    expect(bloomLevelWeight(0.7), 1.0);
    expect(_mipWeights(1.0, 6), everyElement(closeTo(1.0, 1e-9)));
  });

  test('scatter widens monotonically at constant brightness', () {
    var previous = 0.0;
    for (var scatter = 0.0; scatter <= 1.0; scatter += 0.1) {
      final weight = bloomLevelWeight(scatter);
      expect(weight, greaterThan(previous));
      previous = weight;
      final mips = _mipWeights(weight, 6);
      expect(mips.reduce((a, b) => a + b), closeTo(6, 1e-9));
      for (var level = 1; level < 6; level++) {
        expect(mips[level] / mips[level - 1], closeTo(weight, 1e-9));
      }
    }
  });

  test('intermediate mips stay within their inputs at full scatter', () {
    // Constant 8000 mips sum to 48000, inside half-float range, and no
    // intermediate may pass 8000 on the way there.
    const levels = 6;
    final weight = bloomLevelWeight(1.0);
    var up = 8000.0;
    for (var level = levels - 2; level >= 0; level--) {
      final w = bloomUpsampleWeights(weight, level, levels);
      up = w.source * up + w.base * 8000.0;
      if (level > 0) expect(up, closeTo(8000.0, 1e-6));
    }
    expect(up, closeTo(48000.0, 1e-6));
  });

  test('a prefilter wider than the tap budget adds an exact box stage', () {
    expect(bloomPrefilterScale(9.14), 1);
    expect(bloomPrefilterScale(15), 1);
    // 5120 and 6144 pixel targets over a 256 pixel first mip.
    expect(bloomPrefilterScale(20), 2);
    expect(bloomPrefilterScale(24), 2);
    for (final footprint in [16.0, 20.0, 24.0, 40.0, 100.0, 225.0]) {
      final scale = bloomPrefilterScale(footprint);
      // Each stage's box spans at most one texel past its footprint.
      expect(footprint / scale + 1, lessThanOrEqualTo(kMaxBloomThresholdTaps));
      expect(scale + 1, lessThanOrEqualTo(kMaxBloomThresholdTaps));
    }
  });

  test('the threshold shader loop bound matches the Dart cap', () {
    final source = File(
      'shaders/flutter_scene_bloom_threshold.frag',
    ).readAsStringSync();
    expect(source, contains('const int kMaxTaps = $kMaxBloomThresholdTaps;'));
  });
}

// Each downsample mip's weight in the finished bloom.
List<double> _mipWeights(double levelWeight, int levels) {
  // Contribution of every mip to the current upsample level.
  var contribution = List<double>.filled(levels, 0)..[levels - 1] = 1.0;
  for (var level = levels - 2; level >= 0; level--) {
    final w = bloomUpsampleWeights(levelWeight, level, levels);
    contribution = [
      for (var j = 0; j < levels; j++)
        contribution[j] * w.source + (j == level ? w.base : 0.0),
    ];
  }
  return contribution;
}
