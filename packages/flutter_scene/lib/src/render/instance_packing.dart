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
/// The transforms go into a dedicated [gpu.DeviceBuffer] rather than the
/// per-frame transient uniform `HostBuffer`. On the GLES backend a vertex
/// buffer sourced from that shared host buffer reads corrupted data,
/// because the same buffer also serves the uniform emplacements issued
/// later in the same draw (`Material.bind`) and GLES binds vertex
/// attributes by stateful pointer into the live buffer object; the
/// symptom was objects toggling between transforms. A standalone buffer
/// is never disturbed by other emplacements, so the binding stays valid
/// on every backend. The render pass keeps the buffer alive through
/// submission via the recorded binding.
// TODO(instance-buffer-pool): this allocates a device buffer per draw per
// frame. Fine for typical scenes; pool these for instance-heavy scenes.
void bindInstanceTransforms(gpu.RenderPass pass, Float32List packed) {
  if (packed.isEmpty) return;
  final buffer = gpu.gpuContext.createDeviceBufferWithCopy(
    ByteData.sublistView(packed),
  );
  pass.bindVertexBuffer(
    gpu.BufferView(
      buffer,
      offsetInBytes: 0,
      lengthInBytes: packed.lengthInBytes,
    ),
    slot: 1,
  );
}
