/// Reading a primitive's skinning influences, however many sets the source
/// spread them across.
library;

import 'dart:typed_data';

import 'package:scene/scene.dart' show sceneLog;

import 'accessor.dart';
import 'types.dart';

/// The most `JOINTS_n`/`WEIGHTS_n` pairs a primitive is scanned for.
///
/// glTF requires the suffixes to run sequentially from 0, and real exporters
/// stay far below this; the cap only bounds the scan for a malformed file.
const int _maxInfluenceSets = 8;

/// Weight below which an influence contributes nothing to the blend and only
/// risks displacing a useful one out of the four slots.
const double _minMeaningfulWeight = 1e-6;

/// One vertex's skinning influences, four per vertex, joint index and weight
/// interleaved the way the vertex layout wants them.
typedef JointInfluences = ({Float32List joints, Float32List weights});

/// Whether [primitive] carries skinning influences at all.
bool primitiveHasJointInfluences(GltfMeshPrimitive primitive) =>
    primitive.attributes.containsKey('JOINTS_0') &&
    primitive.attributes.containsKey('WEIGHTS_0');

/// Reads [primitive]'s skinning influences as one four-slot set per vertex.
///
/// The engine's vertex layout carries four influences. A rig authored with
/// more (UniRig and other auto-riggers, a Blender export left above the
/// four-influence limit) spreads them across `JOINTS_1`/`WEIGHTS_1` and
/// beyond. Reading only set 0 leaves those vertices holding a fraction of a
/// unit of weight, and a vertex that blends less than a full unit is dragged
/// toward the armature origin — the mesh collapses inward even in its rest
/// pose.
///
/// With one set the values are returned as authored, so an asset that already
/// fits the layout is read exactly as before. Above one set the merge keeps
/// the strongest four influences per vertex and renormalizes over them, which
/// is what "Limit Total + Normalize All" does in Blender before an export
/// that fits. Dropping the tail changes the deformation slightly; leaving the
/// weight unaccounted for does not deform the mesh at all.
///
/// Returns `vertexCount * 4` floats in each list.
JointInfluences readJointInfluences({
  required GltfMeshPrimitive primitive,
  required List<GltfAccessor> accessors,
  required List<GltfBufferView> bufferViews,
  required Uint8List bufferData,
  required int vertexCount,
}) {
  final jointSets = <Float32List>[];
  final weightSets = <Float32List>[];
  var incompletePair = false;
  for (var set = 0; set < _maxInfluenceSets; set++) {
    final jointIdx = primitive.attributes['JOINTS_$set'];
    final weightIdx = primitive.attributes['WEIGHTS_$set'];
    // Suffixes run sequentially, so the first absent pair ends the run.
    if (jointIdx == null && weightIdx == null) break;
    if (jointIdx == null || weightIdx == null) {
      // Half a pair binds nothing. Skip it rather than fail the import over
      // it, and say so, since the mesh will deform short of its authored
      // shape and the file is why.
      incompletePair = true;
      continue;
    }
    jointSets.add(
      readAccessorAsFloat32(accessors[jointIdx], bufferViews, bufferData),
    );
    weightSets.add(
      readAccessorAsFloat32(accessors[weightIdx], bufferViews, bufferData),
    );
  }

  if (incompletePair) {
    sceneLog(
      'glTF: a skinned primitive pairs a JOINTS_n with no WEIGHTS_n (or the '
      'reverse); that set was ignored and those vertices will blend short of '
      'a full unit of weight.',
    );
  }

  // The overwhelmingly common case: one set, already shaped for the layout.
  // Returned untouched, so nothing about an asset that always fit changes.
  if (jointSets.length == 1) {
    return (joints: jointSets[0], weights: weightSets[0]);
  }
  if (jointSets.isEmpty) {
    return (
      joints: Float32List(vertexCount * 4),
      weights: _rigidWeights(vertexCount),
    );
  }

  sceneLog(
    'glTF: a skinned primitive carries ${jointSets.length} influence sets; '
    'merged to the strongest 4 per vertex and renormalized.',
  );
  return _mergeInfluenceSets(jointSets, weightSets, vertexCount);
}

/// Weights that bind every vertex wholly to joint 0.
///
/// Used when a primitive claims to be skinned but carries no usable
/// influence, so the mesh follows one bone instead of collapsing to the
/// armature origin.
Float32List _rigidWeights(int vertexCount) {
  final weights = Float32List(vertexCount * 4);
  for (var v = 0; v < vertexCount; v++) {
    weights[v * 4] = 1.0;
  }
  return weights;
}

JointInfluences _mergeInfluenceSets(
  List<Float32List> jointSets,
  List<Float32List> weightSets,
  int vertexCount,
) {
  final mergedJoints = Float32List(vertexCount * 4);
  final mergedWeights = Float32List(vertexCount * 4);

  // Scratch for one vertex's influences, ranked by descending weight.
  // Reused across vertices so the merge allocates once.
  final candidateJoint = Int32List(_maxInfluenceSets * 4);
  final candidateWeight = Float64List(_maxInfluenceSets * 4);

  for (var v = 0; v < vertexCount; v++) {
    var count = 0;
    for (var s = 0; s < weightSets.length; s++) {
      final weights = weightSets[s];
      final joints = jointSets[s];
      for (var c = 0; c < 4; c++) {
        final weight = weights[v * 4 + c];
        if (weight <= _minMeaningfulWeight) continue;
        final joint = joints[v * 4 + c].toInt();
        // A joint listed in two sets is one influence split in two. Summing
        // it keeps the vertex's total intact and frees the slot the
        // duplicate would have taken from a joint that has none.
        var merged = false;
        for (var i = 0; i < count; i++) {
          if (candidateJoint[i] != joint) continue;
          candidateWeight[i] += weight;
          merged = true;
          break;
        }
        if (merged) continue;
        candidateJoint[count] = joint;
        candidateWeight[count] = weight;
        count++;
      }
    }

    if (count == 0) {
      // Every influence was zero. Bind to whatever joint set 0 names first,
      // so the vertex rides a real bone rather than the armature origin.
      mergedJoints[v * 4] = jointSets[0][v * 4];
      mergedWeights[v * 4] = 1.0;
      continue;
    }

    // Insertion sort by descending weight: `count` is at most 32 and usually
    // five or six, and exporters list the strongest first within a set, so
    // the input is close to sorted already.
    for (var i = 1; i < count; i++) {
      final weight = candidateWeight[i];
      final joint = candidateJoint[i];
      var k = i - 1;
      while (k >= 0 && candidateWeight[k] < weight) {
        candidateWeight[k + 1] = candidateWeight[k];
        candidateJoint[k + 1] = candidateJoint[k];
        k--;
      }
      candidateWeight[k + 1] = weight;
      candidateJoint[k + 1] = joint;
    }

    final kept = count < 4 ? count : 4;
    // Normalize over the influences that survive, not over everything that
    // was offered, so the vertex blends a full unit of weight however much
    // of the tail was cut. That is what pins the mesh to its authored shape
    // when the joints sit at their bind pose.
    var keptTotal = 0.0;
    for (var c = 0; c < kept; c++) {
      keptTotal += candidateWeight[c];
    }
    // The empty slots carry the dominant joint at weight zero: they
    // contribute nothing, and the index is one the skin is known to hold.
    final dominant = candidateJoint[0].toDouble();
    for (var c = 0; c < 4; c++) {
      mergedJoints[v * 4 + c] = c < kept
          ? candidateJoint[c].toDouble()
          : dominant;
      mergedWeights[v * 4 + c] = c < kept
          ? candidateWeight[c] / keptTotal
          : 0.0;
    }
  }

  return (joints: mergedJoints, weights: mergedWeights);
}
