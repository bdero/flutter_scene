part of 'webgpu_backend.dart';

/// `GPUSampler`s by the options they encode, created once each.
final class _SamplerCache {
  _SamplerCache(this._device);

  final WebGpuDevice _device;
  final Map<int, GPUSampler> _samplers = {};

  int get length => _samplers.length;

  /// The sampler for [options]. With [nonFiltering], every filter is nearest:
  /// the copy a filtering sampler is swapped for when the bound texture
  /// cannot be filtered (see `gpu_sample_types.dart`).
  GPUSampler get(SamplerOptions options, {bool nonFiltering = false}) {
    final minFilter = nonFiltering ? MinMagFilter.nearest : options.minFilter;
    final magFilter = nonFiltering ? MinMagFilter.nearest : options.magFilter;
    final mipFilter = nonFiltering ? MipFilter.nearest : options.mipFilter;
    // WebGPU allows anisotropy only with every filter linear, and caps it at
    // 16.
    final allLinear =
        minFilter == MinMagFilter.linear &&
        magFilter == MinMagFilter.linear &&
        mipFilter == MipFilter.linear;
    final anisotropy = allLinear ? options.maxAnisotropy.clamp(1, 16) : 1;
    final key =
        minFilter.index |
        magFilter.index << 1 |
        mipFilter.index << 2 |
        options.widthAddressMode.index << 3 |
        options.heightAddressMode.index << 5 |
        anisotropy << 7;
    return _samplers[key] ??= _device.device.createSampler(
      _obj({
        'addressModeU': _addressMode(options.widthAddressMode),
        'addressModeV': _addressMode(options.heightAddressMode),
        'addressModeW': 'clamp-to-edge',
        'minFilter': minFilter.name,
        'magFilter': magFilter.name,
        'mipmapFilter': mipFilter.name,
        'maxAnisotropy': anisotropy,
      }),
    );
  }

  static String _addressMode(SamplerAddressMode mode) => switch (mode) {
    SamplerAddressMode.clampToEdge => 'clamp-to-edge',
    SamplerAddressMode.repeat => 'repeat',
    SamplerAddressMode.mirror => 'mirror-repeat',
  };
}
