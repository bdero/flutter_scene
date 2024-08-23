import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:flutter_scene/geometry/geometry.dart';
import 'package:flutter_scene/material/material.dart';
import 'package:flutter_scene/scene_encoder.dart';
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

  final Geometry geometry;
  final Material material;
}

base class Mesh {
  Mesh(Geometry geometry, Material material)
      : primitives = [MeshPrimitive(geometry, material)];

  Mesh.primitives({required this.primitives});

  final List<MeshPrimitive> primitives;

  void render(SceneEncoder encoder, Matrix4 worldTransform,
      gpu.Texture? jointsTexture, int jointTextureWidth) {
    for (var primitive in primitives) {
      primitive.geometry.setJointsTexture(jointsTexture, jointTextureWidth);
      encoder.encode(worldTransform, primitive.geometry, primitive.material);
    }
  }
}
