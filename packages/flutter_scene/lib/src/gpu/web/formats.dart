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
}

enum TextureCoordinateSystem { uploadFromHost, renderToTexture }

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
