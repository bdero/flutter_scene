import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';
import 'package:flutter_scene_importer/gltf.dart';

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
    final view = bufferViews[accessor.bufferView!];
    final floats = readAccessorAsFloat32(accessor, view, bufferData);
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
