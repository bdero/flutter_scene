part of '_gpu.dart';

/// The active device's texture limits.
GpuLimits get gpuLimits => _stub();

/// Creates a 3D texture of [width] x [height] x [depth] texels.
Texture createTexture3D(
  StorageMode storageMode,
  int width,
  int height,
  int depth, {
  PixelFormat format = PixelFormat.r8g8b8a8UNormInt,
}) => _stub();

/// Whether [texture] is a 3D texture.
bool isTexture3D(Texture texture) => _stub();

/// The depth of a 3D [texture], or 1 for every other kind.
int textureDepth(Texture texture) => _stub();

/// Records work with [encode] into the command buffers it opens, submits
/// them, and times them to completion.
Future<GpuWorkTiming> timeGpuWork(
  void Function(CommandBuffer Function() newCommandBuffer) encode,
) => _stub();
