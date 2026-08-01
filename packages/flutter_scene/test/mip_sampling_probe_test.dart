// Covers the mip sampling measurement itself: on a healthy backend the
// minified draw reads the black upper mips, so the probe reports working
// sampling. GPU-gated like the other render suites.

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

void main() {
  if (!_gpuAvailable()) {
    test(
      'mip sampling probe (skipped: no GPU device)',
      () {},
      skip: 'Requires a GPU device.',
    );
    return;
  }

  test('measures working mip sampling on a healthy backend', () async {
    await Scene.initializeStaticResources();
    expect(await measureMipSampling(), isTrue);
  });
}
