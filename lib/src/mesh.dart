import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/geometry/geometry.dart';
import 'package:flutter_scene/src/material/material.dart';
import 'package:flutter_scene/src/scene_encoder.dart';
import 'package:vector_math/vector_math.dart';

/// Represents a single part of a [Mesh], containing both [Geometry] and [Material] properties.
///
/// A `MeshPrimitive` defines the [Geometry] and [Material] of one specific part of the model.
/// By combining multiple `MeshPrimitive` objects, a full 3D model can be created, with different
/// parts of the model having different [Geometry] and [Material].
///
/// For example, imagine a 3D model of a car. The body of the car, the windows, and the wheels
/// could each be represented by different `MeshPrimitive` objects. The body might have a red
/// paint [Material], the windows a transparent glass [Material], and the wheels a black rubber [Material].
/// Each of these parts of the car has its own [Geometry] and [Material], and together
/// they form the complete model.
base class MeshPrimitive {
  MeshPrimitive(this.geometry, this.material);

  Geometry geometry;
  Material material;
}

/// Defines the shape and appearance of a 3D model in the scene.
///
/// It consists of a list of [MeshPrimitive] instances, where each primitive
/// contains the [Geometry] and the [Material] to render a specific part of
/// the 3d model.
base class Mesh {
  /// Creates a `Mesh` consisting of a single [MeshPrimitive] with the given [Geometry] and [Material].
  Mesh(Geometry geometry, Material material)
    : primitives = [MeshPrimitive(geometry, material)];

  Mesh.primitives({required this.primitives});

  /// The list of [MeshPrimitive] objects that make up the [Geometry] and [Material] of the 3D model.
  final List<MeshPrimitive> primitives;

  /// Draws the [Geometry] and [Material] data of each [MeshPrimitive] onto the screen.
  ///
  /// This method prepares the [Mesh] for rendering by passing its data to a [SceneEncoder].
  /// For skinned meshes, which are typically used in animations,
  /// the joint [gpu.Texture] data is also included to ensure proper rendering of animated features.
  void render(
    SceneEncoder encoder,
    Matrix4 worldTransform,
    gpu.Texture? jointsTexture,
    int jointTextureWidth,
  ) {
    for (var primitive in primitives) {
      primitive.geometry.setJointsTexture(jointsTexture, jointTextureWidth);
      encoder.encode(worldTransform, primitive.geometry, primitive.material);
    }
  }
}
