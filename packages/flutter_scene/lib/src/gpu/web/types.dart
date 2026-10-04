part of '_gpu.dart';

// Plain data shared by every web backend: descriptions of resources and
// state, holding no backend objects of their own.

/// A reference to a byte range within a GPU-resident [DeviceBuffer].
class BufferView {
  const BufferView(
    this.buffer, {
    required this.offsetInBytes,
    required this.lengthInBytes,
  });

  final DeviceBuffer buffer;
  final int offsetInBytes;
  final int lengthInBytes;
}

// ---------------------------------------------------------------------------
// Render-target value types (mirroring flutter_gpu).
// ---------------------------------------------------------------------------

base class ColorAttachment {
  ColorAttachment({
    this.loadAction = LoadAction.clear,
    this.storeAction = StoreAction.store,
    vm.Vector4? clearValue,
    required this.texture,
    this.mipLevel = 0,
    this.slice = 0,
    this.resolveTexture,
  }) : clearValue = clearValue ?? vm.Vector4.zero();

  LoadAction loadAction;
  StoreAction storeAction;
  vm.Vector4 clearValue;
  Texture texture;

  /// The mip level of [texture] to render into.
  int mipLevel;

  /// The slice of [texture] to render into. Cubemap textures are not
  /// supported on the web backend, so this must be 0.
  // TODO(rendertarget): cubemap slices on the web backend.
  int slice;

  Texture? resolveTexture;
}

base class DepthStencilAttachment {
  DepthStencilAttachment({
    this.depthLoadAction = LoadAction.clear,
    this.depthStoreAction = StoreAction.dontCare,
    this.depthClearValue = 0.0,
    this.stencilLoadAction = LoadAction.clear,
    this.stencilStoreAction = StoreAction.dontCare,
    this.stencilClearValue = 0,
    required this.texture,
    this.mipLevel = 0,
    this.slice = 0,
  });

  LoadAction depthLoadAction;
  StoreAction depthStoreAction;
  double depthClearValue;
  LoadAction stencilLoadAction;
  StoreAction stencilStoreAction;
  int stencilClearValue;
  Texture texture;

  /// The mip level of [texture] to render into.
  int mipLevel;

  /// The slice of [texture] to render into. Cubemap textures are not
  /// supported on the web backend, so this must be 0.
  int slice;
}

base class StencilConfig {
  StencilConfig({
    this.compareFunction = CompareFunction.always,
    this.stencilFailureOperation = StencilOperation.keep,
    this.depthFailureOperation = StencilOperation.keep,
    this.depthStencilPassOperation = StencilOperation.keep,
    this.readMask = 0xFFFFFFFF,
    this.writeMask = 0xFFFFFFFF,
  });

  CompareFunction compareFunction;
  StencilOperation stencilFailureOperation;
  StencilOperation depthFailureOperation;
  StencilOperation depthStencilPassOperation;
  int readMask;
  int writeMask;
}

enum StencilFace { both, front, back }

base class ColorBlendEquation {
  ColorBlendEquation({
    this.colorBlendOperation = BlendOperation.add,
    this.sourceColorBlendFactor = BlendFactor.one,
    this.destinationColorBlendFactor = BlendFactor.oneMinusSourceAlpha,
    this.alphaBlendOperation = BlendOperation.add,
    this.sourceAlphaBlendFactor = BlendFactor.one,
    this.destinationAlphaBlendFactor = BlendFactor.oneMinusSourceAlpha,
  });

  BlendOperation colorBlendOperation;
  BlendFactor sourceColorBlendFactor;
  BlendFactor destinationColorBlendFactor;
  BlendOperation alphaBlendOperation;
  BlendFactor sourceAlphaBlendFactor;
  BlendFactor destinationAlphaBlendFactor;
}

base class SamplerOptions {
  SamplerOptions({
    this.minFilter = MinMagFilter.nearest,
    this.magFilter = MinMagFilter.nearest,
    this.mipFilter = MipFilter.nearest,
    this.widthAddressMode = SamplerAddressMode.clampToEdge,
    this.heightAddressMode = SamplerAddressMode.clampToEdge,
    this.maxAnisotropy = 1,
  });

  MinMagFilter minFilter;
  MinMagFilter magFilter;
  MipFilter mipFilter;
  SamplerAddressMode widthAddressMode;
  SamplerAddressMode heightAddressMode;

  /// The maximum anisotropy clamp used when sampling. The default value of 1
  /// disables anisotropic filtering. Mirrors `package:flutter_gpu`; applied via
  /// `EXT_texture_filter_anisotropic` and clamped to the device maximum.
  int maxAnisotropy;
}

base class DepthRange {
  DepthRange({this.zNear = 0.0, this.zFar = 1.0});
  double zNear;
  double zFar;
}

base class Scissor {
  Scissor({this.x = 0, this.y = 0, this.width = 0, this.height = 0});
  int x, y, width, height;
}

base class Viewport {
  Viewport({
    this.x = 0,
    this.y = 0,
    this.width = 0,
    this.height = 0,
    DepthRange? depthRange,
  }) : depthRange = depthRange ?? DepthRange();

  int x, y, width, height;
  DepthRange depthRange;
}

base class RenderTarget {
  const RenderTarget({
    this.colorAttachments = const <ColorAttachment>[],
    this.depthStencilAttachment,
  });

  RenderTarget.singleColor(
    ColorAttachment colorAttachment, {
    DepthStencilAttachment? depthStencilAttachment,
  }) : this(
         colorAttachments: [colorAttachment],
         depthStencilAttachment: depthStencilAttachment,
       );

  final List<ColorAttachment> colorAttachments;
  final DepthStencilAttachment? depthStencilAttachment;
}

enum CompletionStatus { successful, error }

typedef CompletionCallback = void Function(CompletionStatus status);
