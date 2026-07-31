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

/// One retained instance group consumed by [packInstanceDataBatches].
class InstanceDataBatch {
  InstanceDataBatch({
    required this.nodeTransform,
    required List<Matrix4> instances,
    required List<Vector4> colors,
    required this.nodeWindingFlipped,
    List<bool>? instanceWindingFlipped,
    this.indices,
  }) : instances = instances,
       colors = colors,
       instanceWindingFlipped = instanceWindingFlipped,
       assert(instances.length == colors.length),
       assert(
         instanceWindingFlipped == null ||
             instanceWindingFlipped.length == instances.length,
       ),
       assert(indices == null || indices.length <= instances.length);

  InstanceDataBatch.single({
    required this.nodeTransform,
    required this.nodeWindingFlipped,
  }) : instances = null,
       colors = null,
       instanceWindingFlipped = null,
       indices = null;

  final Matrix4 nodeTransform;
  final List<Matrix4>? instances;
  final List<Vector4>? colors;
  final bool nodeWindingFlipped;
  final List<bool>? instanceWindingFlipped;
  final List<int>? indices;

  int get length =>
      instances == null ? 1 : (indices?.length ?? instances!.length);
}

/// Packs several retained groups without building a flattened matrix list.
PackedInstanceData packInstanceDataBatches(List<InstanceDataBatch> batches) {
  var count = 0;
  for (final batch in batches) {
    count += batch.length;
  }
  final flipped = Uint8List(count);
  var cwCount = 0;
  var flatIndex = 0;
  for (final batch in batches) {
    final instances = batch.instances;
    if (instances == null) {
      if (batch.nodeWindingFlipped) {
        flipped[flatIndex] = 1;
        cwCount++;
      }
      flatIndex++;
      continue;
    }
    final retainedParity = batch.instanceWindingFlipped;
    final indices = batch.indices;
    for (var slot = 0; slot < batch.length; slot++) {
      final i = indices?[slot] ?? slot;
      final instanceFlipped =
          retainedParity?[i] ?? (instances[i].determinant() < 0);
      if (batch.nodeWindingFlipped != instanceFlipped) {
        flipped[flatIndex] = 1;
        cwCount++;
      }
      flatIndex++;
    }
  }

  final ccw = Float32List((count - cwCount) * 20);
  final cw = Float32List(cwCount * 20);
  final world = Matrix4.zero();
  var ccwIndex = 0, cwIndex = 0;
  flatIndex = 0;
  for (final batch in batches) {
    final instances = batch.instances;
    if (instances == null) {
      final isFlipped = flipped[flatIndex++] != 0;
      final target = isFlipped ? cw : ccw;
      final targetIndex = isFlipped ? cwIndex++ : ccwIndex++;
      final offset = targetIndex * 20;
      target.setAll(offset, batch.nodeTransform.storage);
      target.setRange(offset + 16, offset + 20, _whiteColor);
      continue;
    }
    final colors = batch.colors!;
    final indices = batch.indices;
    for (var slot = 0; slot < batch.length; slot++) {
      final i = indices?[slot] ?? slot;
      world.setFrom(batch.nodeTransform);
      world.multiply(instances[i]);
      final isFlipped = flipped[flatIndex++] != 0;
      final target = isFlipped ? cw : ccw;
      final targetIndex = isFlipped ? cwIndex++ : ccwIndex++;
      final offset = targetIndex * 20;
      target.setAll(offset, world.storage);
      target.setAll(offset + 16, colors[i].storage);
    }
  }
  return PackedInstanceData(ccw, cw);
}

const List<double> _whiteColor = [1, 1, 1, 1];

/// Packs world transforms followed by linear RGBA color multipliers.
PackedInstanceData packInstanceData(
  Matrix4 nodeTransform,
  List<Matrix4> instances,
  List<Vector4> colors, {
  bool nodeWindingFlipped = false,
  List<bool>? instanceWindingFlipped,
  List<int>? indices,
  Vector3? sortBackToFrontFrom,
}) {
  assert(instances.length == colors.length);
  if (sortBackToFrontFrom == null) {
    return packInstanceDataBatches([
      InstanceDataBatch(
        nodeTransform: nodeTransform,
        instances: instances,
        colors: colors,
        nodeWindingFlipped: nodeWindingFlipped,
        instanceWindingFlipped: instanceWindingFlipped,
        indices: indices,
      ),
    ]);
  }

  final sorted = _sortInstances(
    nodeTransform,
    instances,
    nodeWindingFlipped,
    sortBackToFrontFrom,
    instanceWindingFlipped,
    indices,
  );

  Float32List pack(List<int> order) {
    final result = Float32List(order.length * 20);
    for (var i = 0; i < order.length; i++) {
      final source = order[i];
      final offset = i * 20;
      result.setRange(offset, offset + 16, sorted.worldTransforms, source * 16);
      result.setAll(offset + 16, colors[source].storage);
    }
    return result;
  }

  return PackedInstanceData(pack(sorted.ccw), pack(sorted.cw));
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
  List<bool>? instanceWindingFlipped,
  List<int>? indices,
  Vector3? sortBackToFrontFrom,
}) {
  if (sortBackToFrontFrom != null) {
    return _packSortedInstanceTransforms(
      nodeTransform,
      instances,
      nodeWindingFlipped,
      sortBackToFrontFrom,
      instanceWindingFlipped,
      indices,
    );
  }
  final count = indices?.length ?? instances.length;
  var cwCount = 0;
  final flipped = Uint8List(count);
  for (var slot = 0; slot < count; slot++) {
    final i = indices?[slot] ?? slot;
    final flip =
        nodeWindingFlipped !=
        (instanceWindingFlipped?[i] ?? (instances[i].determinant() < 0));
    if (flip) {
      flipped[slot] = 1;
      cwCount++;
    }
  }
  final ccw = Float32List((count - cwCount) * 16);
  final cw = Float32List(cwCount * 16);
  var ccwIndex = 0, cwIndex = 0;
  final world = Matrix4.zero();
  for (var slot = 0; slot < count; slot++) {
    final i = indices?[slot] ?? slot;
    world.setFrom(nodeTransform);
    world.multiply(instances[i]);
    if (flipped[slot] != 0) {
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
  List<bool>? instanceWindingFlipped,
  List<int>? indices,
) {
  final sorted = _sortInstances(
    nodeTransform,
    instances,
    nodeWindingFlipped,
    cameraPosition,
    instanceWindingFlipped,
    indices,
  );

  Float32List pack(List<int> order) {
    final result = Float32List(order.length * 16);
    for (var i = 0; i < order.length; i++) {
      result.setRange(
        i * 16,
        i * 16 + 16,
        sorted.worldTransforms,
        order[i] * 16,
      );
    }
    return result;
  }

  return PackedInstanceTransforms(pack(sorted.ccw), pack(sorted.cw));
}

({Float32List worldTransforms, List<int> ccw, List<int> cw}) _sortInstances(
  Matrix4 nodeTransform,
  List<Matrix4> instances,
  bool nodeWindingFlipped,
  Vector3 cameraPosition,
  List<bool>? instanceWindingFlipped,
  List<int>? indices,
) {
  final worldTransforms = Float32List(instances.length * 16);
  final distances = Float64List(instances.length);
  final ccw = <int>[];
  final cw = <int>[];
  final world = Matrix4.zero();
  final count = indices?.length ?? instances.length;
  for (var slot = 0; slot < count; slot++) {
    final i = indices?[slot] ?? slot;
    final instance = instances[i];
    world
      ..setFrom(nodeTransform)
      ..multiply(instance);
    worldTransforms.setAll(i * 16, world.storage);
    final storage = world.storage;
    final dx = storage[12] - cameraPosition.x;
    final dy = storage[13] - cameraPosition.y;
    final dz = storage[14] - cameraPosition.z;
    distances[i] = dx * dx + dy * dy + dz * dz;
    final flipped =
        nodeWindingFlipped !=
        (instanceWindingFlipped?[i] ?? (instance.determinant() < 0));
    (flipped ? cw : ccw).add(i);
  }
  int farthestFirst(int a, int b) => distances[b].compareTo(distances[a]);
  ccw.sort(farthestFirst);
  cw.sort(farthestFirst);
  return (worldTransforms: worldTransforms, ccw: ccw, cw: cw);
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
