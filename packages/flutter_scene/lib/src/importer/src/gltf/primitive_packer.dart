import 'dart:math' show sqrt;
import 'dart:typed_data';

import 'package:scene/scene.dart' show sceneLog;

import '../../constants.dart';
import 'accessor.dart';
import 'coordinate_policy.dart';
import 'draco/gltf_draco.dart';
import 'types.dart';

/// Pure-data result of packing a glTF mesh primitive into
/// flutter_scene's vertex layout.
///
/// Shared by the runtime GLB importer and the offline scene emitter so layout,
/// attribute defaults, and index handling stay identical. The selected
/// coordinate policy controls whether spatial values remain in source space
/// or are baked into native scene space.
class PackedPrimitive {
  PackedPrimitive({
    required this.vertexBytes,
    required this.vertexCount,
    required this.indexBytes,
    required this.indexCount,
    required this.indices32Bit,
    required this.isSkinned,
    required this.sourceWindingFlipped,
    this.morphTargets,
  });

  /// Packed vertex buffer in the engine's vertex layout (72 bytes per
  /// unskinned vertex, 104 per skinned).
  final Uint8List vertexBytes;

  /// Number of vertices in [vertexBytes].
  final int vertexCount;

  /// Packed index buffer, either 16- or 32-bit per [indices32Bit].
  final Uint8List indexBytes;

  /// Number of indices in [indexBytes].
  final int indexCount;

  /// Whether [indexBytes] holds 32-bit (`true`) or 16-bit indices.
  final bool indices32Bit;

  /// Whether the vertex layout includes joints and weights.
  final bool isSkinned;

  /// Whether the packed source convention reverses native winding.
  final bool sourceWindingFlipped;

  /// The primitive's morph target deltas, remapped to the packed vertex
  /// order and coordinate-converted like the base vertices, or null when
  /// the primitive declares no targets.
  final PackedMorphTargets? morphTargets;
}

/// Morph target deltas packed alongside a [PackedPrimitive], target-major
/// (`[target][vertex][component]`), aligned with the packed vertex order.
class PackedMorphTargets {
  PackedMorphTargets({
    required this.targetCount,
    required this.vertexCount,
    required this.positionDeltas,
    this.normalDeltas,
    this.tangentDeltas,
  });

  /// The number of morph targets.
  final int targetCount;

  /// The packed primitive's vertex count each target's deltas cover.
  final int vertexCount;

  /// Position deltas, `targetCount * vertexCount * 3` floats.
  final Float32List positionDeltas;

  /// Normal deltas (same shape as [positionDeltas]), or null when no target
  /// carries them or the base primitive has no authored normals.
  final Float32List? normalDeltas;

  /// Tangent deltas, xyz only (the bitangent sign always comes from the
  /// base tangent), or null when absent. Stored for later use; blending
  /// does not apply them yet. TODO(morph-tangent-deltas): apply tangent
  /// deltas in the CPU and GPU blend paths.
  final Float32List? tangentDeltas;
}

/// Packs a glTF mesh primitive into the engine's vertex/index layout.
///
/// The vertex layout matches `shaders/flutter_scene_(un)skinned.vert`:
///
/// - Unskinned (72 bytes/vertex): position(3 f32), normal(3 f32),
///   texture_coords(2 f32), texture_coords_1(2 f32), color(4 f32),
///   tangent(4 f32).
/// - Skinned (104 bytes/vertex): unskinned + joints(4 f32) +
///   weights(4 f32). Sources rigged with more than four influences per
///   vertex are merged down to the strongest four and renormalized
///   (see [_mergeJointInfluenceSets]); vertices then always blend a full
///   unit of weight, so skinned meshes hold their authored rest shape.
///
/// When the primitive omits the NORMAL attribute, glTF requires the
/// client to generate flat normals. A vertex shared by several
/// triangles can't carry a single per-face normal, so the primitive is
/// de-indexed (every triangle expanded to three unique vertices, each
/// carrying that triangle's face normal) with a sequential index
/// buffer. Primitives that author normals are kept as-is.
///
/// Set [includeSkinning] to false when the owning node has no skin. Some
/// exporters leave joint attributes on otherwise static primitives.
PackedPrimitive packGltfPrimitive({
  required GltfMeshPrimitive primitive,
  required List<GltfAccessor> accessors,
  required List<GltfBufferView> bufferViews,
  required Uint8List bufferData,
  required GltfCoordinatePolicy coordinatePolicy,
  bool includeSkinning = true,
}) {
  // KHR_draco_mesh_compression: decode the payload and swap in synthesized
  // accessor tables, so the packing below reads decoded data unchanged.
  if (primitive.draco != null) {
    final resolved = decodeDracoPrimitive(
      primitive: primitive,
      accessors: accessors,
      bufferViews: bufferViews,
      bufferData: bufferData,
    );
    accessors = resolved.accessors;
    bufferViews = resolved.bufferViews;
    bufferData = resolved.bufferData;
  }
  final positionIdx = primitive.attributes['POSITION'];
  if (positionIdx == null) {
    throw const FormatException('Mesh primitive is missing POSITION attribute');
  }
  final positions = _readVec3(positionIdx, accessors, bufferViews, bufferData);
  final vertexCount = positions.length ~/ 3;

  // Read (or synthesize) the triangle index list up front: it's needed
  // both to build the index buffer and to generate normals when the
  // glTF primitive omits them.
  final Uint32List indexList;
  final bool indices32Bit;
  if (primitive.indices != null) {
    final accessor = accessors[primitive.indices!];
    indexList = readAccessorAsUint32(accessor, bufferViews, bufferData);
    indices32Bit = accessor.componentType == GltfComponentType.unsignedInt;
  } else {
    // No indices: a sequential triangle list.
    indexList = Uint32List(vertexCount);
    for (int i = 0; i < vertexCount; i++) {
      indexList[i] = i;
    }
    indices32Bit = false;
  }

  // Source attribute arrays, indexed by original glTF vertex index.
  final texCoords = _readOptionalVec2(
    'TEXCOORD_0',
    primitive,
    accessors,
    bufferViews,
    bufferData,
    vertexCount,
  );
  final texCoords1 = _readOptionalVec2(
    'TEXCOORD_1',
    primitive,
    accessors,
    bufferViews,
    bufferData,
    vertexCount,
  );
  final colors = _readOptionalColor(
    'COLOR_0',
    primitive,
    accessors,
    bufferViews,
    bufferData,
    vertexCount,
  );
  final tangents = _readOptionalVec4(
    'TANGENT',
    primitive,
    accessors,
    bufferViews,
    bufferData,
    vertexCount,
  );
  final hasJoints =
      includeSkinning &&
      primitive.attributes.containsKey('JOINTS_0') &&
      primitive.attributes.containsKey('WEIGHTS_0');
  Float32List? joints;
  Float32List? weights;
  if (hasJoints) {
    // Assets rigged with more than four influences per vertex (UniRig,
    // auto-riggers, Blender exports above the engine's budget) spread the
    // blend across several JOINTS_n/WEIGHTS_n sets. Reading only set 0
    // would leave vertices far short of a full unit of weight, which draws
    // them pulled toward the armature origin even in the rest pose.
    final merged = _mergeJointInfluenceSets(
      primitive: primitive,
      accessors: accessors,
      bufferViews: bufferViews,
      bufferData: bufferData,
      vertexCount: vertexCount,
    );
    joints = merged.$1;
    weights = merged.$2;
  }

  // Determine the output vertex set. With authored normals the mesh is
  // kept as-is; without them it is de-indexed for flat normals (see the
  // function doc).
  final List<int> srcOf; // output vertex index -> source vertex index
  final Float32List normals; // output-vertex normals (3 per vertex)
  final Uint32List outIndexList;
  final bool outIndices32Bit;

  if (primitive.attributes.containsKey('NORMAL')) {
    normals = _readVec3(
      primitive.attributes['NORMAL']!,
      accessors,
      bufferViews,
      bufferData,
    );
    srcOf = List<int>.generate(vertexCount, (i) => i);
    outIndexList = indexList;
    outIndices32Bit = indices32Bit;
  } else {
    final triCount = indexList.length ~/ 3;
    final outCount = triCount * 3;
    srcOf = List<int>.filled(outCount, 0);
    normals = Float32List(outCount * 3);
    for (int t = 0; t < triCount; t++) {
      final i0 = indexList[t * 3];
      final i1 = indexList[t * 3 + 1];
      final i2 = indexList[t * 3 + 2];
      final ax = positions[i0 * 3];
      final ay = positions[i0 * 3 + 1];
      final az = positions[i0 * 3 + 2];
      final e1x = positions[i1 * 3] - ax;
      final e1y = positions[i1 * 3 + 1] - ay;
      final e1z = positions[i1 * 3 + 2] - az;
      final e2x = positions[i2 * 3] - ax;
      final e2y = positions[i2 * 3 + 1] - ay;
      final e2z = positions[i2 * 3 + 2] - az;
      var nx = e1y * e2z - e1z * e2y;
      var ny = e1z * e2x - e1x * e2z;
      var nz = e1x * e2y - e1y * e2x;
      final len = sqrt(nx * nx + ny * ny + nz * nz);
      if (len > 1e-12) {
        nx /= len;
        ny /= len;
        nz /= len;
      } else {
        // Degenerate (zero-area) triangle: pick an arbitrary normal.
        nx = 0;
        ny = 1;
        nz = 0;
      }
      for (int c = 0; c < 3; c++) {
        final k = t * 3 + c;
        srcOf[k] = indexList[t * 3 + c];
        normals[k * 3] = nx;
        normals[k * 3 + 1] = ny;
        normals[k * 3 + 2] = nz;
      }
    }
    outIndexList = Uint32List(outCount);
    for (int k = 0; k < outCount; k++) {
      outIndexList[k] = k;
    }
    // 16-bit indices address 0..65535.
    outIndices32Bit = outCount > 0x10000;
  }

  final outVertexCount = srcOf.length;
  final perVertex = hasJoints ? kSkinnedPerVertexSize : kUnskinnedPerVertexSize;
  final stride = perVertex ~/ 4; // floats per vertex
  final out = Float32List(outVertexCount * stride);

  for (int k = 0; k < outVertexCount; k++) {
    final o = k * stride;
    final s = srcOf[k];
    out[o + 0] = positions[s * 3 + 0];
    out[o + 1] = positions[s * 3 + 1];
    out[o + 2] = positions[s * 3 + 2];
    out[o + 3] = normals[k * 3 + 0];
    out[o + 4] = normals[k * 3 + 1];
    out[o + 5] = normals[k * 3 + 2];
    out[o + 6] = texCoords[s * 2 + 0];
    out[o + 7] = texCoords[s * 2 + 1];
    out[o + 8] = texCoords1[s * 2 + 0];
    out[o + 9] = texCoords1[s * 2 + 1];
    out[o + 10] = colors[s * 4 + 0];
    out[o + 11] = colors[s * 4 + 1];
    out[o + 12] = colors[s * 4 + 2];
    out[o + 13] = colors[s * 4 + 3];
    out[o + 14] = tangents[s * 4 + 0];
    out[o + 15] = tangents[s * 4 + 1];
    out[o + 16] = tangents[s * 4 + 2];
    out[o + 17] = tangents[s * 4 + 3];
    if (hasJoints) {
      final j = o + 18;
      out[j + 0] = joints![s * 4 + 0];
      out[j + 1] = joints[s * 4 + 1];
      out[j + 2] = joints[s * 4 + 2];
      out[j + 3] = joints[s * 4 + 3];
      out[j + 4] = weights![s * 4 + 0];
      out[j + 5] = weights[s * 4 + 1];
      out[j + 6] = weights[s * 4 + 2];
      out[j + 7] = weights[s * 4 + 3];
    }
  }

  // Runtime import stops above with an exact source copy. Offline import pays
  // for a separate conversion pass so serialized geometry is native.
  if (coordinatePolicy.bakesNative) {
    for (var o = 0; o < out.length; o += stride) {
      out[o + 2] = -out[o + 2];
      out[o + 5] = -out[o + 5];
      out[o + 16] = -out[o + 16];
      out[o + 17] = -out[o + 17];
    }
    // Negating Z mirrors triangle winding; swap indices (a, b, c) -> (a, c, b)
    // so baked native geometry retains Counter-Clockwise (CCW) front faces.
    for (var i = 0; i + 2 < outIndexList.length; i += 3) {
      final tmp = outIndexList[i + 1];
      outIndexList[i + 1] = outIndexList[i + 2];
      outIndexList[i + 2] = tmp;
    }
  }

  // The engine wants 16- or 32-bit indices. Pass 32-bit through; narrow
  // everything else to 16-bit.
  final Uint8List indexBytes;
  if (outIndices32Bit) {
    indexBytes = outIndexList.buffer.asUint8List(
      outIndexList.offsetInBytes,
      outIndexList.lengthInBytes,
    );
  } else {
    final widened = Uint16List(outIndexList.length);
    for (int i = 0; i < outIndexList.length; i++) {
      widened[i] = outIndexList[i];
    }
    indexBytes = widened.buffer.asUint8List(
      widened.offsetInBytes,
      widened.lengthInBytes,
    );
  }

  return PackedPrimitive(
    vertexBytes: out.buffer.asUint8List(out.offsetInBytes, out.lengthInBytes),
    vertexCount: outVertexCount,
    indexBytes: indexBytes,
    indexCount: outIndexList.length,
    indices32Bit: outIndices32Bit,
    isSkinned: hasJoints,
    sourceWindingFlipped: coordinatePolicy.sourceWindingFlipped,
    morphTargets: _packMorphTargets(
      primitive,
      accessors,
      bufferViews,
      bufferData,
      srcOf: srcOf,
      sourceVertexCount: vertexCount,
      coordinatePolicy: coordinatePolicy,
    ),
  );
}

/// Reads a primitive's morph targets into packed, target-major delta slabs
/// aligned with the packed vertex order ([srcOf] maps output vertex to
/// source vertex, identity unless the primitive was de-indexed for flat
/// normals). Deltas are additive per spec; a native-baking policy negates
/// each delta's Z like the base attributes.
/// The most joint/weight sets a primitive is scanned for. glTF requires
/// set suffixes to be sequential starting at 0; real exporters stay far
/// below this.
const int _maxJointInfluenceSets = 8;

/// Skipped weight threshold when ranking influences: anything at or below
/// contributes nothing to the blend and only risks displacing a useful
/// influence out of the four slots.
const double _minMeaningfulWeight = 1e-6;

/// Merges every `JOINTS_n`/`WEIGHTS_n` attribute pair into one four-slot
/// influence set per vertex, keeping the strongest influences and
/// renormalizing so the surviving weights sum to 1.
///
/// With four or fewer influences per vertex the merge is exact. Above
/// four it approximates: the weakest influences are dropped and the
/// survivors renormalize to a full unit of weight — the same contract
/// Blender's "Limit Total + Normalize All" applies before export. Slots
/// that end up empty carry weight 0 bound to the vertex's dominant joint,
/// so the shader never multiplies an uninitialized index into the joints
/// texture.
///
/// Returns `(joints, weights)`, `vertexCount * 4` floats each.
(Float32List, Float32List) _mergeJointInfluenceSets({
  required GltfMeshPrimitive primitive,
  required List<GltfAccessor> accessors,
  required List<GltfBufferView> bufferViews,
  required Uint8List bufferData,
  required int vertexCount,
}) {
  final jointSets = <Float32List>[];
  final weightSets = <Float32List>[];
  var droppedSets = false;
  for (var set = 0; set < _maxJointInfluenceSets; set++) {
    final jointIdx = primitive.attributes['JOINTS_$set'];
    final weightIdx = primitive.attributes['WEIGHTS_$set'];
    if (jointIdx == null && weightIdx == null) continue;
    if (jointIdx == null || weightIdx == null) {
      // A lone half-pair cannot bind anything; skip it rather than fail.
      droppedSets = true;
      continue;
    }
    jointSets.add(
      _readVec4(jointIdx, accessors, bufferViews, bufferData),
    );
    weightSets.add(
      _readVec4(weightIdx, accessors, bufferViews, bufferData),
    );
  }

  final mergedJoints = Float32List(vertexCount * 4);
  final mergedWeights = Float32List(vertexCount * 4);

  // Influence scratch space: up to [_maxJointInfluenceSets] * 4 entries,
  // ranked by descending weight with stable order for ties.
  final infJoint = Int32List(_maxJointInfluenceSets * 4);
  final infWeight = Float32List(_maxJointInfluenceSets * 4);

  if (weightSets.length > 1 || droppedSets) {
    sceneLog(
      'glTF: primitive carries ${weightSets.length} joint/weight influence '
      'sets${droppedSets ? ' (some incomplete pairs ignored)' : ''}; merged '
      'to the top 4 influences per vertex and renormalized.',
    );
  }

  for (var v = 0; v < vertexCount; v++) {
    var count = 0;
    var total = 0.0;
    for (var s = 0; s < weightSets.length; s++) {
      final ws = weightSets[s];
      final js = jointSets[s];
      for (var c = 0; c < 4; c++) {
        final w = ws[v * 4 + c];
        if (w <= _minMeaningfulWeight) continue;
        total += w;
        infJoint[count] = js[v * 4 + c].toInt();
        infWeight[count] = w;
        count++;
      }
    }

    if (count == 0 || total <= 0) {
      // Degenerate vertex (all-zero weights): pin to set 0 slot 0 so it
      // follows a real bone instead of collapsing toward the origin.
      final fallback = weightSets.isEmpty
          ? 0
          : jointSets[0][v * 4].toInt();
      mergedJoints[v * 4] = fallback.toDouble();
      mergedWeights[v * 4] = 1.0;
      continue;
    }

    // Rank by descending weight, insertion sort (count is tiny and the
    // array is nearly sorted in practice since exporters list strongest
    // first within each set).
    for (var i = 1; i < count; i++) {
      final w = infWeight[i];
      final j = infJoint[i];
      var k = i - 1;
      while (k >= 0 && infWeight[k] < w) {
        infWeight[k + 1] = infWeight[k];
        infJoint[k + 1] = infJoint[k];
        k--;
      }
      infWeight[k + 1] = w;
      infJoint[k + 1] = j;
    }

    final kept = count < 4 ? count : 4;
    final dominant = infJoint[0];
    // Normalize over the KEPT influences so every vertex blends a full
    // unit of weight even after dropping the tail: this pins the mesh to
    // its authored shape whenever the joints sit at their bind pose, no
    // matter how many influences were cut.
    var keptSum = 0.0;
    for (var c = 0; c < kept; c++) {
      keptSum += infWeight[c];
    }
    for (var c = 0; c < 4; c++) {
      mergedJoints[v * 4 + c] =
          c < kept ? infJoint[c].toDouble() : dominant.toDouble();
      mergedWeights[v * 4 + c] =
          c < kept ? infWeight[c] / keptSum : 0.0;
    }
  }

  return (mergedJoints, mergedWeights);
}

PackedMorphTargets? _packMorphTargets(
  GltfMeshPrimitive primitive,
  List<GltfAccessor> accessors,
  List<GltfBufferView> bufferViews,
  Uint8List bufferData, {
  required List<int> srcOf,
  required int sourceVertexCount,
  required GltfCoordinatePolicy coordinatePolicy,
}) {
  final targets = primitive.targets;
  if (targets.isEmpty) return null;

  final hasBaseNormals = primitive.attributes.containsKey('NORMAL');
  final hasBaseTangents = primitive.attributes.containsKey('TANGENT');
  final anyNormals = targets.any((t) => t.containsKey('NORMAL'));
  final anyTangents = targets.any((t) => t.containsKey('TANGENT'));
  // Without authored base normals the primitive was de-indexed to flat
  // normals; deltas relative to normals the asset never authored have no
  // meaning, so they are dropped. TODO(morph-flat-normals): regenerate flat
  // normals from morphed positions instead of keeping the rest normals.
  if (anyNormals && !hasBaseNormals) {
    sceneLog(
      'glTF morph targets carry NORMAL deltas but the base primitive has no '
      'authored normals; morphing keeps the generated flat normals',
    );
  }
  // Tangent deltas without base normals cannot produce a valid frame; with
  // base normals but no base tangent there is nothing to offset.
  if (anyTangents && !hasBaseTangents) {
    sceneLog(
      'glTF morph targets carry TANGENT deltas but the base primitive has no '
      'authored tangents; ignoring them',
    );
  }
  final includeNormals = anyNormals && hasBaseNormals;
  final includeTangents = anyTangents && hasBaseTangents && hasBaseNormals;

  final outVertexCount = srcOf.length;
  final targetCount = targets.length;
  final positionDeltas = Float32List(targetCount * outVertexCount * 3);
  final normalDeltas = includeNormals
      ? Float32List(targetCount * outVertexCount * 3)
      : null;
  final tangentDeltas = includeTangents
      ? Float32List(targetCount * outVertexCount * 3)
      : null;

  void fill(Float32List slab, int targetIndex, int accessorIndex) {
    final accessor = accessors[accessorIndex];
    if (accessor.count != sourceVertexCount) {
      throw FormatException(
        'glTF morph target accessor has ${accessor.count} elements; the '
        'primitive has $sourceVertexCount vertices',
      );
    }
    final source = readAccessorAsFloat32(accessor, bufferViews, bufferData);
    // POSITION/NORMAL deltas are VEC3; TANGENT deltas are VEC3 per spec but
    // a VEC4-authored one is tolerated (its w is ignored, the bitangent sign
    // always comes from the base tangent).
    final comps = accessor.type.componentCount;
    if (comps < 3) {
      throw FormatException(
        'glTF morph target accessor has $comps components; expected 3',
      );
    }
    final base = targetIndex * outVertexCount * 3;
    final flipZ = coordinatePolicy.bakesNative;
    for (var k = 0; k < outVertexCount; k++) {
      final s = srcOf[k] * comps;
      slab[base + k * 3] = source[s];
      slab[base + k * 3 + 1] = source[s + 1];
      slab[base + k * 3 + 2] = flipZ ? -source[s + 2] : source[s + 2];
    }
  }

  for (var t = 0; t < targetCount; t++) {
    final target = targets[t];
    // A target may omit any attribute; omitted deltas stay zero.
    final position = target['POSITION'];
    if (position != null) fill(positionDeltas, t, position);
    final normal = target['NORMAL'];
    if (normalDeltas != null && normal != null) fill(normalDeltas, t, normal);
    final tangent = target['TANGENT'];
    if (tangentDeltas != null && tangent != null) {
      fill(tangentDeltas, t, tangent);
    }
  }

  return PackedMorphTargets(
    targetCount: targetCount,
    vertexCount: outVertexCount,
    positionDeltas: positionDeltas,
    normalDeltas: normalDeltas,
    tangentDeltas: tangentDeltas,
  );
}

Float32List _readVec3(
  int idx,
  List<GltfAccessor> accessors,
  List<GltfBufferView> bufferViews,
  Uint8List bufferData,
) {
  final accessor = accessors[idx];
  return readAccessorAsFloat32(accessor, bufferViews, bufferData);
}

Float32List _readVec4(
  int idx,
  List<GltfAccessor> accessors,
  List<GltfBufferView> bufferViews,
  Uint8List bufferData,
) {
  final accessor = accessors[idx];
  return readAccessorAsFloat32(accessor, bufferViews, bufferData);
}

Float32List _readOptionalVec4(
  String name,
  GltfMeshPrimitive primitive,
  List<GltfAccessor> accessors,
  List<GltfBufferView> bufferViews,
  Uint8List bufferData,
  int vertexCount,
) {
  final idx = primitive.attributes[name];
  if (idx == null) return Float32List(vertexCount * 4);
  return _readVec4(idx, accessors, bufferViews, bufferData);
}

Float32List _readOptionalVec2(
  String name,
  GltfMeshPrimitive primitive,
  List<GltfAccessor> accessors,
  List<GltfBufferView> bufferViews,
  Uint8List bufferData,
  int vertexCount,
) {
  final idx = primitive.attributes[name];
  if (idx == null) return Float32List(vertexCount * 2);
  final accessor = accessors[idx];
  return readAccessorAsFloat32(accessor, bufferViews, bufferData);
}

Float32List _readOptionalColor(
  String name,
  GltfMeshPrimitive primitive,
  List<GltfAccessor> accessors,
  List<GltfBufferView> bufferViews,
  Uint8List bufferData,
  int vertexCount,
) {
  final idx = primitive.attributes[name];
  if (idx == null) {
    // Default vertex color = opaque white.
    final out = Float32List(vertexCount * 4);
    for (int i = 0; i < vertexCount; i++) {
      out[i * 4 + 0] = 1.0;
      out[i * 4 + 1] = 1.0;
      out[i * 4 + 2] = 1.0;
      out[i * 4 + 3] = 1.0;
    }
    return out;
  }
  final accessor = accessors[idx];
  final raw = readAccessorAsFloat32(accessor, bufferViews, bufferData);
  if (accessor.type == GltfAccessorType.vec4) return raw;
  // Promote vec3 colors to vec4 with alpha=1.
  final out = Float32List(vertexCount * 4);
  for (int i = 0; i < vertexCount; i++) {
    out[i * 4 + 0] = raw[i * 3 + 0];
    out[i * 4 + 1] = raw[i * 3 + 1];
    out[i * 4 + 2] = raw[i * 3 + 2];
    out[i * 4 + 3] = 1.0;
  }
  return out;
}
