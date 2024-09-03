import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:flutter_scene/geometry/geometry.dart';
import 'package:flutter_scene/material/material.dart';
import 'package:flutter_scene/scene_encoder.dart';
import 'package:vector_math/vector_math.dart';

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
