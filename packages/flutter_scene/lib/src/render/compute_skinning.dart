import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_scene/src/geometry/geometry.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/importer/constants.dart';
import 'package:flutter_scene/src/render/engine_compute_shaders.dart';
import 'package:flutter_scene/src/render/frame_transients.dart';
import 'package:flutter_scene/src/render/render_scene.dart';
import 'package:flutter_scene/src/render/uniform_slots.dart';
import 'package:flutter_scene/src/skin.dart';

/// Whether skinned meshes are skinned by a compute pass where the device
/// supports compute. Off draws every skinned mesh through the vertex shader,
/// which renders the same.
@visibleForTesting
bool computeSkinningEnabled = true;

/// Skins every skinned render item once per frame with a compute pass, so the
/// shadow, prepass, and color passes draw the result instead of each skinning
/// in its vertex shader.
///
/// Runs only on a device with compute (Metal and Vulkan on Flutter 3.53 or
/// newer, and WebGPU), once the engine's compute shaders load. Until then,
/// and for whatever it cannot skin, the vertex shader skins as before.
///
/// TODO(compute-skinning): skin morphed skinned meshes and levels of detail,
/// skip items no pass draws this frame, and drop the joints texture upload
/// when nothing reads it (the velocity pass still skins in its vertex shader).
class ComputeSkinning {
  ComputeSkinning._();

  /// The renderer's instance.
  static final ComputeSkinning instance = ComputeSkinning._();

  // Each output is rewritten every frame, so one per frame in flight keeps the
  // GPU from reading a buffer this frame's dispatch is writing. Matches the
  // joints texture ring.
  static const int _ringSize = 3;

  static const int _workgroupSize = 64;

  _Shaders? _shaders;
  bool _failed = false;
  int _frame = 0;

  final Expando<_SkinBuffers> _skinBuffers = Expando('computeSkinJoints');
  final Expando<_ItemOutputs> _itemOutputs = Expando('computeSkinOutputs');

  // The skinning parameters, reused every dispatch since emplace copies them.
  final Uint32List _info = Uint32List(4);

  /// Skins [scene]'s skinned items for this frame and records each result on
  /// its item ([RenderItem.preSkinnedVertices]), or clears them all when it
  /// cannot. Call after the joint matrices are computed and before any pass
  /// draws.
  void dispatch(RenderScene scene) {
    final shaders = _readyShaders();
    if (shaders == null) {
      _clear(scene);
      return;
    }
    _frame++;
    final slot = _frame % _ringSize;
    gpu.CommandBuffer? commandBuffer;
    gpu.GpuComputePass? pass;
    try {
      for (final item in scene.items) {
        final source = _skinnable(item);
        if (source == null) {
          item.preSkinnedVertices = null;
          item.preSkinnedSource = null;
          continue;
        }
        commandBuffer ??= gpu.gpuContext.createCommandBuffer();
        pass ??= gpu.createComputePass(commandBuffer)
          ..bindPipeline(shaders.pipeline);
        item.preSkinnedVertices = _encode(pass, shaders, item, source, slot);
        item.preSkinnedSource = source;
      }
      if (pass == null) return;
      pass.end();
      rendererSubmissions.submit(commandBuffer!);
    } catch (error, stack) {
      // Nothing was submitted, so every item falls back for good.
      _failed = true;
      _shaders = null;
      _clear(scene);
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'flutter_scene',
          context: ErrorDescription(
            'while skinning meshes in a compute pass. Skinned meshes skin in '
            'their vertex shader instead',
          ),
        ),
      );
    }
  }

  // The geometry [item] draws, when this pass can skin it.
  static SkinnedGeometry? _skinnable(RenderItem item) {
    final geometry = item.geometry;
    // Exact type, since a subclass (morphed skinned geometry) skins more.
    if (item.skin == null ||
        item.jointsTexture == null ||
        item.morphWeights != null ||
        geometry.runtimeType != SkinnedGeometry) {
      return null;
    }
    geometry as SkinnedGeometry;
    if (geometry.interleavedVertexStream == null ||
        geometry.uploadedVertexCount == 0) {
      return null;
    }
    return geometry;
  }

  gpu.BufferView _encode(
    gpu.GpuComputePass pass,
    _Shaders shaders,
    RenderItem item,
    SkinnedGeometry geometry,
    int slot,
  ) {
    final skin = item.skin!;
    final joints = (_skinBuffers[skin] ??= _SkinBuffers()).upload(
      skin,
      _frame,
      slot,
    );

    final vertexCount = geometry.uploadedVertexCount;
    final output = (_itemOutputs[item] ??= _ItemOutputs()).output(
      vertexCount,
      slot,
    );

    // A storage binding's offset must be aligned, and the geometry arena's
    // offsets are not, so the view starts at the aligned offset below the
    // vertices and the shader skips the difference.
    final stream = geometry.interleavedVertexStream!;
    final alignment = gpu.computeLimits.minStorageBufferOffsetAlignment;
    final start = stream.offsetInBytes - stream.offsetInBytes % alignment;
    final source = gpu.BufferView(
      stream.buffer,
      offsetInBytes: start,
      lengthInBytes: stream.offsetInBytes - start + stream.lengthInBytes,
    );

    _info
      ..[0] = vertexCount
      ..[1] = (stream.offsetInBytes - start) ~/ 4
      ..[2] = skin.joints.length;
    pass
      ..bindStorageBuffer(shaders.sourceVertices, source)
      ..bindStorageBuffer(shaders.jointMatrices, joints)
      ..bindStorageBuffer(shaders.skinnedVertices, output)
      ..bindUniform(
        shaders.skinInfo,
        uniformTransients.emplace(scratchBytesOf(_info)),
      )
      ..dispatch((vertexCount + _workgroupSize - 1) ~/ _workgroupSize);
    return output;
  }

  static void _clear(RenderScene scene) {
    for (final item in scene.items) {
      item.preSkinnedVertices = null;
      item.preSkinnedSource = null;
    }
  }

  // The shaders once the engine's compute library has loaded, starting the
  // load when this device can use them.
  _Shaders? _readyShaders() {
    if (!computeSkinningEnabled || _failed) return null;
    final shaders = _shaders;
    if (shaders != null) return shaders;
    final library = EngineComputeShaders.request();
    if (library == null) return null;
    try {
      final shader =
          library['SkinVertices'] ??
          (throw StateError('The compute bundle has no SkinVertices entry.'));
      return _shaders = _Shaders(
        pipeline: gpu.createComputePipeline(shader),
        sourceVertices: gpu.getStorageBufferSlot(shader, 'SourceVertices'),
        jointMatrices: gpu.getStorageBufferSlot(shader, 'JointMatrices'),
        skinnedVertices: gpu.getStorageBufferSlot(shader, 'SkinnedVertices'),
        skinInfo: shader.cachedUniformSlot('SkinInfo'),
      );
    } catch (error, stack) {
      _failed = true;
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'flutter_scene',
          context: ErrorDescription(
            'while preparing the compute skinning shader. Skinned meshes skin '
            'in their vertex shader instead',
          ),
        ),
      );
      return null;
    }
  }

  /// Forgets the loaded shaders and any failure, so a test can drive the load
  /// from a known state.
  @visibleForTesting
  void debugReset() {
    _shaders = null;
    _failed = false;
  }

  /// Whether the compute shaders have loaded, so dispatches skin.
  @visibleForTesting
  bool get debugReady => _shaders != null;

  /// Waits for the compute shaders to load, starting the load if needed.
  /// Completes at once on a device that skins in the vertex shader.
  @visibleForTesting
  Future<void> debugWaitUntilReady() async {
    await EngineComputeShaders.whenLoaded();
    _readyShaders();
  }
}

final class _Shaders {
  _Shaders({
    required this.pipeline,
    required this.sourceVertices,
    required this.jointMatrices,
    required this.skinnedVertices,
    required this.skinInfo,
  });

  final gpu.GpuComputePipeline pipeline;
  final gpu.GpuStorageBufferSlot sourceVertices;
  final gpu.GpuStorageBufferSlot jointMatrices;
  final gpu.GpuStorageBufferSlot skinnedVertices;
  final gpu.UniformSlot skinInfo;
}

// A skin's joint matrices as a storage buffer, one per frame in flight. Shared
// by every item the skin deforms.
final class _SkinBuffers {
  final List<gpu.DeviceBuffer?> _ring = List.filled(
    ComputeSkinning._ringSize,
    null,
  );
  int _uploadedFrame = -1;
  int _jointCount = -1;

  gpu.BufferView upload(Skin skin, int frame, int slot) {
    final jointCount = skin.joints.length;
    // At least one matrix, since a storage binding cannot be empty.
    final bytes = (jointCount > 0 ? jointCount : 1) * 64;
    if (jointCount != _jointCount) {
      _ring.fillRange(0, _ring.length, null);
      _jointCount = jointCount;
      _uploadedFrame = -1;
    }
    final buffer = _ring[slot] ??= gpu.gpuContext.createDeviceBuffer(
      gpu.StorageMode.hostVisible,
      bytes,
    );
    if (_uploadedFrame != frame && jointCount > 0) {
      _uploadedFrame = frame;
      final floats = skin.currentJointMatrices;
      buffer.overwrite(ByteData.sublistView(floats, 0, jointCount * 16));
    }
    return gpu.BufferView(buffer, offsetInBytes: 0, lengthInBytes: bytes);
  }
}

// An item's skinned vertices, one buffer per frame in flight.
final class _ItemOutputs {
  final List<gpu.DeviceBuffer?> _ring = List.filled(
    ComputeSkinning._ringSize,
    null,
  );
  int _vertexCount = -1;

  gpu.BufferView output(int vertexCount, int slot) {
    if (vertexCount != _vertexCount) {
      _ring.fillRange(0, _ring.length, null);
      _vertexCount = vertexCount;
    }
    final bytes = vertexCount * kSkinnedPerVertexSize;
    final buffer = _ring[slot] ??= gpu.gpuContext.createDeviceBuffer(
      gpu.StorageMode.devicePrivate,
      bytes,
    );
    return gpu.BufferView(buffer, offsetInBytes: 0, lengthInBytes: bytes);
  }
}
