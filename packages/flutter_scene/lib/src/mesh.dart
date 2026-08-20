import 'package:flutter_scene/src/geometry/geometry.dart';
import 'package:flutter_scene/src/geometry/morph_targets.dart';
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
/// {@category Geometry}
base class MeshPrimitive {
  /// Pairs [geometry] with the [material] used to shade it.
  MeshPrimitive(this.geometry, this.material);

  /// The vertex/index data drawn by this primitive.
  Geometry geometry;

  /// The shader and per-material parameters used to render [geometry].
  Material material;

  /// Whether this primitive draws in the opaque/translucent color passes.
  /// Defaults to `true`.
  ///
  /// Ands with the owning node's visibility hierarchy, so hiding either the
  /// node or the primitive hides it. Independent of [castsShadow]; a
  /// primitive can stay invisible while still casting a shadow.
  /// {@category Geometry}
  bool visible = true;

  /// Whether this primitive casts shadows. Defaults to `true`.
  ///
  /// Ands with the owning node's [Node.castsShadows]. Independent of
  /// [visible], so a primitive can render while opting out of
  /// self-shadowing, or stay invisible while still casting a shadow.
  /// {@category Geometry}
  bool castsShadow = true;
}

/// Defines the shape and appearance of a 3D model in the scene.
///
/// It consists of a list of [MeshPrimitive] instances, where each primitive
/// contains the [Geometry] and the [Material] to render a specific part of
/// the 3d model.
/// {@category Geometry}
base class Mesh {
  /// Creates a `Mesh` consisting of a single [MeshPrimitive] with the given [Geometry] and [Material].
  Mesh(Geometry geometry, Material material)
    : primitives = [MeshPrimitive(geometry, material)];

  /// Creates a `Mesh` composed of the supplied [MeshPrimitive] list.
  ///
  /// Use this constructor for multi-material models, where each
  /// [MeshPrimitive] pairs a separate [Geometry] with its own [Material].
  Mesh.primitives({required this.primitives});

  /// Returns a shallow copy: a new [Mesh] with new [MeshPrimitive]s that
  /// reuse this mesh's [Geometry] and [Material] instances.
  ///
  /// The heavy GPU resources (geometry buffers, textures) stay shared, but
  /// the new primitives are independent slots, so reassigning a clone's
  /// `primitive.material` does not affect the original or sibling clones.
  /// Used by [Node.clone] so model instances can be reskinned per instance.
  Mesh clone() => Mesh.primitives(
    primitives: [
      for (final p in primitives) MeshPrimitive(p.geometry, p.material),
    ],
  );

  /// The list of [MeshPrimitive] objects that make up the [Geometry] and [Material] of the 3D model.
  final List<MeshPrimitive> primitives;

  /// The morph target data of this mesh's first morphed primitive, or null
  /// when no primitive carries targets. Every primitive of an imported mesh
  /// shares one target count and order (the importers validate it), so the
  /// first primitive's names, defaults, and count speak for the whole mesh.
  MorphTargetData? get morphTargets {
    for (final p in primitives) {
      final data = p.geometry.morphTargets;
      if (data != null) return data;
    }
    return null;
  }

  vm.Aabb3? _localBoundsCache;
  bool _localBoundsCached = false;
  List<int>? _cachedBoundsVersions;
  List<Geometry>? _cachedGeometries;

  /// Local-space union of every primitive's [Geometry.localBounds], or
  /// `null` when no primitive has computable bounds.
  ///
  /// Cached. The cache refreshes itself when a primitive's geometry is
  /// replaced, or reports a new [Geometry.localBoundsVersion], so swapping
  /// or mutating a primitive's geometry stays correct without an explicit
  /// invalidation.
  vm.Aabb3? get localBounds {
    if (_localBoundsCached && _boundsCacheStillValid()) {
      return _localBoundsCache;
    }
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
    _cachedBoundsVersions = <int>[
      for (final p in primitives) p.geometry.localBoundsVersion,
    ];
    _cachedGeometries = <Geometry>[for (final p in primitives) p.geometry];
    return result;
  }

  // Valid only if the primitive list still holds the same geometry instances
  // (identity) at the same bounds versions the cache was built from. The
  // identity compare is what catches a replaced primitive geometry, whose
  // fresh instance can share the old one's version number.
  bool _boundsCacheStillValid() {
    final versions = _cachedBoundsVersions;
    final geometries = _cachedGeometries;
    if (versions == null ||
        geometries == null ||
        versions.length != primitives.length) {
      return false;
    }
    for (var i = 0; i < primitives.length; i++) {
      final geometry = primitives[i].geometry;
      if (!identical(geometries[i], geometry) ||
          versions[i] != geometry.localBoundsVersion) {
        return false;
      }
    }
    return true;
  }

  /// Invalidate the cached [localBounds]. Rarely needed, since the cache
  /// already detects a replaced primitive geometry and a bumped
  /// [Geometry.localBoundsVersion]; call this only after mutating a
  /// geometry's bounds through a path that leaves its version unchanged.
  void markLocalBoundsDirty() {
    _localBoundsCache = null;
    _localBoundsCached = false;
    _cachedBoundsVersions = null;
    _cachedGeometries = null;
  }
}
