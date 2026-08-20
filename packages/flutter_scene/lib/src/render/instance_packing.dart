import 'package:flutter/foundation.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/render/frame_transients.dart';
import 'package:vector_math/vector_math.dart';

/// Reusable storage for instance data copied into transient GPU buffers.
class InstancePackingScratch {
  Float32List _ccw = Float32List(0);
  Float32List _cw = Float32List(0);
  Uint8List _flipped = Uint8List(0);
  Uint8List _batchWinding = Uint8List(0);
  final Matrix4 world = Matrix4.zero();

  Float32List ccw(int length) {
    _ccw = _growFloat(_ccw, length);
    return Float32List.sublistView(_ccw, 0, length);
  }

  Float32List cw(int length) {
    _cw = _growFloat(_cw, length);
    return Float32List.sublistView(_cw, 0, length);
  }

  Uint8List flipped(int length) {
    _flipped = _growBytes(_flipped, length);
    final result = Uint8List.sublistView(_flipped, 0, length);
    result.fillRange(0, length, 0);
    return result;
  }

  Uint8List batchWinding(int length) {
    _batchWinding = _growBytes(_batchWinding, length);
    return Uint8List.sublistView(_batchWinding, 0, length);
  }

  static Float32List _growFloat(Float32List current, int length) =>
      current.length >= length ? current : Float32List(_capacity(length));

  static Uint8List _growBytes(Uint8List current, int length) =>
      current.length >= length ? current : Uint8List(_capacity(length));

  static int _capacity(int length) {
    var capacity = 1;
    while (capacity < length) {
      capacity <<= 1;
    }
    return capacity;
  }
}

/// Shared by synchronous render encoders. Each bind copies the packed bytes
/// before another call can overwrite this storage.
final InstancePackingScratch transientInstancePackingScratch =
    InstancePackingScratch();

/// Floats in the model transform alone, the record a depth-style pass consumes.
const int kInstanceTransformFloats = 16;

/// Floats in the engine's fixed instance record, the model transform plus the
/// color multiplier. A material declaring `instance_attributes` appends its
/// packed attribute floats after these.
const int kInstanceRecordFloats = 20;

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

/// Per-instance world transforms and color multipliers for a color pass,
/// followed by the material's declared per-instance attributes.
class PackedInstanceData implements PackedInstances {
  PackedInstanceData(this.ccw, this.cw, {this.attributeFloats = 0});

  @override
  final Float32List ccw;
  @override
  final Float32List cw;

  /// Attribute floats appended to each record, past the transform and color.
  final int attributeFloats;

  /// Floats one record occupies.
  int get recordFloats => kInstanceRecordFloats + attributeFloats;

  @override
  int get ccwCount => ccw.length ~/ recordFloats;
  @override
  int get cwCount => cw.length ~/ recordFloats;
}

/// One retained instance group consumed by [packInstanceDataBatches].
class InstanceDataBatch {
  InstanceDataBatch({
    required this.nodeTransform,
    required List<Matrix4> instances,
    required List<Vector4> colors,
    required this.nodeWindingFlipped,
    this.instanceWindingFlipped,
    this.indices,
    this.attributeData,
    this.attributeFloats = 0,
  }) : instances = instances,
       colors = colors,
       packedWorldData = null,
       packedWindingFlipped = null,
       assert(instances.length == colors.length),
       assert(
         instanceWindingFlipped == null ||
             instanceWindingFlipped.length == instances.length,
       ),
       assert(indices == null || indices.length <= instances.length),
       assert(attributeFloats == 0 || attributeData != null);

  InstanceDataBatch.single({
    required this.nodeTransform,
    required this.nodeWindingFlipped,
  }) : instances = null,
       colors = null,
       packedWorldData = null,
       packedWindingFlipped = null,
       instanceWindingFlipped = null,
       indices = null,
       attributeData = null,
       attributeFloats = 0;

  InstanceDataBatch.cached({
    required Float32List packedWorldData,
    required Uint8List packedWindingFlipped,
    this.indices,
    this.attributeFloats = 0,
  }) : nodeTransform = _identity,
       instances = null,
       colors = null,
       packedWorldData = packedWorldData,
       packedWindingFlipped = packedWindingFlipped,
       nodeWindingFlipped = false,
       instanceWindingFlipped = null,
       attributeData = null,
       assert(
         packedWorldData.length % (kInstanceRecordFloats + attributeFloats) ==
             0,
       ),
       assert(
         packedWindingFlipped.length ==
             packedWorldData.length ~/
                 (kInstanceRecordFloats + attributeFloats),
       ),
       assert(
         indices == null ||
             indices.length <=
                 packedWorldData.length ~/
                     (kInstanceRecordFloats + attributeFloats),
       );

  static final Matrix4 _identity = Matrix4.identity();

  final Matrix4 nodeTransform;
  final List<Matrix4>? instances;
  final List<Vector4>? colors;
  final Float32List? packedWorldData;
  final Uint8List? packedWindingFlipped;
  final bool nodeWindingFlipped;
  final List<bool>? instanceWindingFlipped;
  final List<int>? indices;

  /// Per-instance custom attribute floats for the unpacked path,
  /// [attributeFloats] per instance in declaration order. Null when the batch
  /// carries none.
  final Float32List? attributeData;

  /// Custom attribute floats this batch's source records carry.
  final int attributeFloats;

  /// Floats one source record occupies in [packedWorldData].
  int get sourceRecordFloats => kInstanceRecordFloats + attributeFloats;

  int get length => packedWorldData == null
      ? (instances == null ? 1 : (indices?.length ?? instances!.length))
      : (indices?.length ?? packedWorldData!.length ~/ sourceRecordFloats);
}

/// Packs several retained groups without building a flattened matrix list.
///
/// [attributeFloats] is the material's custom per-instance attribute width;
/// records are that much wider and a batch that carries no matching attribute
/// data contributes zeros, never stale scratch bytes.
PackedInstanceData packInstanceDataBatches(
  List<InstanceDataBatch> batches, {
  int attributeFloats = 0,
  InstancePackingScratch? scratch,
}) {
  final recordFloats = kInstanceRecordFloats + attributeFloats;
  var count = 0;
  for (final batch in batches) {
    count += batch.length;
  }
  final flipped = scratch?.flipped(count) ?? Uint8List(count);
  final batchWinding =
      scratch?.batchWinding(batches.length) ?? Uint8List(batches.length);
  var cwCount = 0;
  var flatIndex = 0;
  for (var batchIndex = 0; batchIndex < batches.length; batchIndex++) {
    final batch = batches[batchIndex];
    final batchCwStart = cwCount;
    final packedWinding = batch.packedWindingFlipped;
    if (packedWinding != null) {
      final indices = batch.indices;
      for (var slot = 0; slot < batch.length; slot++) {
        final i = indices?[slot] ?? slot;
        if (packedWinding[i] != 0) {
          flipped[flatIndex] = 1;
          cwCount++;
        }
        flatIndex++;
      }
      final batchCwCount = cwCount - batchCwStart;
      batchWinding[batchIndex] = batchCwCount == 0
          ? 0
          : (batchCwCount == batch.length ? 1 : 2);
      continue;
    }
    final instances = batch.instances;
    if (instances == null) {
      if (batch.nodeWindingFlipped) {
        flipped[flatIndex] = 1;
        cwCount++;
      }
      flatIndex++;
      batchWinding[batchIndex] = batch.nodeWindingFlipped ? 1 : 0;
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
    final batchCwCount = cwCount - batchCwStart;
    batchWinding[batchIndex] = batchCwCount == 0
        ? 0
        : (batchCwCount == batch.length ? 1 : 2);
  }

  final ccwLength = (count - cwCount) * recordFloats;
  final cwLength = cwCount * recordFloats;
  final ccw = scratch?.ccw(ccwLength) ?? Float32List(ccwLength);
  final cw = scratch?.cw(cwLength) ?? Float32List(cwLength);
  final world = scratch?.world ?? Matrix4.zero();
  var ccwIndex = 0, cwIndex = 0;
  flatIndex = 0;
  for (var batchIndex = 0; batchIndex < batches.length; batchIndex++) {
    final batch = batches[batchIndex];
    // A batch whose source does not carry this material's attributes (a
    // synthesized single-node record) contributes zeros rather than whatever
    // the reused scratch last held.
    final carriesAttributes =
        attributeFloats > 0 && batch.attributeFloats == attributeFloats;
    final packedData = batch.packedWorldData;
    if (packedData != null) {
      final indices = batch.indices;
      if (indices == null && (attributeFloats == 0 || carriesAttributes)) {
        final winding = batchWinding[batchIndex];
        if (winding != 2) {
          final target = winding == 0 ? ccw : cw;
          final targetIndex = winding == 0 ? ccwIndex : cwIndex;
          final offset = targetIndex * recordFloats;
          target.setRange(offset, offset + packedData.length, packedData);
          if (winding == 0) {
            ccwIndex += batch.length;
          } else {
            cwIndex += batch.length;
          }
          flatIndex += batch.length;
          continue;
        }
      }
      final sourceFloats = batch.sourceRecordFloats;
      for (var slot = 0; slot < batch.length; slot++) {
        final source = indices?[slot] ?? slot;
        final isFlipped = flipped[flatIndex++] != 0;
        final target = isFlipped ? cw : ccw;
        final targetIndex = isFlipped ? cwIndex++ : ccwIndex++;
        final offset = targetIndex * recordFloats;
        final copied = carriesAttributes ? recordFloats : kInstanceRecordFloats;
        target.setRange(
          offset,
          offset + copied,
          packedData,
          source * sourceFloats,
        );
        if (copied < recordFloats) {
          target.fillRange(offset + copied, offset + recordFloats, 0);
        }
      }
      continue;
    }
    final instances = batch.instances;
    if (instances == null) {
      final isFlipped = flipped[flatIndex++] != 0;
      final target = isFlipped ? cw : ccw;
      final targetIndex = isFlipped ? cwIndex++ : ccwIndex++;
      final offset = targetIndex * recordFloats;
      target.setAll(offset, batch.nodeTransform.storage);
      target.setRange(offset + 16, offset + kInstanceRecordFloats, _whiteColor);
      if (attributeFloats > 0) {
        target.fillRange(
          offset + kInstanceRecordFloats,
          offset + recordFloats,
          0,
        );
      }
      continue;
    }
    final colors = batch.colors!;
    final indices = batch.indices;
    final attributes = carriesAttributes ? batch.attributeData! : null;
    for (var slot = 0; slot < batch.length; slot++) {
      final i = indices?[slot] ?? slot;
      world.setFrom(batch.nodeTransform);
      world.multiply(instances[i]);
      final isFlipped = flipped[flatIndex++] != 0;
      final target = isFlipped ? cw : ccw;
      final targetIndex = isFlipped ? cwIndex++ : ccwIndex++;
      final offset = targetIndex * recordFloats;
      target.setAll(offset, world.storage);
      target.setAll(offset + 16, colors[i].storage);
      if (attributes != null) {
        target.setRange(
          offset + kInstanceRecordFloats,
          offset + recordFloats,
          attributes,
          i * attributeFloats,
        );
      } else if (attributeFloats > 0) {
        target.fillRange(
          offset + kInstanceRecordFloats,
          offset + recordFloats,
          0,
        );
      }
    }
  }
  return PackedInstanceData(ccw, cw, attributeFloats: attributeFloats);
}

/// Packs retained groups as transform-only records for depth-style passes.
PackedInstanceTransforms packInstanceTransformBatches(
  List<InstanceDataBatch> batches, {
  InstancePackingScratch? scratch,
}) {
  var count = 0;
  for (final batch in batches) {
    count += batch.length;
  }
  final flipped = scratch?.flipped(count) ?? Uint8List(count);
  var cwCount = 0;
  var flatIndex = 0;
  for (final batch in batches) {
    final packedWinding = batch.packedWindingFlipped;
    if (packedWinding != null) {
      final indices = batch.indices;
      for (var slot = 0; slot < batch.length; slot++) {
        final i = indices?[slot] ?? slot;
        if (packedWinding[i] != 0) {
          flipped[flatIndex] = 1;
          cwCount++;
        }
        flatIndex++;
      }
      continue;
    }
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

  final ccwLength = (count - cwCount) * 16;
  final cwLength = cwCount * 16;
  final ccw = scratch?.ccw(ccwLength) ?? Float32List(ccwLength);
  final cw = scratch?.cw(cwLength) ?? Float32List(cwLength);
  final world = scratch?.world ?? Matrix4.zero();
  var ccwIndex = 0, cwIndex = 0;
  flatIndex = 0;
  for (final batch in batches) {
    final packedData = batch.packedWorldData;
    if (packedData != null) {
      final indices = batch.indices;
      final sourceFloats = batch.sourceRecordFloats;
      for (var slot = 0; slot < batch.length; slot++) {
        final source = indices?[slot] ?? slot;
        final isFlipped = flipped[flatIndex++] != 0;
        final target = isFlipped ? cw : ccw;
        final targetIndex = isFlipped ? cwIndex++ : ccwIndex++;
        final offset = targetIndex * kInstanceTransformFloats;
        target.setRange(
          offset,
          offset + kInstanceTransformFloats,
          packedData,
          source * sourceFloats,
        );
      }
      continue;
    }
    final instances = batch.instances;
    if (instances == null) {
      final isFlipped = flipped[flatIndex++] != 0;
      final target = isFlipped ? cw : ccw;
      final targetIndex = isFlipped ? cwIndex++ : ccwIndex++;
      target.setAll(targetIndex * 16, batch.nodeTransform.storage);
      continue;
    }
    final indices = batch.indices;
    for (var slot = 0; slot < batch.length; slot++) {
      final i = indices?[slot] ?? slot;
      world
        ..setFrom(batch.nodeTransform)
        ..multiply(instances[i]);
      final isFlipped = flipped[flatIndex++] != 0;
      final target = isFlipped ? cw : ccw;
      final targetIndex = isFlipped ? cwIndex++ : ccwIndex++;
      target.setAll(targetIndex * 16, world.storage);
    }
  }
  return PackedInstanceTransforms(ccw, cw);
}

const List<double> _whiteColor = [1, 1, 1, 1];

/// Packs world transforms followed by linear RGBA color multipliers, then the
/// material's declared per-instance attributes.
PackedInstanceData packInstanceData(
  Matrix4 nodeTransform,
  List<Matrix4> instances,
  List<Vector4> colors, {
  bool nodeWindingFlipped = false,
  List<bool>? instanceWindingFlipped,
  List<int>? indices,
  Vector3? sortBackToFrontFrom,
  Float32List? attributeData,
  int attributeFloats = 0,
  InstancePackingScratch? scratch,
}) {
  assert(instances.length == colors.length);
  if (sortBackToFrontFrom == null) {
    return packInstanceDataBatches(
      [
        InstanceDataBatch(
          nodeTransform: nodeTransform,
          instances: instances,
          colors: colors,
          nodeWindingFlipped: nodeWindingFlipped,
          instanceWindingFlipped: instanceWindingFlipped,
          indices: indices,
          attributeData: attributeData,
          attributeFloats: attributeData == null ? 0 : attributeFloats,
        ),
      ],
      attributeFloats: attributeFloats,
      scratch: scratch,
    );
  }

  final sorted = _sortInstances(
    nodeTransform,
    instances,
    nodeWindingFlipped,
    sortBackToFrontFrom,
    instanceWindingFlipped,
    indices,
  );

  final recordFloats = kInstanceRecordFloats + attributeFloats;
  Float32List pack(List<int> order) {
    final result = Float32List(order.length * recordFloats);
    for (var i = 0; i < order.length; i++) {
      final source = order[i];
      final offset = i * recordFloats;
      result.setRange(offset, offset + 16, sorted.worldTransforms, source * 16);
      result.setAll(offset + 16, colors[source].storage);
      if (attributeData != null && attributeFloats > 0) {
        result.setRange(
          offset + kInstanceRecordFloats,
          offset + recordFloats,
          attributeData,
          source * attributeFloats,
        );
      }
    }
    return result;
  }

  return PackedInstanceData(
    pack(sorted.ccw),
    pack(sorted.cw),
    attributeFloats: attributeFloats,
  );
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
  InstancePackingScratch? scratch,
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
  final flipped = scratch?.flipped(count) ?? Uint8List(count);
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
  final ccwLength = (count - cwCount) * 16;
  final cwLength = cwCount * 16;
  final ccw = scratch?.ccw(ccwLength) ?? Float32List(ccwLength);
  final cw = scratch?.cw(cwLength) ?? Float32List(cwLength);
  var ccwIndex = 0, cwIndex = 0;
  final world = scratch?.world ?? Matrix4.zero();
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
///
/// [attributeFloats] widens the record to match a material declaring
/// `instance_attributes`; a non-instanced draw has nowhere to take those
/// values from, so they read zero (documented in MATERIALS.md).
void bindSingleInstanceData(
  gpu.RenderPass pass,
  Matrix4 worldTransform, {
  int slot = 1,
  int attributeFloats = 0,
}) {
  bindInstanceData(
    pass,
    packSingleInstanceData(worldTransform, attributeFloats: attributeFloats),
    slot: slot,
  );
}

/// The one-element record [bindSingleInstanceData] uploads: [worldTransform], a
/// white color multiplier, then [attributeFloats] zeros.
///
/// The returned list is shared scratch; the caller copies it out before the
/// next call.
Float32List packSingleInstanceData(
  Matrix4 worldTransform, {
  int attributeFloats = 0,
}) {
  if (attributeFloats == 0) {
    return _singleInstanceDataScratch..setAll(0, worldTransform.storage);
  }
  final floats = kInstanceRecordFloats + attributeFloats;
  var scratch = _singleWideInstanceDataScratch;
  if (scratch == null || scratch.length != floats) {
    scratch = _singleWideInstanceDataScratch = Float32List(floats)
      ..setRange(16, kInstanceRecordFloats, const [1, 1, 1, 1]);
  }
  return scratch
    ..setAll(0, worldTransform.storage)
    ..fillRange(kInstanceRecordFloats, floats, 0);
}

// Reused like the fixed-width scratch above, rebuilt when a draw needs a
// different attribute width (a scene mixes few such materials).
Float32List? _singleWideInstanceDataScratch;

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
