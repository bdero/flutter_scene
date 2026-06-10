/// Offline bounds analysis shared by the scene emitters.
///
/// Provides static primitive AABBs (from the POSITION accessor's
/// spec-provided min/max, falling back to a vertex scan) and skinned
/// pose-union AABBs: for every skinned primitive, the union of the mesh's
/// extent across every animated pose, sampled at each keyframe time of every
/// channel driving the skin's joints. A pose-union bound is the only sound
/// cull bound for skinned content; the rest-pose AABB under-covers the mesh
/// once joints animate.
///
/// Pure Dart (no `dart:ui`/GPU), so it runs in the build-hook isolate.
library;

import 'dart:math';
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'accessor.dart';
import 'types.dart';

/// A mutable axis-aligned bounding box accumulator.
class AabbBounds {
  /// Creates a box from its extents.
  AabbBounds(
    this.minX,
    this.minY,
    this.minZ,
    this.maxX,
    this.maxY,
    this.maxZ,
    this.isEmpty,
  );

  /// An empty box (no points included yet).
  factory AabbBounds.empty() => AabbBounds(0, 0, 0, 0, 0, 0, true);

  /// The box extents. Meaningless while [isEmpty] is set.
  double minX, minY, minZ, maxX, maxY, maxZ;

  /// Whether no point has been included yet.
  bool isEmpty;

  /// Grows the box to include the point `(x, y, z)`.
  void includePoint(double x, double y, double z) {
    if (isEmpty) {
      minX = maxX = x;
      minY = maxY = y;
      minZ = maxZ = z;
      isEmpty = false;
      return;
    }
    if (x < minX) minX = x;
    if (y < minY) minY = y;
    if (z < minZ) minZ = z;
    if (x > maxX) maxX = x;
    if (y > maxY) maxY = y;
    if (z > maxZ) maxZ = z;
  }

  /// Grows the box to include the min/max corners of another AABB.
  void includeMinMax(
    double otherMinX,
    double otherMinY,
    double otherMinZ,
    double otherMaxX,
    double otherMaxY,
    double otherMaxZ,
  ) {
    includePoint(otherMinX, otherMinY, otherMinZ);
    includePoint(otherMaxX, otherMaxY, otherMaxZ);
  }

  /// Grows the box to include [other] (no-op when [other] is empty).
  void expandToBounds(AabbBounds other) {
    if (other.isEmpty) return;
    includePoint(other.minX, other.minY, other.minZ);
    includePoint(other.maxX, other.maxY, other.maxZ);
  }

  /// Copies [other]'s state into this box.
  void copyFrom(AabbBounds other) {
    minX = other.minX;
    minY = other.minY;
    minZ = other.minZ;
    maxX = other.maxX;
    maxY = other.maxY;
    maxZ = other.maxZ;
    isEmpty = other.isEmpty;
  }

  /// In-place transform mirroring vector_math's Aabb3.transform: uses
  /// the Arvo `absoluteRotate` shortcut (centre + abs(M_3x3) *
  /// half-extents) instead of 8-corner expansion.
  void transform(Matrix4 m) {
    if (isEmpty) return;
    final cx = (minX + maxX) * 0.5;
    final cy = (minY + maxY) * 0.5;
    final cz = (minZ + maxZ) * 0.5;
    final hx = (maxX - minX) * 0.5;
    final hy = (maxY - minY) * 0.5;
    final hz = (maxZ - minZ) * 0.5;
    final newCenter = m.transformed3(Vector3(cx, cy, cz));
    final s = m.storage;
    final newHx = (s[0]).abs() * hx + (s[4]).abs() * hy + (s[8]).abs() * hz;
    final newHy = (s[1]).abs() * hx + (s[5]).abs() * hy + (s[9]).abs() * hz;
    final newHz = (s[2]).abs() * hx + (s[6]).abs() * hy + (s[10]).abs() * hz;
    minX = newCenter.x - newHx;
    minY = newCenter.y - newHy;
    minZ = newCenter.z - newHz;
    maxX = newCenter.x + newHx;
    maxY = newCenter.y + newHy;
    maxZ = newCenter.z + newHz;
  }

  /// Transform every corner of [other] by [transform] and union the
  /// result into this box. Eight-corner expansion is used (rather
  /// than the cheaper centre-plus-extents trick) because this runs
  /// offline and tightness matters more than throughput.
  void expandToTransformedBox(AabbBounds other, Matrix4 transform) {
    if (other.isEmpty) return;
    for (int i = 0; i < 8; i++) {
      final x = (i & 1) == 0 ? other.minX : other.maxX;
      final y = (i & 2) == 0 ? other.minY : other.maxY;
      final z = (i & 4) == 0 ? other.minZ : other.maxZ;
      final p = transform.transformed3(Vector3(x, y, z));
      includePoint(p.x, p.y, p.z);
    }
  }
}

/// Build a local-space AABB for a primitive. Uses the accessor's
/// spec-provided `min`/`max` when present (the glTF spec requires them
/// on POSITION accessors but consumers occasionally omit them); falls
/// back to a vertex scan otherwise.
AabbBounds aabbFromAccessorOrPositions(
  GltfAccessor accessor,
  Float32List positions,
) {
  final min = accessor.min;
  final max = accessor.max;
  if (min != null && min.length >= 3 && max != null && max.length >= 3) {
    return AabbBounds(min[0], min[1], min[2], max[0], max[1], max[2], false);
  }
  return aabbFromPositions(positions);
}

/// Build a local-space AABB by scanning packed vec3 [positions].
AabbBounds aabbFromPositions(Float32List positions) {
  double minX = double.infinity, minY = double.infinity, minZ = double.infinity;
  double maxX = double.negativeInfinity,
      maxY = double.negativeInfinity,
      maxZ = double.negativeInfinity;
  for (int i = 0; i + 2 < positions.length; i += 3) {
    final x = positions[i];
    final y = positions[i + 1];
    final z = positions[i + 2];
    if (x < minX) minX = x;
    if (y < minY) minY = y;
    if (z < minZ) minZ = z;
    if (x > maxX) maxX = x;
    if (y > maxY) maxY = y;
    if (z > maxZ) maxZ = z;
  }
  return AabbBounds(minX, minY, minZ, maxX, maxY, maxZ, positions.length < 3);
}

/// Computes the skinned pose-union AABB of every skinned mesh primitive,
/// keyed by glTF node index.
///
/// For each node with both a skin and a mesh, the result holds one entry per
/// triangle-mode (`mode == 4`) primitive, in source order: the union of the
/// primitive's extent across the bind pose and every keyframe time of every
/// animation channel driving the skin's joints, in mesh-local space. An entry
/// is `null` when the primitive carries no `JOINTS_0`/`WEIGHTS_0` attributes
/// (it packs and renders unskinned) or the union came up empty; consumers
/// treat a missing bound as "always visible".
Map<int, List<AabbBounds?>> bakeSkinnedPoseUnionAabbs(
  GltfDocument doc,
  Uint8List bufferData,
) {
  final result = <int, List<AabbBounds?>>{};
  if (doc.nodes.isEmpty) return result;

  // Build a parent-index table once (glTF only stores children).
  final parentOf = List<int>.filled(doc.nodes.length, -1);
  for (int p = 0; p < doc.nodes.length; p++) {
    for (final c in doc.nodes[p].children) {
      if (c >= 0 && c < parentOf.length) parentOf[c] = p;
    }
  }

  for (int nodeIdx = 0; nodeIdx < doc.nodes.length; nodeIdx++) {
    final glNode = doc.nodes[nodeIdx];
    if (glNode.skin == null || glNode.mesh == null) continue;
    if (glNode.mesh! < 0 || glNode.mesh! >= doc.meshes.length) continue;

    final skin = doc.skins[glNode.skin!];
    final jointNodeIndices = skin.joints;
    if (jointNodeIndices.isEmpty) continue;

    final isJointNode = <int, int>{
      for (int i = 0; i < jointNodeIndices.length; i++) jointNodeIndices[i]: i,
    };

    // Inverse bind matrices, one per joint. When the glTF asset omits
    // them, the spec mandates identity — match the runtime behaviour.
    final ibm = _readInverseBindMatrices(skin, doc, bufferData);

    // Collect every channel that drives any joint in this skin.
    // Sample times default to {0} (bind pose) plus every keyframe time
    // from those channels. With the emitters converting CUBICSPLINE to
    // bare keyframe values, evaluating at each keyframe time is exact
    // for our pipeline.
    final sampleTimes = <double>{0.0};
    final relevantChannels = <_PoseChannel>[];
    for (final anim in doc.animations) {
      for (final ch in anim.channels) {
        if (ch.targetNode == null) continue;
        if (!isJointNode.containsKey(ch.targetNode!)) continue;
        if (ch.sampler < 0 || ch.sampler >= anim.samplers.length) continue;
        final sampler = anim.samplers[ch.sampler];
        final inputAcc = doc.accessors[sampler.input];
        final outputAcc = doc.accessors[sampler.output];
        final inputView = doc.bufferViews[inputAcc.bufferView!];
        final outputView = doc.bufferViews[outputAcc.bufferView!];
        final times = readAccessorAsFloat32(inputAcc, inputView, bufferData);
        final values = readAccessorAsFloat32(outputAcc, outputView, bufferData);
        final isCubic = sampler.interpolation == 'CUBICSPLINE';
        final pc = _PoseChannel(
          targetNode: ch.targetNode!,
          targetPath: ch.targetPath,
          times: times,
          values: values,
          isCubic: isCubic,
        );
        if (pc.isUsable) {
          relevantChannels.add(pc);
          for (final t in times) {
            sampleTimes.add(t);
          }
        }
      }
    }

    // Index relevant channels by target node for fast lookup during
    // pose evaluation.
    final channelsByNode = <int, List<_PoseChannel>>{};
    for (final c in relevantChannels) {
      channelsByNode.putIfAbsent(c.targetNode, () => []).add(c);
    }

    final sortedTimes = sampleTimes.toList()..sort();

    // Pre-compute the static (un-animated) localTransform components
    // for each joint and every joint ancestor, so pose evaluation can
    // fall back to them when a channel doesn't drive a particular
    // component.
    final staticTrs = <int, _StaticTrs>{};
    for (final jIdx in jointNodeIndices) {
      _collectStaticTrs(jIdx, doc, parentOf, isJointNode, staticTrs);
    }

    // Iterate the mesh's triangle-mode primitives in glTF source order.
    final unions = <AabbBounds?>[];
    for (final glPrim in doc.meshes[glNode.mesh!].primitives) {
      if (glPrim.mode != 4) continue;
      if (!glPrim.attributes.containsKey('JOINTS_0') ||
          !glPrim.attributes.containsKey('WEIGHTS_0')) {
        unions.add(null);
        continue;
      }

      final influence = _computeJointInfluenceAabbs(
        glPrim,
        doc,
        bufferData,
        jointNodeIndices.length,
      );

      final poseUnion = AabbBounds.empty();
      // Per-pose scratch storage to avoid re-allocating during the
      // tight (sample-times × joints) loop.
      final palette = List<Matrix4>.generate(
        jointNodeIndices.length,
        (_) => Matrix4.identity(),
      );
      final transformedScratch = AabbBounds.empty();

      for (final t in sortedTimes) {
        _buildJointPaletteAtTime(
          jointNodeIndices: jointNodeIndices,
          parentOf: parentOf,
          isJointNode: isJointNode,
          channelsByNode: channelsByNode,
          staticTrs: staticTrs,
          ibm: ibm,
          time: t,
          out: palette,
        );

        for (int j = 0; j < jointNodeIndices.length; j++) {
          final infl = influence[j];
          if (infl.isEmpty) continue;
          transformedScratch
            ..copyFrom(infl)
            ..transform(palette[j]);
          poseUnion.expandToBounds(transformedScratch);
        }
      }

      unions.add(poseUnion.isEmpty ? null : poseUnion);
    }
    result[nodeIdx] = unions;
  }
  return result;
}

class _PoseChannel {
  _PoseChannel({
    required this.targetNode,
    required this.targetPath,
    required this.times,
    required this.values,
    required this.isCubic,
  });
  final int targetNode;

  /// One of `'translation'`, `'rotation'`, `'scale'`. (`'weights'`
  /// drives morph targets, which flutter_scene doesn't currently
  /// support; those channels are filtered out via [isUsable].)
  final String targetPath;
  final Float32List times;
  final Float32List values;

  /// CUBICSPLINE samplers store [in_tangent, value, out_tangent] per
  /// keyframe; the value lives at offset 1 with stride 3 within each
  /// component group. LINEAR/STEP store the value at offset 0 stride 1.
  final bool isCubic;

  bool get isUsable =>
      targetPath == 'translation' ||
      targetPath == 'rotation' ||
      targetPath == 'scale';

  /// Returns the value at time [t] as a `List<double>` of either 3
  /// (translation/scale) or 4 (rotation) components, sampled with
  /// LINEAR / SLERP interpolation between bracketing keyframes. The
  /// runtime treats CUBICSPLINE samplers as LINEAR over their stripped
  /// keyframe values, so we mirror that here.
  List<double> sampleAt(double t) {
    final componentCount = targetPath == 'rotation' ? 4 : 3;
    final stride = isCubic ? componentCount * 3 : componentCount;
    final valueOffsetInGroup = isCubic ? componentCount : 0;

    if (times.isEmpty) {
      return List<double>.filled(componentCount, 0);
    }
    if (t <= times.first) {
      return _readKeyframe(0, stride, valueOffsetInGroup, componentCount);
    }
    if (t >= times.last) {
      return _readKeyframe(
        times.length - 1,
        stride,
        valueOffsetInGroup,
        componentCount,
      );
    }

    int lo = 0, hi = times.length - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (times[mid] <= t) {
        lo = mid;
      } else {
        hi = mid;
      }
    }

    final t0 = times[lo];
    final t1 = times[hi];
    final span = t1 - t0;
    final f = span == 0 ? 0.0 : (t - t0) / span;
    final v0 = _readKeyframe(lo, stride, valueOffsetInGroup, componentCount);
    final v1 = _readKeyframe(hi, stride, valueOffsetInGroup, componentCount);

    if (targetPath == 'rotation') {
      // SLERP between two unit quaternions.
      return _slerp(v0, v1, f);
    }
    return [
      for (int i = 0; i < componentCount; i++) v0[i] + (v1[i] - v0[i]) * f,
    ];
  }

  List<double> _readKeyframe(
    int keyframeIndex,
    int stride,
    int valueOffsetInGroup,
    int componentCount,
  ) {
    final base = keyframeIndex * stride + valueOffsetInGroup;
    return [for (int i = 0; i < componentCount; i++) values[base + i]];
  }
}

List<double> _slerp(List<double> a, List<double> b, double t) {
  // Quaternion SLERP. Mirrors vector_math's Quaternion.slerp behaviour.
  double ax = a[0], ay = a[1], az = a[2], aw = a[3];
  double bx = b[0], by = b[1], bz = b[2], bw = b[3];
  double dot = ax * bx + ay * by + az * bz + aw * bw;
  if (dot < 0) {
    bx = -bx;
    by = -by;
    bz = -bz;
    bw = -bw;
    dot = -dot;
  }
  if (dot > 0.9995) {
    // Falls back to lerp + normalize for numerical stability when the
    // quaternions are nearly identical.
    final rx = ax + (bx - ax) * t;
    final ry = ay + (by - ay) * t;
    final rz = az + (bz - az) * t;
    final rw = aw + (bw - aw) * t;
    final inv = 1.0 / sqrt(rx * rx + ry * ry + rz * rz + rw * rw);
    return [rx * inv, ry * inv, rz * inv, rw * inv];
  }
  final theta0 = _safeAcos(dot);
  final theta = theta0 * t;
  final sinTheta = sin(theta);
  final sinTheta0 = sin(theta0);
  final s0 = cos(theta) - dot * sinTheta / sinTheta0;
  final s1 = sinTheta / sinTheta0;
  return [
    ax * s0 + bx * s1,
    ay * s0 + by * s1,
    az * s0 + bz * s1,
    aw * s0 + bw * s1,
  ];
}

double _safeAcos(double v) {
  if (v <= -1.0) return pi;
  if (v >= 1.0) return 0.0;
  return acos(v);
}

class _StaticTrs {
  _StaticTrs(this.translation, this.rotation, this.scale, this.matrixOnly);
  final Vector3 translation;
  final Quaternion rotation;
  final Vector3 scale;

  /// When the glTF node uses a `matrix` field instead of TRS
  /// (animations can't drive these per spec), the translation /
  /// rotation / scale fields are decomposed copies for use in pose
  /// evaluation, but [matrixOnly] is set so we know we shouldn't
  /// re-compose if no channel drives this node.
  final Matrix4? matrixOnly;
}

void _collectStaticTrs(
  int nodeIdx,
  GltfDocument doc,
  List<int> parentOf,
  Map<int, int> isJointNode,
  Map<int, _StaticTrs> out,
) {
  int current = nodeIdx;
  while (current >= 0 && !out.containsKey(current)) {
    final n = doc.nodes[current];
    Vector3 t;
    Quaternion r;
    Vector3 s;
    Matrix4? matrixOnly;
    if (n.matrix != null) {
      // Decompose the matrix so animation overrides on individual
      // components (rare for matrix-mode nodes, but legal in glTF if
      // the channels were authored for a different version of the
      // file) can compose with the static remainder. Track that the
      // static value came from a matrix so we can short-circuit.
      matrixOnly = n.matrix!.clone();
      t = Vector3.zero();
      r = Quaternion.identity();
      s = Vector3(1, 1, 1);
      n.matrix!.decompose(t, r, s);
    } else {
      t = (n.translation ?? Vector3.zero()).clone();
      r = (n.rotation ?? Quaternion.identity())..normalize();
      s = (n.scale ?? Vector3(1.0, 1.0, 1.0)).clone();
    }
    out[current] = _StaticTrs(t, r, s, matrixOnly);
    if (!isJointNode.containsKey(current)) break;
    current = parentOf[current];
  }
}

/// Build the per-joint palette matrix at [time], writing into [out].
///
/// `palette[j]` post-multiplied by a vertex in mesh-local space
/// produces the vertex's contribution from joint `j` after the
/// animated pose has been applied.
void _buildJointPaletteAtTime({
  required List<int> jointNodeIndices,
  required List<int> parentOf,
  required Map<int, int> isJointNode,
  required Map<int, List<_PoseChannel>> channelsByNode,
  required Map<int, _StaticTrs> staticTrs,
  required List<Matrix4> ibm,
  required double time,
  required List<Matrix4> out,
}) {
  // Cache pose-time local transforms for any joint or joint-ancestor
  // node we touch during this sample. The walk is guaranteed
  // ancestor-before-descendant only for joints whose chain we visit;
  // we fall back to recompute if we hit an unevaluated entry.
  final localCache = <int, Matrix4>{};

  Matrix4 localAt(int n) {
    final cached = localCache[n];
    if (cached != null) return cached;

    final st = staticTrs[n];
    if (st == null) {
      localCache[n] = Matrix4.identity();
      return localCache[n]!;
    }
    final channels = channelsByNode[n];

    Vector3 t = st.translation;
    Quaternion r = st.rotation;
    Vector3 s = st.scale;
    bool overridden = false;
    if (channels != null) {
      for (final c in channels) {
        final v = c.sampleAt(time);
        switch (c.targetPath) {
          case 'translation':
            t = Vector3(v[0], v[1], v[2]);
            overridden = true;
            break;
          case 'rotation':
            r = Quaternion(v[0], v[1], v[2], v[3]);
            overridden = true;
            break;
          case 'scale':
            s = Vector3(v[0], v[1], v[2]);
            overridden = true;
            break;
        }
      }
    }

    Matrix4 m;
    if (!overridden && st.matrixOnly != null) {
      m = st.matrixOnly!.clone();
    } else {
      m = Matrix4.compose(t, r, s);
    }
    localCache[n] = m;
    return m;
  }

  // Walk each joint's chain up through joint ancestors, mirroring the
  // runtime in Skin.getJointsTexture.
  for (int j = 0; j < jointNodeIndices.length; j++) {
    int current = jointNodeIndices[j];
    Matrix4 accumulated = Matrix4.identity();
    while (current >= 0 && isJointNode.containsKey(current)) {
      final m = localAt(current);
      accumulated = m * accumulated;
      current = parentOf[current];
    }
    accumulated = accumulated * ibm[j];
    out[j].setFrom(accumulated);
  }
}

List<Matrix4> _readInverseBindMatrices(
  GltfSkin skin,
  GltfDocument doc,
  Uint8List bufferData,
) {
  final out = <Matrix4>[];
  if (skin.inverseBindMatrices == null) {
    for (int i = 0; i < skin.joints.length; i++) {
      out.add(Matrix4.identity());
    }
    return out;
  }
  final accessor = doc.accessors[skin.inverseBindMatrices!];
  final view = doc.bufferViews[accessor.bufferView!];
  final floats = readAccessorAsFloat32(accessor, view, bufferData);
  for (int i = 0; i < skin.joints.length; i++) {
    final base = i * 16;
    out.add(
      Matrix4(
        floats[base + 0],
        floats[base + 1],
        floats[base + 2],
        floats[base + 3],
        floats[base + 4],
        floats[base + 5],
        floats[base + 6],
        floats[base + 7],
        floats[base + 8],
        floats[base + 9],
        floats[base + 10],
        floats[base + 11],
        floats[base + 12],
        floats[base + 13],
        floats[base + 14],
        floats[base + 15],
      ),
    );
  }
  return out;
}

/// Per-joint AABB of vertex positions weighted onto that joint, in
/// mesh-local space. Vertices with weight 0 on a joint don't
/// contribute to that joint's influence AABB.
List<AabbBounds> _computeJointInfluenceAabbs(
  GltfMeshPrimitive prim,
  GltfDocument doc,
  Uint8List bufferData,
  int jointCount,
) {
  final influence = List<AabbBounds>.generate(
    jointCount,
    (_) => AabbBounds.empty(),
  );
  final positions = _readFloats(prim.attributes['POSITION']!, doc, bufferData);
  final joints = _readFloats(prim.attributes['JOINTS_0']!, doc, bufferData);
  final weights = _readFloats(prim.attributes['WEIGHTS_0']!, doc, bufferData);
  final vertexCount = positions.length ~/ 3;
  for (int v = 0; v < vertexCount; v++) {
    final px = positions[v * 3 + 0];
    final py = positions[v * 3 + 1];
    final pz = positions[v * 3 + 2];
    for (int c = 0; c < 4; c++) {
      final w = weights[v * 4 + c];
      if (w <= 0) continue;
      final j = joints[v * 4 + c].toInt();
      if (j < 0 || j >= jointCount) continue;
      influence[j].includePoint(px, py, pz);
    }
  }
  return influence;
}

Float32List _readFloats(int idx, GltfDocument doc, Uint8List bufferData) {
  final a = doc.accessors[idx];
  return readAccessorAsFloat32(a, doc.bufferViews[a.bufferView!], bufferData);
}
