// ignore: depend_on_referenced_packages
import 'dart:typed_data';

import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene_importer/generated/scene_impeller.fb_flatbuffers.dart'
    as fb;
export 'package:flutter_scene_importer/generated/scene_impeller.fb_flatbuffers.dart';

extension MatrixHelpers on fb.Matrix {
  Matrix4 toMatrix4() {
    return Matrix4.fromList(<double>[
      m0, m1, m2, m3, //
      m4, m5, m6, m7, //
      m8, m9, m10, m11, //
      m12, m13, m14, m15 //
    ]);
  }
}

extension Vector3Helpers on fb.Vec3 {
  Vector3 toVector3() {
    return Vector3(x, y, z);
  }
}

extension QuaternionHelpers on fb.Vec4 {
  Quaternion toQuaternion() {
    return Quaternion(x, y, z, w);
  }
}

extension IndexTypeHelpers on fb.IndexType {
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

extension SceneHelpers on fb.Scene {
  Matrix4 transformAsMatrix4() {
    return transform?.toMatrix4() ?? Matrix4.identity();
  }

  /// Find a root child node in the scene.
  fb.Node? getChild(int index) {
    int? childIndex = children?[index];
    if (childIndex == null) {
      return null;
    }
    return nodes?[childIndex];
  }
}

extension NodeHelpers on fb.Node {
  fb.Node? getChild(fb.Scene scene, int index) {
    int? childIndex = children?[index];
    if (childIndex == null) {
      return null;
    }
    return scene.nodes?[childIndex];
  }
}

extension TextureHelpers on fb.Texture {
  gpu.Texture toTexture() {
    if (embeddedImage == null || embeddedImage!.bytes == null) {
      throw Exception('Texture has no embedded image');
    }
    gpu.Texture texture = gpu.gpuContext.createTexture(
        gpu.StorageMode.hostVisible,
        embeddedImage!.width,
        embeddedImage!.height);
    Uint8List textureData = embeddedImage!.bytes! as Uint8List;
    texture.overwrite(ByteData.sublistView(textureData));

    return texture;
  }
}
