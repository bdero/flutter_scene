/// Build-time emitter: parsed glTF → packed `.model` flatbuffer bytes.
///
/// Writes the same `fb.SceneT` shape that the C++ importer in
/// `importer_gltf.cc` produces, just done in pure Dart so the build hook
/// doesn't need to shell out to a compiled binary. See `model_emitter_test`
/// for byte-level parity coverage against the C++ output.
library;

import 'dart:math' show acos, cos, pi, sin, sqrt;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:vector_math/vector_math.dart';

// Import the generated flatbuffer types directly rather than going through
// flatbuffer.dart, which transitively pulls in `flutter_gpu/gpu.dart` and
// `dart:ui` — both unavailable in the build-hook isolate.
import '../../generated/scene_impeller.fb_flatbuffers.dart' as fb;
import '../../gltf.dart';
import '../../third_party/flat_buffers.dart' as fbb;

/// Convert a parsed glTF document (plus its associated binary buffer) into
/// the byte representation of a `.model` flatbuffer file.
Uint8List emitModel(GltfDocument doc, Uint8List bufferData) {
  final scene = _buildScene(doc, bufferData);
  final builder = fbb.Builder();
  final offset = scene.pack(builder);
  builder.finish(offset, 'IPSC');
  return builder.buffer;
}

fb.SceneT _buildScene(GltfDocument doc, Uint8List bufferData) {
  final scene = fb.SceneT();

  // Scene-level Z-flip transform (matches C++ importer_gltf.cc:499).
  scene.transform = _matrixT(Matrix4.identity()..setEntry(2, 2, -1.0));

  // Root-level child node indexes from the default scene.
  final sceneIdx = doc.scene ?? (doc.scenes.isNotEmpty ? 0 : -1);
  if (sceneIdx >= 0 && sceneIdx < doc.scenes.length) {
    scene.children = doc.scenes[sceneIdx].nodes.toList();
  } else {
    scene.children = <int>[];
  }

  // Textures (one entry per glTF texture; embedded RGBA when an image source
  // is present and decodable).
  scene.textures = [
    for (final t in doc.textures) _buildTexture(t, doc, bufferData),
  ];

  // Nodes (flat list).
  scene.nodes = [
    for (int i = 0; i < doc.nodes.length; i++)
      _buildNode(doc.nodes[i], i, doc, bufferData),
  ];

  // Post-pass: bake skinned primitives' pose-union AABBs by sampling
  // every animation that drives any joint of the bound skin. Must run
  // before _bakeCombinedAabbs so skinned subtrees can contribute their
  // pose-union extents instead of opting out.
  _bakePoseUnionAabbs(scene.nodes!, doc, bufferData);

  // Post-pass: bake each node's combined local-space AABB so the
  // runtime can cull entire subtrees with a single AABB-vs-frustum
  // test.
  _bakeCombinedAabbs(scene.nodes!, doc);

  // Animations.
  scene.animations = [
    for (final a in doc.animations) _buildAnimation(a, doc, bufferData),
  ];

  return scene;
}

/// Walks the node forest in post-order and assigns
/// `combined_local_aabb` to each node where it can be computed
/// soundly.
///
/// Skinned primitives contribute their `skinned_pose_union_aabb` (a
/// superset of every animated pose extent) when the offline analysis
/// produced one; otherwise the subtree is left unbounded and the
/// runtime treats absent bounds as "always visible" so animated
/// meshes don't disappear when posed outside their bind-pose extent.
void _bakeCombinedAabbs(List<fb.NodeT> nodes, GltfDocument doc) {
  // Memoize: null when the subtree is unbounded (skinned without a
  // pose-union bound), an `_AabbBox` otherwise. `_AabbBox.empty`
  // represents a soundly computed but empty subtree (no geometry at
  // all), which still serializes as a degenerate AABB so we can tell
  // it apart from "unbounded" at runtime.
  final memo = List<_AabbBox?>.filled(nodes.length, null);
  final computed = List<bool>.filled(nodes.length, false);

  _AabbBox? walk(int idx) {
    if (computed[idx]) return memo[idx];
    computed[idx] = true;

    final node = nodes[idx];
    final glNode = doc.nodes[idx];

    final isSkinned = glNode.skin != null;
    final box = _AabbBox.empty();
    bool subtreeBoundedSoFar = true;

    for (final prim in node.meshPrimitives ?? const <fb.MeshPrimitiveT>[]) {
      final aabb = isSkinned ? prim.skinnedPoseUnionAabb : prim.boundsAabb;
      if (aabb != null) {
        box.expandToAabb(aabb);
      } else if (isSkinned) {
        // Skinned primitive with no pose-union bound (e.g. animations
        // were absent or analysis was skipped). The whole subtree
        // becomes unbounded.
        subtreeBoundedSoFar = false;
      }
    }

    bool subtreeBounded = subtreeBoundedSoFar;
    for (final childIdx in node.children ?? const <int>[]) {
      if (childIdx < 0 || childIdx >= nodes.length) continue;
      final childBox = walk(childIdx);
      if (childBox == null) {
        subtreeBounded = false;
        continue;
      }
      if (childBox.isEmpty) continue;
      // Transform the child's combined AABB into this node's local
      // space using the child's local transform.
      final childLocal = _localTransformFor(doc.nodes[childIdx]);
      box.expandToTransformedBox(childBox, childLocal);
    }

    if (!subtreeBounded) {
      memo[idx] = null;
      return null;
    }

    memo[idx] = box;
    if (!box.isEmpty) {
      node.combinedLocalAabb = fb.Aabb3T(
        min: fb.Vec3T(x: box.minX, y: box.minY, z: box.minZ),
        max: fb.Vec3T(x: box.maxX, y: box.maxY, z: box.maxZ),
      );
    }
    return box;
  }

  for (int i = 0; i < nodes.length; i++) {
    walk(i);
  }
}

/// Mutable AABB used during the bake post-pass. Tracks emptiness
/// explicitly so a node with no geometry stays distinguishable from
/// a node whose AABB happens to include the origin.
class _AabbBox {
  _AabbBox(
    this.minX,
    this.minY,
    this.minZ,
    this.maxX,
    this.maxY,
    this.maxZ,
    this.isEmpty,
  );

  factory _AabbBox.empty() => _AabbBox(0, 0, 0, 0, 0, 0, true);

  double minX, minY, minZ, maxX, maxY, maxZ;
  bool isEmpty;

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

  void expandToAabb(fb.Aabb3T a) {
    final mn = a.min, mx = a.max;
    includePoint(mn.x, mn.y, mn.z);
    includePoint(mx.x, mx.y, mx.z);
  }

  void expandToAabbBox(_AabbBox other) {
    if (other.isEmpty) return;
    includePoint(other.minX, other.minY, other.minZ);
    includePoint(other.maxX, other.maxY, other.maxZ);
  }

  void copyFrom(_AabbBox other) {
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
  void expandToTransformedBox(_AabbBox other, Matrix4 transform) {
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

// ───── Nodes ─────

fb.NodeT _buildNode(
  GltfNode n,
  int index,
  GltfDocument doc,
  Uint8List bufferData,
) {
  final out = fb.NodeT();
  out.name = resolveGltfNodeName(n.name, index);
  out.children = n.children.toList();
  out.transform = _matrixT(_localTransformFor(n));

  if (n.mesh != null && n.mesh! < doc.meshes.length) {
    out.meshPrimitives = [
      for (final p in doc.meshes[n.mesh!].primitives)
        if (p.mode == 4) _buildMeshPrimitive(p, doc, bufferData),
    ];
  }

  if (n.skin != null && n.skin! < doc.skins.length) {
    out.skin = _buildSkin(doc.skins[n.skin!], doc, bufferData);
  }
  return out;
}

Matrix4 _localTransformFor(GltfNode n) {
  if (n.matrix != null) return n.matrix!.clone();
  return Matrix4.compose(
    n.translation ?? Vector3.zero(),
    n.rotation ?? Quaternion.identity(),
    n.scale ?? Vector3(1.0, 1.0, 1.0),
  );
}

// ───── Mesh primitives ─────

fb.MeshPrimitiveT _buildMeshPrimitive(
  GltfMeshPrimitive p,
  GltfDocument doc,
  Uint8List bufferData,
) {
  final out = fb.MeshPrimitiveT();

  // Pack vertices and indices with the shared packer (vertex layout,
  // index handling, normal generation, de-indexing). The runtime GLB
  // importer uses the same code, so the offline .model output matches
  // it byte-for-byte.
  final packed = packGltfPrimitive(
    primitive: p,
    accessors: doc.accessors,
    bufferViews: doc.bufferViews,
    bufferData: bufferData,
  );
  if (packed.isSkinned) {
    out.verticesType = fb.VertexBufferTypeId.SkinnedVertexBuffer;
    out.vertices = fb.SkinnedVertexBufferT(
      vertices: packed.vertexBytes,
      vertexCount: packed.vertexCount,
    );
  } else {
    out.verticesType = fb.VertexBufferTypeId.UnskinnedVertexBuffer;
    out.vertices = fb.UnskinnedVertexBufferT(
      vertices: packed.vertexBytes,
      vertexCount: packed.vertexCount,
    );
  }
  out.indices =
      fb.IndicesT()
        ..data = packed.indexBytes
        ..count = packed.indexCount
        ..type =
            packed.indices32Bit ? fb.IndexType.k32Bit : fb.IndexType.k16Bit;

  // Material.
  if (p.material != null && p.material! < doc.materials.length) {
    out.material = _buildMaterial(doc.materials[p.material!]);
  }

  // Bounds. Prefer the accessor's spec-provided min/max for the AABB so
  // we don't redo work the asset already encodes; the sphere always
  // requires a vertex pass. De-indexing duplicates points without
  // adding new ones, so the original positions cover the same extent.
  final positionAccessor = doc.accessors[p.attributes['POSITION']!];
  final positions = _readVec3(p.attributes['POSITION']!, doc, bufferData);
  if (positions.isNotEmpty) {
    out.boundsAabb = _aabbFromAccessorOrPositions(positionAccessor, positions);
    out.boundsSphere = _sphereFromPositions(positions);
  }
  return out;
}

// ───── Materials ─────

fb.MaterialT _buildMaterial(GltfMaterial m) {
  final out = fb.MaterialT();
  out.type =
      m.unlit ? fb.MaterialType.kUnlit : fb.MaterialType.kPhysicallyBased;
  out.baseColorTexture = m.pbrMetallicRoughness?.baseColorTexture?.index ?? -1;
  out.metallicRoughnessTexture =
      m.pbrMetallicRoughness?.metallicRoughnessTexture?.index ?? -1;
  out.normalTexture = m.normalTexture?.index ?? -1;
  out.occlusionTexture = m.occlusionTexture?.index ?? -1;
  out.emissiveTexture = m.emissiveTexture?.index ?? -1;
  final pbr = m.pbrMetallicRoughness;
  out.baseColorFactor = fb.ColorT(
    r: _at(pbr?.baseColorFactor, 0, 1.0),
    g: _at(pbr?.baseColorFactor, 1, 1.0),
    b: _at(pbr?.baseColorFactor, 2, 1.0),
    a: _at(pbr?.baseColorFactor, 3, 1.0),
  );
  out.metallicFactor = pbr?.metallicFactor ?? 0.0;
  out.roughnessFactor = pbr?.roughnessFactor ?? 0.5;
  out.normalScale = m.normalTexture?.scale ?? 1.0;
  out.occlusionStrength = m.occlusionTexture?.strength ?? 1.0;
  out.emissiveFactor = fb.Vec3T(
    x: _at(m.emissiveFactor, 0, 0.0),
    y: _at(m.emissiveFactor, 1, 0.0),
    z: _at(m.emissiveFactor, 2, 0.0),
  );
  // glTF alpha mode: 0 = OPAQUE, 1 = MASK, 2 = BLEND.
  out.alphaMode = switch (m.alphaMode) {
    'MASK' => 1,
    'BLEND' => 2,
    _ => 0,
  };
  out.alphaCutoff = m.alphaCutoff;
  return out;
}

double _at(List<double>? a, int i, double fallback) =>
    (a != null && a.length > i) ? a[i] : fallback;

// ───── Textures ─────

fb.TextureT _buildTexture(
  GltfTexture t,
  GltfDocument doc,
  Uint8List bufferData,
) {
  final out = fb.TextureT();
  if (t.source == null || t.source! >= doc.images.length) {
    return out;
  }
  final image = doc.images[t.source!];
  out.uri = image.uri;
  if (image.bufferView != null) {
    final bv = doc.bufferViews[image.bufferView!];
    final encoded = Uint8List.sublistView(
      bufferData,
      bv.byteOffset,
      bv.byteOffset + bv.byteLength,
    );
    final decoded = img.decodeImage(encoded);
    if (decoded != null) {
      // package:image gives us per-pixel iterators; force RGBA 8-bit so the
      // runtime upload path (gpuTextureFromImage's overwrite) gets the
      // expected layout.
      final rgba = decoded.convert(numChannels: 4, format: img.Format.uint8);
      final bytes = rgba.getBytes(order: img.ChannelOrder.rgba);
      out.embeddedImage = fb.EmbeddedImageT(
        bytes: bytes,
        componentCount: 4,
        componentType: fb.ComponentType.k8Bit,
        width: rgba.width,
        height: rgba.height,
      );
    }
  }
  return out;
}

// ───── Skins ─────

fb.SkinT _buildSkin(GltfSkin s, GltfDocument doc, Uint8List bufferData) {
  final out = fb.SkinT();
  out.joints = s.joints.toList();
  out.skeleton = s.skeleton ?? -1;
  if (s.inverseBindMatrices != null) {
    final accessor = doc.accessors[s.inverseBindMatrices!];
    final view = doc.bufferViews[accessor.bufferView!];
    final floats = readAccessorAsFloat32(accessor, view, bufferData);
    out.inverseBindMatrices =
        [
          for (int i = 0; i < s.joints.length; i++)
            _matrixFromFloats(floats, i * 16),
        ].reversed.toList();
  } else {
    out.inverseBindMatrices = [
      for (int i = 0; i < s.joints.length; i++) _matrixT(Matrix4.identity()),
    ];
  }
  // The generated XT.pack walks struct vectors forward, but the flatbuffer
  // builder grows backward, so the on-disk order ends up reversed. We
  // pre-reverse to compensate. (Empty/identity-only lists don't need it.)
  return out;
}

// ───── Animations ─────

fb.AnimationT _buildAnimation(
  GltfAnimation a,
  GltfDocument doc,
  Uint8List bufferData,
) {
  final out = fb.AnimationT();
  out.name = a.name ?? '';
  final channels = <fb.ChannelT>[];
  for (final ch in a.channels) {
    if (ch.targetNode == null) continue;
    if (ch.sampler < 0 || ch.sampler >= a.samplers.length) continue;
    final sampler = a.samplers[ch.sampler];
    final inputAcc = doc.accessors[sampler.input];
    final outputAcc = doc.accessors[sampler.output];
    final inputView = doc.bufferViews[inputAcc.bufferView!];
    final outputView = doc.bufferViews[outputAcc.bufferView!];
    final times = readAccessorAsFloat32(inputAcc, inputView, bufferData);
    final values = readAccessorAsFloat32(outputAcc, outputView, bufferData);
    final isCubic = sampler.interpolation == 'CUBICSPLINE';

    final channel = fb.ChannelT();
    channel.node = ch.targetNode!;
    channel.timeline = times.toList();

    switch (ch.targetPath) {
      case 'translation':
        channel.keyframesType = fb.KeyframesTypeId.TranslationKeyframes;
        channel.keyframes = fb.TranslationKeyframesT(
          values: _vec3List(values, isCubic),
        );
      case 'scale':
        channel.keyframesType = fb.KeyframesTypeId.ScaleKeyframes;
        channel.keyframes = fb.ScaleKeyframesT(
          values: _vec3List(values, isCubic),
        );
      case 'rotation':
        channel.keyframesType = fb.KeyframesTypeId.RotationKeyframes;
        channel.keyframes = fb.RotationKeyframesT(
          values: _vec4List(values, isCubic),
        );
      default:
        // 'weights' (morph targets) and unknowns: skip.
        continue;
    }
    channels.add(channel);
  }
  out.channels = channels;
  return out;
}

// Reversed to compensate for the generated XT.pack vector-of-struct
// reversal — see the comment in _buildSkin.
List<fb.Vec3T> _vec3List(Float32List values, bool isCubic) {
  final stride = isCubic ? 9 : 3;
  final off = isCubic ? 3 : 0;
  return [
    for (int i = 0; i + stride <= values.length; i += stride)
      fb.Vec3T(
        x: values[i + off],
        y: values[i + off + 1],
        z: values[i + off + 2],
      ),
  ].reversed.toList();
}

List<fb.Vec4T> _vec4List(Float32List values, bool isCubic) {
  final stride = isCubic ? 12 : 4;
  final off = isCubic ? 4 : 0;
  return [
    for (int i = 0; i + stride <= values.length; i += stride)
      fb.Vec4T(
        x: values[i + off],
        y: values[i + off + 1],
        z: values[i + off + 2],
        w: values[i + off + 3],
      ),
  ].reversed.toList();
}

// ───── Pose-union AABB bake (skinned primitives) ─────

/// For every node with a skin, walk every animation that drives any
/// joint of that skin and compute a local-space AABB covering vertex
/// positions across every animated pose.
///
/// Approach: pre-compute per-joint vertex influence AABBs for each
/// primitive (one O(vertex) pass), then sample animations at every
/// unique keyframe time, build the joint palette, and union
/// (palette[j] * influence[j]) into the pose-union AABB. This avoids
/// re-transforming every vertex for every pose; it produces a slightly
/// looser bound than a true per-vertex evaluation but is still a sound
/// upper bound on rendered extents.
///
/// `t = 0` is always sampled so the bind pose is included even when no
/// animation explicitly references it.
void _bakePoseUnionAabbs(
  List<fb.NodeT> nodes,
  GltfDocument doc,
  Uint8List bufferData,
) {
  if (doc.nodes.isEmpty) return;

  // Build a parent-index table once (glTF only stores children).
  final parentOf = List<int>.filled(doc.nodes.length, -1);
  for (int p = 0; p < doc.nodes.length; p++) {
    for (final c in doc.nodes[p].children) {
      if (c >= 0 && c < parentOf.length) parentOf[c] = p;
    }
  }

  for (int nodeIdx = 0; nodeIdx < nodes.length; nodeIdx++) {
    final glNode = doc.nodes[nodeIdx];
    if (glNode.skin == null || glNode.mesh == null) continue;
    final fbNode = nodes[nodeIdx];
    final fbPrims = fbNode.meshPrimitives;
    if (fbPrims == null || fbPrims.isEmpty) continue;

    final skin = doc.skins[glNode.skin!];
    final jointNodeIndices = skin.joints;
    if (jointNodeIndices.isEmpty) continue;

    final isJointNode = <int, int>{
      for (int i = 0; i < jointNodeIndices.length; i++) jointNodeIndices[i]: i,
    };

    // Inverse bind matrices, one per joint. When the glTF asset omits
    // them, the spec mandates identity — match the runtime behaviour
    // in Skin.fromFlatbuffer.
    final ibm = _readInverseBindMatrices(skin, doc, bufferData);

    // Collect every channel that drives any joint in this skin.
    // Sample times default to {0} (bind pose) plus every keyframe time
    // from those channels. With the emitter converting CUBICSPLINE to
    // bare keyframe values (see _vec3List/_vec4List), evaluating at
    // each keyframe time is exact for our pipeline.
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

    // Iterate primitives. fbPrims is filtered to triangle-mode
    // (mode == 4) primitives only, in the same order as glTF source.
    final glPrims = doc.meshes[glNode.mesh!].primitives;
    int fbPrimIdx = 0;
    for (final glPrim in glPrims) {
      if (glPrim.mode != 4) continue;
      final fbPrim = fbPrims[fbPrimIdx++];
      if (!glPrim.attributes.containsKey('JOINTS_0') ||
          !glPrim.attributes.containsKey('WEIGHTS_0')) {
        continue;
      }

      final influence = _computeJointInfluenceAabbs(
        glPrim,
        doc,
        bufferData,
        jointNodeIndices.length,
      );

      final poseUnion = _AabbBox.empty();
      // Per-pose scratch storage to avoid re-allocating during the
      // tight (sample-times × joints) loop.
      final palette = List<Matrix4>.generate(
        jointNodeIndices.length,
        (_) => Matrix4.identity(),
      );
      final transformedScratch = _AabbBox.empty();

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
          poseUnion.expandToAabbBox(transformedScratch);
        }
      }

      if (!poseUnion.isEmpty) {
        fbPrim.skinnedPoseUnionAabb = fb.Aabb3T(
          min: fb.Vec3T(
            x: poseUnion.minX,
            y: poseUnion.minY,
            z: poseUnion.minZ,
          ),
          max: fb.Vec3T(
            x: poseUnion.maxX,
            y: poseUnion.maxY,
            z: poseUnion.maxZ,
          ),
        );
      }
    }
  }
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
List<_AabbBox> _computeJointInfluenceAabbs(
  GltfMeshPrimitive prim,
  GltfDocument doc,
  Uint8List bufferData,
  int jointCount,
) {
  final influence = List<_AabbBox>.generate(
    jointCount,
    (_) => _AabbBox.empty(),
  );
  final positions = _readVec3(prim.attributes['POSITION']!, doc, bufferData);
  final joints = _readVec4(prim.attributes['JOINTS_0']!, doc, bufferData);
  final weights = _readVec4(prim.attributes['WEIGHTS_0']!, doc, bufferData);
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

// ───── Bounds ─────

/// Build a local-space AABB for a primitive. Uses the accessor's
/// spec-provided `min`/`max` when present (the glTF spec requires them
/// on POSITION accessors but consumers occasionally omit them); falls
/// back to a vertex scan otherwise.
fb.Aabb3T _aabbFromAccessorOrPositions(
  GltfAccessor accessor,
  Float32List positions,
) {
  final min = accessor.min;
  final max = accessor.max;
  if (min != null && min.length >= 3 && max != null && max.length >= 3) {
    return fb.Aabb3T(
      min: fb.Vec3T(x: min[0], y: min[1], z: min[2]),
      max: fb.Vec3T(x: max[0], y: max[1], z: max[2]),
    );
  }
  return _aabbFromPositions(positions);
}

fb.Aabb3T _aabbFromPositions(Float32List positions) {
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
  return fb.Aabb3T(
    min: fb.Vec3T(x: minX, y: minY, z: minZ),
    max: fb.Vec3T(x: maxX, y: maxY, z: maxZ),
  );
}

/// Bounding sphere via Ritter's two-pass approximation: pick the most
/// distant pair along an arbitrary first vertex, seed with their
/// midpoint, then expand to cover any remaining outliers. Tighter than
/// the AABB-circumscribed sphere for elongated meshes while still being
/// O(n).
fb.SphereT _sphereFromPositions(Float32List positions) {
  final vertexCount = positions.length ~/ 3;
  if (vertexCount == 0) {
    return fb.SphereT(center: fb.Vec3T(x: 0, y: 0, z: 0), radius: 0);
  }
  if (vertexCount == 1) {
    return fb.SphereT(
      center: fb.Vec3T(x: positions[0], y: positions[1], z: positions[2]),
      radius: 0,
    );
  }

  // Pass 1: pick vertex farthest from positions[0], then farthest from
  // that. The pair seeds the initial diameter.
  Vector3 readAt(int i) =>
      Vector3(positions[i * 3], positions[i * 3 + 1], positions[i * 3 + 2]);

  final p0 = readAt(0);
  int bestA = 0;
  double bestDist = 0;
  for (int i = 1; i < vertexCount; i++) {
    final d = readAt(i).distanceToSquared(p0);
    if (d > bestDist) {
      bestDist = d;
      bestA = i;
    }
  }
  final a = readAt(bestA);
  int bestB = bestA;
  bestDist = 0;
  for (int i = 0; i < vertexCount; i++) {
    final d = readAt(i).distanceToSquared(a);
    if (d > bestDist) {
      bestDist = d;
      bestB = i;
    }
  }
  final b = readAt(bestB);

  Vector3 center = (a + b) * 0.5;
  double radius = a.distanceTo(b) * 0.5;
  double radiusSq = radius * radius;

  // Pass 2: expand to cover any vertex outside the seed sphere.
  for (int i = 0; i < vertexCount; i++) {
    final v = readAt(i);
    final dSq = v.distanceToSquared(center);
    if (dSq > radiusSq) {
      final d = sqrt(dSq);
      final newRadius = (radius + d) * 0.5;
      final shift = (newRadius - radius) / d;
      center = center + (v - center) * shift;
      radius = newRadius;
      radiusSq = radius * radius;
    }
  }

  return fb.SphereT(
    center: fb.Vec3T(x: center.x, y: center.y, z: center.z),
    radius: radius,
  );
}

// ───── Helpers ─────

fb.MatrixT _matrixT(Matrix4 m) {
  final s = m.storage;
  return fb.MatrixT(
    m0: s[0],
    m1: s[1],
    m2: s[2],
    m3: s[3],
    m4: s[4],
    m5: s[5],
    m6: s[6],
    m7: s[7],
    m8: s[8],
    m9: s[9],
    m10: s[10],
    m11: s[11],
    m12: s[12],
    m13: s[13],
    m14: s[14],
    m15: s[15],
  );
}

fb.MatrixT _matrixFromFloats(Float32List floats, int offset) {
  return fb.MatrixT(
    m0: floats[offset + 0],
    m1: floats[offset + 1],
    m2: floats[offset + 2],
    m3: floats[offset + 3],
    m4: floats[offset + 4],
    m5: floats[offset + 5],
    m6: floats[offset + 6],
    m7: floats[offset + 7],
    m8: floats[offset + 8],
    m9: floats[offset + 9],
    m10: floats[offset + 10],
    m11: floats[offset + 11],
    m12: floats[offset + 12],
    m13: floats[offset + 13],
    m14: floats[offset + 14],
    m15: floats[offset + 15],
  );
}

Float32List _readVec3(int idx, GltfDocument doc, Uint8List bufferData) {
  final a = doc.accessors[idx];
  return readAccessorAsFloat32(a, doc.bufferViews[a.bufferView!], bufferData);
}

Float32List _readVec4(int idx, GltfDocument doc, Uint8List bufferData) {
  final a = doc.accessors[idx];
  return readAccessorAsFloat32(a, doc.bufferViews[a.bufferView!], bufferData);
}
