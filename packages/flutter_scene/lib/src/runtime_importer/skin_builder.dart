import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';
import 'package:flutter_scene/src/importer/gltf.dart';
import 'package:flutter_scene/src/importer/src/gltf/bounds_baker.dart';

import '../node.dart';
import '../skin.dart';

/// Builds an engine [Skin] from a glTF skin definition. Joints are resolved
/// against the engine's full node list, and inverse-bind matrices are read
/// from the referenced accessor.
Skin buildSkin({
  required GltfSkin gltfSkin,
  required List<GltfAccessor> accessors,
  required List<GltfBufferView> bufferViews,
  required Uint8List bufferData,
  required List<Node> engineNodes,
  required GltfCoordinatePolicy coordinatePolicy,
}) {
  final skin = Skin();

  for (final jointIndex in gltfSkin.joints) {
    if (jointIndex < 0 || jointIndex >= engineNodes.length) {
      throw FormatException('glTF skin joint index $jointIndex out of range');
    }
    final node = engineNodes[jointIndex];
    node.isJoint = true;
    skin.joints.add(node);
  }

  if (gltfSkin.inverseBindMatrices != null) {
    final accessor = accessors[gltfSkin.inverseBindMatrices!];
    if (accessor.type != GltfAccessorType.mat4) {
      throw FormatException(
        'glTF skin inverseBindMatrices accessor must be MAT4, '
        'got ${accessor.type}',
      );
    }
    final floats = coordinatePolicy.convertMatrices(
      readAccessorAsFloat32(accessor, bufferViews, bufferData),
    );
    if (floats.length != gltfSkin.joints.length * 16) {
      throw FormatException(
        'glTF skin has ${gltfSkin.joints.length} joints but the inverse-bind '
        'matrices accessor only provides ${floats.length ~/ 16}',
      );
    }
    for (int i = 0; i < gltfSkin.joints.length; i++) {
      // Matrix4.fromFloat32List expects a 16-float column-major buffer; glTF
      // stores matrices in column-major order, so this is a direct copy.
      skin.inverseBindMatrices.add(
        Matrix4.fromFloat32List(
          Float32List.fromList(floats.sublist(i * 16, i * 16 + 16)),
        ),
      );
    }
  } else {
    // Spec default: identity matrices.
    for (int i = 0; i < gltfSkin.joints.length; i++) {
      skin.inverseBindMatrices.add(Matrix4.identity());
    }
  }

  return skin;
}

/// The pose bounds of each skinned node's triangle primitives, keyed by glTF
/// node index, with one entry per primitive in source order.
///
/// The baked poses place the vertices in the space of the skeleton's parent,
/// the first ancestor of its joints that is not a joint, while culling places the
/// bounds through the skinned node. So each box moves by the skeleton parent's
/// rest transform and then by the inverse of the node's. A node whose rest
/// transform does not invert, or whose joints hang under different parents,
/// gets null entries and is never culled.
Map<int, List<Aabb3?>> skinnedPoseBounds(
  GltfDocument doc,
  Uint8List bufferData,
) {
  final parents = List<int>.filled(doc.nodes.length, -1);
  for (var parent = 0; parent < doc.nodes.length; parent++) {
    for (final child in doc.nodes[parent].children) {
      if (child >= 0 && child < parents.length) parents[child] = parent;
    }
  }

  // Walks at most one step per node, so a malformed parent cycle ends.
  Matrix4 restOf(int node) {
    final rest = Matrix4.identity();
    var steps = 0;
    for (var at = node; at >= 0 && steps++ < parents.length; at = parents[at]) {
      final gltf = doc.nodes[at];
      final local =
          gltf.matrix?.clone() ??
          Matrix4.compose(
            gltf.translation ?? Vector3.zero(),
            gltf.rotation ?? Quaternion.identity(),
            gltf.scale ?? Vector3.all(1),
          );
      rest.setFrom(local..multiply(rest));
    }
    return rest;
  }

  // The first ancestor of the skin's joints that is not a joint, -1 for the
  // scene root, or null when the joints hang under different ones.
  int? skeletonParentOf(int skin) {
    final joints = doc.skins[skin].joints.toSet();
    int? shared;
    for (final joint in joints) {
      var at = joint;
      var steps = 0;
      while (at >= 0 && joints.contains(at) && steps++ < parents.length) {
        at = parents[at];
      }
      if (shared != null && shared != at) return null;
      shared = at;
    }
    return shared;
  }

  List<Aabb3?> boundsOf(int node, List<AabbBounds?> boxes) {
    final skeleton = skeletonParentOf(doc.nodes[node].skin!);
    final toNode = restOf(node);
    if (skeleton == null || toNode.invert() == 0) {
      return List.filled(boxes.length, null);
    }
    if (skeleton >= 0) toNode.multiply(restOf(skeleton));
    return [
      for (final box in boxes)
        if (box == null || box.isEmpty)
          null
        else
          Aabb3.minMax(
            Vector3(box.minX, box.minY, box.minZ),
            Vector3(box.maxX, box.maxY, box.maxZ),
          )..transform(toNode),
    ];
  }

  final unions = bakeSkinnedPoseUnionAabbs(doc, bufferData);
  return {
    for (final MapEntry(key: node, value: boxes) in unions.entries)
      node: boundsOf(node, boxes),
  };
}
