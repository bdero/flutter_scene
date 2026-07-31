import 'package:flutter/foundation.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/render/frame_transients.dart';
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
abstract interface class PackedInstances {
  Float32List get ccw;
  Float32List get cw;
  int get ccwCount;
  int get cwCount;
}

class PackedInstanceTransforms implements PackedInstances {
  PackedInstanceTransforms(this.ccw, this.cw);

  @override
  final Float32List ccw;
  @override
  final Float32List cw;

  @override
  int get ccwCount => ccw.length ~/ 16;
  @override
  int get cwCount => cw.length ~/ 16;
}

/// Per-instance world transforms and color multipliers for a color pass.
class PackedInstanceData implements PackedInstances {
  PackedInstanceData(this.ccw, this.cw);

  @override
  final Float32List ccw;
  @override
  final Float32List cw;

  @override
  int get ccwCount => ccw.length ~/ 20;
  @override
  int get cwCount => cw.length ~/ 20;
}

/// Packs world transforms followed by linear RGBA color multipliers.
PackedInstanceData packInstanceData(
  Matrix4 nodeTransform,
  List<Matrix4> instances,
  List<Vector4> colors, {
  bool nodeWindingFlipped = false,
  Vector3? sortBackToFrontFrom,
}) {
  assert(instances.length == colors.length);
  if (sortBackToFrontFrom == null) {
    var cwCount = 0;
    final flipped = List<bool>.filled(instances.length, false);
    for (var i = 0; i < instances.length; i++) {
      final flip = nodeWindingFlipped != (instances[i].determinant() < 0);
      flipped[i] = flip;
      if (flip) cwCount++;
    }
    final ccw = Float32List((instances.length - cwCount) * 20);
    final cw = Float32List(cwCount * 20);
    final world = Matrix4.zero();
    var ccwIndex = 0, cwIndex = 0;
    for (var i = 0; i < instances.length; i++) {
      world.setFrom(nodeTransform);
      world.multiply(instances[i]);
      final target = flipped[i] ? cw : ccw;
      final targetIndex = flipped[i] ? cwIndex++ : ccwIndex++;
      final offset = targetIndex * 20;
      target.setAll(offset, world.storage);
      target.setAll(offset + 16, colors[i].storage);
    }
    return PackedInstanceData(ccw, cw);
  }

  final ccwWorld = <_InstanceData>[];
  final cwWorld = <_InstanceData>[];
  for (var i = 0; i < instances.length; i++) {
    final instance = instances[i];
    final world = nodeTransform * instance;
    final translation = world.getTranslation();
    final camera = sortBackToFrontFrom;
    final dx = translation.x - camera.x;
    final dy = translation.y - camera.y;
    final dz = translation.z - camera.z;
    final distanceSquared = dx * dx + dy * dy + dz * dz;
    final entry = _InstanceData(world, colors[i], distanceSquared);
    final flipped = nodeWindingFlipped != (instance.determinant() < 0);
    (flipped ? cwWorld : ccwWorld).add(entry);
  }
  int farthestFirst(_InstanceData a, _InstanceData b) =>
      b.distanceSquared.compareTo(a.distanceSquared);
  ccwWorld.sort(farthestFirst);
  cwWorld.sort(farthestFirst);

  Float32List pack(List<_InstanceData> entries) {
    final result = Float32List(entries.length * 20);
    for (var i = 0; i < entries.length; i++) {
      final offset = i * 20;
      result.setAll(offset, entries[i].transform.storage);
      result.setAll(offset + 16, entries[i].color.storage);
    }
    return result;
  }

  return PackedInstanceData(pack(ccwWorld), pack(cwWorld));
}

class _InstanceData {
  _InstanceData(this.transform, this.color, this.distanceSquared);

  final Matrix4 transform;
  final Vector4 color;
  final double distanceSquared;
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
  Vector3? sortBackToFrontFrom,
}) {
  if (sortBackToFrontFrom != null) {
    return _packSortedInstanceTransforms(
      nodeTransform,
      instances,
      nodeWindingFlipped,
      sortBackToFrontFrom,
    );
  }
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

PackedInstanceTransforms _packSortedInstanceTransforms(
  Matrix4 nodeTransform,
  List<Matrix4> instances,
  bool nodeWindingFlipped,
  Vector3 cameraPosition,
) {
  final ccwWorld = <({Matrix4 transform, double distanceSquared})>[];
  final cwWorld = <({Matrix4 transform, double distanceSquared})>[];
  for (final instance in instances) {
    final world = nodeTransform * instance;
    final translation = world.getTranslation();
    final dx = translation.x - cameraPosition.x;
    final dy = translation.y - cameraPosition.y;
    final dz = translation.z - cameraPosition.z;
    final ({Matrix4 transform, double distanceSquared}) entry = (
      transform: world,
      distanceSquared: dx * dx + dy * dy + dz * dz,
    );
    final flipped = nodeWindingFlipped != (instance.determinant() < 0);
    (flipped ? cwWorld : ccwWorld).add(entry);
  }
  int farthestFirst(
    ({Matrix4 transform, double distanceSquared}) a,
    ({Matrix4 transform, double distanceSquared}) b,
  ) => b.distanceSquared.compareTo(a.distanceSquared);
  ccwWorld.sort(farthestFirst);
  cwWorld.sort(farthestFirst);

  Float32List pack(List<({Matrix4 transform, double distanceSquared})> sorted) {
    final result = Float32List(sorted.length * 16);
    for (var i = 0; i < sorted.length; i++) {
      result.setAll(i * 16, sorted[i].transform.storage);
    }
    return result;
  }

  return PackedInstanceTransforms(pack(ccwWorld), pack(cwWorld));
}

/// Uploads a single world transform as a one-element instance buffer and
/// binds it to the instance-rate vertex buffer slot.
///
/// Every draw through the unskinned vertex shader needs this: the model
/// matrix arrives via instance attributes whether or not the draw is
/// instanced.
// Reused across every call (one per non-instanced draw); the arena emplace
// copies the bytes out immediately, so a shared scratch is safe.
final Float32List _singleTransformScratch = Float32List(16);
final Float32List _singleInstanceDataScratch = Float32List(20)
  ..setRange(16, 20, const [1, 1, 1, 1]);

void bindSingleInstanceTransform(
  gpu.RenderPass pass,
  Matrix4 worldTransform, {
  int slot = 1,
}) {
  bindInstanceTransforms(
    pass,
    _singleTransformScratch..setAll(0, worldTransform.storage),
    slot: slot,
  );
}

/// Uploads one world transform with a white instance-color multiplier.
void bindSingleInstanceData(
  gpu.RenderPass pass,
  Matrix4 worldTransform, {
  int slot = 1,
}) {
  bindInstanceData(
    pass,
    _singleInstanceDataScratch..setAll(0, worldTransform.storage),
    slot: slot,
  );
}

/// Uploads [packed] transforms and binds them to the instance-rate slot.
///
/// The transforms are emplaced into [instanceTransients], the arena
/// dedicated to instance-rate vertex data. It stays separate from the
/// uniform arena because the two need different alignments (vertex fetch
/// needs element alignment; uniforms need the context's minimum uniform
/// alignment), and separate blocks keep either stream from padding the
/// other.
void bindInstanceTransforms(
  gpu.RenderPass pass,
  Float32List packed, {
  int slot = 1,
}) {
  if (packed.isEmpty) return;
  pass.bindVertexBuffer(
    instanceTransients.emplace(ByteData.sublistView(packed)),
    slot: slot,
  );
}

/// Uploads packed transform and color data to an instance-rate slot.
void bindInstanceData(gpu.RenderPass pass, Float32List packed, {int slot = 1}) {
  if (packed.isEmpty) return;
  pass.bindVertexBuffer(
    instanceTransients.emplace(ByteData.sublistView(packed)),
    slot: slot,
  );
}
