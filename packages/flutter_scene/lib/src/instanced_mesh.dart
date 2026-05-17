import 'package:flutter/foundation.dart';
import 'package:flutter_scene/src/geometry/geometry.dart';
import 'package:flutter_scene/src/material/material.dart';
import 'package:vector_math/vector_math.dart';

/// Many copies of one [Geometry] / [Material] pair, each placed by its
/// own model transform.
///
/// Use an `InstancedMesh` for foliage, crowds, debris, or any scene that
/// holds many copies of the same mesh. Attach it to a node with an
/// [InstancedMeshComponent]; the whole set is then one render item, one
/// pipeline, and one cull test rather than one node per copy.
///
/// Phase 3c carries a per-instance transform only. The naive backend
/// still issues one draw call per instance.
class InstancedMesh {
  /// Creates an instanced mesh that draws [geometry] shaded by
  /// [material]. It starts with no instances; add them with
  /// [addInstance].
  InstancedMesh({required this.geometry, required this.material});

  /// The geometry drawn for every instance.
  final Geometry geometry;

  /// The material every instance is shaded with.
  final Material material;

  final List<Matrix4> _instances = [];

  Aabb3? _boundsCache;
  bool _boundsDirty = true;

  /// The number of instances.
  int get instanceCount => _instances.length;

  /// Adds an instance placed by [transform] and returns its index.
  ///
  /// The matrix is copied, so later mutating [transform] does not affect
  /// the instance; use [setInstanceTransform] to move it.
  int addInstance(Matrix4 transform) {
    _instances.add(transform.clone());
    _boundsDirty = true;
    return _instances.length - 1;
  }

  /// Replaces the transform of the instance at [index].
  void setInstanceTransform(int index, Matrix4 transform) {
    _instances[index].setFrom(transform);
    _boundsDirty = true;
  }

  /// Removes the instance at [index]. Instances after it shift down by
  /// one, so their indices change.
  void removeInstanceAt(int index) {
    _instances.removeAt(index);
    _boundsDirty = true;
  }

  /// Removes every instance.
  void clearInstances() {
    _instances.clear();
    _boundsDirty = true;
  }

  /// The live per-instance transform list the render item iterates.
  @internal
  List<Matrix4> get instances => _instances;

  /// Aggregate AABB over every instance, in the instanced mesh's local
  /// space, or `null` when [geometry] has no computable bounds or there
  /// are no instances. Cached; recomputed after any instance change.
  @internal
  Aabb3? get aggregateBounds {
    if (_boundsDirty) {
      _boundsCache = _computeAggregateBounds();
      _boundsDirty = false;
    }
    return _boundsCache;
  }

  Aabb3? _computeAggregateBounds() {
    final base = geometry.localBounds;
    if (base == null || _instances.isEmpty) return null;
    Aabb3? result;
    for (final transform in _instances) {
      final transformed = Aabb3.copy(base)..transform(transform);
      if (result == null) {
        result = transformed;
      } else {
        result.hull(transformed);
      }
    }
    return result;
  }
}
