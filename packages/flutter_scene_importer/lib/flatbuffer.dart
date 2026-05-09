// ignore: depend_on_referenced_packages
import 'dart:typed_data';

import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene_importer/generated/scene_impeller.fb_flatbuffers.dart'
    as fb;
export 'package:flutter_scene_importer/generated/scene_impeller.fb_flatbuffers.dart';

/// Conversion helpers from the flatbuffer 4×4 matrix type.
extension MatrixHelpers on fb.Matrix {
  /// Returns this flatbuffer matrix as a `vector_math` [Matrix4].
  Matrix4 toMatrix4() {
    return Matrix4.fromList(<double>[
      m0, m1, m2, m3, //
      m4, m5, m6, m7, //
      m8, m9, m10, m11, //
      m12, m13, m14, m15, //
    ]);
  }
}

/// Conversion helpers from the flatbuffer 3-vector type.
extension Vector3Helpers on fb.Vec3 {
  /// Returns this flatbuffer vec3 as a `vector_math` [Vector3].
  Vector3 toVector3() {
    return Vector3(x, y, z);
  }
}

/// Conversion helpers from the flatbuffer 4-vector type, interpreted as
/// a quaternion (`(x, y, z, w)`).
extension QuaternionHelpers on fb.Vec4 {
  /// Returns this flatbuffer vec4 as a `vector_math` [Quaternion].
  Quaternion toQuaternion() {
    return Quaternion(x, y, z, w);
  }
}

/// Conversion helpers from the flatbuffer index-type enum.
extension IndexTypeHelpers on fb.IndexType {
  /// Maps the flatbuffer index type to the matching Flutter GPU
  /// [gpu.IndexType].
  gpu.IndexType toIndexType() {
    switch (this) {
      case fb.IndexType.k16Bit:
        return gpu.IndexType.int16;
      case fb.IndexType.k32Bit:
        return gpu.IndexType.int32;
    }
    throw Exception('Unknown index type');
  }
}

/// Convenience helpers on the flatbuffer scene root.
extension SceneHelpers on fb.Scene {
  /// Returns the scene's root transform as a [Matrix4], or the identity
  /// matrix when the scene has no transform set.
  Matrix4 transformAsMatrix4() {
    return transform?.toMatrix4() ?? Matrix4.identity();
  }

  /// Returns the [index]-th direct child of the scene root, or `null`
  /// if the index is out of range or the scene has no children.
  fb.Node? getChild(int index) {
    int? childIndex = children?[index];
    if (childIndex == null) {
      return null;
    }
    return nodes?[childIndex];
  }
}

/// Convenience helpers on flatbuffer node references.
extension NodeHelpers on fb.Node {
  /// Returns the [index]-th direct child of this node, resolved against
  /// [scene]'s shared node table, or `null` if the index is out of
  /// range.
  fb.Node? getChild(fb.Scene scene, int index) {
    int? childIndex = children?[index];
    if (childIndex == null) {
      return null;
    }
    return scene.nodes?[childIndex];
  }
}

/// Conversion helper for embedded textures in a `.model` payload.
extension TextureHelpers on fb.Texture {
  /// Uploads this texture's embedded image data to a Flutter GPU
  /// texture.
  ///
  /// Throws if the texture has no embedded image (for example, a URI-only
  /// texture reference). Callers needing URI fallback should sample the
  /// asset bundle themselves before calling.
  gpu.Texture toTexture() {
    if (embeddedImage == null || embeddedImage!.bytes == null) {
      throw Exception('Texture has no embedded image');
    }
    gpu.Texture texture = gpu.gpuContext.createTexture(
      gpu.StorageMode.hostVisible,
      embeddedImage!.width,
      embeddedImage!.height,
    );
    Uint8List textureData = embeddedImage!.bytes! as Uint8List;
    texture.overwrite(ByteData.sublistView(textureData));

    return texture;
  }
}
