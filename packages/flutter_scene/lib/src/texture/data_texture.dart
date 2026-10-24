import 'dart:typed_data';

import '../gpu/gpu.dart' as gpu;
import 'texture2d.dart';

/// The pixel formats a data texture ([Texture2D.fromData], [Texture2DArray],
/// [Texture3D]) can hold, with their size per texel.
///
/// These are the uncompressed sampleable formats every backend allocates.
/// Single-channel 16-bit formats (`r16`, `r16Float`) are absent because Flutter
/// GPU has none; store 16-bit data as `r8g8UNormInt` (high byte in red, so a
/// filtered `r * 255.0 * 256.0 + g * 255.0` is still the filtered value) or as
/// `r32Float`.
const Map<gpu.PixelFormat, int> dataTextureBytesPerTexel = {
  gpu.PixelFormat.r8UNormInt: 1,
  gpu.PixelFormat.r8g8UNormInt: 2,
  gpu.PixelFormat.r8g8b8a8UNormInt: 4,
  gpu.PixelFormat.r32Float: 4,
  gpu.PixelFormat.r16g16b16a16Float: 8,
  gpu.PixelFormat.r32g32b32a32Float: 16,
};

int _bytesPerTexel(gpu.PixelFormat format) =>
    dataTextureBytesPerTexel[format] ??
    (throw ArgumentError.value(
      format,
      'format',
      'Not a data texture format; use one of '
          '${dataTextureBytesPerTexel.keys.map((f) => f.name).join(', ')}',
    ));

/// [data]'s bytes, checked to be exactly [expected] long.
ByteData _texelBytes(TypedData data, int expected, String what) {
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
/// Filtering is within a layer: a linear sampler blends neighbouring texels of
/// the layer it reads, never neighbouring layers. Volume data that needs
/// filtering across slices blends two layer reads in the shader, or uses a
/// [Texture3D] where the backend has one.
///
/// ```dart
/// final layers = Texture2DArray.fromLayers(
///   [for (final slice in slices) slice], // Uint8List of width * height
///   width: 256,
///   height: 256,
///   format: gpu.PixelFormat.r8UNormInt,
/// );
/// material.parameters.setTexture(
///   'layers',
///   layers.gpuTexture,
///   sampler: layers.sampledSampler,
/// );
/// ```
/// {@category Assets and loading}
class Texture2DArray implements TextureSource {
  Texture2DArray._(this._texture, this._sampler);

  /// Uploads [layers], each [width] x [height] texels of [format], into a
  /// new 2D-array texture.
  ///
  /// Throws [UnsupportedError] where the backend has no array textures, and
  /// [ArgumentError] when a layer is not exactly one layer's bytes. Check
  /// `gpuLimits.fitsTextureArray` before allocating large stacks.
  factory Texture2DArray.fromLayers(
    List<TypedData> layers, {
    required int width,
    required int height,
    gpu.PixelFormat format = gpu.PixelFormat.r8g8b8a8UNormInt,
    TextureSampling sampling = TextureSampling.data,
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
    gpu.PixelFormat format = gpu.PixelFormat.r8g8b8a8UNormInt,
    TextureSampling sampling = TextureSampling.data,
  }) {
    _bytesPerTexel(format);
    if (!gpu.gpuContext.doesSupportTextureArrays) {
      throw UnsupportedError(
        'This backend has no 2D-array textures; check '
        'gpuLimits.supportsTextureArrays.',
      );
    }
    final texture = gpu.gpuContext.createTexture(
      gpu.StorageMode.hostVisible,
      width,
      height,
      format: format,
      textureType: gpu.TextureType.texture2DArray,
      enableRenderTargetUsage: false,
      layerCount: layerCount,
    );
    return Texture2DArray._(texture, sampling.toSamplerOptions());
  }

  final gpu.Texture _texture;
  final gpu.SamplerOptions _sampler;

  /// The underlying GPU texture, for [MaterialParameters.setTexture] and
  /// other advanced use.
  gpu.Texture get gpuTexture => _texture;

  @override
  gpu.Texture? get sampledTexture => _texture;

  @override
  gpu.SamplerOptions get sampledSampler => _sampler;

  int get width => _texture.width;
  int get height => _texture.height;
  int get layerCount => _texture.layerCount;
  gpu.PixelFormat get format => _texture.format;

  /// The bytes one layer holds.
  int get layerByteSize => width * height * _bytesPerTexel(format);

  /// The GPU memory the texels occupy, excluding any driver padding.
  int get byteSize => layerByteSize * layerCount;

  /// Replaces layer [layer] with [data], exactly one layer of texels.
  void writeLayer(int layer, TypedData data) {
    RangeError.checkValidIndex(layer, this, 'layer', layerCount);
    _texture.overwrite(
      _texelBytes(data, layerByteSize, 'Layer $layer'),
      slice: layer,
    );
  }
}

/// A volume of texels in one GPU texture, sampled in a material as a
/// `sampler3D` with `texture(name, uvw)`, with hardware trilinear filtering
/// across all three axes.
///
/// Only the web backends (WebGL2 and WebGPU) have 3D textures; Flutter GPU on
/// native has none. Check [isSupported] and fall back to a [Texture2DArray].
/// {@category Assets and loading}
class Texture3D implements TextureSource {
  Texture3D._(this._texture, this._sampler);

  /// Whether the active backend can create 3D textures.
  static bool get isSupported => gpu.gpuLimits.supports3DTextures;

  /// Uploads [voxels], [width] x [height] x [depth] texels of [format] laid
  /// out row by row and slice by slice, into a new 3D texture.
  factory Texture3D.fromVoxels(
    TypedData voxels, {
    required int width,
    required int height,
    required int depth,
    gpu.PixelFormat format = gpu.PixelFormat.r8g8b8a8UNormInt,
    TextureSampling sampling = TextureSampling.data,
  }) {
    final result = Texture3D.empty(
      width: width,
      height: height,
      depth: depth,
      format: format,
      sampling: sampling,
    );
    final sliceBytes = result.sliceByteSize;
    _texelBytes(voxels, sliceBytes * depth, 'The volume');
    final bytes = Uint8List.sublistView(voxels);
    for (var z = 0; z < depth; z++) {
      result.writeSlice(
        z,
        Uint8List.sublistView(bytes, z * sliceBytes, (z + 1) * sliceBytes),
      );
    }
    return result;
  }

  /// Allocates a 3D texture without uploading anything, for data that arrives
  /// a slice at a time through [writeSlice].
  factory Texture3D.empty({
    required int width,
    required int height,
    required int depth,
    gpu.PixelFormat format = gpu.PixelFormat.r8g8b8a8UNormInt,
    TextureSampling sampling = TextureSampling.data,
  }) {
    _bytesPerTexel(format);
    final texture = gpu.createTexture3D(
      gpu.StorageMode.hostVisible,
      width,
      height,
      depth,
      format: format,
    );
    return Texture3D._(texture, sampling.toSamplerOptions());
  }

  final gpu.Texture _texture;
  final gpu.SamplerOptions _sampler;

  /// The underlying GPU texture, for [MaterialParameters.setTexture] and
  /// other advanced use.
  gpu.Texture get gpuTexture => _texture;

  @override
  gpu.Texture? get sampledTexture => _texture;

  @override
  gpu.SamplerOptions get sampledSampler => _sampler;

  int get width => _texture.width;
  int get height => _texture.height;
  int get depth => gpu.textureDepth(_texture);
  gpu.PixelFormat get format => _texture.format;

  /// The bytes one depth slice holds.
  int get sliceByteSize => width * height * _bytesPerTexel(format);

  /// The GPU memory the texels occupy, excluding any driver padding.
  int get byteSize => sliceByteSize * depth;

  /// Replaces depth slice [z] with [data], exactly one slice of texels.
  void writeSlice(int z, TypedData data) {
    RangeError.checkValidIndex(z, this, 'z', depth);
    _texture.overwrite(_texelBytes(data, sliceByteSize, 'Slice $z'), slice: z);
  }
}
