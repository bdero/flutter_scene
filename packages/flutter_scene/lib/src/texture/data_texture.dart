import 'dart:typed_data';

import '../gpu/gpu.dart' as gpu;
import 'texture2d.dart';

/// The texel formats a data texture ([Texture2D.fromData], [Texture2DArray])
/// can hold.
///
/// These are the uncompressed sampleable formats every backend allocates.
/// There is no single-channel 16-bit format yet; store 16-bit data as [rg8]
/// with the high byte in red, so a filtered `r * 255.0 * 256.0 + g * 255.0` is
/// still the filtered value, or as [r32Float].
///
/// {@category Assets and loading}
enum DataTextureFormat {
  /// One 8-bit unsigned normalized channel.
  r8(gpu.PixelFormat.r8UNormInt, 1),

  /// Two 8-bit unsigned normalized channels.
  rg8(gpu.PixelFormat.r8g8UNormInt, 2),

  /// Four 8-bit unsigned normalized channels.
  rgba8(gpu.PixelFormat.r8g8b8a8UNormInt, 4),

  /// One 32-bit float channel. Samples with nearest filtering by default,
  /// since not every device filters 32-bit floats.
  r32Float(gpu.PixelFormat.r32Float, 4),

  /// Four 16-bit float channels.
  rgba16Float(gpu.PixelFormat.r16g16b16a16Float, 8),

  /// Four 32-bit float channels. Samples with nearest filtering by default,
  /// since not every device filters 32-bit floats.
  rgba32Float(gpu.PixelFormat.r32g32b32a32Float, 16);

  const DataTextureFormat(this._pixelFormat, this.bytesPerTexel);

  final gpu.PixelFormat _pixelFormat;

  /// The bytes one texel occupies.
  final int bytesPerTexel;

  bool get _is32BitFloat => this == r32Float || this == rgba32Float;

  /// The sampling a data texture of this format gets when none is given:
  /// [TextureSampling.data], with nearest filtering for the 32-bit float
  /// formats. Linear filtering of those needs device support (missing on
  /// older iOS GPUs and on WebGL2 without `OES_texture_float_linear`), where
  /// it samples black or fails, so it is opt in.
  TextureSampling get defaultSampling => _is32BitFloat
      ? const TextureSampling(
          mipmaps: false,
          minFilter: gpu.MinMagFilter.nearest,
          magFilter: gpu.MinMagFilter.nearest,
          addressMode: gpu.SamplerAddressMode.clampToEdge,
        )
      : TextureSampling.data;
}

/// The engine's pixel format for [format].
gpu.PixelFormat dataTexturePixelFormat(DataTextureFormat format) =>
    format._pixelFormat;

/// [data]'s bytes, checked to be exactly [expected] long.
ByteData dataTextureBytes(TypedData data, int expected, String what) {
  if (data.lengthInBytes != expected) {
    throw ArgumentError(
      '$what holds ${data.lengthInBytes} bytes; expected $expected.',
    );
  }
  return ByteData.sublistView(data);
}

/// A stack of same-size 2D layers in one GPU texture, sampled in a material as
/// a `sampler2DArray` with `texture(name, vec3(uv, layer))`.
///
/// Filtering is within a layer. A linear sampler blends neighbouring texels of
/// the layer it reads, never neighbouring layers, so volume data that needs
/// filtering across slices blends two layer reads in the shader.
///
/// ```dart
/// final layers = Texture2DArray.fromLayers(
///   slices, // one Uint8List of width * height bytes per layer
///   width: 256,
///   height: 256,
///   format: DataTextureFormat.r8,
/// );
/// material.parameters.setTexture(
///   'layers',
///   layers.gpuTexture,
///   sampler: layers.sampledSampler,
/// );
/// ```
///
/// {@category Assets and loading}
class Texture2DArray implements TextureSource {
  Texture2DArray._(this._texture, this.format, this._sampler);

  /// Whether the active backend can create 2D-array textures. True on the web
  /// backends, and on Metal and Vulkan with Flutter 3.50 or newer.
  static bool get isSupported => gpu.supportsTextureArrays;

  /// Uploads [layers], each [width] x [height] texels of [format], into a
  /// new 2D-array texture.
  ///
  /// Throws [UnsupportedError] where the backend has no array textures (see
  /// [isSupported]), and [ArgumentError] when a layer is not exactly one
  /// layer's bytes.
  factory Texture2DArray.fromLayers(
    List<TypedData> layers, {
    required int width,
    required int height,
    DataTextureFormat format = DataTextureFormat.rgba8,
    TextureSampling? sampling,
  }) {
    if (layers.isEmpty) {
      throw ArgumentError.value(layers, 'layers', 'needs at least one layer');
    }
    final result = Texture2DArray.empty(
      width: width,
      height: height,
      layerCount: layers.length,
      format: format,
      sampling: sampling,
    );
    for (var i = 0; i < layers.length; i++) {
      result.writeLayer(i, layers[i]);
    }
    return result;
  }

  /// Allocates a 2D-array texture without uploading anything, for data that
  /// arrives a layer at a time through [writeLayer]. Unwritten layers hold
  /// undefined contents.
  factory Texture2DArray.empty({
    required int width,
    required int height,
    required int layerCount,
    DataTextureFormat format = DataTextureFormat.rgba8,
    TextureSampling? sampling,
  }) {
    if (!isSupported) {
      throw UnsupportedError(
        'This backend has no 2D-array textures; check '
        'Texture2DArray.isSupported.',
      );
    }
    final texture = gpu.createTexture2DArray(
      gpu.StorageMode.hostVisible,
      width,
      height,
      layerCount,
      format: format._pixelFormat,
    );
    return Texture2DArray._(
      texture,
      format,
      (sampling ?? format.defaultSampling).toSamplerOptions(),
    );
  }

  final gpu.Texture _texture;
  final gpu.SamplerOptions _sampler;

  /// The format of every layer.
  final DataTextureFormat format;

  /// The underlying GPU texture, for [MaterialParameters.setTexture].
  gpu.Texture get gpuTexture => _texture;

  @override
  gpu.Texture? get sampledTexture => _texture;

  @override
  gpu.SamplerOptions get sampledSampler => _sampler;

  /// The width of each layer in texels.
  int get width => _texture.width;

  /// The height of each layer in texels.
  int get height => _texture.height;

  /// The number of layers.
  int get layerCount => gpu.textureLayerCount(_texture);

  /// The bytes one layer holds.
  int get layerByteSize => width * height * format.bytesPerTexel;

  /// The GPU memory the texels occupy, excluding any driver padding.
  int get byteSize => layerByteSize * layerCount;

  /// Replaces layer [layer] with [data], exactly one layer of texels.
  // TODO(data-texture-regions): sub-rectangle writes need region uploads in
  // Flutter GPU; until then a partial update rewrites the whole layer.
  void writeLayer(int layer, TypedData data) {
    RangeError.checkValidIndex(layer, this, 'layer', layerCount);
    _texture.overwrite(
      dataTextureBytes(data, layerByteSize, 'Layer $layer'),
      slice: layer,
    );
  }
}
