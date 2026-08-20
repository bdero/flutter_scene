import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:vector_math/vector_math.dart';
import 'package:flutter_scene/src/importer/gltf.dart';
import 'package:flutter_scene/src/importer/gltf_light_units.dart';

import '../animation.dart';
import '../components/component.dart';
import '../components/directional_light_component.dart';
import '../components/image_based_light_component.dart';
import '../components/materials_variants_component.dart';
import '../components/point_light_component.dart';
import '../components/spot_light_component.dart';
import '../light.dart';
import '../material/material.dart';
import '../material/unlit_material.dart';
import '../mesh.dart';
import '../node.dart';
import '../skin.dart';
import '../texture/texture2d.dart';
import 'animation_builder.dart';
import 'geometry_builder.dart';
import 'gltf_resources.dart';
import 'material_builder.dart';
import 'skin_builder.dart';
import 'texture_builder.dart';

export 'package:flutter_scene/src/importer/gltf.dart'
    show GltfImportWarning, GltfWarningCallback;
export 'gltf_resources.dart' show GltfResourceResolver;

/// Parse a GLB byte stream into a [Node] tree.
///
/// Returns a synthesized root node whose children are the root nodes of the
/// GLB's default scene. Each scene node is created and wired up to match the
/// glTF node hierarchy. [onWarning], when given, receives non-fatal import
/// issues (an unrecognized extension, an image that fell back to a
/// placeholder); without it they print instead.
Future<Node> importGlb(
  Uint8List bytes, {
  GltfWarningCallback? onWarning,
}) async {
  final container = parseGlb(bytes);
  final doc = parseGltfJson(container.json);
  _deliverWarnings(doc.warnings, onWarning);
  final normalized = await _normalizeBuffers(
    doc,
    glbBinaryChunk: container.binaryChunk,
    resolveUri: null,
  );
  final gltf = decodeMeshoptBufferViews(normalized.doc, normalized.bufferData);
  final packed = await _packPrimitives(gltf.doc, gltf.bufferData);
  return _buildScene(
    gltf.doc,
    gltf.bufferData,
    packed,
    null,
    onWarning: onWarning,
  );
}

/// Parse a multi-file glTF document into a [Node] tree.
///
/// [gltfJson] is the raw bytes of the `.gltf` file. [resolveUri] fetches
/// each external resource (the `.bin` buffer and image files) the
/// document references by relative URI, percent-decoded; `data:` URIs are
/// decoded internally and never reach the resolver. A document with more
/// than one buffer has every buffer concatenated and its bufferViews
/// rebased, the same normalization the offline importer performs.
/// [onWarning], when given, receives non-fatal import issues; without it
/// they print instead.
Future<Node> importGltf(
  Uint8List gltfJson, {
  required GltfResourceResolver resolveUri,
  GltfWarningCallback? onWarning,
}) async {
  final json = jsonDecode(utf8.decode(gltfJson)) as Map<String, Object?>;
  final doc = parseGltfJson(json);
  _deliverWarnings(doc.warnings, onWarning);
  final normalized = await _normalizeBuffers(
    doc,
    glbBinaryChunk: Uint8List(0),
    resolveUri: resolveUri,
  );
  final gltf = decodeMeshoptBufferViews(normalized.doc, normalized.bufferData);
  final packed = await _packPrimitives(gltf.doc, gltf.bufferData);
  return _buildScene(
    gltf.doc,
    gltf.bufferData,
    packed,
    resolveUri,
    onWarning: onWarning,
  );
}

// Delivers parse-time warnings to onWarning, or prints them when absent.
// Safe to call before any isolate hop: parseGltfJson always runs on the
// calling isolate, never inside compute().
void _deliverWarnings(
  List<GltfImportWarning> warnings,
  GltfWarningCallback? onWarning,
) {
  for (final warning in warnings) {
    if (onWarning != null) {
      onWarning(warning);
    } else {
      debugPrint('glTF import: $warning');
    }
  }
}

/// Packs every mesh primitive's vertex/index data on a background isolate,
/// off the UI thread, so a large model does not stall the app while it loads.
///
/// Returns the packed primitives indexed `[meshIndex][primitiveIndex]`, with a
/// null entry for each non-triangle primitive (skipped, see [_populateNode]).
/// The GPU upload of these buffers still happens on the raster thread, in
/// [geometryFromPacked]; only the pure-data packing moves off it. On the web,
/// where [compute] runs inline, this is a no-op indirection.
///
/// TODO(runtime-import-offload): the JSON parse and the skin/animation accessor
/// decode still run on the calling thread. They are small next to vertex
/// packing, but could also move onto the isolate (parse from raw bytes there,
/// return the packed skins/animations too) to fully offload a heavy import.
typedef _PackedPrimitiveVariants = ({
  PackedPrimitive unskinned,
  PackedPrimitive skinned,
});

Future<List<List<_PackedPrimitiveVariants?>>> _packPrimitives(
  GltfDocument doc,
  Uint8List bufferData,
) => compute(_packPrimitivesIsolate, (doc: doc, bufferData: bufferData));

// Top-level so it can run on a background isolate. Packs each primitive with
// the shared [packGltfPrimitive]; non-triangle topologies pack to null.
List<List<_PackedPrimitiveVariants?>> _packPrimitivesIsolate(
  ({GltfDocument doc, Uint8List bufferData}) input,
) {
  final doc = input.doc;
  final skinnedMeshes = <int>{};
  final unskinnedMeshes = <int>{};
  for (final node in doc.nodes) {
    final mesh = node.mesh;
    if (mesh == null) continue;
    (node.skin == null ? unskinnedMeshes : skinnedMeshes).add(mesh);
  }

  _PackedPrimitiveVariants pack(int meshIndex, GltfMeshPrimitive primitive) {
    PackedPrimitive run(bool includeSkinning) => packGltfPrimitive(
      primitive: primitive,
      accessors: doc.accessors,
      bufferViews: doc.bufferViews,
      bufferData: input.bufferData,
      coordinatePolicy: GltfCoordinatePolicy.runtimeBoundary,
      includeSkinning: includeSkinning,
    );
    final carriesSkinning =
        primitive.attributes.containsKey('JOINTS_0') &&
        primitive.attributes.containsKey('WEIGHTS_0');
    if (carriesSkinning && skinnedMeshes.contains(meshIndex)) {
      final skinned = run(true);
      if (!unskinnedMeshes.contains(meshIndex)) {
        return (unskinned: skinned, skinned: skinned);
      }
      return (unskinned: run(false), skinned: skinned);
    }
    final unskinned = run(false);
    return (unskinned: unskinned, skinned: unskinned);
  }

  for (final mesh in doc.meshes) {
    validateMorphTargetConsistency(mesh);
  }
  return [
    for (var meshIndex = 0; meshIndex < doc.meshes.length; meshIndex++)
      [
        for (final p in doc.meshes[meshIndex].primitives)
          if (p.mode != 4) null else pack(meshIndex, p),
      ],
  ];
}

/// Builds the [Node] tree from a parsed document, its resolved buffer, and its
/// pre-packed primitives. Shared by the GLB and multi-file glTF entry points.
Future<Node> _buildScene(
  GltfDocument doc,
  Uint8List bufferData,
  List<List<_PackedPrimitiveVariants?>> packed,
  GltfResourceResolver? resolveUri, {
  GltfWarningCallback? onWarning,
}) async {
  // Decode all textures up front so material construction can reference
  // them by index without per-material async work.
  final List<Texture2D> textures = await buildTextures(
    doc,
    bufferData,
    resolveUri: resolveUri,
    onWarning: onWarning,
  );
  final materials = await Future.wait([
    for (final material in doc.materials) buildMaterial(material, textures),
  ]);

  // Pre-allocate engine Node placeholders 1:1 with glTF nodes so children
  // can refer to them by index regardless of the order we visit them in.
  final List<Node> engineNodes = List.generate(doc.nodes.length, (_) => Node());

  // Collects each primitive's per-variant materials (KHR_materials_variants)
  // so the component attached to the root can swap them later.
  final List<MaterialsVariantBinding> variantBindings = [];

  for (int i = 0; i < doc.nodes.length; i++) {
    _populateNode(
      index: i,
      engineNode: engineNodes[i],
      gltfNode: doc.nodes[i],
      doc: doc,
      packed: packed,
      engineNodes: engineNodes,
      materials: materials,
      variantBindings: variantBindings,
    );
  }

  // Build skins (after nodes are wired so isJoint flags propagate correctly)
  // and attach them to nodes that reference them.
  final List<Skin> skins = [
    for (final s in doc.skins)
      buildSkin(
        gltfSkin: s,
        accessors: doc.accessors,
        bufferViews: doc.bufferViews,
        bufferData: bufferData,
        engineNodes: engineNodes,
        coordinatePolicy: GltfCoordinatePolicy.runtimeBoundary,
      ),
  ];
  for (int i = 0; i < doc.nodes.length; i++) {
    final skinIdx = doc.nodes[i].skin;
    if (skinIdx != null && skinIdx >= 0 && skinIdx < skins.length) {
      engineNodes[i].skin = skins[skinIdx];
    }
  }

  // Pick the default scene (or the first one, or empty).
  final sceneIndex = doc.scene ?? (doc.scenes.isNotEmpty ? 0 : null);
  // Keep source data untouched and convert once at the imported boundary.
  // Packed geometry carries its source winding so the renderer can combine
  // it with this mirror without rewriting indices or vertex data.
  final root = Node(
    name: 'root',
    localTransform: Matrix4.identity()..setEntry(2, 2, -1.0),
  );
  if (doc.materialsVariants.isNotEmpty) {
    root.addComponent(
      MaterialsVariantsComponent.internal(
        doc.materialsVariants,
        variantBindings,
      ),
    );
  }
  final imageBasedLight = await _buildImageBasedLight(
    doc,
    bufferData,
    sceneIndex,
    resolveUri,
  );
  if (imageBasedLight != null) {
    root.addComponent(imageBasedLight);
  }
  if (sceneIndex != null && sceneIndex < doc.scenes.length) {
    for (final rootNodeIdx in doc.scenes[sceneIndex].nodes) {
      if (rootNodeIdx >= 0 && rootNodeIdx < engineNodes.length) {
        root.add(engineNodes[rootNodeIdx]);
      }
    }
  }

  // Build animations and attach them to the synthesized root, mirroring how
  // the scene realizer attaches them.
  for (final ga in doc.animations) {
    root.addParsedAnimation(
      buildAnimation(
        gltfAnimation: ga,
        accessors: doc.accessors,
        bufferViews: doc.bufferViews,
        bufferData: bufferData,
        engineNodes: engineNodes,
        coordinatePolicy: GltfCoordinatePolicy.runtimeBoundary,
      ),
    );
  }

  debugPrint(
    'Unpacking glTF (nodes: ${doc.nodes.length}, '
    'meshes: ${doc.meshes.length}, '
    'materials: ${doc.materials.length}, '
    'skins: ${doc.skins.length}, '
    'animations: ${doc.animations.length})',
  );

  return root;
}

void _populateNode({
  required int index,
  required Node engineNode,
  required GltfNode gltfNode,
  required GltfDocument doc,
  required List<List<_PackedPrimitiveVariants?>> packed,
  required List<Node> engineNodes,
  required List<Material> materials,
  required List<MaterialsVariantBinding> variantBindings,
}) {
  engineNode.name = resolveGltfNodeName(gltfNode.name, index);
  const coordinatePolicy = GltfCoordinatePolicy.runtimeBoundary;
  final matrix = gltfNode.matrix;
  if (matrix != null) {
    engineNode.localTransform = coordinatePolicy.convertTransform(matrix);
  } else {
    // Keep the authored TRS. Recovering it from the composed matrix puts
    // a mirrored bone's negative scale on the wrong axis, which breaks
    // animation blending.
    engineNode.setLocalTransformTrs(
      DecomposedTransform(
        translation: coordinatePolicy.convertPosition(
          gltfNode.translation ?? Vector3.zero(),
        ),
        rotation: coordinatePolicy.convertRotation(
          gltfNode.rotation ?? Quaternion.identity(),
        ),
        scale: gltfNode.scale?.clone() ?? Vector3(1.0, 1.0, 1.0),
      ),
    );
  }

  if (gltfNode.mesh != null) {
    final gltfMesh = doc.meshes[gltfNode.mesh!];
    final packedMesh = packed[gltfNode.mesh!];
    final primitives = <MeshPrimitive>[];
    for (int pi = 0; pi < gltfMesh.primitives.length; pi++) {
      final p = gltfMesh.primitives[pi];
      final packedVariants = packedMesh[pi];
      // A null entry is a non-triangle topology skipped during packing; they
      // need shader/render-state support that flutter_scene's pipeline doesn't
      // currently expose.
      if (packedVariants == null) {
        debugPrint(
          'Skipping mesh primitive with unsupported topology mode ${p.mode}',
        );
        continue;
      }
      final packedPrimitive = gltfNode.skin == null
          ? packedVariants.unskinned
          : packedVariants.skinned;
      final geometry = geometryFromPacked(
        packedPrimitive,
        morphTargetNames: gltfMesh.targetNames,
        defaultMorphWeights: gltfMesh.weights,
      );
      final material = p.material != null
          ? materials[p.material!]
          : UnlitMaterial();
      final primitive = MeshPrimitive(geometry, material);
      if (p.variantMappings.isNotEmpty) {
        // Build each variant's material now (textures are already decoded)
        // so selection is a plain reassignment. A mapping that names the
        // default material index reuses the default instance.
        variantBindings.add(
          MaterialsVariantBinding(
            node: engineNode,
            primitiveIndex: primitives.length,
            defaultMaterial: material,
            materialsByVariant: {
              for (final entry in p.variantMappings.entries)
                if (entry.value >= 0 && entry.value < doc.materials.length)
                  entry.key: entry.value == p.material
                      ? material
                      : materials[entry.value],
            },
          ),
        );
      }
      primitives.add(primitive);
    }
    if (primitives.isNotEmpty) {
      engineNode.mesh = Mesh.primitives(primitives: primitives);
      // node.weights overrides the mesh defaults for this instance.
      final nodeWeights = gltfNode.weights;
      if (nodeWeights != null && engineNode.internalMorphWeights != null) {
        engineNode.setMorphWeights(nodeWeights);
      }
    }
  }

  final lightIndex = gltfNode.light;
  if (lightIndex != null && lightIndex >= 0 && lightIndex < doc.lights.length) {
    final component = _buildLightComponent(doc.lights[lightIndex]);
    if (component != null) {
      engineNode.addComponent(component);
    }
  }

  for (final childIndex in gltfNode.children) {
    if (childIndex < 0 || childIndex >= engineNodes.length) {
      throw Exception('glTF node child index $childIndex out of range');
    }
    engineNode.add(engineNodes[childIndex]);
  }
}

// Surfaces the default scene's EXT_lights_image_based light, resolving each
// specular face image's bytes so the caller can build an environment from
// them. Returns null when the document declares none.
Future<ImageBasedLightComponent?> _buildImageBasedLight(
  GltfDocument doc,
  Uint8List bufferData,
  int? sceneIndex,
  GltfResourceResolver? resolveUri,
) async {
  if (sceneIndex == null || sceneIndex >= doc.scenes.length) return null;
  final lightIndex = doc.scenes[sceneIndex].imageBasedLight;
  if (lightIndex == null ||
      lightIndex < 0 ||
      lightIndex >= doc.imageBasedLights.length) {
    return null;
  }
  final light = doc.imageBasedLights[lightIndex];
  final specular = <List<Uint8List>>[];
  for (final level in light.specularImages) {
    final faces = <Uint8List>[];
    for (final imageIndex in level) {
      final bytes = await resolveGltfImageBytes(
        doc,
        bufferData,
        imageIndex,
        resolveUri: resolveUri,
      );
      if (bytes == null) {
        debugPrint(
          'Skipping EXT_lights_image_based specular image $imageIndex, its '
          'bytes could not be sourced.',
        );
        continue;
      }
      faces.add(bytes);
    }
    if (faces.length == level.length) specular.add(faces);
  }
  return ImageBasedLightComponent.internal(
    name: light.name,
    rotation: light.rotation,
    intensity: light.intensity,
    irradianceCoefficients: light.irradianceCoefficients,
    specularImageSize: light.specularImageSize,
    specularImages: specular,
  );
}

// Builds the engine light component for a KHR_lights_punctual light, or null
// for an unsupported type. glTF lights emit along the node's local -Z axis, so
// directional and spot lights take that as their local direction. The node
// transform and imported boundary then aim them in native world space.
Component? _buildLightComponent(GltfPunctualLight light) {
  // The extension carries no shadow metadata, so imported lights do not add
  // shadow passes implicitly.
  final intensity = gltfLightIntensity(light);
  switch (light.type) {
    case 'directional':
      return DirectionalLightComponent.aimed(
        DirectionalLight(
          color: light.color.clone(),
          intensity: intensity,
          castsShadow: false,
        ),
        Vector3(0.0, 0.0, -1.0),
      );
    case 'point':
      return PointLightComponent(
        PointLight(
          color: light.color.clone(),
          intensity: intensity,
          range: light.range ?? 0.0,
        ),
      );
    case 'spot':
      return SpotLightComponent(
        SpotLight(
          direction: Vector3(0.0, 0.0, -1.0),
          color: light.color.clone(),
          intensity: intensity,
          range: light.range ?? 0.0,
          innerConeAngle: light.innerConeAngle,
          outerConeAngle: light.outerConeAngle,
          castsShadow: false,
        ),
      );
    default:
      debugPrint('Skipping unsupported KHR_lights_punctual type ${light.type}');
      return null;
  }
}

/// Resolves every buffer the document references and concatenates them into
/// one blob with [GltfBufferView]s rebased to absolute offsets into it,
/// returning a document copy that carries the rebased views. Mirrors the
/// offline importer's multi-buffer normalization
/// (`in_memory_import.dart`'s `_normalizeGltf`) so the runtime path supports
/// the same multi-buffer `.gltf` documents.
///
/// For GLB the implicit buffer 0 (no uri) is the embedded BIN chunk. Every
/// other buffer is resolved from its URI: a `data:` URI decodes inline, an
/// external URI is percent-decoded and passed to [resolveUri].
Future<({GltfDocument doc, Uint8List bufferData})> _normalizeBuffers(
  GltfDocument doc, {
  required Uint8List glbBinaryChunk,
  required GltfResourceResolver? resolveUri,
}) async {
  if (doc.buffers.isEmpty) {
    return (doc: doc, bufferData: glbBinaryChunk);
  }

  final blob = BytesBuilder();
  void padTo4() {
    while (blob.length % 4 != 0) {
      blob.addByte(0);
    }
  }

  // EXT_meshopt_compression placeholder buffers hold no data the decode path
  // reads, so they contribute nothing to the blob and are never resolved.
  final placeholders = meshoptPlaceholderBuffers(doc);
  final bufferBase = <int>[];
  for (int i = 0; i < doc.buffers.length; i++) {
    padTo4();
    bufferBase.add(blob.length);
    if (placeholders.contains(i)) continue;
    blob.add(
      await _resolveBufferBytes(doc.buffers[i].uri, glbBinaryChunk, resolveUri),
    );
  }

  final bufferViews = [
    for (final v in doc.bufferViews)
      GltfBufferView(
        buffer: 0,
        byteLength: v.byteLength,
        byteOffset: v.byteOffset + bufferBase[v.buffer],
        byteStride: v.byteStride,
        meshopt: v.meshopt?.rebased(
          buffer: 0,
          byteOffset: v.meshopt!.byteOffset + bufferBase[v.meshopt!.buffer],
        ),
      ),
  ];

  final normalized = GltfDocument(
    scene: doc.scene,
    scenes: doc.scenes,
    nodes: doc.nodes,
    meshes: doc.meshes,
    accessors: doc.accessors,
    bufferViews: bufferViews,
    buffers: doc.buffers,
    materials: doc.materials,
    textures: doc.textures,
    images: doc.images,
    samplers: doc.samplers,
    skins: doc.skins,
    animations: doc.animations,
    lights: doc.lights,
    materialsVariants: doc.materialsVariants,
    warnings: doc.warnings,
  );
  return (doc: normalized, bufferData: blob.toBytes());
}

Future<Uint8List> _resolveBufferBytes(
  String? uri,
  Uint8List glbBinaryChunk,
  GltfResourceResolver? resolveUri,
) async {
  if (uri == null) return glbBinaryChunk; // GLB embedded buffer.
  if (uri.startsWith('data:')) return decodeGltfDataUri(uri);
  if (resolveUri == null) {
    throw FormatException(
      'glTF references external buffer "$uri" but no resource resolver was '
      'provided. Use importGltf / Node.fromGltfBytes for multi-file glTF.',
    );
  }
  return resolveUri(Uri.decodeComponent(uri));
}
