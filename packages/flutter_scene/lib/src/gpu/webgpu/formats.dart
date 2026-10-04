part of 'webgpu_backend.dart';

/// How a [PixelFormat] maps onto WebGPU.
final class _GpuFormat {
  const _GpuFormat(
    this.name, {
    this.bytesPerBlock = 4,
    this.blockSize = 1,
    this.depth = false,
    this.stencil = false,
    this.float32 = false,
    this.feature,
  });

  /// The `GPUTextureFormat`.
  final String name;

  /// Bytes per texel, or per block for compressed formats.
  final int bytesPerBlock;

  /// Block edge in texels; 1 for uncompressed formats.
  final int blockSize;

  final bool depth;
  final bool stencil;

  /// A 32-bit float format, filterable only with `float32-filterable`.
  final bool float32;

  /// The device feature the format needs, if any.
  final String? feature;

  bool get compressed => blockSize > 1;
  bool get depthOrStencil => depth || stencil;
}

const String _bc = 'texture-compression-bc';
const String _etc2 = 'texture-compression-etc2';
const String _astc = 'texture-compression-astc';

/// Formats the backend supports. WebGPU has no alpha-only format, no
/// extended-range (XR) formats, and no HDR ASTC, so those are absent.
const Map<PixelFormat, _GpuFormat> _formats = {
  PixelFormat.r8UNormInt: _GpuFormat('r8unorm', bytesPerBlock: 1),
  PixelFormat.r8g8UNormInt: _GpuFormat('rg8unorm', bytesPerBlock: 2),
  PixelFormat.r8g8b8a8UNormInt: _GpuFormat('rgba8unorm'),
  PixelFormat.r8g8b8a8UNormIntSRGB: _GpuFormat('rgba8unorm-srgb'),
  PixelFormat.b8g8r8a8UNormInt: _GpuFormat('bgra8unorm'),
  PixelFormat.b8g8r8a8UNormIntSRGB: _GpuFormat('bgra8unorm-srgb'),
  PixelFormat.r16g16b16a16Float: _GpuFormat('rgba16float', bytesPerBlock: 8),
  PixelFormat.r32g32b32a32Float: _GpuFormat(
    'rgba32float',
    bytesPerBlock: 16,
    float32: true,
  ),
  PixelFormat.r32Float: _GpuFormat('r32float', float32: true),
  PixelFormat.s8UInt: _GpuFormat('stencil8', bytesPerBlock: 1, stencil: true),
  PixelFormat.d24UnormS8Uint: _GpuFormat(
    'depth24plus-stencil8',
    depth: true,
    stencil: true,
  ),
  PixelFormat.d32FloatS8UInt: _GpuFormat(
    'depth32float-stencil8',
    bytesPerBlock: 5,
    depth: true,
    stencil: true,
    feature: 'depth32float-stencil8',
  ),
  PixelFormat.bc1RGBAUNormInt: _GpuFormat(
    'bc1-rgba-unorm',
    bytesPerBlock: 8,
    blockSize: 4,
    feature: _bc,
  ),
  PixelFormat.bc1RGBAUNormIntSRGB: _GpuFormat(
    'bc1-rgba-unorm-srgb',
    bytesPerBlock: 8,
    blockSize: 4,
    feature: _bc,
  ),
  PixelFormat.bc3RGBAUNormInt: _GpuFormat(
    'bc3-rgba-unorm',
    bytesPerBlock: 16,
    blockSize: 4,
    feature: _bc,
  ),
  PixelFormat.bc3RGBAUNormIntSRGB: _GpuFormat(
    'bc3-rgba-unorm-srgb',
    bytesPerBlock: 16,
    blockSize: 4,
    feature: _bc,
  ),
  PixelFormat.bc5RGUNormInt: _GpuFormat(
    'bc5-rg-unorm',
    bytesPerBlock: 16,
    blockSize: 4,
    feature: _bc,
  ),
  PixelFormat.bc7RGBAUNormInt: _GpuFormat(
    'bc7-rgba-unorm',
    bytesPerBlock: 16,
    blockSize: 4,
    feature: _bc,
  ),
  PixelFormat.bc7RGBAUNormIntSRGB: _GpuFormat(
    'bc7-rgba-unorm-srgb',
    bytesPerBlock: 16,
    blockSize: 4,
    feature: _bc,
  ),
  PixelFormat.etc2RGB8UNormInt: _GpuFormat(
    'etc2-rgb8unorm',
    bytesPerBlock: 8,
    blockSize: 4,
    feature: _etc2,
  ),
  PixelFormat.etc2RGB8UNormIntSRGB: _GpuFormat(
    'etc2-rgb8unorm-srgb',
    bytesPerBlock: 8,
    blockSize: 4,
    feature: _etc2,
  ),
  PixelFormat.etc2RGBA8UNormInt: _GpuFormat(
    'etc2-rgba8unorm',
    bytesPerBlock: 16,
    blockSize: 4,
    feature: _etc2,
  ),
  PixelFormat.etc2RGBA8UNormIntSRGB: _GpuFormat(
    'etc2-rgba8unorm-srgb',
    bytesPerBlock: 16,
    blockSize: 4,
    feature: _etc2,
  ),
  PixelFormat.astc4x4LDR: _GpuFormat(
    'astc-4x4-unorm',
    bytesPerBlock: 16,
    blockSize: 4,
    feature: _astc,
  ),
  PixelFormat.astc4x4LDRSRGB: _GpuFormat(
    'astc-4x4-unorm-srgb',
    bytesPerBlock: 16,
    blockSize: 4,
    feature: _astc,
  ),
  PixelFormat.astc8x8LDR: _GpuFormat(
    'astc-8x8-unorm',
    bytesPerBlock: 16,
    blockSize: 8,
    feature: _astc,
  ),
  PixelFormat.astc8x8LDRSRGB: _GpuFormat(
    'astc-8x8-unorm-srgb',
    bytesPerBlock: 16,
    blockSize: 8,
    feature: _astc,
  ),
};

/// The WebGPU format for [format] on [device], substituting where the device
/// lacks a feature the engine can do without.
_GpuFormat _gpuFormatFor(PixelFormat format, WebGpuDevice device) {
  final entry = _formats[format];
  if (entry == null) {
    throw UnsupportedError('The WebGPU backend has no format for $format.');
  }
  final feature = entry.feature;
  if (feature == null || device.hasFeature(feature)) return entry;
  if (format == PixelFormat.d32FloatS8UInt) {
    // Same as WebGL2 without float depth: 24-bit depth renders the same with
    // standard precision.
    return _formats[PixelFormat.d24UnormS8Uint]!;
  }
  throw UnsupportedError(
    '$format needs the "$feature" WebGPU feature, which this device lacks; '
    'check GpuContext.supportsTextureCompression first.',
  );
}
