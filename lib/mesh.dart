import 'package:flutter_scene/flutter_scene.dart';

import 'package:flutter_scene/geometry/geometry.dart';
import 'package:flutter_scene/material/material.dart';
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

  void render(SceneEncoder encoder, Matrix4 worldTransform) {
    for (var primitive in primitives) {
      encoder.encode(worldTransform, primitive.geometry, primitive.material);
    }
  }
}
