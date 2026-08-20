import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter_scene/src/fmat/fmat_ast.dart';
import 'package:flutter_scene/src/geometry/geometry.dart';
import 'package:flutter_scene/src/material/instance_attributes.dart';
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
  InstancedMesh({
    required this.geometry,
    required this.material,
    this.cullInstances = false,
    this.sortTransparentInstances = true,
  });

  /// The geometry drawn for every instance.
  final Geometry geometry;

  /// The material every instance is shaded with.
  final Material material;

  /// Whether the renderer culls each instance after the aggregate bounds pass.
  ///
  /// Enable this for large spatial groups whose individual instances can enter
  /// the view at different times. Small compact groups are usually cheaper to
  /// draw after the single aggregate cull.
  final bool cullInstances;

  /// Whether translucent instances are sorted back to front before drawing.
  ///
  /// Disable this for dense particles or other order-independent batches when
  /// the sort costs more than the small blending difference it produces.
  final bool sortTransparentInstances;

  final List<Matrix4> _instances = [];
  final List<Vector4> _colors = [];
  final List<bool> _windingFlipped = [];
  List<Matrix4>? _instanceUpdateView;

  Aabb3? _boundsCache;
  bool _boundsDirty = true;
  int _boundsGeometryVersion = -1;
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
    _windingFlipped.add(transform.determinant() < 0);
    _growAttributeStorage();
    _boundsDirty = true;
    _revision++;
    return _instances.length - 1;
  }

  static final Vector4 _white = Vector4(1, 1, 1, 1);

  /// Replaces the transform of the instance at [index].
  void setInstanceTransform(int index, Matrix4 transform) {
    _instances[index].setFrom(transform);
    _windingFlipped[index] = transform.determinant() < 0;
    _boundsDirty = true;
    _revision++;
  }

  /// Updates every instance transform in place and invalidates the batch once.
  ///
  /// [update] receives a fixed-length view. Mutate its matrices without adding,
  /// removing, or replacing entries. Set [recomputeWinding] to false only when
  /// the edits cannot change any transform's winding parity.
  void updateInstanceTransforms(
    void Function(List<Matrix4> transforms) update, {
    bool recomputeWinding = true,
  }) {
    try {
      update(_instanceUpdateView ??= UnmodifiableListView<Matrix4>(_instances));
    } finally {
      if (recomputeWinding) {
        for (var i = 0; i < _instances.length; i++) {
          _windingFlipped[i] = _instances[i].determinant() < 0;
        }
      }
      _boundsDirty = true;
      _revision++;
    }
  }

  /// Replaces the color multiplier of the instance at [index].
  void setInstanceColor(int index, Vector4 color) {
    _colors[index].setFrom(color);
    _revision++;
  }

  /// Sets one declared per-instance attribute on the instance at [index].
  ///
  /// [name] must name an attribute in the bound material's
  /// `instance_attributes` list, and [value] must match its declared type: a
  /// `num` for `float`, or the matching [Vector2] / [Vector3] / [Vector4].
  /// An instance whose attributes are never set draws with zeros.
  /// {@category Scene graph}
  void setInstanceAttribute(int index, String name, Object value) {
    RangeError.checkValidIndex(index, _instances, 'index');
    final schema = _requireSchema(name);
    final slot = schema.slot(name);
    if (slot == null) {
      throw ArgumentError('Unknown instance attribute "$name".');
    }
    final offset = index * schema.floatCount + slot.floatOffset;
    switch ((slot.type, value)) {
      case (FmatType.float_, final num v):
        _attributeData[offset] = v.toDouble();
      case (FmatType.vec2, final Vector2 v):
        _attributeData.setAll(offset, v.storage);
      case (FmatType.vec3, final Vector3 v):
        _attributeData.setAll(offset, v.storage);
      case (FmatType.vec4, final Vector4 v):
        _attributeData.setAll(offset, v.storage);
      default:
        throw ArgumentError(
          'Instance attribute "$name" is ${slot.type.glslType}; cannot assign '
          'a ${value.runtimeType}.',
        );
    }
    _revision++;
  }

  /// Writes every declared per-instance attribute of the instance at [index]
  /// from [packed], in declaration order.
  ///
  /// This is the raw path for hot loops. [packed] is the instance's slice of
  /// the instance-rate record, so its length is the material's packed
  /// attribute width including the pad float a `vec3` carries; the throw names
  /// the expected length.
  /// {@category Scene graph}
  void setInstanceAttributes(int index, Float32List packed) {
    RangeError.checkValidIndex(index, _instances, 'index');
    final schema = _requireSchema(null);
    if (packed.length != schema.floatCount) {
      throw ArgumentError(
        'This material packs ${schema.floatCount} instance attribute float(s) '
        'per instance, but ${packed.length} were supplied.',
      );
    }
    _attributeData.setAll(index * schema.floatCount, packed);
    _revision++;
  }

  /// Removes the instance at [index]. Instances after it shift down by
  /// one, so their indices change.
  void removeInstanceAt(int index) {
    final schema = _syncAttributeStorage();
    if (schema != null) {
      final floats = schema.floatCount;
      final tail = (_instances.length - index - 1) * floats;
      if (tail > 0) {
        _attributeStore.setRange(
          index * floats,
          index * floats + tail,
          _attributeStore,
          (index + 1) * floats,
        );
      }
      _attributeUsed -= floats;
      _attributeView = null;
    }
    _instances.removeAt(index);
    _colors.removeAt(index);
    _windingFlipped.removeAt(index);
    _boundsDirty = true;
    _revision++;
  }

  /// Removes every instance.
  void clearInstances() {
    _instances.clear();
    _colors.clear();
    _windingFlipped.clear();
    _attributeUsed = 0;
    _attributeView = null;
    _boundsDirty = true;
    _revision++;
  }

  static final Float32List _noAttributes = Float32List(0);

  // The declaration comes from the bound material, so a hot reload that
  // changes it is picked up here and the stale packing is dropped. The store
  // grows geometrically and [_attributeUsed] is the live prefix, so filling a
  // large group one instance at a time stays linear.
  InstanceAttributeSchema? _attributeSchema;
  Float32List _attributeStore = _noAttributes;
  Float32List? _attributeView;
  int _attributeUsed = 0;

  Float32List get _attributeData => _attributeView ??= Float32List.sublistView(
    _attributeStore,
    0,
    _attributeUsed,
  );

  InstanceAttributeSchema? _syncAttributeStorage() {
    final schema = material.instanceAttributes;
    if (!identical(schema, _attributeSchema)) {
      _attributeSchema = schema;
      _attributeStore = _noAttributes;
      _attributeView = null;
      _attributeUsed = 0;
    }
    if (schema == null) return null;
    final needed = _instances.length * schema.floatCount;
    if (needed > _attributeStore.length) {
      var capacity = _attributeStore.isEmpty
          ? schema.floatCount
          : _attributeStore.length;
      while (capacity < needed) {
        capacity *= 2;
      }
      final grown = Float32List(capacity);
      grown.setRange(0, _attributeUsed, _attributeStore);
      _attributeStore = grown;
      _attributeView = null;
    } else if (needed > _attributeUsed) {
      // Capacity a removed instance left behind; a new instance starts zeroed.
      _attributeStore.fillRange(_attributeUsed, needed, 0);
    }
    if (needed != _attributeUsed) {
      _attributeUsed = needed;
      _attributeView = null;
    }
    return schema;
  }

  void _growAttributeStorage() {
    if (material.instanceAttributes != null) _syncAttributeStorage();
  }

  InstanceAttributeSchema _requireSchema(String? name) {
    final schema = _syncAttributeStorage();
    if (schema == null) {
      throw ArgumentError(
        name == null
            ? 'This mesh\'s material declares no instance attributes.'
            : 'Unknown instance attribute "$name".',
      );
    }
    return schema;
  }

  /// Packed per-instance attribute floats matching [instances], or null when
  /// the material declares none.
  @internal
  Float32List? get instanceAttributeData {
    final schema = _syncAttributeStorage();
    return schema == null ? null : _attributeData;
  }

  /// Attribute floats each instance record carries, zero when the material
  /// declares none.
  @internal
  int get instanceAttributeFloats =>
      material.instanceAttributes?.floatCount ?? 0;

  /// The live per-instance transform list the render item iterates.
  @internal
  List<Matrix4> get instances => _instances;

  /// Live per-instance linear RGBA multipliers.
  @internal
  List<Vector4> get colors => _colors;

  /// Per-instance local winding parity matching [instances].
  @internal
  List<bool> get windingFlipped => _windingFlipped;

  /// Changes whenever instance data changes.
  @internal
  int get revision => _revision;

  /// Aggregate AABB over every instance, in the instanced mesh's local
  /// space, or `null` when [geometry] has no computable bounds or there
  /// are no instances. Cached; recomputed after any instance change.
  @internal
  Aabb3? get aggregateBounds {
    final geometryVersion = geometry.localBoundsVersion;
    if (_boundsDirty || _boundsGeometryVersion != geometryVersion) {
      _boundsCache = _computeAggregateBounds();
      _boundsDirty = false;
      _boundsGeometryVersion = geometryVersion;
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
