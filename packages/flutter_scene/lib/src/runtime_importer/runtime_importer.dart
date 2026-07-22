import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:vector_math/vector_math.dart';
import 'package:flutter_scene/src/importer/gltf.dart';

import '../animation.dart';
import '../components/component.dart';
import '../components/directional_light_component.dart';
import '../components/materials_variants_component.dart';
import '../components/point_light_component.dart';
import '../components/spot_light_component.dart';
import '../light.dart';
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

export 'gltf_resources.dart' show GltfResourceResolver;

/// Parse a GLB byte stream into a [Node] tree.
///
/// Returns a synthesized root node whose children are the root nodes of the
/// GLB's default scene. Each scene node is created and wired up to match the
/// glTF node hierarchy.
Future<Node> importGlb(Uint8List bytes) async {
  final container = parseGlb(bytes);
  final doc = parseGltfJson(container.json);
  final bufferData = await _resolveBufferData(
    doc,
    glbBinaryChunk: container.binaryChunk,
    resolveUri: null,
  );
  final packed = await _packPrimitives(doc, bufferData);
  return _buildScene(doc, bufferData, packed, null);
}

/// Parse a multi-file glTF document into a [Node] tree.
///
/// [gltfJson] is the raw bytes of the `.gltf` file. [resolveUri] fetches
/// each external resource (the `.bin` buffer and image files) the
/// document references by relative URI; `data:` URIs are decoded
/// internally and never reach the resolver.
Future<Node> importGltf(
  Uint8List gltfJson, {
  required GltfResourceResolver resolveUri,
}) async {
  final json = jsonDecode(utf8.decode(gltfJson)) as Map<String, Object?>;
  final doc = parseGltfJson(json);
  final bufferData = await _resolveBufferData(
    doc,
    glbBinaryChunk: Uint8List(0),
    resolveUri: resolveUri,
  );
  final packed = await _packPrimitives(doc, bufferData);
  return _buildScene(doc, bufferData, packed, resolveUri);
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
Future<List<List<PackedPrimitive?>>> _packPrimitives(
  GltfDocument doc,
  Uint8List bufferData,
) => compute(_packPrimitivesIsolate, (doc: doc, bufferData: bufferData));

// Top-level so it can run on a background isolate. Packs each primitive with
// the shared [packGltfPrimitive]; non-triangle topologies pack to null.
List<List<PackedPrimitive?>> _packPrimitivesIsolate(
  ({GltfDocument doc, Uint8List bufferData}) input,
) {
  final doc = input.doc;
  return [
    for (final mesh in doc.meshes)
      [
        for (final p in mesh.primitives)
          if (p.mode != 4)
            null
          else
            packGltfPrimitive(
              primitive: p,
              accessors: doc.accessors,
              bufferViews: doc.bufferViews,
              bufferData: input.bufferData,
            ),
      ],
  ];
}

/// Builds the [Node] tree from a parsed document, its resolved buffer, and its
/// pre-packed primitives. Shared by the GLB and multi-file glTF entry points.
Future<Node> _buildScene(
  GltfDocument doc,
  Uint8List bufferData,
  List<List<PackedPrimitive?>> packed,
  GltfResourceResolver? resolveUri,
) async {
  // Decode all textures up front so material construction can reference
  // them by index without per-material async work.
  final List<Texture2D> textures = await buildTextures(
    doc,
    bufferData,
    resolveUri: resolveUri,
  );

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
      textures: textures,
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
  // Apply a Z-axis flip on the scene root to convert from glTF's right-handed
  // coordinate system to flutter_scene's expected convention, matching the
  // handedness mirror the scene realizer applies for right-handed documents.
  final root = Node(
    name: 'root',
    localTransform: Matrix4.identity()..setEntry(2, 2, -1.0),
  )..excludeFromWindingParity = true;
  if (doc.materialsVariants.isNotEmpty) {
    root.addComponent(
      MaterialsVariantsComponent.internal(
        doc.materialsVariants,
        variantBindings,
      ),
    );
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
  required List<List<PackedPrimitive?>> packed,
  required List<Node> engineNodes,
  required List<Texture2D> textures,
  required List<MaterialsVariantBinding> variantBindings,
}) {
  engineNode.name = resolveGltfNodeName(gltfNode.name, index);
  final matrix = gltfNode.matrix;
  if (matrix != null) {
    engineNode.localTransform = matrix.clone();
  } else {
    // Keep the authored TRS. Recovering it from the composed matrix puts
    // a mirrored bone's negative scale on the wrong axis, which breaks
    // animation blending.
    engineNode.setLocalTransformTrs(
      DecomposedTransform(
        translation: gltfNode.translation?.clone() ?? Vector3.zero(),
        rotation: gltfNode.rotation?.clone() ?? Quaternion.identity(),
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
      final packedPrimitive = packedMesh[pi];
      // A null entry is a non-triangle topology skipped during packing; they
      // need shader/render-state support that flutter_scene's pipeline doesn't
      // currently expose.
      if (packedPrimitive == null) {
        debugPrint(
          'Skipping mesh primitive with unsupported topology mode ${p.mode}',
        );
        continue;
      }
      final geometry = geometryFromPacked(packedPrimitive);
      final material = p.material != null
          ? buildMaterial(doc.materials[p.material!], textures)
          : UnlitMaterial();
      final primitive = MeshPrimitive(geometry, material);
      if (p.variantMappings.isNotEmpty) {
        // Build each variant's material now (textures are already decoded)
        // so selection is a plain reassignment. A mapping that names the
        // default material index reuses the default instance.
        variantBindings.add(
          MaterialsVariantBinding(
            node: engineNode,
            primitive: primitive,
            defaultMaterial: material,
            materialsByVariant: {
              for (final entry in p.variantMappings.entries)
                if (entry.value >= 0 && entry.value < doc.materials.length)
                  entry.key: entry.value == p.material
                      ? material
                      : buildMaterial(doc.materials[entry.value], textures),
            },
          ),
        );
      }
      primitives.add(primitive);
    }
    if (primitives.isNotEmpty) {
      engineNode.mesh = Mesh.primitives(primitives: primitives);
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

// Builds the engine light component for a KHR_lights_punctual light, or null
// for an unsupported type. glTF lights emit along the node's local -Z axis, so
// directional and spot lights take that as their local direction (the node
// transform, and the scene-root handedness flip, then aim them in world space).
//
// TODO(lighting): glTF point/spot intensity is candela and directional is lux;
// flutter_scene uses an artistic multiplier, so the value is carried through
// unconverted. Map photometric units to the engine's exposure if physical
// intensities are needed.
Component? _buildLightComponent(GltfPunctualLight light) {
  switch (light.type) {
    case 'directional':
      return DirectionalLightComponent(
        DirectionalLight(
          direction: Vector3(0.0, 0.0, -1.0),
          color: light.color.clone(),
          intensity: light.intensity,
        ),
      );
    case 'point':
      return PointLightComponent(
        PointLight(
          color: light.color.clone(),
          intensity: light.intensity,
          range: light.range ?? 0.0,
        ),
      );
    case 'spot':
      return SpotLightComponent(
        SpotLight(
          direction: Vector3(0.0, 0.0, -1.0),
          color: light.color.clone(),
          intensity: light.intensity,
          range: light.range ?? 0.0,
          innerConeAngle: light.innerConeAngle,
          outerConeAngle: light.outerConeAngle,
        ),
      );
    default:
      debugPrint('Skipping unsupported KHR_lights_punctual type ${light.type}');
      return null;
  }
}

/// Returns the binary buffer that backs the document's bufferViews.
///
/// For GLB the implicit "buffer 0" is the embedded BIN chunk. For
/// multi-file glTF the single buffer is resolved from its URI: a
/// `data:` URI is decoded inline, an external URI goes through
/// [resolveUri]. glTF documents with more than one buffer are not yet
/// supported (none of the engine's target assets need it).
Future<Uint8List> _resolveBufferData(
  GltfDocument doc, {
  required Uint8List glbBinaryChunk,
  required GltfResourceResolver? resolveUri,
}) async {
  if (doc.buffers.isEmpty) {
    return glbBinaryChunk;
  }
  if (doc.buffers.length > 1) {
    throw const FormatException(
      'glTF with multiple buffers is not yet supported by the runtime '
      'importer',
    );
  }
  final uri = doc.buffers.first.uri;
  if (uri == null) return glbBinaryChunk; // GLB embedded buffer.
  if (uri.startsWith('data:')) return decodeGltfDataUri(uri);
  if (resolveUri == null) {
    throw FormatException(
      'glTF references external buffer "$uri" but no resource resolver was '
      'provided. Use importGltf / Node.fromGltfBytes for multi-file glTF.',
    );
  }
  return resolveUri(uri);
}
