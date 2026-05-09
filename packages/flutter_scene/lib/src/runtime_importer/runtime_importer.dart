import 'package:flutter/foundation.dart';
import 'package:vector_math/vector_math.dart';

import '../material/unlit_material.dart';
import '../mesh.dart';
import '../node.dart';
import 'geometry_builder.dart';
import 'glb.dart';
import 'gltf_parser.dart';
import 'gltf_types.dart';
import 'material_builder.dart';

/// Parse a GLB byte stream into a [Node] tree.
///
/// Returns a synthesized root node whose children are the root nodes of the
/// GLB's default scene. Each scene node is created and wired up to match the
/// glTF node hierarchy.
Future<Node> importGlb(Uint8List bytes) async {
  final container = parseGlb(bytes);
  final doc = parseGltfJson(container.json);

  final bufferData = _resolveBufferData(doc, container.binaryChunk);

  // Pre-allocate engine Node placeholders 1:1 with glTF nodes so children
  // can refer to them by index regardless of the order we visit them in.
  final List<Node> engineNodes = List.generate(doc.nodes.length, (_) => Node());

  for (int i = 0; i < doc.nodes.length; i++) {
    _populateNode(
      engineNode: engineNodes[i],
      gltfNode: doc.nodes[i],
      doc: doc,
      bufferData: bufferData,
      engineNodes: engineNodes,
    );
  }

  // Pick the default scene (or the first one, or empty).
  final sceneIndex = doc.scene ?? (doc.scenes.isNotEmpty ? 0 : null);
  final root = Node(name: 'root');
  if (sceneIndex != null && sceneIndex < doc.scenes.length) {
    for (final rootNodeIdx in doc.scenes[sceneIndex].nodes) {
      if (rootNodeIdx >= 0 && rootNodeIdx < engineNodes.length) {
        root.add(engineNodes[rootNodeIdx]);
      }
    }
  }

  debugPrint(
    'Unpacking glTF (nodes: ${doc.nodes.length}, '
    'meshes: ${doc.meshes.length}, '
    'materials: ${doc.materials.length})',
  );

  return root;
}

void _populateNode({
  required Node engineNode,
  required GltfNode gltfNode,
  required GltfDocument doc,
  required Uint8List bufferData,
  required List<Node> engineNodes,
}) {
  engineNode.name = gltfNode.name ?? '';
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
      final material = p.material != null
          ? buildMaterial(doc.materials[p.material!])
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
/// For GLB, the implicit "buffer 0" is the embedded BIN chunk. External buffer
/// references (data URIs or relative URIs) are not yet supported — they're
/// part of the .gltf (text) loader path planned as a follow-up.
Uint8List _resolveBufferData(GltfDocument doc, Uint8List glbBinaryChunk) {
  if (doc.buffers.isEmpty) {
    return glbBinaryChunk;
  }
  if (doc.buffers.length > 1) {
    throw const FormatException(
      'GLB with multiple buffers is not yet supported by the runtime importer',
    );
  }
  final b = doc.buffers.first;
  if (b.uri == null) return glbBinaryChunk; // GLB embedded buffer
  throw FormatException(
    'GLB references external buffer URI "${b.uri}". External buffers are not '
    'yet supported by the runtime importer.',
  );
}

