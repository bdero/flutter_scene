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
/// The transforms are emplaced into [instanceTransformBuffers], a `HostBuffer`
/// dedicated to instance vertex data, separate from the per-frame transient
/// uniform `HostBuffer`. On the GLES backend, sourcing this vertex buffer
/// from the same `HostBuffer` that also serves uniform emplacements
/// corrupts the model matrix (objects toggle between transforms), because
/// the uniform emplacements `Material.bind` issues later in the same draw
/// disturb the vertex binding into the shared GL buffer object. Metal and
/// Vulkan resolve buffer+offset at submit and were unaffected. A separate
/// buffer that only ever holds vertex data removes the interference on
/// every backend, while keeping the cheap per-frame `HostBuffer`
/// sub-allocation (no per-draw device-buffer creation, which stalls the
/// GLES backend).
void bindInstanceTransforms(gpu.RenderPass pass, Float32List packed) {
  if (packed.isEmpty) return;
  pass.bindVertexBuffer(
    instanceTransformBuffers.emplace(ByteData.sublistView(packed)),
    slot: 1,
  );
}

/// A `HostBuffer` dedicated to instance-rate transform vertex data, kept
/// apart from the uniform transients buffer (see [bindInstanceTransforms]
/// for why). [beginFrame] cycles it to the next frame's backing storage
/// and is driven once per frame from the render setup.
class InstanceTransformBuffers {
  // Created lazily: the GPU context initializes on the raster thread after
  // the first frame on some backends, so it isn't available at startup.
  gpu.HostBuffer? _buffer;
  gpu.HostBuffer get _host => _buffer ??= gpu.gpuContext.createHostBuffer();

  /// Cycles to the next frame's backing storage. Call once per frame
  /// before any [emplace].
  void beginFrame() => _host.reset();

  /// Emplaces [data] and returns a view to bind as the instance-rate
  /// vertex buffer.
  gpu.BufferView emplace(ByteData data) => _host.emplace(data);
}

/// The process-wide instance-transform vertex buffer. One GPU context per
/// process, so a single buffer serves every scene; [beginFrame] is driven
/// from the per-frame render setup.
// TODO(instance-buffer-ownership): a single process-wide buffer means two
// Scenes rendering in the same frame both reset it; make it per-Surface if
// multi-scene-per-frame becomes common.
final InstanceTransformBuffers instanceTransformBuffers =
    InstanceTransformBuffers();
