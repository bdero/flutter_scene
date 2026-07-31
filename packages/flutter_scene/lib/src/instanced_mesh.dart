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
/// {@category Scene graph}
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
  final List<Vector4> _colors = [];

  Aabb3? _boundsCache;
  bool _boundsDirty = true;
  int _revision = 0;

  /// The number of instances.
  int get instanceCount => _instances.length;

  /// Adds an instance placed by [transform] and returns its index.
  ///
  /// The matrix is copied, so later mutating [transform] does not affect
  /// the instance; use [setInstanceTransform] to move it.
  int addInstance(Matrix4 transform, {Vector4? color}) {
    _instances.add(transform.clone());
    _colors.add((color ?? _white).clone());
    _boundsDirty = true;
    _revision++;
    return _instances.length - 1;
  }

  static final Vector4 _white = Vector4(1, 1, 1, 1);

  /// Replaces the transform of the instance at [index].
  void setInstanceTransform(int index, Matrix4 transform) {
    _instances[index].setFrom(transform);
    _boundsDirty = true;
    _revision++;
  }

  /// Replaces the color multiplier of the instance at [index].
  void setInstanceColor(int index, Vector4 color) {
    _colors[index].setFrom(color);
    _revision++;
  }

  /// Removes the instance at [index]. Instances after it shift down by
  /// one, so their indices change.
  void removeInstanceAt(int index) {
    _instances.removeAt(index);
    _colors.removeAt(index);
    _boundsDirty = true;
    _revision++;
  }

  /// Removes every instance.
  void clearInstances() {
    _instances.clear();
    _colors.clear();
    _boundsDirty = true;
    _revision++;
  }

  /// The live per-instance transform list the render item iterates.
  @internal
  List<Matrix4> get instances => _instances;

  /// Live per-instance linear RGBA multipliers.
  @internal
  List<Vector4> get colors => _colors;

  /// Changes whenever instance data changes.
  @internal
  int get revision => _revision;

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
