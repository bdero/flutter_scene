import 'dart:collection';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' hide Matrix4;
import 'package:flutter_scene/src/camera.dart';
import 'package:flutter_scene/src/components/component.dart';
import 'package:flutter_scene/src/components/instanced_mesh_component.dart';
import 'package:flutter_scene/src/components/mesh_component.dart';
import 'package:flutter_scene/src/geometry/mesh_data.dart';
import 'package:flutter_scene/src/geometry/morph_targets.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/runtime_importer/runtime_importer.dart';
import 'package:flutter_scene/src/scene.dart';
import 'package:flutter_scene/src/animation.dart';
import 'package:flutter_scene/src/mesh.dart';
import 'package:flutter_scene/src/render/render_layers.dart';
import 'package:flutter_scene/src/render/render_scene.dart';
import 'package:flutter_scene/src/skin.dart';
import 'package:vector_math/vector_math.dart';
import 'package:vector_math/vector_math.dart' as vm;

void _visitMutable<T>(List<T> items, void Function(T item) visit) {
  HashSet<T>? visited;
  var index = 0;
  while (index < items.length) {
    final item = items[index];
    final tracked = visited;
    if (tracked != null && tracked.contains(item)) {
      index++;
      continue;
    }
    visit(item);

    // Unmutated and detachment paths stay linear and allocation-free.
    // Insertion before the cursor creates identity tracking.
    if (index < items.length && identical(items[index], item)) {
      tracked?.add(item);
      index++;
      continue;
    }

    final detached =
        (item is Component && !item.isAttached) ||
        (item is Node && item.parent == null);
    if (detached) {
      tracked?.add(item);
      continue;
    }

    final currentIndex = items.indexWhere(
      (candidate) => identical(candidate, item),
    );
    if (currentIndex <= index) {
      tracked?.add(item);
      continue;
    }

    if (tracked == null) {
      visited = HashSet<T>.identity()
        ..addAll(items.take(currentIndex + 1))
        ..add(item);
    } else {
      tracked.add(item);
    }
    index = 0;
  }
}

/// A `Node` represents a single element in a 3D scene graph.
///
/// Each node can contain a transform (position, rotation, scale), a mesh (3D geometry and material),
/// and child nodes. Nodes are used to build complex scenes by establishing relationships
/// between different elements, allowing for transformations to propagate down the hierarchy.
/// {@category Scene graph}
base class Node implements SceneGraph {
  /// Creates a node with an optional [name], [localTransform], and [mesh].
  ///
  /// When omitted, [localTransform] defaults to the identity matrix and the
  /// node has no associated geometry. A non-null [mesh] is attached as a
  /// [MeshComponent].
  Node({this.name = '', Matrix4? localTransform, Mesh? mesh})
    : _localTransform = localTransform ?? Matrix4.identity() {
    if (mesh != null) {
      addComponent(MeshComponent(mesh));
    }
  }

  /// The name of this node, used for identification.
  String name;

  /// Whether this node is visible in the scene. If false, the node and its children will not be rendered.
  bool visible = true;

  /// A highlight/outline color (linear RGBA) for this node, or null for none.
  ///
  /// When set, the scene draws a selection-style outline around this node's
  /// geometry in that color (see `Scene.highlightStyle`). Highlighting is a
  /// per-node property, so different nodes can use different colors. Setting it
  /// does not affect the node's normal rendering.
  /// {@category Rendering}
  Vector4? highlightColor;

  /// Whether this node and its descendants should be tested against the
  /// camera frustum each frame. When `true` (the default), subtrees
  /// whose [combinedLocalBounds] don't intersect the frustum are
  /// skipped entirely. Set to `false` for procedural geometry, large
  /// terrain pieces, or anything else where the cached bound is
  /// known-stale or known-misleading.
  ///
  /// Subtrees that report no bound (skinned content, geometry without
  /// computable bounds) are treated as always visible regardless of
  /// this flag.
  bool frustumCulled = true;

  /// The render layers this node occupies, a 32-bit bitmask. A
  /// [RenderView] renders this node's mesh only when its
  /// [RenderView.layerMask] intersects these layers
  /// (`layers & layerMask != 0`). Defaults to [kRenderLayerDefault]
  /// (layer 0). Each node carries its own layers; the value is not
  /// inherited by children.
  int layers = kRenderLayerDefault;

  /// The light channels this node's meshes occupy, an 8-bit bitmask. A light
  /// reaches them only when its own channel mask intersects this one
  /// (`light.channelMask & lightChannelMask != 0`), so a light can be aimed at
  /// a subset of the scene without a second scene graph. `0xFF` (the default)
  /// takes every channel; `0` takes none and leaves the meshes with only
  /// image-based lighting, which channels never gate. Not inherited by
  /// children; set it on each mesh-bearing node.
  ///
  /// A directional light's `shadowCasterChannelMask` tests against this same
  /// value, so a node can be lit without casting into that light's shadow map
  /// and the other way around.
  /// {@category Scene graph}
  int lightChannelMask = 0xFF;

  /// Marks this node's meshes as static shadow casters: their geometry,
  /// material coverage, and world transform are promised not to change while
  /// mounted, so the engine may render them into cached shadow-map tiles that
  /// are reused across frames instead of re-encoding every caster every
  /// frame. Large static worlds become dramatically cheaper to shadow; nodes
  /// left dynamic (the default) still cast per-frame shadows on top of the
  /// cache. A static node that does change (moves, remesh, material coverage
  /// edit) shows stale shadows until its render item re-registers, so flag
  /// only genuinely static content. Not inherited by children; set it on each
  /// mesh-bearing node. Materials with a `vertex { }` displacement stage
  /// should stay dynamic, since their cached shadows would not follow a
  /// camera-dependent displacement.
  bool shadowStatic = false;

  /// Whether this node's meshes cast shadows. Defaults to `true`.
  ///
  /// This does not affect whether the meshes receive shadows. The value is not
  /// inherited by children.
  bool castsShadows = true;

  /// Whether scene raycasts (`Scene.raycast`) test this node's meshes.
  ///
  /// Disable for geometry that renders but should be transparent to rays
  /// (effects, decals); it then neither blocks nor receives picks. Distinct
  /// from [visible]: invisible nodes are already skipped by default.
  bool raycastable = true;

  Matrix4 _localTransform;
  DecomposedTransform? _localTransformTrs;

  /// The transform of this node relative to its parent: position,
  /// rotation, and scale.
  ///
  /// Prefer [position], [rotation], and [scale] for the common case, or
  /// assign a whole matrix. Both mark this node and its descendants' cached
  /// world transforms stale, and this node and its ancestors' cached bounds
  /// stale.
  ///
  /// The getter returns the live matrix, so editing it in place does NOT
  /// mark anything stale and the node silently will not move (debug builds
  /// throw on the next read). To edit in place, use [mutateLocalTransform],
  /// which dirties for you, or assign a fresh matrix
  /// (`node.localTransform = node.localTransform.clone()..translateByVector3(...)`).
  Matrix4 get localTransform => _localTransform;
  set localTransform(Matrix4 value) {
    _localTransform = value;
    _localTransformTrs = null;
    markTransformDirty();
  }

  /// Edits [localTransform] in place through [edit], then marks the node
  /// stale.
  ///
  /// The correct way to reach for the raw matrix, since a bare
  /// `localTransform.translateByVector3(...)` mutates the live matrix without
  /// dirtying the cache and the node silently will not move. [position],
  /// [rotation], and [scale] cover most edits without a matrix.
  ///
  /// ```dart
  /// node.mutateLocalTransform((m) => m.translateByVector3(Vector3(0.0, 1.0, 0.0)));
  /// ```
  /// {@category Scene graph}
  void mutateLocalTransform(void Function(Matrix4 transform) edit) {
    edit(_localTransform);
    _localTransformTrs = null;
    markTransformDirty();
  }

  /// The authored decomposition of [localTransform], when known.
  ///
  /// A matrix decompose puts a mirror's negative sign on the X scale no
  /// matter which axis the source mirrored, so animation blends anchored
  /// to a re-decomposed bind pose fade mirrored bones through zero scale.
  /// Importers record the authored decomposition here and blending
  /// anchors to it. Cleared when [localTransform] is assigned a matrix.
  @internal
  DecomposedTransform? get localTransformTrs => _localTransformTrs;

  /// Sets [localTransform] from [trs], keeping the decomposition.
  @internal
  void setLocalTransformTrs(DecomposedTransform trs) {
    _localTransform = trs.toMatrix4();
    _localTransformTrs = trs;
    markTransformDirty();
  }

  /// This node's position relative to its parent.
  ///
  /// The getter returns a copy, so editing it does not move the node, and
  /// debug builds throw on such an edit. Assign to move the node
  /// (`node.position = Vector3(0, 1, 0)`, or `node.position += ...`).
  /// Setting leaves [rotation] and [scale] alone.
  /// {@category Scene graph}
  Vector3 get position {
    assert(_debugCheckTransformHandouts());
    final trs = _localTransformTrs;
    final value = trs != null
        ? trs.translation.clone()
        : _localTransform.getTranslation();
    assert(_debugRecordHandout('position', value, value.clone()));
    return value;
  }

  set position(Vector3 value) {
    assert(_debugForgetHandout('position'));
    _localTransformTrs?.translation.setFrom(value);
    _localTransform.setTranslation(value);
    markTransformDirty();
  }

  /// This node's rotation relative to its parent.
  ///
  /// Same copy rules as [position]. Setting leaves the position and scale
  /// alone, and records the decomposition, so all three read back what was
  /// set.
  /// {@category Scene graph}
  Quaternion get rotation {
    assert(_debugCheckTransformHandouts());
    final value = _decomposedLocalTransform().rotation.clone();
    assert(_debugRecordHandout('rotation', value, value.clone()));
    return value;
  }

  set rotation(Quaternion value) {
    assert(_debugForgetHandout('rotation'));
    final trs = _decomposedLocalTransform();
    trs.rotation.setFrom(value);
    setLocalTransformTrs(trs);
  }

  /// This node's scale relative to its parent.
  ///
  /// Same copy rules as [position]. Setting leaves the position and
  /// rotation alone. A scale set here, or recorded by an importer, reads
  /// back exactly; on a node whose transform arrived as a matrix the
  /// getter decomposes it, which reports a mirror on X whichever axis the
  /// matrix actually mirrored.
  /// {@category Scene graph}
  Vector3 get scale {
    assert(_debugCheckTransformHandouts());
    final value = _decomposedLocalTransform().scale.clone();
    assert(_debugRecordHandout('scale', value, value.clone()));
    return value;
  }

  set scale(Vector3 value) {
    assert(_debugForgetHandout('scale'));
    final trs = _decomposedLocalTransform();
    trs.scale.setFrom(value);
    setLocalTransformTrs(trs);
  }

  // The decomposition of [localTransform], the authored one when the node
  // carries it and a fresh decompose otherwise. A derived result is not
  // stored, so reading never promotes a decomposed mirror to authored data.
  DecomposedTransform _decomposedLocalTransform() {
    final authored = _localTransformTrs;
    if (authored != null) return authored;
    final translation = Vector3.zero();
    final rotation = Quaternion.identity();
    final scale = Vector3.zero();
    _localTransform.decompose(translation, rotation, scale);
    return DecomposedTransform(
      translation: translation,
      rotation: rotation,
      scale: scale,
    );
  }

  // Cached world-space transform, valid while _worldTransformDirty is
  // false. Recomputed lazily by globalTransform and by the render walk.
  final Matrix4 _worldTransform = Matrix4.identity();
  bool _worldTransformDirty = true;
  int _worldTransformVersion = 0;

  // Copy of _localTransform as it stood when _worldTransform was last
  // computed, so a cache hit can catch an in-place edit that skipped
  // markTransformDirty. Only the asserts below write it, so it stays null in
  // release builds and costs nothing there.
  Matrix4? _debugLocalTransformShadow;

  // Whether this node's accumulated transform reverses triangle winding (an
  // odd number of negative-determinant transforms up the chain). Cached
  // alongside _worldTransform and invalidated by the same dirty flag.
  bool _windingFlipped = false;

  /// The skin attached to this node, used for skeletal animation. Set by
  /// importers (both the scene importer and the runtime glTF/GLB loader).
  Skin? skin;

  // This node instance's morph target weights, lazily seeded from the mesh's
  // defaults on first access. Per instance so clones sharing one morphed
  // geometry can hold different expressions, matching glTF's node.weights
  // override of mesh.weights.
  Float32List? _morphWeights;

  MorphTargetData? get _meshMorphTargets => mesh?.morphTargets;

  /// The number of morph targets on this node's mesh, or zero when the mesh
  /// has none.
  int get morphTargetCount => _meshMorphTargets?.targetCount ?? 0;

  /// The morph target names from the source asset (`extras.targetNames`),
  /// empty strings for unnamed targets. Empty when the mesh has no targets.
  List<String> get morphTargetNames =>
      _meshMorphTargets?.targetNames ?? const [];

  /// The mesh-authored default morph weights, or null when the mesh has no
  /// targets. Returns a copy.
  Float32List? get defaultMorphWeights {
    final defaults = _meshMorphTargets?.defaultWeights;
    return defaults == null ? null : Float32List.fromList(defaults);
  }

  /// This node's current morph target weights, or null when the mesh has no
  /// targets. Returns a copy; drive weights through [setMorphWeight] or
  /// [setMorphWeights].
  Float32List? get morphWeights {
    final live = internalMorphWeights;
    return live == null ? null : Float32List.fromList(live);
  }

  /// Sets the weight of morph target [index] on this node instance.
  ///
  /// Throws a [StateError] when the mesh has no morph targets and a
  /// [RangeError] when [index] is outside `[0, morphTargetCount)`.
  void setMorphWeight(int index, double value) {
    final live = internalMorphWeights;
    if (live == null) {
      throw StateError("This node's mesh has no morph targets");
    }
    live[index] = value;
  }

  /// Replaces morph weights on this node instance, in target order. Entries
  /// beyond the mesh's target count are ignored; missing trailing entries
  /// keep their current value.
  void setMorphWeights(List<double> values) {
    final live = internalMorphWeights;
    if (live == null) {
      throw StateError("This node's mesh has no morph targets");
    }
    for (var i = 0; i < values.length && i < live.length; i++) {
      live[i] = values[i];
    }
  }

  /// The live weight storage the renderer and animation system read and
  /// write, or null when the mesh has no morph targets.
  @internal
  Float32List? get internalMorphWeights {
    final data = _meshMorphTargets;
    if (data == null) return null;
    final live = _morphWeights;
    if (live != null && live.length == data.targetCount) return live;
    return _morphWeights = Float32List.fromList(data.defaultWeights);
  }

  /// Assigns the world-space transform of this node, automatically computing
  /// the [localTransform] needed to place the node at [transform] given the
  /// current parent transform.
  ///
  /// If the node has no parent, this is equivalent to assigning
  /// [localTransform] directly.
  set globalTransform(Matrix4 transform) {
    final parent = _parent;
    if (parent == null) {
      localTransform = transform;
    } else {
      // Solve `transform == parent.globalTransform * localTransform` for
      // localTransform. (`Matrix4.invert` returns the determinant and mutates
      // the receiver. `copyInverse` is the non-destructive version.)
      final parentInverse = Matrix4.identity();
      parentInverse.copyInverse(parent.globalTransform);
      localTransform = parentInverse * transform;
    }
  }

  /// The world-space transform of this node, with every ancestor's
  /// transform applied.
  ///
  /// Cached: O(1) when the cache is current, recomputed up the parent
  /// chain only after a transform change.
  Matrix4 get globalTransform {
    assert(_debugCheckTransformHandouts());
    if (!_worldTransformDirty) {
      assert(_debugCheckLocalTransformUnmutated());
      return _worldTransform;
    }
    final parent = _parent;
    final selfFlip = _localTransform.determinant() < 0;
    if (parent == null) {
      _worldTransform.setFrom(_localTransform);
      _windingFlipped = selfFlip;
    } else {
      _worldTransform
        ..setFrom(parent.globalTransform)
        ..multiply(_localTransform);
      // parent.globalTransform above refreshed the parent's cache, so
      // parent._windingFlipped is current.
      _windingFlipped = selfFlip != parent._windingFlipped;
    }
    _worldTransformDirty = false;
    _worldTransformVersion++;
    assert(_debugSnapshotLocalTransform());
    return _worldTransform;
  }

  /// Orients this node so its forward axis (local `+Z`) points at [target] in
  /// world space, keeping [up] as the reference up (defaults to `+Y`). Only
  /// the node's rotation changes; its world position and scale are preserved.
  ///
  /// `+Z` is the engine's forward convention: cameras look down it,
  /// directional and spot lights aim down it, and imported models face it, so
  /// this aims any of them. [up] must not be parallel to the direction from
  /// the node to [target]; for a straight-down or straight-up view pass
  /// `Vector3(0, 0, 1)` or `Vector3(0, 0, -1)` instead of `Vector3(0, 1, 0)`.
  /// {@category Scene graph}
  void lookAt(Vector3 target, {Vector3? up}) =>
      lookAtFrom(globalTransform.getTranslation(), target, up: up);

  /// Places the node at [eye] and orients its forward axis (local `+Z`) at
  /// [target] in world space. The imperative camera one-liner, positioning and
  /// aiming in a single call; the node's world scale is preserved. See
  /// [lookAt] for the forward-axis convention and the [up] constraint.
  /// {@category Scene graph}
  void lookAtFrom(Vector3 eye, Vector3 target, {Vector3? up}) {
    final world = globalTransform.storage;
    final scale = Vector3(
      Vector3(world[0], world[1], world[2]).length,
      Vector3(world[4], world[5], world[6]).length,
      Vector3(world[8], world[9], world[10]).length,
    );
    globalTransform = _lookAtMatrix(
      eye,
      target,
      up ?? Vector3(0.0, 1.0, 0.0),
      scale,
    );
  }

  /// A local transform placing an object at [eye] with its forward axis (local
  /// `+Z`) facing [target], and [up] as the reference up (defaults to `+Y`).
  ///
  /// The static counterpart to [lookAt], for the construction and declarative
  /// paths: pass it to `Node(localTransform: ...)` or a declarative node's
  /// `transform:`. See [lookAt] for the forward-axis convention and the [up]
  /// constraint.
  /// {@category Scene graph}
  static Matrix4 lookAtTransform(Vector3 eye, Vector3 target, {Vector3? up}) =>
      _lookAtMatrix(
        eye,
        target,
        up ?? Vector3(0.0, 1.0, 0.0),
        Vector3(1.0, 1.0, 1.0),
      );

  // Builds the world transform whose `+Z` faces [target] from [eye] with the
  // given per-axis [scale]. The rotation is the inverse of the equivalent view
  // basis, so a CameraComponent on the node renders the same view a
  // PerspectiveCamera(position: eye, target: target) would.
  static Matrix4 _lookAtMatrix(
    Vector3 eye,
    Vector3 target,
    Vector3 up,
    Vector3 scale,
  ) {
    final viewDirection = target - eye;
    assert(
      viewDirection.length2 > 1e-12,
      'lookAt target equals the eye, so the direction is undefined. Move '
      'target away from eye.',
    );
    assert(
      up.cross(viewDirection).length2 > 1e-12,
      'lookAt up is parallel to the eye-to-target direction, so the basis is '
      'degenerate. Use an up that is not parallel to it; for a straight-down '
      'or straight-up view use Vector3(0, 0, 1) or Vector3(0, 0, -1).',
    );
    final forward = viewDirection.normalized();
    final right = up.cross(forward).normalized();
    final trueUp = forward.cross(right).normalized();
    return Matrix4(
      right.x * scale.x,
      right.y * scale.x,
      right.z * scale.x,
      0.0, //
      trueUp.x * scale.y,
      trueUp.y * scale.y,
      trueUp.z * scale.y,
      0.0, //
      forward.x * scale.z,
      forward.y * scale.z,
      forward.z * scale.z,
      0.0, //
      eye.x,
      eye.y,
      eye.z,
      1.0, //
    );
  }

  // Records _localTransform alongside the world transform just cached.
  bool _debugSnapshotLocalTransform() {
    (_debugLocalTransformShadow ??= Matrix4.zero()).setFrom(_localTransform);
    return true;
  }

  // Debug-only record of what each of the position/rotation/scale getters
  // last handed out, as a check that the copy still holds the value it was
  // given. Only assert-invoked helpers write it, so it stays null in release
  // builds and costs nothing there.
  Map<String, bool Function()>? _debugTransformHandouts;

  bool _debugRecordHandout(String property, Object value, Object snapshot) {
    (_debugTransformHandouts ??= {})[property] = () => value == snapshot;
    return true;
  }

  // Drops the record for [property]. Read, edit the copy, assign it back is
  // the supported way to move a node, so assigning clears the suspicion.
  bool _debugForgetHandout(String property) {
    _debugTransformHandouts?.remove(property);
    return true;
  }

  // Throws when a copy handed out by position, rotation, or scale was edited
  // in place, an edit that cannot reach the node.
  bool _debugCheckTransformHandouts() {
    final handouts = _debugTransformHandouts;
    if (handouts == null) return true;
    for (final entry in handouts.entries) {
      if (entry.value()) continue;
      final property = entry.key;
      handouts.clear();
      throw StateError(
        'Node "$name": node.$property returns a copy, and that copy was '
        'edited in place, so the node did not move. Assign the value instead '
        '(node.$property = ...), or clone it first when you want scratch.',
      );
    }
    return true;
  }

  // Throws when _localTransform changed without the cache being invalidated,
  // which only an in-place edit can do.
  bool _debugCheckLocalTransformUnmutated() {
    final shadow = _debugLocalTransformShadow;
    if (shadow == null || shadow == _localTransform) return true;
    throw StateError(
      'Node "$name": localTransform was mutated in place, so its cached world '
      'transform is stale and the node will not move. Assign a new matrix '
      '(node.localTransform = ...) or call node.markTransformDirty() after an '
      'in-place edit.',
    );
  }

  /// Changes whenever this node's world transform is recomputed.
  @internal
  int get worldTransformVersion {
    globalTransform;
    return _worldTransformVersion;
  }

  /// Whether this node's accumulated transform reverses triangle winding (a
  /// mirror / negative scale somewhere up the chain). The renderer flips cull
  /// winding for such nodes so their front faces are not culled.
  @internal
  bool get windingFlipped {
    // Touch globalTransform to refresh the cache (which sets _windingFlipped).
    globalTransform;
    return _windingFlipped;
  }

  Node? _parent;

  /// The parent node of this node in the scene graph.
  Node? get parent => _parent;
  bool _isSceneRoot = false;

  /// The collection of [MeshPrimitive] objects that represent the 3D
  /// geometry and material properties of this node.
  ///
  /// This is a convenience over the node's first [MeshComponent]. The
  /// getter returns that component's mesh, or `null` when the node has no
  /// `MeshComponent`. The setter replaces the first `MeshComponent`'s
  /// mesh (adding a `MeshComponent` when there is none), or, given
  /// `null`, removes every `MeshComponent`.
  Mesh? get mesh => _meshComponents.isEmpty ? null : _meshComponents.first.mesh;
  set mesh(Mesh? value) {
    if (value == null) {
      for (final meshComponent in _meshComponents.toList()) {
        removeComponent(meshComponent);
      }
    } else if (_meshComponents.isNotEmpty) {
      _meshComponents.first.mesh = value;
    } else {
      addComponent(MeshComponent(value));
    }
  }

  // The render scene this node is mounted into, or null when the node is
  // not part of a live scene graph.
  RenderScene? _renderScene;

  /// The render scene this node is mounted into, or `null` when the node
  /// is not part of a live scene graph. Used by engine components to
  /// register and unregister their render items.
  @internal
  RenderScene? get internalRenderScene => _renderScene;

  // Whether this node and every ancestor is visible, recomputed each
  // frame by [scenePrePass].
  bool _effectiveVisible = false;

  /// Whether this node and every ancestor is visible right now. Light
  /// collection reads it so a hidden node's lights stop contributing the
  /// way its meshes stop drawing. Walks ancestors rather than reading the
  /// pre-pass cache so it holds before the first frame too.
  @internal
  bool get internalEffectiveVisible {
    for (Node? current = this; current != null; current = current.parent) {
      if (!current.visible) return false;
    }
    return true;
  }

  // The components attached to this node, in attach order.
  final List<Component> _components = [];

  // Typed fast paths: the subsets of [_components] that feed the render
  // layer, so the per-frame pre-pass refreshes their render items
  // without scanning the full component list.
  final List<MeshComponent> _meshComponents = [];

  // Components that correct an animated pose, ticked after the subtree.
  // Kept in their own list so the common node pays one emptiness check.
  final List<Component> _lateComponents = [];
  final List<InstancedMeshComponent> _instancedMeshComponents = [];

  /// Attaches [component] to this node.
  ///
  /// The component must not already be attached to a node. This fires its
  /// [Component.onAttach] hook, and, if this node is already part of a
  /// live scene, its [Component.onMount] and [Component.onLoad] hooks.
  void addComponent(Component component) {
    if (component.isAttached) {
      throw Exception('Component is already attached to a node');
    }
    _components.add(component);
    if (component.wantsLateUpdate) _lateComponents.add(component);
    if (component is MeshComponent) {
      _meshComponents.add(component);
      markBoundsDirty();
    } else if (component is InstancedMeshComponent) {
      _instancedMeshComponents.add(component);
    }
    component.attachTo(this);
    if (_renderScene != null) {
      component.mount();
    }
  }

  /// Detaches [component] from this node.
  ///
  /// Fires [Component.onUnmount] (when this node is in a live scene) and
  /// [Component.onDetach]. Throws if [component] is not attached here.
  void removeComponent(Component component) {
    if (!_components.contains(component)) {
      throw Exception('Component is not attached to this node');
    }
    if (_renderScene != null) {
      component.unmount();
    }
    component.detachFrom();
    _components.remove(component);
    if (component is MeshComponent) {
      _meshComponents.remove(component);
      markBoundsDirty();
    } else if (component is InstancedMeshComponent) {
      _instancedMeshComponents.remove(component);
    }
    _lateComponents.remove(component);
  }

  /// Returns the first attached component of type [T], or `null`.
  T? getComponent<T>() {
    for (final component in _components) {
      if (component is T) return component as T;
    }
    return null;
  }

  /// Returns every attached component of type [T], in attach order.
  Iterable<T> getComponents<T>() => _components.whereType<T>();

  void _mount(RenderScene renderScene) {
    _renderScene = renderScene;
    _visitMutable(_components, (component) => component.mount());
    _visitMutable(children, (child) => child._mount(renderScene));
  }

  void _unmount() {
    _visitMutable(children, (child) => child._unmount());
    _visitMutable(_components, (component) => component.unmount());
    _renderScene = null;
  }

  // Combined local-space AABB cache. Three states:
  //   * _combinedBoundsCached == false: not yet computed (fall through
  //     to the lazy compute path on first access).
  //   * _combinedBoundsCached == true, _combinedBoundsCache == null:
  //     subtree is unbounded (skinned content, or geometry without
  //     computable bounds); treat as always visible.
  //   * _combinedBoundsCached == true, _combinedBoundsCache != null:
  //     valid cached AABB.
  vm.Aabb3? _combinedBoundsCache;
  bool _combinedBoundsCached = false;

  /// Local-space AABB covering this node's mesh and every descendant's
  /// (transformed) bounds. Returns `null` when the subtree contains
  /// skinned content or geometry without computable bounds, signalling
  /// "treat as always visible." Cached; invalidated by [markBoundsDirty].
  ///
  /// Mutating a `localTransform` matrix in place (rather than
  /// reassigning it) does not automatically invalidate the cache. Call
  /// [markBoundsDirty] after any in-place transform mutation.
  vm.Aabb3? get combinedLocalBounds {
    if (_combinedBoundsCached) return _combinedBoundsCache;
    _computeAndCacheCombinedLocalBounds();
    return _combinedBoundsCache;
  }

  void _computeAndCacheCombinedLocalBounds() {
    vm.Aabb3? result;
    bool subtreeBounded = true;

    final m = mesh;
    if (m != null) {
      final mb = m.localBounds;
      if (mb != null) {
        result = vm.Aabb3.copy(mb);
      } else if (m.primitives.isNotEmpty) {
        // Mesh with primitives but no localBounds (caller-managed
        // buffers without an override, or skinned mesh imported from a
        // file with no animation data) acts as unbounded.
        subtreeBounded = false;
      }
    }

    for (final child in children) {
      final childBounds = child.combinedLocalBounds;
      if (childBounds == null) {
        subtreeBounded = false;
        continue;
      }
      final transformed = vm.Aabb3.copy(childBounds)
        ..transform(child.localTransform);
      if (result == null) {
        result = transformed;
      } else {
        result.hull(transformed);
      }
    }

    _combinedBoundsCache = subtreeBounded ? result : null;
    _combinedBoundsCached = true;
  }

  /// The subtree's axis-aligned bounds in world space, or `null` when the
  /// subtree is unbounded ([combinedLocalBounds] is `null`, e.g. skinned
  /// content or caller-managed geometry).
  ///
  /// This is [combinedLocalBounds] placed into world space with this node's
  /// [globalTransform], the same bound the renderer frustum-culls against.
  /// Handy for framing a camera on a loaded model (see
  /// [PerspectiveCamera.framing]) or sizing an effect to a model's extent,
  /// without walking vertices by hand.
  vm.Aabb3? get combinedWorldBounds {
    final bounds = combinedLocalBounds;
    if (bounds == null) return null;
    return vm.Aabb3.copy(bounds)..transform(globalTransform);
  }

  /// The nodes in this subtree (this node and its descendants, depth-first)
  /// that carry a mesh with at least one primitive.
  ///
  /// The usual entry point after loading a model, when you need the drawable
  /// nodes to read geometry back, swap materials, or attach effects. Includes
  /// this node when it has a mesh.
  Iterable<Node> get meshNodes sync* {
    final m = mesh;
    if (m != null && m.primitives.isNotEmpty) yield this;
    for (final child in children) {
      yield* child.meshNodes;
    }
  }

  /// This subtree's geometry flattened into one snapshot, with every
  /// descendant transform baked into the vertices.
  ///
  /// [transform] places the result. The default identity leaves the data in
  /// this node's local space, which is the frame a collider attached to this
  /// node expects; pass [globalTransform] for world space instead, which is
  /// the frame for a collider on a node that has none of its own.
  ///
  /// Baking matters because physics does not simulate scale, so a collider
  /// can never pick up a scale from the graph the way a mesh does. Pick the
  /// frame so that whatever the collider ends up on carries only a
  /// translation and a rotation. Runtime glTF import is the case to watch,
  /// since [fromGlbAsset] roots its model under the source handedness flip,
  /// which has to go into the vertices rather than onto the collider:
  ///
  /// ```dart
  /// final model = await Node.fromGlbAsset('assets/ground.glb');
  /// final ground = Node(name: 'ground')..add(model);
  /// ground.addComponent(
  ///   Collider(
  ///     shape: model
  ///         .extractMeshData(transform: model.localTransform)
  ///         .toTriMeshShape(),
  ///   ),
  /// );
  /// ```
  ///
  /// Scenes from [loadScene] carry that flip in their vertices already, so
  /// there the default frame is the one to use.
  ///
  /// An attribute missing from any one primitive is dropped from the whole
  /// result, since the merged mesh carries a single attribute set. Skinned
  /// geometry contributes its bind pose.
  ///
  /// Throws a [StateError] when the subtree holds no triangles, or holds
  /// geometry this cannot read: caller-managed vertex buffers
  /// (`Geometry.isReadable` is false), non-triangle primitives, or instanced
  /// meshes, none of which can be flattened into a single mesh.
  /// {@category Geometry}
  MeshData extractMeshData({Matrix4? transform}) {
    final parts = <MeshData>[];
    _collectMeshData(transform ?? Matrix4.identity(), parts);
    if (parts.isEmpty) {
      throw StateError(
        'Node "$name" has no triangle geometry in its subtree to extract',
      );
    }
    return MeshData.merge(_reduceToSharedAttributes(parts));
  }

  void _collectMeshData(Matrix4 worldTransform, List<MeshData> parts) {
    if (_instancedMeshComponents.isNotEmpty) {
      throw StateError(
        'Node "$name" carries an instanced mesh, which extractMeshData '
        'cannot flatten; build the per-instance meshes yourself',
      );
    }
    for (final component in _meshComponents) {
      for (final primitive in component.mesh.primitives) {
        final geometry = primitive.geometry;
        if (!geometry.isReadable) {
          throw StateError(
            'Node "$name" has geometry with no readable CPU data; it was '
            'built from a caller-managed vertex buffer',
          );
        }
        final data = geometry.extractMeshData();
        if (data.primitiveType != gpu.PrimitiveType.triangle) {
          throw StateError(
            'Node "$name" has ${data.primitiveType.name} geometry; '
            'extractMeshData flattens triangles only',
          );
        }
        if (data.triangleCount == 0) continue;
        parts.add(
          worldTransform.isIdentity() ? data : data.transformed(worldTransform),
        );
      }
    }
    for (final child in children) {
      child._collectMeshData(
        worldTransform.multiplied(child.localTransform),
        parts,
      );
    }
  }

  /// Strips each part down to the attributes every part carries, so
  /// [MeshData.merge] (which requires one shared attribute set) accepts them.
  static List<MeshData> _reduceToSharedAttributes(List<MeshData> parts) {
    if (parts.length == 1) return parts;
    final normals = parts.every((p) => p.normals != null);
    final texCoords = parts.every((p) => p.texCoords != null);
    final texCoords1 = parts.every((p) => p.texCoords1 != null);
    final colors = parts.every((p) => p.colors != null);
    final tangents = parts.every((p) => p.tangents != null);
    final shared = <String, int>{};
    for (final entry in parts.first.customAttributes.entries) {
      final components = entry.value.components;
      final inAll = parts.every(
        (p) => p.customAttributes[entry.key]?.components == components,
      );
      if (inAll) shared[entry.key] = components;
    }

    if (normals &&
        texCoords &&
        texCoords1 &&
        colors &&
        tangents &&
        shared.length == parts.first.customAttributes.length &&
        parts.every((p) => p.customAttributes.length == shared.length)) {
      return parts;
    }

    return [
      for (final part in parts)
        MeshData(
          positions: part.positions,
          vertexCount: part.vertexCount,
          normals: normals ? part.normals : null,
          texCoords: texCoords ? part.texCoords : null,
          texCoords1: texCoords1 ? part.texCoords1 : null,
          colors: colors ? part.colors : null,
          tangents: tangents ? part.tangents : null,
          indices: part.indices,
          primitiveType: part.primitiveType,
          customAttributes: {
            for (final name in shared.keys) name: part.customAttributes[name]!,
          },
        ),
    ];
  }

  /// Whether this node's subtree would survive frustum culling against
  /// [camera] for a render target of the given [dimensions].
  ///
  /// Returns `true` when the node is configured to opt out of culling
  /// ([frustumCulled] is `false`), when the subtree is unbounded
  /// (skinned content, or geometry without computable bounds, both of
  /// which the renderer conservatively treats as always visible), or
  /// when the world-space AABB intersects the camera frustum. Returns
  /// `false` only when there is a sound bound and it lies entirely
  /// outside the frustum.
  ///
  /// Uses [globalTransform] to place the subtree's local-space AABB
  /// into world space.
  bool isVisibleTo(Camera camera, Size dimensions) {
    if (!frustumCulled) return true;
    final bounds = combinedLocalBounds;
    if (bounds == null) return true;
    final worldAabb = vm.Aabb3.copy(bounds)..transform(globalTransform);
    return camera.getFrustum(dimensions).intersectsWithAabb3(worldAabb);
  }

  /// Mark this node's [combinedLocalBounds] cache (and every ancestor's)
  /// stale. Call after replacing a mesh, mutating a child's local
  /// transform in place, or any other change that affects the bound.
  void markBoundsDirty() {
    Node? current = this;
    while (current != null && current._combinedBoundsCached) {
      current._combinedBoundsCache = null;
      current._combinedBoundsCached = false;
      current = current._parent;
    }
  }

  /// Marks this node's transform changed: its own and its descendants'
  /// cached world transforms become stale, and its own and its
  /// ancestors' cached bounds become stale.
  ///
  /// Assigning [localTransform] does this automatically. Call it
  /// manually only after mutating the [localTransform] matrix in place.
  void markTransformDirty() {
    _markWorldTransformDirty();
    markBoundsDirty();
  }

  void _markWorldTransformDirty() {
    // An already-dirty node has an already-dirty subtree, so stop.
    if (_worldTransformDirty) return;
    _worldTransformDirty = true;
    for (final child in children) {
      child._markWorldTransformDirty();
    }
  }

  /// Whether this node is a joint in a skeleton for animation.
  bool isJoint = false;

  final List<Animation> _animations = [];

  /// Append to the parsed animation list. Used by importers (including the
  /// runtime glTF/GLB loader).
  void addParsedAnimation(Animation animation) {
    _animations.add(animation);
  }

  /// The list of animations parsed when this node was deserialized.
  ///
  /// To instantiate an animation on a node, use [createAnimationClip].
  /// To search for an animation by name, use [findAnimationByName].
  List<Animation> get parsedAnimations => _animations;

  AnimationPlayer? _animationPlayer;

  /// Searches this node's descendants for the first child whose [Node.name]
  /// matches [name].
  ///
  /// Performs a depth-first search of the subtree rooted at this node and
  /// returns the first match, or `null` if no descendant has the given name.
  ///
  /// When [excludeAnimationPlayers] is `true`, descendants that already
  /// have an animation player attached are skipped — primarily used
  /// internally to avoid recursing into clip-attached subtrees.
  Node? getChildByName(String name, {bool excludeAnimationPlayers = false}) {
    for (var child in children) {
      if (excludeAnimationPlayers && child._animationPlayer != null) {
        continue;
      }
      if (child.name == name) {
        return child;
      }
      var result = child.getChildByName(name);
      if (result != null) {
        return result;
      }
    }
    return null;
  }

  /// Searches for an [Animation] by name.
  ///
  /// Returns `null` if no animation with the specified name is found.
  ///
  /// To enumerate all animations on this node, use [parsedAnimations].
  /// Animations can be instantiated on a nodes using [createAnimationClip].
  Animation? findAnimationByName(String name) {
    return _animations.firstWhereOrNull((element) => element.name == name);
  }

  /// Instantiates [animation] as an [AnimationClip] bound to this node.
  ///
  /// The returned clip starts paused at time 0; call [AnimationClip.play] to
  /// begin playback. Multiple clips may be created on the same node and are
  /// blended together by an internal [AnimationPlayer] each frame.
  ///
  /// To enumerate animations parsed from a model, use [parsedAnimations] or
  /// [findAnimationByName].
  AnimationClip createAnimationClip(Animation animation) {
    _animationPlayer ??= AnimationPlayer();
    return _animationPlayer!.createAnimationClip(animation, this);
  }

  /// Unregisters [clip] from this node's animation player so it no longer
  /// contributes to the blend. No-op when [clip] is not registered here.
  void removeAnimationClip(AnimationClip clip) =>
      _animationPlayer?.removeClip(clip);

  /// Load a glTF binary (GLB) model directly from raw bytes.
  ///
  /// No offline conversion is required, useful for runtime use cases such
  /// as user-uploaded models, network-loaded assets, or model editors.
  /// [onWarning], when given, receives non-fatal import issues (an
  /// unrecognized extension, an image that fell back to a placeholder);
  /// without it they print instead.
  ///
  /// Example:
  /// ```dart
  /// final bytes = await rootBundle.load('assets/dash.glb');
  /// final node = await Node.fromGlbBytes(bytes.buffer.asUint8List());
  /// ```
  static Future<Node> fromGlbBytes(
    Uint8List bytes, {
    GltfWarningCallback? onWarning,
  }) {
    return importGlb(bytes, onWarning: onWarning);
  }

  /// Convenience wrapper for [fromGlbBytes] that loads from the asset bundle.
  static Future<Node> fromGlbAsset(
    String assetPath, {
    GltfWarningCallback? onWarning,
  }) async {
    final byteData = await rootBundle.load(assetPath);
    return importGlb(
      byteData.buffer.asUint8List(
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      ),
      onWarning: onWarning,
    );
  }

  /// Load a multi-file glTF model from the raw bytes of its `.gltf`
  /// (JSON) file.
  ///
  /// Multi-file glTF keeps its geometry buffer and images in separate
  /// files referenced by relative URI. [resolveUri] fetches each of
  /// those resources by URI, percent-decoded — for example downloading
  /// them relative to the `.gltf`'s own URL, or reading sibling files
  /// from disk. `data:` URIs are decoded internally and never reach
  /// [resolveUri]. A document with more than one buffer is supported;
  /// its buffers are concatenated and rebased before use. [onWarning],
  /// when given, receives non-fatal import issues; without it they
  /// print instead.
  ///
  /// For single-file `.glb` models use [fromGlbBytes] instead.
  ///
  /// Example:
  /// ```dart
  /// final node = await Node.fromGltfBytes(
  ///   gltfJsonBytes,
  ///   resolveUri: (uri) => fetchBytes('$baseUrl/$uri'),
  /// );
  /// ```
  static Future<Node> fromGltfBytes(
    Uint8List gltfJson, {
    required GltfResourceResolver resolveUri,
    GltfWarningCallback? onWarning,
  }) {
    return importGltf(gltfJson, resolveUri: resolveUri, onWarning: onWarning);
  }

  /// This list allows the node to act as a parent in the scene graph hierarchy. Transformations
  /// applied to this node, such as translation, rotation, and scaling, will also affect all child nodes.
  final List<Node> children = [];

  /// Registers this node as the root node of the scene graph.
  ///
  /// Throws an exception if the node is already a root or has a parent.
  void registerAsRoot(Scene scene) {
    name = 'root';
    if (_isSceneRoot) {
      throw Exception('Node is already a root');
    }
    if (_parent != null) {
      throw Exception('Node already has a parent');
    }
    _isSceneRoot = true;
    _mount(scene.renderScene);
  }

  /// Mounts this subtree into [renderScene] without a full [Scene].
  ///
  /// [Scene] construction touches the GPU context, which is unavailable
  /// in unit tests, so this seam lets render-lifecycle tests exercise
  /// the mount / unmount path (and the [RenderItem] registration it
  /// drives) against a bare [RenderScene].
  @visibleForTesting
  void debugMountInto(RenderScene renderScene) => _mount(renderScene);

  @override
  void add(Node child) {
    if (child._parent != null) {
      throw Exception('Child already has a parent');
    }
    children.add(child);
    child._parent = this;
    child._markWorldTransformDirty();
    final renderScene = _renderScene;
    if (renderScene != null) {
      child._mount(renderScene);
    }
    markBoundsDirty();
  }

  @override
  void addAll(Iterable<Node> children) {
    for (var child in children) {
      add(child);
    }
  }

  @override
  void addMesh(Mesh mesh) {
    final node = Node(mesh: mesh);
    add(node);
  }

  @override
  void remove(Node child) {
    if (child._parent != this) {
      throw Exception('Child is not attached to this node');
    }
    children.remove(child);
    child._parent = null;
    child._markWorldTransformDirty();
    if (child._renderScene != null) {
      child._unmount();
    }
    markBoundsDirty();
  }

  @override
  void removeAll() {
    while (children.isNotEmpty) {
      remove(children.last);
    }
  }

  /// Returns the sequence of [Node.name] values that walks from [ancestor]
  /// down to [child] through the scene graph.
  ///
  /// Useful for serializing a stable reference to a descendant node that
  /// can later be resolved with [getChildByNamePath].
  ///
  /// Returns `null` (and prints a debug warning) if [ancestor] is not an
  /// actual ancestor of [child].
  static Iterable<String>? getNamePath(Node ancestor, Node child) {
    List<String> result = [];
    Node? current = child;
    while (current != null) {
      if (identical(current, ancestor)) {
        return result.reversed;
      }
      result.add(current.name);
      current = current._parent;
    }

    debugPrint(
      'Name path formation failed because the given ancestor was not an ancestor of the given child.',
    );
    return null;
  }

  /// Returns the sequence of child indices that walks from [ancestor] down
  /// to [child] through the scene graph.
  ///
  /// Each entry is the index into the corresponding parent's [children] at
  /// that level. Useful for re-resolving a node reference on a cloned
  /// subtree (see [clone]).
  ///
  /// Returns `null` (and prints a debug warning) if [ancestor] is not an
  /// actual ancestor of [child].
  static Iterable<int>? getIndexPath(Node ancestor, Node child) {
    List<int> result = [];
    Node? current = child;
    while (current != null) {
      if (identical(current, ancestor)) {
        return result.reversed;
      }
      if (current._parent == null) {
        break;
      }
      result.add(current._parent!.children.indexOf(current));
      current = current._parent;
    }

    debugPrint(
      'Index path formation failed because the given ancestor was not an ancestor of the given child.',
    );
    return null;
  }

  /// Resolves a [namePath] (as produced by [getNamePath]) to a descendant
  /// node, or `null` if any segment does not match.
  Node? getChildByNamePath(Iterable<String> namePath) {
    Node? current = this;
    for (var name in namePath) {
      current = current!.getChildByName(name);
      if (current == null) {
        return null;
      }
    }
    return current;
  }

  /// Resolves an [indexPath] (as produced by [getIndexPath]) to a descendant
  /// node, or `null` if any segment is out of range.
  Node? getChildByIndexPath(Iterable<int> indexPath) {
    Node? current = this;
    for (var index in indexPath) {
      if (index < 0 || index >= current!.children.length) {
        return null;
      }
      current = current.children[index];
    }
    return current;
  }

  /// Returns the root node of the graph that this node is a part of.
  Node getRoot() {
    Node? current = this;
    while (current!._parent != null) {
      current = current._parent;
    }
    return current;
  }

  /// Returns the depth of this node in the scene graph hierarchy.
  /// The root node has a depth of 0.
  int getDepth() {
    int depth = 0;
    Node? current = this;
    while (current!._parent != null) {
      current = current._parent;
      depth++;
    }
    return depth;
  }

  /// Prints the hierarchy of this node and all its children to the console.
  void debugPrintHierarchy({int depth = 0}) {
    String indent = '  ' * depth;
    debugPrint('$indent$name');
    for (var child in children) {
      child.debugPrintHierarchy(depth: depth + 1);
    }
  }

  /// Creates a copy of this node.
  ///
  /// If [recursive] is `true`, the copy will include all child nodes.
  Node clone({bool recursive = true}) {
    // First, clone the node tree and collect any skins that need to be re-bound.
    List<Skin> clonedSkins = [];
    Node result = _cloneAndCollectSkins(recursive, clonedSkins);

    // Then, re-bind the skins to the cloned node tree.

    // Each of the clonedSkins currently have joint references in the old tree.
    for (var clonedSkin in clonedSkins) {
      for (
        int jointIndex = 0;
        jointIndex < clonedSkin.joints.length;
        jointIndex++
      ) {
        Node? joint = clonedSkin.joints[jointIndex];
        if (joint == null) {
          clonedSkin.joints[jointIndex] = null;
          continue;
        }

        Node? newJoint;

        // Get the index path from this node to the joint.
        Iterable<int>? nodeIndexPath = Node.getIndexPath(this, joint);
        if (nodeIndexPath != null) {
          // Then, replay the path on the cloned node tree to find the cloned
          // joint reference.
          newJoint = result.getChildByIndexPath(nodeIndexPath);
        }

        // Inline replace the joint reference with the cloned joint.
        // If the joint isn't found, a null placeholder is added.
        clonedSkin.joints[jointIndex] = newJoint;
      }
    }

    return result;
  }

  Node _cloneAndCollectSkins(bool recursive, List<Skin> clonedSkins) {
    // Clone the mesh wrapper so each instance owns its primitives (and can be
    // reskinned independently); the geometry and materials stay shared.
    Node result = Node(
      name: name,
      localTransform: localTransform.clone(),
      mesh: mesh?.clone(),
    );
    result.isJoint = isJoint;
    result._localTransformTrs = _localTransformTrs?.clone();
    result._morphWeights = _morphWeights == null
        ? null
        : Float32List.fromList(_morphWeights!);
    result._animations.addAll(_animations);
    // Components opt into cloning through [Component.cloneFor]; mesh
    // components are excluded because the mesh is already cloned through the
    // constructor above.
    for (final component in _components) {
      if (component is MeshComponent) continue;
      final copy = component.cloneFor(result);
      if (copy != null) result.addComponent(copy);
    }
    if (recursive) {
      for (var child in children) {
        result.add(child._cloneAndCollectSkins(recursive, clonedSkins));
      }
    }

    if (skin != null) {
      result.skin = Skin();
      for (Matrix4 inverseBindMatrix in skin!.inverseBindMatrices) {
        result.skin!.inverseBindMatrices.add(Matrix4.copy(inverseBindMatrix));
      }
      // Initially copy all the original joints. All of these will be replaced
      // with the cloned joints in Node.clone().
      result.skin!.joints.addAll(skin!.joints);
      clonedSkins.add(result.skin!);
    }

    return result;
  }

  /// Replaces this node's parsed animations with [animations] and re-binds any
  /// [AnimationClip]s created from the old set (matched by name), keeping
  /// their playback state.
  ///
  /// Used by scene hot reload when a reloaded scene's animations changed. The
  /// re-bind recaptures each bound node's rest pose from its current local
  /// transform; pass [restPoseOf] to supply the authored rest transform
  /// instead, so a node frozen mid-playback does not have its animated pose
  /// captured as the rest pose.
  void reloadParsedAnimations(
    List<Animation> animations, {
    Matrix4? Function(Node node)? restPoseOf,
  }) {
    _animations
      ..clear()
      ..addAll(animations);
    final player = _animationPlayer;
    if (player == null) return;
    if (restPoseOf != null) {
      for (final animation in _animations) {
        for (final channel in animation.channels) {
          final nodeName = channel.bindTarget.nodeName;
          final target = nodeName == name ? this : getChildByName(nodeName);
          if (target == null) continue;
          final pose = restPoseOf(target);
          if (pose != null) target.localTransform = pose;
        }
      }
    }
    player.rebind(this, animations: _animations);
  }

  /// Detaches this node from its parent in the scene graph.
  ///
  /// Once detached, this node is removed from its parent's list of children, effectively
  /// disconnecting this node and its subtree (all child nodes) from the scene graph.
  /// This operation is useful for temporarily removing nodes from the scene without deleting them.
  ///
  /// Throws an exception if this is the root node of the scene graph.
  /// No action is taken if the node already has no parent.
  void detach() {
    if (_isSceneRoot) {
      throw Exception('Root node cannot be detached');
    }
    final parent = _parent;
    if (parent != null) {
      parent.remove(this);
    }
  }

  /// Walks this node's subtree once per frame to prepare it for
  /// rendering: ticks components and animation players and refreshes the
  /// [RenderItem]s the render passes iterate.
  ///
  /// Called by [Scene.update] and [Scene.render]; not normally called
  /// directly. [deltaSeconds] is the elapsed time since the previous
  /// tick. [ancestorsVisible] is whether every ancestor of this node is
  /// visible, and defaults to `true` for the root.
  void scenePrePass(double deltaSeconds, [bool ancestorsVisible = true]) {
    _effectiveVisible = ancestorsVisible && visible;

    // Components tick whenever the node is mounted, independent of visibility.
    _visitMutable(_components, (component) => component.tick(deltaSeconds));

    if (_effectiveVisible) {
      _animationPlayer?.update(deltaSeconds);
      for (final meshComponent in _meshComponents) {
        meshComponent.refreshRenderItems();
      }
      for (final instancedMeshComponent in _instancedMeshComponents) {
        instancedMeshComponent.refreshRenderItem();
      }
    } else {
      // Keep a hidden subtree's items out of the render passes.
      for (final meshComponent in _meshComponents) {
        meshComponent.hideRenderItems();
      }
      for (final instancedMeshComponent in _instancedMeshComponents) {
        instancedMeshComponent.hideRenderItem();
      }
    }
    _visitMutable(
      children,
      (child) => child.scenePrePass(deltaSeconds, _effectiveVisible),
    );

    // After the subtree, so anything correcting an animated pose sees the
    // pose it is correcting. Empty for almost every node, so the common case
    // is one list check.
    if (_lateComponents.isNotEmpty) {
      _visitMutable(
        _lateComponents,
        (component) => component.lateTick(deltaSeconds),
      );
    }
  }

  /// Walks this node's subtree once per physics substep and dispatches
  /// [Component.fixedTick] to every component.
  ///
  /// Called by [Scene]'s fixed-step driver inside its substepping loop,
  /// before the physics world's step. Traversal order is parent before
  /// children, matching [scenePrePass].
  void sceneFixedPass(double fixedDt) {
    _visitMutable(_components, (component) => component.fixedTick(fixedDt));
    _visitMutable(children, (child) => child.sceneFixedPass(fixedDt));
  }
}
