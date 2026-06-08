/// Build-time emitter: parsed glTF -> an `.fscene` document and its `.fsceneb`
/// binary package.
///
/// This is the `.fscene` counterpart of the `.model` emitter. It builds a
/// [SceneDocument] from the same parsed glTF the `.model` path consumes, then
/// packages it as a `.fsceneb` container. Geometry is packed with the shared
/// [packGltfPrimitive], so a primitive's vertex/index payload bytes are
/// identical to the bytes the `.model` emitter stores (validated by
/// byte-comparison tests).
///
/// Pure Dart (no `dart:ui` / Flutter GPU), so it runs in the build-hook
/// isolate. Ids are derived deterministically from the binary chunk, so
/// re-importing the same asset yields an identical document.
///
// TODO(fscene): emit skins and animations (inverse-bind-matrix and keyframe
// payloads); bake node-level / skinned pose-union bounds for subtree culling.
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
import '../gltf/primitive_packer.dart';
import '../gltf/types.dart';

/// Converts a parsed glTF document (plus its binary buffer) into `.fsceneb`
/// container bytes.
Uint8List emitFsceneb(GltfDocument doc, Uint8List bufferData) =>
    writeFsceneb(buildSceneDocument(doc, bufferData));

/// Builds an `.fscene` [SceneDocument] from a parsed glTF document.
///
/// The document is declared right-handed ([Handedness.right]); the realizer
/// applies the glTF-to-engine mirror, so no per-node winding flip is baked in.
SceneDocument buildSceneDocument(GltfDocument doc, Uint8List bufferData) {
  final seed = _seedFrom(bufferData);
  final document = SceneDocument(
    documentId: DocumentId.generate(Random(seed)),
    allocator: IdAllocator(session: seed),
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
      _buildTexture(document, texture, doc, bufferData),
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

  // Geometry resources per mesh primitive, shared across the nodes that
  // reference the same mesh.
  final meshPairs = <int, List<(LocalId, LocalId)>>{};
  for (var meshIndex = 0; meshIndex < doc.meshes.length; meshIndex++) {
    final pairs = <(LocalId, LocalId)>[];
    for (final primitive in doc.meshes[meshIndex].primitives) {
      if (primitive.mode != 4) continue; // triangles only
      final geometryId = _buildGeometry(document, primitive, doc, bufferData);
      pairs.add((geometryId, materialFor(primitive.material)));
    }
    meshPairs[meshIndex] = pairs;
  }

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
        // TODO(fscene): bind node.skin once skins are emitted (P4b).
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

  return document;
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
  Uint8List bufferData,
) {
  final packed = packGltfPrimitive(
    primitive: primitive,
    accessors: doc.accessors,
    bufferViews: doc.bufferViews,
    bufferData: bufferData,
  );
  final vertices = document.addPayload(
    PayloadSpec(
      document.newId(),
      encoding: PayloadEncoding.vertexBuffer,
      layout: packed.isSkinned ? 'skinned' : 'unskinned',
      length: packed.vertexBytes.length,
      bytes: packed.vertexBytes,
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
          bounds: _bounds(primitive, doc),
        ),
      )
      .id;
}

BoundsSpec? _bounds(GltfMeshPrimitive primitive, GltfDocument doc) {
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
  Uint8List bufferData,
) {
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
      final bytes = rgba.getBytes(order: img.ChannelOrder.rgba);
      final payload = document.addPayload(
        PayloadSpec(
          document.newId(),
          encoding: PayloadEncoding.image,
          format: 'rgba8',
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
    // An external image; the realizer loads it as an asset.
    // TODO(fscene): the realizer needs an async external-image-asset path.
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
int _seedFrom(Uint8List data) {
  var hash = 0x811c9dc5;
  for (final byte in data) {
    hash = (hash ^ byte) & 0xffffffff;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash == 0 ? 1 : hash;
}
