part of '_gpu.dart';

// Stub-backend mirrors of flutter_gpu's enums and value types. Bodies are
// declarative only - the stub is a compile-time fallback chosen when
// neither `dart.library.io` nor `dart.library.js_interop` is available
// (i.e. analyzer contexts without a concrete platform target).

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

enum StencilFace { both, front, back }

enum CompletionStatus { successful, error }

typedef CompletionCallback = void Function(CompletionStatus status);
