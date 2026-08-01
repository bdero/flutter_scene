/// Covers TextureSampling.toSamplerOptions: the trilinear + anisotropic
/// defaults, and the guard that drops anisotropy when a filter is nearest
/// (which the backend rejects). Also covers GpuTextureSource picking the same
/// defaults for a texture it did not build, which is GPU-gated.
library;

import 'package:flutter_scene/scene.dart' show Scene;
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/texture/texture2d.dart';
import 'package:flutter_test/flutter_test.dart';

bool _gpuAvailable() {
  try {
    Scene();
    return true;
  } catch (_) {
    return false;
  }
}

// 8x8 so the mipped case has levels to ask for (the allocator caps a 4x4 at 2).
gpu.Texture _texture({required int mipLevelCount}) =>
    gpu.gpuContext.createTexture(
      gpu.StorageMode.hostVisible,
      8,
      8,
      mipLevelCount: mipLevelCount,
    );

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

  group('GpuTextureSource default sampler', () {
    if (!_gpuAvailable()) {
      // ignore: avoid_print
      print('GPU unavailable - skipping.');
      return;
    }

    test('a mipped texture filters like a Texture2D', () {
      final sampler = GpuTextureSource(_texture(mipLevelCount: 3)).sampler;
      expect(sampler.mipFilter, gpu.MipFilter.linear);
      expect(sampler.maxAnisotropy, TextureSampling.defaultMaxAnisotropy);
      expect(
        sampler.maxAnisotropy,
        const TextureSampling().toSamplerOptions().maxAnisotropy,
      );
    });

    test('a mipless texture drops mip filtering and anisotropy', () {
      final sampler = GpuTextureSource(_texture(mipLevelCount: 1)).sampler;
      expect(sampler.mipFilter, gpu.MipFilter.nearest);
      expect(sampler.maxAnisotropy, 1);
    });

    test('an explicit sampler is passed through untouched', () {
      final explicit = gpu.SamplerOptions(maxAnisotropy: 4);
      expect(
        GpuTextureSource(_texture(mipLevelCount: 3), sampler: explicit).sampler,
        same(explicit),
      );
    });
  });
}
