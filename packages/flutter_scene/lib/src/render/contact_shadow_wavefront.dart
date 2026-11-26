import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/contact_shadows.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/render/contact_shadow_wavefront_plan.dart';
import 'package:flutter_scene/src/render/engine_compute_shaders.dart';
import 'package:flutter_scene/src/render/frame_transients.dart';
import 'package:flutter_scene/src/render/projection_params.dart';
import 'package:flutter_scene/src/render/render_graph.dart';
import 'package:flutter_scene/src/render/uniform_slots.dart';

/// The wavefront variants' sample counts, smallest first, matching the
/// `ContactShadowsWavefront<N>` entries of the compute bundle.
const List<int> kWavefrontSampleCounts = [60, 127, 191];

/// The sample count whose reach best fits a march of [distance] world units:
/// its projected length at a view depth of one world unit, where the closest
/// surfaces that matter sit, rounded up to the next variant.
@visibleForTesting
int wavefrontSampleCount(
  double distance,
  ProjectionParams projection,
  int height,
) {
  final pixels = distance * height / (2.0 * projection.scaleY);
  for (final count in kWavefrontSampleCounts) {
    if (pixels <= count) return count;
  }
  return kWavefrontSampleCounts.last;
}

/// Marches the primary directional light's contact shadow with the wavefront
/// compute kernel (`contact_shadows_wavefront.glsl`) where the device runs
/// compute, into an rgba8 texture whose r the contact shadow pass copies
/// into the mask.
///
/// One instance lives on the scene, holding the kernels and an output buffer
/// per frame in flight.
class ContactShadowWavefront {
  // The output is rewritten every frame, so one buffer per frame in flight
  // keeps the GPU from reading a buffer this frame's dispatch is writing.
  static const int _ringSize = 3;

  final List<gpu.DeviceBuffer?> _ring = List.filled(_ringSize, null);
  int _ringBytes = 0;
  int _frame = 0;
  Map<int, _Kernel>? _kernels;
  bool _failed = false;

  /// Whether the kernels are ready on this device, starting their load on
  /// the first call. False without compute, while loading, and after a
  /// failure.
  bool get available => _readyKernels() != null;

  /// Marches the directional light toward view-space direction [towardLight]
  /// over [linearDepth] and returns the texture holding its visibility in r
  /// (texels map 1:1 to [linearDepth]'s), or null when the kernels are not
  /// ready or the projection is orthographic.
  gpu.Texture? encode(
    RenderGraphContext context, {
    required gpu.Texture linearDepth,
    required Vector3 towardLight,
    required double distance,
    required ProjectionParams projection,
    required ContactShadowSettings settings,
    required int maxSampleCount,
  }) {
    if (projection.orthographic) return null;
    final kernels = _readyKernels();
    if (kernels == null) return null;
    final width = linearDepth.width;
    final height = linearDepth.height;
    // Rows padded to 256 bytes, so the copy into the texture is one copy.
    final stride =
        (width + kWavefrontSize - 1) ~/ kWavefrontSize * kWavefrontSize;
    final bytes = stride * height * 4;
    if (bytes != _ringBytes) {
      _ring.fillRange(0, _ringSize, null);
      _ringBytes = bytes;
    }
    _frame++;
    final buffer = _ring[_frame % _ringSize] ??= gpu.gpuContext
        .createDeviceBuffer(gpu.StorageMode.devicePrivate, bytes);
    final output = gpu.BufferView(
      buffer,
      offsetInBytes: 0,
      lengthInBytes: bytes,
    );
    final target = context.texturePool.acquire(
      TransientTextureDescriptor.color(
        width: stride,
        height: height,
        format: gpu.PixelFormat.r8g8b8a8UNormInt,
        debugName: 'contact_shadows_wavefront',
      ),
    );

    final direction = towardLight.normalized();
    final light = projectDirectionalLight(direction, projection, width, height);
    final rings = planWavefrontRings(light.pixel, width, height);
    final sampleCount = math.min(
      wavefrontSampleCount(distance, projection, height),
      maxSampleCount,
    );
    final kernel =
        kernels[kWavefrontSampleCounts.lastWhere(
          (count) => count <= sampleCount,
          orElse: () => kWavefrontSampleCounts.first,
        )]!;

    final info = Float32List(32)
      ..[0] = light.pixel.x
      ..[1] = light.pixel.y
      ..[2] = light.depth
      ..[3] = light.towardLight ? 1.0 : -1.0
      ..[8] = width.toDouble()
      ..[9] = height.toDouble()
      ..[10] = stride.toDouble()
      ..[12] = projection.scaleX
      ..[13] = projection.scaleY
      ..[14] = projection.near
      ..[15] = projection.far
      ..[16] = projection.offsetX
      ..[17] = projection.offsetY
      ..[18] = projection.orthographicFlag
      ..[20] = direction.x
      ..[21] = direction.y
      ..[22] = direction.z
      ..[23] = distance
      ..[24] = settings.thickness
      ..[25] = settings.maxDistance
      ..[26] = settings.fadeRange
      ..[27] = settings.opacity.clamp(0.0, 1.0)
      ..[28] = _shadowContrast;

    final commandBuffer = gpu.gpuContext.createCommandBuffer();
    final pass = gpu.createComputePass(commandBuffer)
      ..bindPipeline(kernel.pipeline)
      ..bindStorageBuffer(kernel.visibility, output)
      ..bindTexture(kernel.linearDepth, linearDepth, sampler: _nearestClamp);
    final table = Float32List(kWavefrontRingTableSize * 4);
    for (final dispatch in batchWavefrontRings(rings)) {
      for (final (i, (radius, start, firstGroup, arcStart))
          in dispatch.entries.indexed) {
        table
          ..[i * 4] = radius.toDouble()
          ..[i * 4 + 1] = start.toDouble()
          ..[i * 4 + 2] = firstGroup.toDouble()
          ..[i * 4 + 3] = arcStart.toDouble();
      }
      info[4] = dispatch.entries.length.toDouble();
      pass
        ..bindUniform(
          kernel.info,
          context.transientsBuffer.emplace(ByteData.sublistView(info)),
        )
        ..bindUniform(
          kernel.rings,
          context.transientsBuffer.emplace(ByteData.sublistView(table)),
        )
        ..dispatch(dispatch.groups);
    }
    pass.end();
    commandBuffer.copyBufferToTexture(output, gpu.TextureRegion(target));
    rendererSubmissions.submit(commandBuffer);
    return target;
  }

  // How sharply a sample's closeness to the ray turns into shadow: one window
  // of distance from the lifted ray is lit, a quarter window or less is fully
  // shadowed.
  static const double _shadowContrast = 4.0;

  static final gpu.SamplerOptions _nearestClamp = gpu.SamplerOptions(
    minFilter: gpu.MinMagFilter.nearest,
    magFilter: gpu.MinMagFilter.nearest,
    widthAddressMode: gpu.SamplerAddressMode.clampToEdge,
    heightAddressMode: gpu.SamplerAddressMode.clampToEdge,
  );

  Map<int, _Kernel>? _readyKernels() {
    if (_failed) return null;
    final kernels = _kernels;
    if (kernels != null) return kernels;
    final library = EngineComputeShaders.request();
    if (library == null) return null;
    try {
      return _kernels = {
        for (final count in kWavefrontSampleCounts)
          count: _Kernel(
            library['ContactShadowsWavefront$count'] ??
                (throw StateError(
                  'The compute bundle has no ContactShadowsWavefront$count '
                  'entry.',
                )),
          ),
      };
    } catch (error, stack) {
      _failed = true;
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'flutter_scene',
          context: ErrorDescription(
            'while preparing the wavefront contact shadow kernels. Contact '
            'shadows march in a fragment pass instead',
          ),
        ),
      );
      return null;
    }
  }

  /// Waits for the compute shaders to load, starting the load if needed.
  @visibleForTesting
  Future<void> debugWaitUntilReady() async {
    await EngineComputeShaders.whenLoaded();
    _readyKernels();
  }

  /// Drops the output buffers.
  void releaseBuffers() {
    _ring.fillRange(0, _ringSize, null);
    _ringBytes = 0;
  }
}

final class _Kernel {
  _Kernel(gpu.Shader shader)
    : pipeline = gpu.createComputePipeline(shader),
      visibility = gpu.getStorageBufferSlot(shader, 'Visibility'),
      linearDepth = shader.cachedUniformSlot('linear_depth'),
      info = shader.cachedUniformSlot('WavefrontInfo'),
      rings = shader.cachedUniformSlot('WavefrontRings');

  final gpu.GpuComputePipeline pipeline;
  final gpu.GpuStorageBufferSlot visibility;
  final gpu.UniformSlot linearDepth;
  final gpu.UniformSlot info;
  final gpu.UniformSlot rings;
}
