import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart';
import 'package:flutter_scene_importer/gltf.dart';

import '../material/unlit_material.dart';
import '../mesh.dart';
import '../node.dart';
import '../skin.dart';
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
  return _buildScene(doc, bufferData, null);
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
  return _buildScene(doc, bufferData, resolveUri);
}

/// Builds the [Node] tree from a parsed document and its resolved
/// buffer. Shared by the GLB and multi-file glTF entry points.
Future<Node> _buildScene(
  GltfDocument doc,
  Uint8List bufferData,
  GltfResourceResolver? resolveUri,
) async {
  // Decode all textures up front so material construction can reference
  // them by index without per-material async work.
  final List<gpu.Texture> textures = await buildTextures(
    doc,
    bufferData,
    resolveUri: resolveUri,
  );

  // Pre-allocate engine Node placeholders 1:1 with glTF nodes so children
  // can refer to them by index regardless of the order we visit them in.
  final List<Node> engineNodes = List.generate(doc.nodes.length, (_) => Node());

  for (int i = 0; i < doc.nodes.length; i++) {
    _populateNode(
      index: i,
      engineNode: engineNodes[i],
      gltfNode: doc.nodes[i],
      doc: doc,
      bufferData: bufferData,
      engineNodes: engineNodes,
      textures: textures,
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
  // coordinate system to flutter_scene's expected convention. This matches
  // what the offline C++ importer writes as the .model's scene-level
  // transform (importer_gltf.cc: `MakeScale({1, 1, -1})`).
  final root = Node(
    name: 'root',
    localTransform: Matrix4.identity()..setEntry(2, 2, -1.0),
  );
  if (sceneIndex != null && sceneIndex < doc.scenes.length) {
    for (final rootNodeIdx in doc.scenes[sceneIndex].nodes) {
      if (rootNodeIdx >= 0 && rootNodeIdx < engineNodes.length) {
        root.add(engineNodes[rootNodeIdx]);
      }
    }
  }

  // Build animations and attach them to the synthesized root, mirroring how
  // the offline (.model) path attaches them in Node.fromFlatbuffer.
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
  required Uint8List bufferData,
  required List<Node> engineNodes,
  required List<gpu.Texture> textures,
}) {
  engineNode.name = resolveGltfNodeName(gltfNode.name, index);
  engineNode.localTransform = _localTransformFor(gltfNode);

  if (gltfNode.mesh != null) {
    final gltfMesh = doc.meshes[gltfNode.mesh!];
    final primitives = <MeshPrimitive>[];
    for (final p in gltfMesh.primitives) {
      // Skip non-triangle topologies for now; they need shader/render-state
      // support that flutter_scene's pipeline doesn't currently expose.
      if (p.mode != 4) {
        debugPrint(
          'Skipping mesh primitive with unsupported topology mode ${p.mode}',
        );
        continue;
      }
      final built = buildGeometry(
        primitive: p,
        accessors: doc.accessors,
        bufferViews: doc.bufferViews,
        bufferData: bufferData,
      );
      final material =
          p.material != null
              ? buildMaterial(doc.materials[p.material!], textures)
              : UnlitMaterial();
      primitives.add(MeshPrimitive(built.geometry, material));
    }
    if (primitives.isNotEmpty) {
      engineNode.mesh = Mesh.primitives(primitives: primitives);
    }
  }

  for (final childIndex in gltfNode.children) {
    if (childIndex < 0 || childIndex >= engineNodes.length) {
      throw Exception('glTF node child index $childIndex out of range');
    }
    engineNode.add(engineNodes[childIndex]);
  }
}

Matrix4 _localTransformFor(GltfNode n) {
  if (n.matrix != null) return n.matrix!.clone();
  final t = n.translation ?? Vector3.zero();
  final r = n.rotation ?? Quaternion.identity();
  final s = n.scale ?? Vector3(1.0, 1.0, 1.0);
  // T * R * S
  final m = Matrix4.compose(t, r, s);
  return m;
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
