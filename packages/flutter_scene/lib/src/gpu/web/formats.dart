part of '_gpu.dart';

// Enum order and naming must match `package:flutter_gpu` exactly so
// consumer code typechecks the same way on both backends. Comments
// abbreviated; see flutter_gpu/src/formats.dart for authoritative docs.

enum StorageMode { hostVisible, devicePrivate, deviceTransient }

enum PixelFormat {
  unknown,
  a8UNormInt,
  r8UNormInt,
  r8g8UNormInt,
  r8g8b8a8UNormInt,
  r8g8b8a8UNormIntSRGB,
  b8g8r8a8UNormInt,
  b8g8r8a8UNormIntSRGB,
  r32g32b32a32Float,
  r16g16b16a16Float,
  b10g10r10XR,
  b10g10r10XRSRGB,
  b10g10r10a10XR,
  s8UInt,
  d24UnormS8Uint,
  d32FloatS8UInt,
  // Block-compressed (sample-only) formats. Support varies by family; check
  // GpuContext.supportsTextureCompression before allocating.
  bc1RGBAUNormInt,
  bc1RGBAUNormIntSRGB,
  bc3RGBAUNormInt,
  bc3RGBAUNormIntSRGB,
  bc5RGUNormInt,
  bc7RGBAUNormInt,
  bc7RGBAUNormIntSRGB,
  etc2RGB8UNormInt,
  etc2RGB8UNormIntSRGB,
  etc2RGBA8UNormInt,
  etc2RGBA8UNormIntSRGB,
  astc4x4LDR,
  astc4x4LDRSRGB,
  astc8x8LDR,
  astc8x8LDRSRGB,
  astc4x4HDR,
  astc8x8HDR;

  /// Whether this is a block-compressed (sample-only) format.
  bool get isCompressed {
    switch (this) {
      case PixelFormat.bc1RGBAUNormInt:
      case PixelFormat.bc1RGBAUNormIntSRGB:
      case PixelFormat.bc3RGBAUNormInt:
      case PixelFormat.bc3RGBAUNormIntSRGB:
      case PixelFormat.bc5RGUNormInt:
      case PixelFormat.bc7RGBAUNormInt:
      case PixelFormat.bc7RGBAUNormIntSRGB:
      case PixelFormat.etc2RGB8UNormInt:
      case PixelFormat.etc2RGB8UNormIntSRGB:
      case PixelFormat.etc2RGBA8UNormInt:
      case PixelFormat.etc2RGBA8UNormIntSRGB:
      case PixelFormat.astc4x4LDR:
      case PixelFormat.astc4x4LDRSRGB:
      case PixelFormat.astc8x8LDR:
      case PixelFormat.astc8x8LDRSRGB:
      case PixelFormat.astc4x4HDR:
      case PixelFormat.astc8x8HDR:
        return true;
      default:
        return false;
    }
  }
}

/// Hardware families for block-compressed texture support.
enum TextureCompressionFamily { bc, etc2, astc, astcHdr }

enum BlendFactor {
  zero,
  one,
  sourceColor,
  oneMinusSourceColor,
  sourceAlpha,
  oneMinusSourceAlpha,
  destinationColor,
  oneMinusDestinationColor,
  destinationAlpha,
  oneMinusDestinationAlpha,
  sourceAlphaSaturated,
  blendColor,
  oneMinusBlendColor,
  blendAlpha,
  oneMinusBlendAlpha,
}

enum BlendOperation { add, subtract, reverseSubtract }

enum LoadAction { dontCare, load, clear }

enum StoreAction {
  dontCare,
  store,
  multisampleResolve,
  storeAndMultisampleResolve,
}

enum ShaderStage { vertex, fragment }

enum MinMagFilter { nearest, linear }

enum MipFilter { nearest, linear }

enum SamplerAddressMode { clampToEdge, repeat, mirror }

enum IndexType { int16, int32 }

enum PrimitiveType { triangle, triangleStrip, line, lineStrip, point }

enum CullMode { none, frontFace, backFace }

enum WindingOrder { clockwise, counterClockwise }

enum PolygonMode { fill, line }

enum CompareFunction {
  never,
  always,
  less,
  equal,
  lessEqual,
  greater,
  notEqual,
  greaterEqual,
}

enum StencilOperation {
  keep,
  zero,
  setToReferenceValue,
  incrementClamp,
  decrementClamp,
  invert,
  incrementWrap,
  decrementWrap,
}

enum TextureType {
  texture2D,
  texture2DMultisample,
  textureCube,
  textureExternalOES,
}
