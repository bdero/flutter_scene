/// Covers TextureSampling.toSamplerOptions: the trilinear + anisotropic
/// defaults, and the guard that drops anisotropy when a filter is nearest
/// (which the backend rejects).
library;

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/texture/texture2d.dart';
import 'package:test/test.dart';

void main() {
  test('defaults are trilinear and anisotropic', () {
    final options = const TextureSampling().toSamplerOptions();
    expect(options.minFilter, gpu.MinMagFilter.linear);
    expect(options.magFilter, gpu.MinMagFilter.linear);
    expect(options.mipFilter, gpu.MipFilter.linear);
    expect(options.maxAnisotropy, 8);
  });

  test(
    'disabling mipmaps forces a nearest mip filter and drops anisotropy',
    () {
      // A nearest mip filter cannot be paired with anisotropy > 1, so the guard
      // must clamp it back to 1 to keep the sampler valid.
      final options = const TextureSampling(mipmaps: false).toSamplerOptions();
      expect(options.mipFilter, gpu.MipFilter.nearest);
      expect(options.maxAnisotropy, 1);
    },
  );

  test('a nearest min filter also drops anisotropy', () {
    final options = const TextureSampling(
      minFilter: gpu.MinMagFilter.nearest,
    ).toSamplerOptions();
    expect(options.maxAnisotropy, 1);
  });
}
