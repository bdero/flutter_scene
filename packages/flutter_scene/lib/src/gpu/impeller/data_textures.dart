part of '_gpu.dart';

/// The active device's texture limits.
///
/// Flutter GPU reports none of the size limits itself. On Apple platforms
/// Impeller always runs on Metal, whose limits are fixed per GPU family and
/// documented in Apple's Metal feature set tables; every GPU current Flutter
/// supports there is in a family with these values. Elsewhere the backend
/// (Vulkan or OpenGL ES) is not known from Dart, so the sizes are null.
// TODO(gpu-limits): read these from the context once flutter_gpu exposes them.
GpuLimits get gpuLimits {
  final arrays = gpuContext.doesSupportTextureArrays;
  if (Platform.isMacOS || Platform.isIOS) {
    return GpuLimits(
      maxTextureSize: 16384,
      maxArrayLayers: 2048,
      max3DTextureSize: null,
      // Metal's sampler-state table, which every sampled texture uses an entry
      // of, holds 16 per stage.
      maxSamplersPerStage: 16,
      supportsTextureArrays: arrays,
      supports3DTextures: false,
      // Every Mac GPU filters 32-bit floats; on iOS only Apple7 and newer do.
      supportsFloat32Filtering: Platform.isMacOS,
    );
  }
  return GpuLimits(
    maxTextureSize: null,
    maxArrayLayers: null,
    max3DTextureSize: null,
    maxSamplersPerStage: null,
    supportsTextureArrays: arrays,
    supports3DTextures: false,
    supportsFloat32Filtering: false,
  );
}

/// Flutter GPU has no 3D texture type, so this always throws. The web
/// backends create one; check [GpuLimits.supports3DTextures] first.
Texture createTexture3D(
  StorageMode storageMode,
  int width,
  int height,
  int depth, {
  PixelFormat format = PixelFormat.r8g8b8a8UNormInt,
}) {
  throw UnsupportedError(
    '3D textures are not available on this backend: Flutter GPU has no 3D '
    'texture type. Check gpuLimits.supports3DTextures, and use a 2D-array '
    'texture instead.',
  );
}

/// Whether [texture] is a 3D texture. Never, on this backend.
bool isTexture3D(Texture texture) => false;

/// The depth of a 3D [texture], or 1 for every other kind.
int textureDepth(Texture texture) => 1;

/// Records work with [encode], which opens as many command buffers as it
/// needs through its argument (Flutter GPU wants one per render pass), and
/// completes with how long they took to finish.
///
/// Each buffer is submitted as soon as the next is opened: a Metal queue
/// holds 64 buffers at most, so opening more before submitting any would
/// deadlock. Flutter GPU has no timer queries, so the result is wall time
/// from the first submission to the last buffer's completion callback, with
/// later buffers encoding while earlier ones run. On Metal and Vulkan that
/// callback fires once the GPU has retired the buffer, and buffers on one
/// queue retire in order; on OpenGL ES it fires once the raster thread has
/// encoded it (see `awaitRasterThread`), which does not include GPU time.
Future<GpuWorkTiming> timeGpuWork(
  void Function(CommandBuffer Function() newCommandBuffer) encode,
) {
  final stopwatch = Stopwatch();
  CommandBuffer? pending;
  void submitPending() {
    pending?.submit();
    stopwatch.start();
  }

  encode(() {
    submitPending();
    return pending = gpuContext.createCommandBuffer();
  });
  final last = pending ?? gpuContext.createCommandBuffer();
  final completer = Completer<GpuWorkTiming>();
  stopwatch.start();
  last.submit(
    completionCallback: (success) {
      stopwatch.stop();
      if (!success) {
        completer.completeError(StateError('GPU work failed to complete.'));
        return;
      }
      completer.complete(
        GpuWorkTiming(stopwatch.elapsed, GpuTimingSource.completion),
      );
    },
  );
  return completer.future;
}
