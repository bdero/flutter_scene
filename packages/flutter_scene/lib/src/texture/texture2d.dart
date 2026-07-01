import 'dart:ui' as ui;

import 'package:flutter/services.dart';

import '../asset_helpers.dart';
import '../gpu/gpu.dart' as gpu;
import 'mipmap.dart';

/// Something a material can sample: it yields the GPU texture to sample for the
/// current frame and the sampler to bind it with. Implemented by [Texture2D]
/// (a static image) and `RenderTexture` (a live, rendered-into texture).
///
/// {@category Assets and loading}
abstract interface class TextureSource {
  /// The GPU texture to sample this frame, or null when none is available yet
  /// (a live source before its first frame; callers substitute a placeholder).
  gpu.Texture? get sampledTexture;

  /// The sampler this source is bound with.
  gpu.SamplerOptions get sampledSampler;
}

/// Wraps a raw [gpu.Texture] as a [TextureSource], for advanced or interop
/// cases that already own a GPU texture (widget/particle textures, custom
/// pipelines) and do not need [Texture2D]'s image decode and mip generation.
///
/// {@category Assets and loading}
class GpuTextureSource implements TextureSource {
  GpuTextureSource(this.texture, {gpu.SamplerOptions? sampler})
    : sampler =
          sampler ??
          gpu.SamplerOptions(
            minFilter: gpu.MinMagFilter.linear,
            magFilter: gpu.MinMagFilter.linear,
            widthAddressMode: gpu.SamplerAddressMode.repeat,
            heightAddressMode: gpu.SamplerAddressMode.repeat,
          );

  final gpu.Texture texture;
  final gpu.SamplerOptions sampler;

  @override
  gpu.Texture? get sampledTexture => texture;

  @override
  gpu.SamplerOptions get sampledSampler => sampler;
}

/// How a texture is sampled. The defaults are trilinear, anisotropic, and
/// mipmapped, the tasteful default for material textures viewed in 3D.
///
/// {@category Assets and loading}
class TextureSampling {
  const TextureSampling({
    this.mipmaps = true,
    this.maxMipmapLevels,
    this.minFilter = gpu.MinMagFilter.linear,
    this.magFilter = gpu.MinMagFilter.linear,
    this.mipFilter = gpu.MipFilter.linear,
    this.maxAnisotropy = 8,
    this.addressMode = gpu.SamplerAddressMode.repeat,
  });

  /// Whether the texture carries a mip chain (built at creation) and is sampled
  /// with mip filtering. Turn off for UI/full-screen sources never minified.
  final bool mipmaps;

  /// Caps the number of mip levels generated (null builds the full chain).
  /// A texture atlas uses this so tiles stop shrinking before they merge into
  /// their neighbors across the padding gutter.
  final int? maxMipmapLevels;

  final gpu.MinMagFilter minFilter;
  final gpu.MinMagFilter magFilter;
  final gpu.MipFilter mipFilter;

  /// Maximum anisotropy (clamped to the device max). 1 disables it.
  final int maxAnisotropy;

  final gpu.SamplerAddressMode addressMode;

  gpu.SamplerOptions toSamplerOptions() {
    final effectiveMipFilter = mipmaps ? mipFilter : gpu.MipFilter.nearest;
    // Anisotropic filtering requires linear min/mag/mip filtering; pairing it
    // with any nearest filter is rejected, so drop it when a filter is nearest
    // (e.g. a mipmaps-off UI texture).
    final allLinear =
        minFilter == gpu.MinMagFilter.linear &&
        magFilter == gpu.MinMagFilter.linear &&
        effectiveMipFilter == gpu.MipFilter.linear;
    return gpu.SamplerOptions(
      minFilter: minFilter,
      magFilter: magFilter,
      mipFilter: effectiveMipFilter,
      widthAddressMode: addressMode,
      heightAddressMode: addressMode,
      maxAnisotropy: allLinear ? maxAnisotropy : 1,
    );
  }
}

/// A 2D image texture ready to bind to a material's texture slot.
///
/// Create one from an asset ([fromAsset]), a decoded `dart:ui` image
/// ([fromImage]), or raw RGBA pixels ([fromPixels]). A mip chain is generated
/// at creation, downsampled correctly for the texture's [TextureContent] (sRGB
/// color averaged in linear light, normals renormalized), and the texture
/// carries its own [TextureSampling] (trilinear + anisotropic by default).
///
/// ```dart
/// final albedo = await Texture2D.fromAsset('assets/brick_color.png');
/// final normal = await Texture2D.fromAsset('assets/brick_normal.png',
///     content: TextureContent.normal);
/// material.baseColorTexture = albedo;
/// material.normalTexture = normal;
/// ```
/// {@category Assets and loading}
class Texture2D implements TextureSource {
  Texture2D._(this._texture, this._sampler);

  final gpu.Texture _texture;
  final gpu.SamplerOptions _sampler;

  /// The underlying GPU texture, for advanced/interop use.
  gpu.Texture get gpuTexture => _texture;

  @override
  gpu.Texture? get sampledTexture => _texture;

  @override
  gpu.SamplerOptions get sampledSampler => _sampler;

  /// Builds a texture from RGBA8888 [pixels] (straight alpha, row-major) of
  /// [width] x [height].
  static Texture2D fromPixels(
    Uint8List pixels,
    int width,
    int height, {
    TextureContent content = TextureContent.color,
    TextureSampling sampling = const TextureSampling(),
  }) {
    var levels = sampling.mipmaps
        ? generateMipChain(pixels, width, height, content)
        : <MipLevel>[MipLevel(width, height, pixels)];
    // The GPU allocator caps mip levels at fullMipCount (floor(log2(min(w, h)))),
    // which is below the canonical chain length for non-square textures, so
    // clamp before requesting the texture or creation throws a range error.
    final maxLevels = gpu.Texture.fullMipCount(width, height);
    final cap = sampling.maxMipmapLevels;
    final limit = cap != null && cap >= 1 && cap < maxLevels ? cap : maxLevels;
    if (limit < levels.length) {
      levels = levels.sublist(0, limit);
    }
    final texture = gpu.gpuContext.createTexture(
      gpu.StorageMode.hostVisible,
      width,
      height,
      mipLevelCount: levels.length,
    );
    for (var i = 0; i < levels.length; i++) {
      texture.overwrite(ByteData.sublistView(levels[i].pixels), mipLevel: i);
    }
    return Texture2D._(texture, sampling.toSamplerOptions());
  }

  /// Builds a texture from a decoded [image].
  static Future<Texture2D> fromImage(
    ui.Image image, {
    TextureContent content = TextureContent.color,
    TextureSampling sampling = const TextureSampling(),
  }) async {
    final bytes = await image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    if (bytes == null) {
      throw Exception('Failed to read RGBA data from image.');
    }
    return fromPixels(
      bytes.buffer.asUint8List(),
      image.width,
      image.height,
      content: content,
      sampling: sampling,
    );
  }

  /// Loads, decodes, and uploads the image asset at [assetPath].
  static Future<Texture2D> fromAsset(
    String assetPath, {
    TextureContent content = TextureContent.color,
    TextureSampling sampling = const TextureSampling(),
    AssetBundle? bundle,
  }) async {
    final image = await imageFromAsset(assetPath, bundle: bundle);
    try {
      return await fromImage(image, content: content, sampling: sampling);
    } finally {
      image.dispose();
    }
  }
}
