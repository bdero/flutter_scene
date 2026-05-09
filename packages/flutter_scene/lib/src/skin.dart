import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_scene/src/node.dart';
import 'package:vector_math/vector_math.dart';
import 'package:flutter_scene_importer/flatbuffer.dart' as fb;
import 'package:flutter_gpu/gpu.dart' as gpu;

int _getNextPowerOfTwoSize(int x) {
  if (x == 0) {
    return 1;
  }

  --x;

  x |= x >> 1;
  x |= x >> 2;
  x |= x >> 4;
  x |= x >> 8;
  x |= x >> 16;

  return x + 1;
}

/// A skeletal binding used by skinned meshes for animation.
///
/// A `Skin` pairs an ordered list of [joints] (scene-graph [Node]s acting as
/// bones) with the [inverseBindMatrices] that transform a mesh from model
/// space into each joint's rest-pose local space. The vertex shader
/// combines these with the joints' current transforms to deform the mesh.
///
/// `Skin` instances are usually populated by an importer rather than
/// constructed directly. They are attached to the mesh-bearing [Node] via
/// [Node.skin].
base class Skin {
  /// The bone nodes referenced by this skin, in shader-binding order.
  ///
  /// Entries may be `null` when [Node.clone] is unable to relocate a joint
  /// in the cloned subtree; the renderer treats null joints as identity
  /// transforms.
  final List<Node?> joints = [];

  /// The inverse bind matrix for each joint, transforming a vertex from
  /// model space into the joint's rest-pose local space.
  ///
  /// Parallel to [joints]: `inverseBindMatrices[i]` corresponds to
  /// `joints[i]`.
  final List<Matrix4> inverseBindMatrices = [];

  /// Creates a [Skin] from a deserialized flatbuffer skin description,
  /// resolving each joint reference against the supplied [sceneNodes].
  ///
  /// Throws if joints and inverse bind matrices are absent or have mismatched
  /// lengths, or if a joint index falls outside [sceneNodes].
  static Skin fromFlatbuffer(fb.Skin skin, List<Node> sceneNodes) {
    if (skin.joints == null ||
        skin.inverseBindMatrices == null ||
        skin.joints!.length != skin.inverseBindMatrices!.length) {
      throw Exception('Skin data is missing joints or bind matrices.');
    }

    Skin result = Skin();
    for (int jointIndex in skin.joints!) {
      if (jointIndex < 0 || jointIndex > sceneNodes.length) {
        throw Exception('Skin join index out of range');
      }
      sceneNodes[jointIndex].isJoint = true;
      result.joints.add(sceneNodes[jointIndex]);
    }

    for (
      int matrixIndex = 0;
      matrixIndex < skin.inverseBindMatrices!.length;
      matrixIndex++
    ) {
      final matrix = skin.inverseBindMatrices![matrixIndex].toMatrix4();

      result.inverseBindMatrices.add(matrix);
    }

    return result;
  }

  /// Computes the joint matrices for the current frame and uploads them as
  /// a square `RGBA32F` GPU texture.
  ///
  /// Each joint occupies four texels (one matrix). The texture's edge
  /// length is rounded up to the next power of two to satisfy GPU sampling
  /// requirements; unused slots are initialized to identity.
  ///
  /// The companion [getTextureWidth] returns the same edge length so the
  /// vertex shader can index into the texture.
  gpu.Texture getJointsTexture() {
    // Each joint has a matrix. 1 matrix = 16 floats. 1 pixel = 4 floats.
    // Therefore, each joint needs 4 pixels.
    int requiredPixels = joints.length * 4;
    int dimensionSize = max(
      2,
      _getNextPowerOfTwoSize(sqrt(requiredPixels).ceil()),
    );

    gpu.Texture texture = gpu.gpuContext.createTexture(
      gpu.StorageMode.hostVisible,
      dimensionSize,
      dimensionSize,
      format: gpu.PixelFormat.r32g32b32a32Float,
    );
    // 64 bytes per matrix. 4 bytes per pixel.
    Float32List jointMatrixFloats = Float32List(
      dimensionSize * dimensionSize * 4,
    );
    // Initialize with identity matrices.
    for (int i = 0; i < jointMatrixFloats.length; i += 16) {
      jointMatrixFloats[i] = 1.0;
      jointMatrixFloats[i + 5] = 1.0;
      jointMatrixFloats[i + 10] = 1.0;
      jointMatrixFloats[i + 15] = 1.0;
    }

    for (int jointIndex = 0; jointIndex < joints.length; jointIndex++) {
      Node? joint = joints[jointIndex];

      // Compute a model space matrix for the joint by walking up the bones to the
      // skeleton root.
      final floatOffset = jointIndex * 16;
      while (joint != null && joint.isJoint) {
        final Matrix4 matrix =
            joint.localTransform *
            Matrix4.fromFloat32List(
              jointMatrixFloats.sublist(floatOffset, floatOffset + 16),
            );

        jointMatrixFloats.setRange(
          floatOffset,
          floatOffset + 16,
          matrix.storage,
        );

        joint = joint.parent;
      }

      // Get the joint transform relative to the default pose of the bone by
      // incorporating the joint's inverse bind matrix. The inverse bind matrix
      // transforms from model space to the default pose space of the joint. The
      // result is a model space matrix that only captures the difference between
      // the joint's default pose and the joint's current pose in the scene. This
      // is necessary because the skinned model's vertex positions (which _define_
      // the default pose) are all in model space.
      final Matrix4 matrix =
          Matrix4.fromFloat32List(
            jointMatrixFloats.sublist(floatOffset, floatOffset + 16),
          ) *
          inverseBindMatrices[jointIndex];

      jointMatrixFloats.setRange(floatOffset, floatOffset + 16, matrix.storage);
    }

    texture.overwrite(jointMatrixFloats.buffer.asByteData());
    return texture;
  }

  /// The edge length, in texels, of the joints texture produced by
  /// [getJointsTexture].
  int getTextureWidth() {
    return _getNextPowerOfTwoSize(sqrt(joints.length * 4).ceil());
  }
}
