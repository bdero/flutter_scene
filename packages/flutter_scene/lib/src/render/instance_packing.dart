import 'package:flutter/foundation.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart';

/// Per-instance world transforms packed for the instance-rate vertex buffer
/// (slot 1), split by winding parity.
///
/// Hardware instancing draws a whole group with one fixed winding order, but
/// a mirrored (negative-determinant) instance reverses triangle winding, so
/// instances are partitioned into the counter-clockwise group ([ccw], the
/// default front-face winding) and the clockwise group ([cw], mirrored).
/// Each list is the instances' world transforms (node transform times
/// instance transform) as consecutive column-major mat4s, 16 floats per
/// instance, exactly the byte layout the `model_transform_0..3` instance
/// attributes consume.
class PackedInstanceTransforms {
  PackedInstanceTransforms(this.ccw, this.cw);

  final Float32List ccw;
  final Float32List cw;

  int get ccwCount => ccw.length ~/ 16;
  int get cwCount => cw.length ~/ 16;
}

/// Packs `nodeTransform * instances[i]` into per-parity instance buffers.
///
/// [nodeWindingFlipped] is the parity of the node's own world transform;
/// each instance's own determinant combines with it, matching the
/// per-instance winding flip the looping path applied.
PackedInstanceTransforms packInstanceTransforms(
  Matrix4 nodeTransform,
  List<Matrix4> instances, {
  bool nodeWindingFlipped = false,
}) {
  var cwCount = 0;
  final flipped = List<bool>.filled(instances.length, false);
  for (var i = 0; i < instances.length; i++) {
    final flip = nodeWindingFlipped != (instances[i].determinant() < 0);
    flipped[i] = flip;
    if (flip) cwCount++;
  }
  final ccw = Float32List((instances.length - cwCount) * 16);
  final cw = Float32List(cwCount * 16);
  var ccwIndex = 0, cwIndex = 0;
  final world = Matrix4.zero();
  for (var i = 0; i < instances.length; i++) {
    world.setFrom(nodeTransform);
    world.multiply(instances[i]);
    if (flipped[i]) {
      cw.setAll(cwIndex * 16, world.storage);
      cwIndex++;
    } else {
      ccw.setAll(ccwIndex * 16, world.storage);
      ccwIndex++;
    }
  }
  return PackedInstanceTransforms(ccw, cw);
}

/// Uploads a single world transform as a one-element instance buffer and
/// binds it to the instance-rate vertex buffer slot.
///
/// Every draw through the unskinned vertex shader needs this: the model
/// matrix arrives via instance attributes whether or not the draw is
/// instanced.
void bindSingleInstanceTransform(gpu.RenderPass pass, Matrix4 worldTransform) {
  bindInstanceTransforms(pass, Float32List.fromList(worldTransform.storage));
}

/// Uploads [packed] transforms and binds them to the instance-rate slot.
///
/// The transforms come from [instanceTransformBuffers], a dedicated pool of
/// [gpu.DeviceBuffer]s, not the per-frame transient uniform `HostBuffer`.
/// On the GLES backend a vertex buffer sourced from that shared host
/// buffer reads corrupted data, because the same buffer also serves the
/// uniform emplacements issued later in the same draw (`Material.bind`) and
/// GLES binds vertex attributes by stateful pointer into the live buffer
/// object; the symptom was objects toggling between transforms. Metal and
/// Vulkan resolve buffer+offset at submit and were unaffected. A dedicated
/// buffer bound at offset 0, never touched by another emplacement, keeps
/// the binding valid on every backend; the pool reuses buffers across
/// frames so the hot draw path does not allocate.
void bindInstanceTransforms(gpu.RenderPass pass, Float32List packed) {
  if (packed.isEmpty) return;
  pass.bindVertexBuffer(
    instanceTransformBuffers.acquire(ByteData.sublistView(packed)),
    slot: 1,
  );
}

/// A pool of [gpu.DeviceBuffer]s for instance-rate transforms, reused
/// across frames so the per-draw binding (see [bindInstanceTransforms])
/// never allocates in the hot path.
///
/// Each draw within a frame gets a distinct buffer (so binding one draw's
/// transforms is never disturbed by a later draw), and a ring of
/// [framesInFlight] buffer sets keeps the GPU's in-flight reads off the
/// buffers the next frame overwrites. Call [beginFrame] once per frame
/// before any [acquire].
class InstanceTransformBuffers {
  InstanceTransformBuffers({this.framesInFlight = 3});

  final int framesInFlight;
  final List<List<gpu.DeviceBuffer>> _rings = [];
  int _frame = 0;
  int _cursor = 0;

  /// Advances to the next frame's buffer set. Call once per frame.
  void beginFrame() {
    while (_rings.length < framesInFlight) {
      _rings.add(<gpu.DeviceBuffer>[]);
    }
    _frame = (_frame + 1) % framesInFlight;
    _cursor = 0;
  }

  /// Returns a buffer view holding [data] at offset 0, reusing a pooled
  /// buffer when one of sufficient size is free this frame.
  gpu.BufferView acquire(ByteData data) {
    if (_rings.isEmpty) beginFrame();
    final ring = _rings[_frame];
    gpu.DeviceBuffer buffer;
    if (_cursor < ring.length &&
        ring[_cursor].sizeInBytes >= data.lengthInBytes) {
      buffer = ring[_cursor];
      buffer.overwrite(data);
    } else {
      buffer = gpu.gpuContext.createDeviceBufferWithCopy(data);
      if (_cursor < ring.length) {
        ring[_cursor] = buffer;
      } else {
        ring.add(buffer);
      }
    }
    _cursor++;
    return gpu.BufferView(
      buffer,
      offsetInBytes: 0,
      lengthInBytes: data.lengthInBytes,
    );
  }
}

/// The process-wide instance-transform buffer pool. One GPU context per
/// process, so a single pool serves every scene; [beginFrame] is driven
/// from the per-frame render setup.
final InstanceTransformBuffers instanceTransformBuffers =
    InstanceTransformBuffers();
