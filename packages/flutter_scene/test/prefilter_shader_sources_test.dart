import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The two GGX radiance prefilters. They share their sample generation and
/// their mirror-band shortcut, so a change to one that misses the other shows
/// up here rather than as a backend-specific image difference.
const _prefilterShaders = [
  'shaders/flutter_scene_prefilter_env.frag',
  'shaders/flutter_scene_prefilter_radiance_cube.frag',
];

String _read(String path) => File(path).readAsStringSync();

void main() {
  for (final path in _prefilterShaders) {
    group(path.split('/').last, () {
      test('returns the mirror sample at roughness 0 without the loop', () {
        final source = _read(path);
        final shortcut = source.indexOf('if (roughness <= 0.0)');
        final loop = source.indexOf('for (int i = 0; i < kPrefilterSamples;');
        expect(
          shortcut,
          greaterThan(0),
          reason: 'band 0 is a delta lobe; sampling it 256 times is waste',
        );
        expect(
          shortcut,
          lessThan(loop),
          reason: 'the shortcut has to come before the sample loop',
        );
        // The shortcut returns the value the firefly clamp already reads, so
        // it is only exact while that value is an unfiltered mirror sample.
        expect(
          source,
          matches(RegExp(r'vec3 center = SampleSourceRadiance(Lod)?\(n[,)]')),
        );
      });

      test('the lattice y term is highp', () {
        final source = _read(path);
        expect(
          source,
          contains('const highp float kGoldenRatioConjugate'),
          reason:
              'the term reaches ~158 by the last sample, which fp16 cannot '
              'resolve a fractional part of. See shaders/PRECISION.md.',
        );
        expect(
          source,
          contains('highp float kronecker'),
          reason: 'the accumulating product needs the precision too',
        );
      });

      test('no float-emulated radical inverse remains', () {
        expect(_read(path), isNot(contains('RadicalInverseVdC')));
      });
    });
  }

  // A progressive fill seeds every band at roughness 0 before pacing the real
  // ones, so a frame that samples a still-filling environment reads a sharp
  // environment instead of the clear color. The seed is only cheap because
  // roughness 0 takes the delta-lobe shortcut, so the override has to land
  // before the sample loop reads it.
  group('mirror seed', () {
    const atlasShader = 'shaders/flutter_scene_prefilter_env.frag';

    test('the atlas prefilter can force roughness to 0', () {
      final source = _read(atlasShader);
      expect(source, contains('float force_mirror;'));
      expect(
        source.indexOf('prefilter_info.force_mirror'),
        lessThan(source.indexOf('if (roughness <= 0.0)')),
        reason: 'the override must be applied before the shortcut tests it',
      );
    });

    test('PrefilterInfo still fits the four floats Dart writes', () {
      final source = _read(atlasShader);
      final block = source.substring(
        source.indexOf('uniform PrefilterInfo {'),
        source.indexOf('prefilter_info;'),
      );
      expect(
        RegExp(r'^\s*float \w+;', multiLine: true).allMatches(block).length,
        4,
        reason:
            'env_prefilter.dart writes a Float32List(4); a fifth member grows '
            'the std140 block past what it uploads',
      );
    });
  });
}
