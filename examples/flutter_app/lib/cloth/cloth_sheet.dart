// Binds a simulated sheet to the mesh that draws it.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../example_settings.dart';
import 'cloth_solver.dart';

/// A [ClothSolver] and the updatable geometry it drives.
///
/// The solver writes structure-of-arrays positions and normals in exactly the
/// layout `MeshGeometry` wants, so [sync] is two buffer uploads with no
/// repacking in between.
class ClothSheet {
  ClothSheet({
    required this.solver,
    required Material material,
    Float32List? colors,
  }) {
    geometry = MeshGeometry.fromArrays(
      positions: solver.positions,
      normals: solver.normals,
      texCoords: solver.texCoords,
      colors: colors,
      indices: solver.triangles,
      storage: GeometryStorage.updatable,
    );
    node = Node(mesh: Mesh(geometry, material));
  }

  final ClothSolver solver;
  late final MeshGeometry geometry;
  late final Node node;

  /// Uploads the solver's current state to the GPU.
  void sync() {
    geometry.updatePositions(solver.positions);
    geometry.updateNormals(solver.normals);
  }
}

/// Per-vertex colors for a sheet, from a `(column, row)` to color function.
///
/// The fabric material multiplies its base color by the vertex color, so the
/// pattern lives in the mesh and one material dresses every sheet.
Float32List clothColors(
  ClothSolver solver,
  vm.Vector3 Function(int column, int row) pattern,
) {
  final colors = Float32List(solver.particleCount * 4);
  for (var r = 0; r < solver.rows; r++) {
    for (var c = 0; c < solver.columns; c++) {
      final i = r * solver.columns + c;
      final rgb = pattern(c, r);
      colors[i * 4] = rgb.x;
      colors[i * 4 + 1] = rgb.y;
      colors[i * 4 + 2] = rgb.z;
      colors[i * 4 + 3] = 1.0;
    }
  }
  return colors;
}

/// Feeds the scene's key light to the fabric material, whose sheen and
/// transmission are direct-light terms the engine BRDF has no hook for.
void applyFabricLight(PreprocessedMaterial fabric) {
  final azimuth = exampleSettings.lightAzimuthDegrees * math.pi / 180.0;
  final elevation = exampleSettings.lightElevationDegrees * math.pi / 180.0;
  final horizontal = math.cos(elevation);
  fabric.parameters
    ..setVec3(
      'light_direction',
      vm.Vector3(
        -horizontal * math.cos(azimuth),
        math.sin(elevation),
        -horizontal * math.sin(azimuth),
      ),
    )
    ..setVec3(
      'light_color',
      exampleSettings.directionalLightEnabled
          ? exampleSettings.lightColor * exampleSettings.lightIntensity
          : vm.Vector3.zero(),
    );
}
