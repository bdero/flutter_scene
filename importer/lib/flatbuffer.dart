library importer;

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
      m0, m4, m8, m12, //
      m1, m5, m9, m13, //
      m2, m6, m10, m14, //
      m3, m7, m11, m15, //
    ]);
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
    return nodes?[childIndex];
  }
}

extension NodeHelpers on fb.Node {
  fb.Node? getChild(fb.Scene scene, int index) {
    int? childIndex = children?[index];
    return scene.nodes?[childIndex];
  }
}

extension TextureHelpers on fb.Texture {
  gpu.Texture toTexture() {
    if (embeddedImage == null || embeddedImage!.bytes == null) {
      throw Exception('Texture has no embedded image');
    }
    gpu.Texture? texture = gpu.gpuContext.createTexture(
        gpu.StorageMode.hostVisible,
        embeddedImage!.width,
        embeddedImage!.height);
    if (texture == null) {
      throw Exception('Failed to allocate texture');
    }
    Uint8List textureData = embeddedImage!.bytes! as Uint8List;
    if (!texture.overwrite(ByteData.sublistView(textureData))) {
      throw Exception('Failed to overwrite texture data');
    }

    return texture;
  }
}
