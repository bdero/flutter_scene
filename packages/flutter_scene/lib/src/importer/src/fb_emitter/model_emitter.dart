/// Build-time emitter: parsed glTF → packed `.model` flatbuffer bytes.
///
/// Writes the same `fb.SceneT` shape that the C++ importer in
/// `importer_gltf.cc` produces, just done in pure Dart so the build hook
/// doesn't need to shell out to a compiled binary. See `model_emitter_test`
/// for byte-level parity coverage against the C++ output.
library;

import 'dart:math' show sqrt;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:vector_math/vector_math.dart';

// Import the generated flatbuffer types directly rather than going through
// flatbuffer.dart, which transitively pulls in `flutter_gpu/gpu.dart` and
// `dart:ui` — both unavailable in the build-hook isolate.
import '../../generated/scene_impeller.fb_flatbuffers.dart' as fb;
import '../../gltf.dart';
import '../../third_party/flat_buffers.dart' as fbb;
import '../gltf/bounds_baker.dart';

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
  // pose-union bound), an `AabbBounds` otherwise. `AabbBounds.empty`
  // represents a soundly computed but empty subtree (no geometry at
  // all), which still serializes as a degenerate AABB so we can tell
  // it apart from "unbounded" at runtime.
  final memo = List<AabbBounds?>.filled(nodes.length, null);
  final computed = List<bool>.filled(nodes.length, false);

  AabbBounds? walk(int idx) {
    if (computed[idx]) return memo[idx];
    computed[idx] = true;

    final node = nodes[idx];
    final glNode = doc.nodes[idx];

    final isSkinned = glNode.skin != null;
    final box = AabbBounds.empty();
    bool subtreeBoundedSoFar = true;

    for (final prim in node.meshPrimitives ?? const <fb.MeshPrimitiveT>[]) {
      final aabb = isSkinned ? prim.skinnedPoseUnionAabb : prim.boundsAabb;
      if (aabb != null) {
        box.includeMinMax(
          aabb.min.x,
          aabb.min.y,
          aabb.min.z,
          aabb.max.x,
          aabb.max.y,
          aabb.max.z,
        );
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
  out.indices = fb.IndicesT()
    ..data = packed.indexBytes
    ..count = packed.indexCount
    ..type = packed.indices32Bit ? fb.IndexType.k32Bit : fb.IndexType.k16Bit;

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
    out.boundsAabb = _toFbAabb(
      aabbFromAccessorOrPositions(positionAccessor, positions),
    );
    out.boundsSphere = _sphereFromPositions(positions);
  }
  return out;
}

fb.Aabb3T _toFbAabb(AabbBounds box) => fb.Aabb3T(
  min: fb.Vec3T(x: box.minX, y: box.minY, z: box.minZ),
  max: fb.Vec3T(x: box.maxX, y: box.maxY, z: box.maxZ),
);

// ───── Materials ─────

fb.MaterialT _buildMaterial(GltfMaterial m) {
  final out = fb.MaterialT();
  out.type = m.unlit
      ? fb.MaterialType.kUnlit
      : fb.MaterialType.kPhysicallyBased;
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
    out.inverseBindMatrices = [
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
  final unions = bakeSkinnedPoseUnionAabbs(doc, bufferData);
  for (final entry in unions.entries) {
    final fbPrims = nodes[entry.key].meshPrimitives;
    if (fbPrims == null) continue;
    final perPrim = entry.value;
    for (int i = 0; i < fbPrims.length && i < perPrim.length; i++) {
      final union = perPrim[i];
      if (union == null) continue;
      fbPrims[i].skinnedPoseUnionAabb = _toFbAabb(union);
    }
  }
}
// ───── Bounds ─────

/// Build a local-space AABB for a primitive. Uses the accessor's
/// spec-provided `min`/`max` when present (the glTF spec requires them
/// on POSITION accessors but consumers occasionally omit them); falls
/// back to a vertex scan otherwise.
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
