import 'package:flutter_scene/src/geometry/geometry.dart';
import 'package:flutter_scene/src/material/material.dart';
import 'package:vector_math/vector_math.dart' as vm;

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
  /// Pairs [geometry] with the [material] used to shade it.
  MeshPrimitive(this.geometry, this.material);

  /// The vertex/index data drawn by this primitive.
  Geometry geometry;

  /// The shader and per-material parameters used to render [geometry].
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

  /// Creates a `Mesh` composed of the supplied [MeshPrimitive] list.
  ///
  /// Use this constructor for multi-material models, where each
  /// [MeshPrimitive] pairs a separate [Geometry] with its own [Material].
  Mesh.primitives({required this.primitives});

  /// The list of [MeshPrimitive] objects that make up the [Geometry] and [Material] of the 3D model.
  final List<MeshPrimitive> primitives;

  vm.Aabb3? _localBoundsCache;
  bool _localBoundsCached = false;

  /// Local-space union of every primitive's [Geometry.localBounds], or
  /// `null` when no primitive has computable bounds. Cached; call
  /// [markLocalBoundsDirty] after replacing a primitive's geometry or
  /// mutating geometry that participates in the union.
  vm.Aabb3? get localBounds {
    if (_localBoundsCached) return _localBoundsCache;
    vm.Aabb3? result;
    for (final p in primitives) {
      final b = p.geometry.localBounds;
      if (b == null) continue;
      if (result == null) {
        result = vm.Aabb3.copy(b);
      } else {
        result.hull(b);
      }
    }
    _localBoundsCache = result;
    _localBoundsCached = true;
    return result;
  }

  /// Invalidate the cached [localBounds]. Call this after replacing a
  /// primitive's geometry or mutating geometry that participates in the
  /// union.
  void markLocalBoundsDirty() {
    _localBoundsCache = null;
    _localBoundsCached = false;
  }
}
