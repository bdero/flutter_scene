// Covers the mip sampling measurement itself: on a healthy backend the
// minified draw reads the black upper mips, so the probe reports working
// sampling. GPU-gated like the other render suites.

import 'dart:typed_data';

import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';

// ignore: implementation_imports
import 'package:flutter_scene/src/render/mip_sampling_probe.dart';

bool _gpuAvailable() {
  try {
    Scene();
    return true;
  } catch (_) {
    return false;
  }
}

// Static initialization swallows a failed shader-bundle load (it logs and
// resets so a later call retries), so a completed future does not mean the
// library is there. Under `flutter test` the bundle asset is usually absent,
// and anything touching `baseShaderLibrary` has to skip rather than throw.
Future<bool> _shaderLibraryReady() async {
  await Scene.initializeStaticResources();
  try {
    baseShaderLibrary;
    return true;
  } catch (_) {
    // ignore: avoid_print
    print('Base shader bundle unavailable - skipping.');
    return false;
  }
}

void main() {
  group('mipChainsAreSampled', () {
    tearDown(() => platformMipSamplingWorks = null);

    test('is true until a probe positively measures the clamp', () {
      expect(mipChainsAreSampled, isTrue);
      platformMipSamplingWorks = true;
      expect(mipChainsAreSampled, isTrue);
    });

    test('is false only for a measured clamp', () {
      platformMipSamplingWorks = false;
      expect(mipChainsAreSampled, isFalse);
    });

    test('an unresolved probe leaves mip chains alone', () {
      // A probe that threw leaves the result null rather than asserting the
      // defect, so a healthy device never loses its mipmaps to a failed
      // measurement. Radiance layout selection reads the same null as "stay on
      // the atlas", which is safe in the other direction.
      platformMipSamplingWorks = null;
      expect(mipChainsAreSampled, isTrue);
      expect(
        EnvironmentMap.shouldUseMipRadianceLayout(
          isWeb: false,
          targetPlatform: TargetPlatform.android,
          backendSupportsMips: true,
          platformMipSamplingWorks: null,
        ),
        isFalse,
      );
    });
  });

  if (!_gpuAvailable()) {
    test(
      'mip sampling probe (skipped: no GPU device)',
      () {},
      skip: 'Requires a GPU device.',
    );
    return;
  }

  test('measures working mip sampling on a healthy backend', () async {
    if (!await _shaderLibraryReady()) return;
    expect(await measureMipSampling(), isTrue);
  });

  test('a measured clamp drops the uploaded chain to the base level', () async {
    await Scene.initializeStaticResources();

    addTearDown(() => platformMipSamplingWorks = null);
    final pixels = Uint8List(16 * 16 * 4);

    platformMipSamplingWorks = true;
    expect(
      Texture2D.fromPixels(pixels, 16, 16).gpuTexture.mipLevelCount,
      greaterThan(1),
    );

    platformMipSamplingWorks = false;
    expect(Texture2D.fromPixels(pixels, 16, 16).gpuTexture.mipLevelCount, 1);
  });
}
