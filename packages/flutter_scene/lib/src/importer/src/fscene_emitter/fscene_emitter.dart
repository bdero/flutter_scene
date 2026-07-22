/// Build-time emitter: parsed glTF -> an `.fscene` document and its `.fsceneb`
/// binary package.
///
/// Builds a [SceneDocument] from a parsed glTF document, then packages it as
/// a `.fsceneb` container. Geometry is packed with the shared
/// [packGltfPrimitive], so a primitive's vertex/index payload bytes are
/// identical to the runtime GLB importer's (validated by byte-comparison
/// tests).
///
/// Pure Dart (no `dart:ui` / Flutter GPU), so it runs in the build-hook
/// isolate. Ids are derived deterministically from the binary chunk, so
/// re-importing the same asset yields an identical document.
///
/// Geometry bounds: unskinned primitives carry their rest AABB; skinned
/// primitives carry the offline-baked pose-union AABB (the union of every
/// animated pose's extent), the only sound cull bound once joints move. A
/// skinned primitive whose pose union could not be computed carries no
/// bounds, and the realizer leaves it unbounded (always visible).
library;

import 'dart:math' show Random;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:vector_math/vector_math.dart';

import '../../../fscene/id.dart';
import '../../../fscene/binary/fsceneb.dart';
import '../../../fscene/property_value.dart';
import '../../../fscene/scene_document.dart';
import '../../../fscene/specs.dart';
import '../../../geometry/interleaved_layout.dart';
import '../../../texture/ktx2_image.dart';
import '../gltf/accessor.dart';
import '../gltf/bounds_baker.dart';
import '../gltf/primitive_packer.dart';
import '../gltf/types.dart';

/// Converts a parsed glTF document (plus its binary buffer) into `.fsceneb`
/// container bytes.
Uint8List emitFsceneb(
  GltfDocument doc,
  Uint8List bufferData, {
  bool compressTextures = false,
}) => writeFsceneb(
  buildSceneDocument(doc, bufferData, compressTextures: compressTextures),
);

/// Builds an `.fscene` [SceneDocument] from a parsed glTF document.
///
/// The document is declared right-handed ([Handedness.right]); the realizer
/// applies the glTF-to-engine mirror, so no per-node winding flip is baked in.
///
/// When [compressTextures] is set, images are stored as mipped, supercompressed
/// KTX2 block payloads (`format: 'ktx2'`) instead of raw `rgba8`, shrinking the
/// container; the realizer transcodes or decodes them at load.
SceneDocument buildSceneDocument(
  GltfDocument doc,
  Uint8List bufferData, {
  bool compressTextures = false,
}) {
  // The document id stays content-derived, so distinct imports get distinct
  // ids, but local ids are minted from a fixed session: a node's id then
  // depends only on its position in the glTF, not on the buffer bytes. So
  // re-importing an edited model keeps the same ids for nodes whose position is
  // unchanged, and prefab overrides keyed by those ids survive the re-import
  // (the editor's linked-asset import relies on this).
  final document = SceneDocument(
    documentId: DocumentId.generate(Random(_seedFrom(bufferData))),
    allocator: IdAllocator(session: _kImporterIdSession),
  );
  document.stage
    ..upAxis = UpAxis.y
    ..handedness = Handedness.right;
  document.generator = 'flutter_scene glTF importer';

  // Pre-mint a stable id per glTF node so child/joint/animation-target
  // references resolve regardless of the build order below.
  final nodeIds = [for (var i = 0; i < doc.nodes.length; i++) document.newId()];

  // Textures, then materials (which reference textures), then mesh geometry
  // (which references materials).
  final textureIds = [
    for (final texture in doc.textures)
      _buildTexture(
        document,
        texture,
        doc,
        bufferData,
        compressTextures: compressTextures,
      ),
  ];
  final materialIds = [
    for (final material in doc.materials)
      _buildMaterial(document, material, textureIds),
  ];

  LocalId? defaultMaterialId;
  LocalId materialFor(int? index) {
    if (index != null && index >= 0 && index < materialIds.length) {
      return materialIds[index];
    }
    return defaultMaterialId ??= document
        .addResource(
          MaterialResource(document.newId(), type: 'physicallyBased'),
        )
        .id;
  }

  // Pose-union analysis for skinned culling, plus which nodes use each mesh
  // (geometry resources are shared per mesh, so a mesh used by a skinned
  // node carries pose-union bounds rather than rest bounds).
  final poseUnions = bakeSkinnedPoseUnionAabbs(doc, bufferData);
  final skinnedUsers = <int, List<int>>{};
  final unskinnedUse = <int>{};
  for (var i = 0; i < doc.nodes.length; i++) {
    final node = doc.nodes[i];
    final mesh = node.mesh;
    if (mesh == null) continue;
    if (node.skin != null) {
      skinnedUsers.putIfAbsent(mesh, () => []).add(i);
    } else {
      unskinnedUse.add(mesh);
    }
  }

  // Geometry resources per mesh primitive, shared across the nodes that
  // reference the same mesh.
  final meshPairs = <int, List<(LocalId, LocalId)>>{};
  for (var meshIndex = 0; meshIndex < doc.meshes.length; meshIndex++) {
    final pairs = <(LocalId, LocalId)>[];
    var primIndex = 0;
    for (final primitive in doc.meshes[meshIndex].primitives) {
      if (primitive.mode != 4) continue; // triangles only
      final bounds = _primitiveBounds(
        primitive,
        doc,
        primIndex,
        skinnedUsers: skinnedUsers[meshIndex],
        alsoUsedUnskinned: unskinnedUse.contains(meshIndex),
        poseUnions: poseUnions,
      );
      final geometryId = _buildGeometry(
        document,
        primitive,
        doc,
        bufferData,
        bounds: bounds,
      );
      pairs.add((geometryId, materialFor(primitive.material)));
      primIndex++;
    }
    meshPairs[meshIndex] = pairs;
  }

  // Skins (joints reference nodes by id; inverse-bind matrices ride in a
  // payload chunk).
  final skinIds = [
    for (final skin in doc.skins)
      _buildSkin(document, skin, doc, bufferData, nodeIds),
  ];

  // Nodes.
  for (var i = 0; i < doc.nodes.length; i++) {
    final node = doc.nodes[i];
    final components = <ComponentSpec>[];
    if (node.mesh != null && node.mesh! < doc.meshes.length) {
      final pairs = meshPairs[node.mesh!] ?? const [];
      if (pairs.isNotEmpty) components.add(_meshComponent(pairs));
    }
    document.addNode(
      NodeSpec(
        id: nodeIds[i],
        name: resolveGltfNodeName(node.name, i),
        transform: _transform(node),
        children: [
          for (final c in node.children)
            if (c >= 0 && c < nodeIds.length) nodeIds[c],
        ],
        components: components,
        skin: (node.skin != null && node.skin! < skinIds.length)
            ? skinIds[node.skin!]
            : null,
      ),
    );
  }

  // Roots from the default scene.
  final sceneIndex = doc.scene ?? (doc.scenes.isNotEmpty ? 0 : -1);
  if (sceneIndex >= 0 && sceneIndex < doc.scenes.length) {
    for (final root in doc.scenes[sceneIndex].nodes) {
      if (root >= 0 && root < nodeIds.length) document.roots.add(nodeIds[root]);
    }
  }

  // Animations (one keyframe timeline/value payload per channel).
  for (final animation in doc.animations) {
    _buildAnimation(document, animation, doc, bufferData, nodeIds);
  }

  return document;
}

LocalId _buildSkin(
  SceneDocument document,
  GltfSkin skin,
  GltfDocument doc,
  Uint8List bufferData,
  List<LocalId> nodeIds,
) {
  final Float32List matrices;
  if (skin.inverseBindMatrices != null) {
    final accessor = doc.accessors[skin.inverseBindMatrices!];
    matrices = readAccessorAsFloat32(
      accessor,
      doc.bufferViews[accessor.bufferView!],
      bufferData,
    );
  } else {
    // Spec default: identity per joint, column-major.
    matrices = Float32List(skin.joints.length * 16);
    for (var i = 0; i < skin.joints.length; i++) {
      matrices[i * 16 + 0] = 1.0;
      matrices[i * 16 + 5] = 1.0;
      matrices[i * 16 + 10] = 1.0;
      matrices[i * 16 + 15] = 1.0;
    }
  }
  final payload = _floatPayload(document, matrices, PayloadEncoding.matrices);
  return document
      .addSkin(
        SkinSpec(
          document.newId(),
          joints: [
            for (final j in skin.joints)
              if (j >= 0 && j < nodeIds.length) nodeIds[j],
          ],
          inverseBindMatrices: payload,
          skeleton: (skin.skeleton != null && skin.skeleton! < nodeIds.length)
              ? nodeIds[skin.skeleton!]
              : null,
        ),
      )
      .id;
}

void _buildAnimation(
  SceneDocument document,
  GltfAnimation animation,
  GltfDocument doc,
  Uint8List bufferData,
  List<LocalId> nodeIds,
) {
  final channels = <AnimationChannelSpec>[];
  for (final channel in animation.channels) {
    final target = channel.targetNode;
    if (target == null || target < 0 || target >= nodeIds.length) continue;
    if (channel.sampler < 0 || channel.sampler >= animation.samplers.length) {
      continue;
    }
    final property = switch (channel.targetPath) {
      'translation' => AnimationProperty.translation,
      'rotation' => AnimationProperty.rotation,
      'scale' => AnimationProperty.scale,
      _ => null, // 'weights' (morph targets) and unknowns
    };
    if (property == null) continue;

    final sampler = animation.samplers[channel.sampler];
    final inputAccessor = doc.accessors[sampler.input];
    final outputAccessor = doc.accessors[sampler.output];
    final times = readAccessorAsFloat32(
      inputAccessor,
      doc.bufferViews[inputAccessor.bufferView!],
      bufferData,
    );
    final values = readAccessorAsFloat32(
      outputAccessor,
      doc.bufferViews[outputAccessor.bufferView!],
      bufferData,
    );
    final componentCount = property == AnimationProperty.rotation ? 4 : 3;
    final keyframes = _stripCubicTangents(
      values,
      componentCount,
      sampler.interpolation == 'CUBICSPLINE',
    );

    channels.add(
      AnimationChannelSpec(
        target: nodeIds[target],
        targetName: resolveGltfNodeName(doc.nodes[target].name, target),
        property: property,
        timeline: _floatPayload(
          document,
          Float32List.fromList(times),
          PayloadEncoding.floats,
        ),
        keyframes: _floatPayload(document, keyframes, PayloadEncoding.floats),
      ),
    );
  }
  if (channels.isEmpty) return;
  document.addAnimation(
    AnimationSpec(
      document.newId(),
      name: animation.name ?? '',
      channels: channels,
    ),
  );
}

// Reduces a CUBICSPLINE sampler's [in-tangent, value, out-tangent] groups to
// just the keyframe values, so the stored timeline is plain LINEAR keyframes
// (the runtime treats both paths' values the same way). Non-cubic data is
// copied through.
Float32List _stripCubicTangents(
  Float32List values,
  int componentCount,
  bool isCubic,
) {
  if (!isCubic) return Float32List.fromList(values);
  final stride = componentCount * 3;
  final out = <double>[];
  for (var i = 0; i + stride <= values.length; i += stride) {
    for (var c = 0; c < componentCount; c++) {
      out.add(values[i + componentCount + c]);
    }
  }
  return Float32List.fromList(out);
}

LocalId _floatPayload(
  SceneDocument document,
  Float32List floats,
  PayloadEncoding encoding,
) {
  final bytes = floats.buffer.asUint8List(
    floats.offsetInBytes,
    floats.lengthInBytes,
  );
  return document
      .addPayload(
        PayloadSpec(
          document.newId(),
          encoding: encoding,
          length: bytes.length,
          bytes: bytes,
        ),
      )
      .id;
}

ComponentSpec _meshComponent(List<(LocalId, LocalId)> pairs) {
  if (pairs.length == 1) {
    return ComponentSpec(
      'mesh',
      properties: {
        'geometry': ResourceRefValue(pairs.first.$1),
        'material': ResourceRefValue(pairs.first.$2),
      },
    );
  }
  return ComponentSpec(
    'mesh',
    properties: {
      'primitives': ListValue([
        for (final (geometryId, materialId) in pairs)
          MapValue({
            'geometry': ResourceRefValue(geometryId),
            'material': ResourceRefValue(materialId),
          }),
      ]),
    },
  );
}

TransformSpec _transform(GltfNode node) {
  if (node.matrix != null) return MatrixTransform(node.matrix!.clone());
  return TrsTransform(
    translation: (node.translation ?? Vector3.zero()).clone(),
    rotation: (node.rotation ?? Quaternion.identity()).clone(),
    scale: (node.scale ?? Vector3(1, 1, 1)).clone(),
  );
}

LocalId _buildGeometry(
  SceneDocument document,
  GltfMeshPrimitive primitive,
  GltfDocument doc,
  Uint8List bufferData, {
  required BoundsSpec? bounds,
}) {
  final packed = packGltfPrimitive(
    primitive: primitive,
    accessors: doc.accessors,
    bufferViews: doc.bufferViews,
    bufferData: bufferData,
  );
  // Unskinned geometry is stored de-interleaved (structure of arrays) so the
  // realizer uploads each attribute straight to its own GPU buffer with no
  // load-time reshuffle. Skinned geometry stays interleaved.
  final Uint8List vertexBytes;
  final String vertexLayout;
  if (packed.isSkinned) {
    vertexBytes = packed.vertexBytes;
    vertexLayout = 'skinned';
  } else {
    vertexBytes = InterleavedLayoutAdapter.concatUnskinnedStreams(
      InterleavedLayoutAdapter.splitUnskinnedAttributes(
        ByteData.sublistView(packed.vertexBytes),
        packed.vertexCount,
      ),
    );
    vertexLayout = InterleavedLayoutAdapter.unskinnedSoaLayout;
  }
  final vertices = document.addPayload(
    PayloadSpec(
      document.newId(),
      encoding: PayloadEncoding.vertexBuffer,
      layout: vertexLayout,
      length: vertexBytes.length,
      bytes: vertexBytes,
    ),
  );
  final indices = document.addPayload(
    PayloadSpec(
      document.newId(),
      encoding: PayloadEncoding.indexBuffer,
      format: packed.indices32Bit ? 'uint32' : 'uint16',
      length: packed.indexBytes.length,
      bytes: packed.indexBytes,
    ),
  );
  return document
      .addResource(
        GeometryResource(
          document.newId(),
          vertices: vertices.id,
          indices: indices.id,
          bounds: bounds,
        ),
      )
      .id;
}

/// Chooses the cull bounds for one shared mesh primitive.
///
/// A primitive used by skinned nodes carries the union of those nodes' baked
/// pose-union AABBs ([poseUnions], aligned with the mesh's triangle-mode
/// primitive order); when any pose union is missing, the primitive carries no
/// bounds and renders unculled. When the mesh is also referenced by an
/// unskinned node, the rest AABB is unioned in so the shared bound covers
/// both usages. Primitives without skinning attributes (or without skinned
/// users) carry the rest AABB.
BoundsSpec? _primitiveBounds(
  GltfMeshPrimitive primitive,
  GltfDocument doc,
  int primIndex, {
  required List<int>? skinnedUsers,
  required bool alsoUsedUnskinned,
  required Map<int, List<AabbBounds?>> poseUnions,
}) {
  final skinnedPrimitive =
      primitive.attributes.containsKey('JOINTS_0') &&
      primitive.attributes.containsKey('WEIGHTS_0');
  if (!skinnedPrimitive || skinnedUsers == null || skinnedUsers.isEmpty) {
    return _restBounds(primitive, doc);
  }

  final box = AabbBounds.empty();
  for (final nodeIndex in skinnedUsers) {
    final unions = poseUnions[nodeIndex];
    final union = unions != null && primIndex < unions.length
        ? unions[primIndex]
        : null;
    // No computable pose union (no joints, empty influence): leave the
    // primitive unbounded so it is never culled mid-animation.
    if (union == null || union.isEmpty) return null;
    box.expandToBounds(union);
  }
  if (alsoUsedUnskinned) {
    final rest = _restBounds(primitive, doc);
    if (rest == null) return null;
    box.includeMinMax(
      rest.min.x,
      rest.min.y,
      rest.min.z,
      rest.max.x,
      rest.max.y,
      rest.max.z,
    );
  }
  if (box.isEmpty) return null;
  return BoundsSpec(
    min: Vector3(box.minX, box.minY, box.minZ),
    max: Vector3(box.maxX, box.maxY, box.maxZ),
  );
}

BoundsSpec? _restBounds(GltfMeshPrimitive primitive, GltfDocument doc) {
  final index = primitive.attributes['POSITION'];
  if (index == null) return null;
  final accessor = doc.accessors[index];
  final min = accessor.min;
  final max = accessor.max;
  if (min != null && min.length >= 3 && max != null && max.length >= 3) {
    return BoundsSpec(
      min: Vector3(min[0], min[1], min[2]),
      max: Vector3(max[0], max[1], max[2]),
    );
  }
  // No spec-provided bounds; the realizer scans positions on upload.
  return null;
}

LocalId _buildMaterial(
  SceneDocument document,
  GltfMaterial material,
  List<LocalId?> textureIds,
) {
  final pbr = material.pbrMetallicRoughness;
  final base = pbr?.baseColorFactor;
  final properties = <String, PropertyValue>{
    'baseColor': ColorValue(
      _at(base, 0, 1.0),
      _at(base, 1, 1.0),
      _at(base, 2, 1.0),
      _at(base, 3, 1.0),
    ),
    'doubleSided': BoolValue(material.doubleSided),
    'alphaMode': StringValue(material.alphaMode.toLowerCase()),
    'alphaCutoff': DoubleValue(material.alphaCutoff),
  };
  _addTexture(
    properties,
    'baseColorTexture',
    pbr?.baseColorTexture,
    textureIds,
  );

  if (material.unlit) {
    return document
        .addResource(
          MaterialResource(
            document.newId(),
            type: 'unlit',
            name: material.name ?? '',
            properties: properties,
          ),
        )
        .id;
  }

  properties['metallic'] = DoubleValue(pbr?.metallicFactor ?? 0.0);
  properties['roughness'] = DoubleValue(pbr?.roughnessFactor ?? 0.5);
  properties['emissive'] = ColorValue(
    _at(material.emissiveFactor, 0, 0.0),
    _at(material.emissiveFactor, 1, 0.0),
    _at(material.emissiveFactor, 2, 0.0),
    1.0,
  );
  properties['occlusionStrength'] = DoubleValue(
    material.occlusionTexture?.strength ?? 1.0,
  );
  if (material.normalTexture?.scale != null) {
    properties['normalScale'] = DoubleValue(material.normalTexture!.scale!);
  }
  _addTexture(
    properties,
    'metallicRoughnessTexture',
    pbr?.metallicRoughnessTexture,
    textureIds,
  );
  _addTexture(properties, 'normalTexture', material.normalTexture, textureIds);
  _addTexture(
    properties,
    'occlusionTexture',
    material.occlusionTexture,
    textureIds,
  );
  _addTexture(
    properties,
    'emissiveTexture',
    material.emissiveTexture,
    textureIds,
  );

  return document
      .addResource(
        MaterialResource(
          document.newId(),
          type: 'physicallyBased',
          name: material.name ?? '',
          properties: properties,
        ),
      )
      .id;
}

void _addTexture(
  Map<String, PropertyValue> properties,
  String key,
  GltfTextureInfo? info,
  List<LocalId?> textureIds,
) {
  if (info == null) return;
  if (info.index < 0 || info.index >= textureIds.length) return;
  final id = textureIds[info.index];
  if (id != null) properties[key] = ResourceRefValue(id);
}

LocalId? _buildTexture(
  SceneDocument document,
  GltfTexture texture,
  GltfDocument doc,
  Uint8List bufferData, {
  bool compressTextures = false,
}) {
  if (texture.source == null || texture.source! >= doc.images.length) {
    return null;
  }
  final image = doc.images[texture.source!];
  if (image.bufferView != null) {
    final view = doc.bufferViews[image.bufferView!];
    final encoded = Uint8List.sublistView(
      bufferData,
      view.byteOffset,
      view.byteOffset + view.byteLength,
    );
    final decoded = img.decodeImage(encoded);
    if (decoded != null) {
      final rgba = decoded.convert(numChannels: 4, format: img.Format.uint8);
      final raw = rgba.getBytes(order: img.ChannelOrder.rgba);
      // sRGB needs no per-role handling here: the engine linearizes sRGB in
      // the fragment shaders (SRGBToLinear on the sampled base color), so
      // every texture uploads as a non-sRGB format regardless of role and
      // the compressed path matches the uncompressed one.
      // TODO(texture-compression): set generateMips once the GPU upload uploads
      // the full chain (see compressed_texture.dart); today the upload uses the
      // base level only, so storing mips would just bloat the container. Mip
      // downsampling should then be gamma-correct for base-color (sRGB) roles,
      // which is where knowing the texture's material slot becomes relevant.
      // ASTC 4x4 (the compressed format) requires both dimensions to be a
      // multiple of the 4x4 block size; a non-aligned compressed texture is
      // rejected at GPU load and shows a placeholder. Fall back to uncompressed
      // rgba8 for those.
      // TODO(texture-compression): pad/rescale to a multiple of 4 (adjusting
      // UVs) so these can stay compressed.
      final blockAligned = rgba.width % 4 == 0 && rgba.height % 4 == 0;
      final compress = compressTextures && blockAligned;
      final bytes = compress
          ? encodeImageToKtx2Bytes(
              raw,
              rgba.width,
              rgba.height,
              supercompress: true,
            )
          : raw;
      final payload = document.addPayload(
        PayloadSpec(
          document.newId(),
          encoding: PayloadEncoding.image,
          format: compress ? 'ktx2' : 'rgba8',
          width: rgba.width,
          height: rgba.height,
          length: bytes.length,
          bytes: bytes,
        ),
      );
      return document
          .addResource(TextureResource(document.newId(), payload: payload.id))
          .id;
    }
  }
  if (image.uri != null) {
    // An external image, carried as an asset reference; the async realize
    // path loads it from the asset bundle by this key, so the uri must be a
    // valid bundle asset path.
    return document
        .addResource(
          TextureResource(document.newId(), asset: AssetRef(image.uri!)),
        )
        .id;
  }
  return null;
}

double _at(List<double>? values, int index, double fallback) =>
    (values != null && values.length > index) ? values[index] : fallback;

// A 32-bit FNV-1a hash of [data], used to seed deterministic, content-derived
// document and session ids so re-importing the same asset is reproducible.
// Build-time only (native), so 64-bit int math is fine.
// The fixed local-id session every import uses, so node ids are positional
// (stable across content edits) rather than content-derived. Distinct imports
// are still distinguished by their content-derived document id.
const int _kImporterIdSession = 0x5ce4e5;

int _seedFrom(Uint8List data) {
  var hash = 0x811c9dc5;
  for (final byte in data) {
    hash = (hash ^ byte) & 0xffffffff;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash == 0 ? 1 : hash;
}
