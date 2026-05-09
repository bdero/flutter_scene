/// Build-time emitter: parsed glTF → packed `.model` flatbuffer bytes.
///
/// Writes the same `fb.SceneT` shape that the C++ importer in
/// `importer_gltf.cc` produces, just done in pure Dart so the build hook
/// doesn't need to shell out to a compiled binary. See `model_emitter_test`
/// for byte-level parity coverage against the C++ output.
library;

import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:vector_math/vector_math.dart';

import '../../constants.dart';
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
      _buildNode(doc.nodes[i], doc, bufferData),
  ];

  // Animations.
  scene.animations = [
    for (final a in doc.animations) _buildAnimation(a, doc, bufferData),
  ];

  return scene;
}

// ───── Nodes ─────

fb.NodeT _buildNode(GltfNode n, GltfDocument doc, Uint8List bufferData) {
  final out = fb.NodeT();
  out.name = n.name ?? '';
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
  final hasJoints = p.attributes.containsKey('JOINTS_0') &&
      p.attributes.containsKey('WEIGHTS_0');

  // Pack vertex bytes using the same layout as flutter_scene's vertex shaders.
  final vertexBytes = _packVertices(p, doc, bufferData, hasJoints: hasJoints);
  final vertexCount = vertexBytes.length ~/
      (hasJoints ? kSkinnedPerVertexSize : kUnskinnedPerVertexSize);
  if (hasJoints) {
    out.verticesType = fb.VertexBufferTypeId.SkinnedVertexBuffer;
    out.vertices = fb.SkinnedVertexBufferT(
      vertices: vertexBytes,
      vertexCount: vertexCount,
    );
  } else {
    out.verticesType = fb.VertexBufferTypeId.UnskinnedVertexBuffer;
    out.vertices = fb.UnskinnedVertexBufferT(
      vertices: vertexBytes,
      vertexCount: vertexCount,
    );
  }

  // Indices (preserve glTF order — no winding flip).
  out.indices = _buildIndices(p, doc, bufferData);

  // Material.
  if (p.material != null && p.material! < doc.materials.length) {
    out.material = _buildMaterial(doc.materials[p.material!]);
  }
  return out;
}

Uint8List _packVertices(
  GltfMeshPrimitive p,
  GltfDocument doc,
  Uint8List bufferData, {
  required bool hasJoints,
}) {
  final positions = _readVec3(p.attributes['POSITION']!, doc, bufferData);
  final vertexCount = positions.length ~/ 3;
  final normals = _readOptionalVec3('NORMAL', p, doc, bufferData, vertexCount);
  final tex = _readOptionalVec2('TEXCOORD_0', p, doc, bufferData, vertexCount);
  final colors = _readOptionalColor('COLOR_0', p, doc, bufferData, vertexCount);

  final stride = (hasJoints ? kSkinnedPerVertexSize : kUnskinnedPerVertexSize) ~/ 4;
  final out = Float32List(vertexCount * stride);
  for (int i = 0; i < vertexCount; i++) {
    final o = i * stride;
    out[o + 0] = positions[i * 3 + 0];
    out[o + 1] = positions[i * 3 + 1];
    out[o + 2] = positions[i * 3 + 2];
    out[o + 3] = normals[i * 3 + 0];
    out[o + 4] = normals[i * 3 + 1];
    out[o + 5] = normals[i * 3 + 2];
    out[o + 6] = tex[i * 2 + 0];
    out[o + 7] = tex[i * 2 + 1];
    out[o + 8] = colors[i * 4 + 0];
    out[o + 9] = colors[i * 4 + 1];
    out[o + 10] = colors[i * 4 + 2];
    out[o + 11] = colors[i * 4 + 3];
  }
  if (hasJoints) {
    final joints = _readVec4(p.attributes['JOINTS_0']!, doc, bufferData);
    final weights = _readVec4(p.attributes['WEIGHTS_0']!, doc, bufferData);
    for (int i = 0; i < vertexCount; i++) {
      final o = i * stride + 12;
      for (int c = 0; c < 4; c++) {
        out[o + c] = joints[i * 4 + c];
        out[o + 4 + c] = weights[i * 4 + c];
      }
    }
  }
  return out.buffer.asUint8List(out.offsetInBytes, out.lengthInBytes);
}

fb.IndicesT _buildIndices(
  GltfMeshPrimitive p,
  GltfDocument doc,
  Uint8List bufferData,
) {
  final out = fb.IndicesT();
  if (p.indices == null) {
    // Synthesize a sequential 16-bit index list.
    final positionAccessor = doc.accessors[p.attributes['POSITION']!];
    final count = positionAccessor.count;
    final widened = Uint16List(count);
    for (int i = 0; i < count; i++) {
      widened[i] = i;
    }
    out.data = widened.buffer.asUint8List(widened.offsetInBytes, widened.lengthInBytes);
    out.count = count;
    out.type = fb.IndexType.k16Bit;
    return out;
  }
  final accessor = doc.accessors[p.indices!];
  final view = doc.bufferViews[accessor.bufferView!];
  final list = readAccessorAsUint32(accessor, view, bufferData);
  if (accessor.componentType == GltfComponentType.unsignedInt) {
    out.data = list.buffer.asUint8List(list.offsetInBytes, list.lengthInBytes);
    out.count = accessor.count;
    out.type = fb.IndexType.k32Bit;
  } else {
    final widened = Uint16List(list.length);
    for (int i = 0; i < list.length; i++) {
      widened[i] = list[i];
    }
    out.data = widened.buffer.asUint8List(widened.offsetInBytes, widened.lengthInBytes);
    out.count = accessor.count;
    out.type = fb.IndexType.k16Bit;
  }
  return out;
}

// ───── Materials ─────

fb.MaterialT _buildMaterial(GltfMaterial m) {
  final out = fb.MaterialT();
  out.type = m.unlit ? fb.MaterialType.kUnlit : fb.MaterialType.kPhysicallyBased;
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
      for (int i = 0; i < s.joints.length; i++)
        _matrixT(Matrix4.identity()),
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
      fb.Vec3T(x: values[i + off], y: values[i + off + 1], z: values[i + off + 2]),
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

// ───── Helpers ─────

fb.MatrixT _matrixT(Matrix4 m) {
  final s = m.storage;
  return fb.MatrixT(
    m0: s[0], m1: s[1], m2: s[2], m3: s[3],
    m4: s[4], m5: s[5], m6: s[6], m7: s[7],
    m8: s[8], m9: s[9], m10: s[10], m11: s[11],
    m12: s[12], m13: s[13], m14: s[14], m15: s[15],
  );
}

fb.MatrixT _matrixFromFloats(Float32List floats, int offset) {
  return fb.MatrixT(
    m0: floats[offset + 0], m1: floats[offset + 1],
    m2: floats[offset + 2], m3: floats[offset + 3],
    m4: floats[offset + 4], m5: floats[offset + 5],
    m6: floats[offset + 6], m7: floats[offset + 7],
    m8: floats[offset + 8], m9: floats[offset + 9],
    m10: floats[offset + 10], m11: floats[offset + 11],
    m12: floats[offset + 12], m13: floats[offset + 13],
    m14: floats[offset + 14], m15: floats[offset + 15],
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

Float32List _readOptionalVec3(
  String name,
  GltfMeshPrimitive p,
  GltfDocument doc,
  Uint8List bufferData,
  int vertexCount,
) {
  final i = p.attributes[name];
  if (i == null) return Float32List(vertexCount * 3);
  return _readVec3(i, doc, bufferData);
}

Float32List _readOptionalVec2(
  String name,
  GltfMeshPrimitive p,
  GltfDocument doc,
  Uint8List bufferData,
  int vertexCount,
) {
  final i = p.attributes[name];
  if (i == null) return Float32List(vertexCount * 2);
  final a = doc.accessors[i];
  return readAccessorAsFloat32(a, doc.bufferViews[a.bufferView!], bufferData);
}

Float32List _readOptionalColor(
  String name,
  GltfMeshPrimitive p,
  GltfDocument doc,
  Uint8List bufferData,
  int vertexCount,
) {
  final i = p.attributes[name];
  if (i == null) {
    final out = Float32List(vertexCount * 4);
    for (int v = 0; v < vertexCount; v++) {
      out[v * 4 + 0] = 1.0;
      out[v * 4 + 1] = 1.0;
      out[v * 4 + 2] = 1.0;
      out[v * 4 + 3] = 1.0;
    }
    return out;
  }
  final a = doc.accessors[i];
  final raw = readAccessorAsFloat32(a, doc.bufferViews[a.bufferView!], bufferData);
  if (a.type == GltfAccessorType.vec4) return raw;
  // Promote vec3 to vec4 with alpha=1.
  final out = Float32List(vertexCount * 4);
  for (int v = 0; v < vertexCount; v++) {
    out[v * 4 + 0] = raw[v * 3 + 0];
    out[v * 4 + 1] = raw[v * 3 + 1];
    out[v * 4 + 2] = raw[v * 3 + 2];
    out[v * 4 + 3] = 1.0;
  }
  return out;
}
