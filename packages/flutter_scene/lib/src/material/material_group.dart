import 'dart:ui' show Color;

import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/fmat/fmat_ast.dart' show FmatType;
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/material/material_parameters.dart';
import 'package:flutter_scene/src/material/preprocessed_material.dart';
import 'package:flutter_scene/src/node.dart';

/// A set of materials that one value is pushed to at once.
///
/// A member that does not declare the name, or declares it with a different
/// type, is skipped, so one group can span a heterogeneous set (every enemy,
/// prop, and tower in a blast radius) without a partial write, unlike
/// [MaterialParameters], which throws on an unknown name or a type mismatch.
/// {@category Materials}
class MaterialGroup {
  /// Groups [materials], or none, to be [add]ed later.
  MaterialGroup([Iterable<PreprocessedMaterial> materials = const []])
    : _materials = {...materials};

  /// Every [PreprocessedMaterial] reachable from [root]'s subtree.
  factory MaterialGroup.of(Node root) {
    final materials = <PreprocessedMaterial>{};
    for (final node in root.meshNodes) {
      final mesh = node.mesh;
      if (mesh == null) continue;
      for (final primitive in mesh.primitives) {
        final material = primitive.material;
        if (material is PreprocessedMaterial) materials.add(material);
      }
    }
    return MaterialGroup(materials);
  }

  final Set<PreprocessedMaterial> _materials;

  /// Adds [material] to the group.
  void add(PreprocessedMaterial material) => _materials.add(material);

  /// Removes [material] from the group. Returns whether it was present.
  bool remove(PreprocessedMaterial material) => _materials.remove(material);

  /// Removes every material from the group.
  void clear() => _materials.clear();

  /// The number of materials in the group.
  int get length => _materials.length;

  /// Sets a float parameter named [name] on every member that declares it.
  void setFloat(String name, double value) {
    for (final material in _materials) {
      if (material.parameters.hasParameterOfType(name, FmatType.float_)) {
        material.parameters.setFloat(name, value);
      }
    }
  }

  /// Sets an int parameter named [name] on every member that declares it.
  void setInt(String name, int value) {
    for (final material in _materials) {
      if (material.parameters.hasParameterOfType(name, FmatType.int_)) {
        material.parameters.setInt(name, value);
      }
    }
  }

  /// Sets a vec2 parameter named [name] on every member that declares it.
  void setVec2(String name, Vector2 value) {
    for (final material in _materials) {
      if (material.parameters.hasParameterOfType(name, FmatType.vec2)) {
        material.parameters.setVec2(name, value);
      }
    }
  }

  /// Sets a vec3 parameter named [name] on every member that declares it.
  void setVec3(String name, Vector3 value) {
    for (final material in _materials) {
      if (material.parameters.hasParameterOfType(name, FmatType.vec3)) {
        material.parameters.setVec3(name, value);
      }
    }
  }

  /// Sets a vec4 parameter named [name] on every member that declares it.
  void setVec4(String name, Vector4 value) {
    for (final material in _materials) {
      if (material.parameters.hasParameterOfType(name, FmatType.vec4)) {
        material.parameters.setVec4(name, value);
      }
    }
  }

  /// Sets a mat4 parameter named [name] on every member that declares it.
  void setMat4(String name, Matrix4 value) {
    for (final material in _materials) {
      if (material.parameters.hasParameterOfType(name, FmatType.mat4)) {
        material.parameters.setMat4(name, value);
      }
    }
  }

  /// Sets a color parameter named [name] on every member that declares it.
  void setColor(String name, Color color) {
    for (final material in _materials) {
      if (material.parameters.hasParameterOfType(name, FmatType.vec4)) {
        material.parameters.setColor(name, color);
      }
    }
  }

  /// Sets a sampler parameter named [name] on every member that declares it.
  void setTexture(
    String name,
    gpu.Texture texture, {
    gpu.SamplerOptions? sampler,
  }) {
    for (final material in _materials) {
      if (material.parameters.hasSampler(name)) {
        material.parameters.setTexture(name, texture, sampler: sampler);
      }
    }
  }
}
