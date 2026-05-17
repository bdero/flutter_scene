import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' hide Matrix4;
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/camera.dart';
import 'package:flutter_scene/src/components/component.dart';
import 'package:flutter_scene/src/components/instanced_mesh_component.dart';
import 'package:flutter_scene/src/components/mesh_component.dart';
import 'package:flutter_scene/src/runtime_importer/runtime_importer.dart';
import 'package:flutter_scene/src/scene.dart';
import 'package:flutter_scene/src/animation.dart';
import 'package:flutter_scene/src/asset_helpers.dart';
import 'package:flutter_scene/src/geometry/geometry.dart';
import 'package:flutter_scene/src/material/material.dart';
import 'package:flutter_scene/src/material/unlit_material.dart';
import 'package:flutter_scene/src/mesh.dart';
import 'package:flutter_scene/src/render/render_scene.dart';
import 'package:flutter_scene/src/skin.dart';
import 'package:flutter_scene_importer/flatbuffer.dart' as fb;
import 'package:flutter_scene_importer/importer.dart';
import 'package:vector_math/vector_math.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// A `Node` represents a single element in a 3D scene graph.
///
/// Each node can contain a transform (position, rotation, scale), a mesh (3D geometry and material),
/// and child nodes. Nodes are used to build complex scenes by establishing relationships
/// between different elements, allowing for transformations to propagate down the hierarchy.
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

  Matrix4 _localTransform;

  /// The transform of this node relative to its parent: position,
  /// rotation, and scale.
  ///
  /// Assigning marks this node and its descendants' cached world
  /// transforms stale, and this node and its ancestors' cached bounds
  /// stale. Mutating the returned matrix in place does not, so call
  /// [markTransformDirty] after an in-place edit.
  Matrix4 get localTransform => _localTransform;
  set localTransform(Matrix4 value) {
    _localTransform = value;
    markTransformDirty();
  }

  // Cached world-space transform, valid while _worldTransformDirty is
  // false. Recomputed lazily by globalTransform and by the render walk.
  final Matrix4 _worldTransform = Matrix4.identity();
  bool _worldTransformDirty = true;

  /// The skin attached to this node, used for skeletal animation. Set by
  /// importers (both the offline .model path and the runtime glTF/GLB loader).
  Skin? skin;

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
      // the receiver — `copyInverse` is the non-destructive version.)
      final parentInverse = Matrix4.identity();
      parent.globalTransform.copyInverse(parentInverse);
      localTransform = parentInverse * transform;
    }
  }

  /// The world-space transform of this node, with every ancestor's
  /// transform applied.
  ///
  /// Cached: O(1) when the cache is current, recomputed up the parent
  /// chain only after a transform change.
  Matrix4 get globalTransform {
    if (!_worldTransformDirty) return _worldTransform;
    final parent = _parent;
    if (parent == null) {
      _worldTransform.setFrom(_localTransform);
    } else {
      _worldTransform
        ..setFrom(parent.globalTransform)
        ..multiply(_localTransform);
    }
    _worldTransformDirty = false;
    return _worldTransform;
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

  // The components attached to this node, in attach order.
  final List<Component> _components = [];

  // Typed fast paths: the subsets of [_components] that feed the render
  // layer, so the per-frame pre-pass refreshes their render items
  // without scanning the full component list.
  final List<MeshComponent> _meshComponents = [];
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
    for (final component in _components) {
      component.mount();
    }
    for (final child in children) {
      child._mount(renderScene);
    }
  }

  void _unmount() {
    for (final child in children) {
      child._unmount();
    }
    for (final component in _components) {
      component.unmount();
    }
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

  /// The asset file should be in a format that can be converted to a scene graph node.
  ///
  /// Flutter Scene uses a specialized 3D model format (`.model`) internally.
  /// You can convert standard glTF binaries (`.glb` files) to this format using [Flutter Scene's offline importer tool](https://pub.dev/packages/flutter_scene_importer).
  ///
  /// Example:
  /// ```dart
  /// final node = await Node.fromAsset('path/to/asset.model');
  /// ```
  static Future<Node> fromAsset(String assetPath) async {
    final buffer = await rootBundle.load(assetPath);
    return fromFlatbuffer(buffer);
  }

  /// Load a glTF binary (GLB) model directly from raw bytes.
  ///
  /// Unlike [fromAsset], no offline conversion to `.model` is required —
  /// useful for runtime use cases such as user-uploaded models, network-loaded
  /// assets, or model editors.
  ///
  /// Example:
  /// ```dart
  /// final bytes = await rootBundle.load('assets/dash.glb');
  /// final node = await Node.fromGlbBytes(bytes.buffer.asUint8List());
  /// ```
  static Future<Node> fromGlbBytes(Uint8List bytes) {
    return importGlb(bytes);
  }

  /// Load a single-file `.glb` model from a [Stream] of byte chunks.
  ///
  /// Convenience wrapper for [fromGlbBytes] that drains the stream
  /// into a single buffer before parsing. Useful when the caller has
  /// a `Stream<List<int>>` (e.g. an `http` response body, a `dart:io`
  /// `File.openRead()` pipe, or a websocket frame source) but not the
  /// full byte buffer up-front.
  ///
  /// This factory buffers the entire stream in memory before
  /// delegating to [fromGlbBytes] — peak memory equals the full GLB
  /// size, matching [fromGlbBytes] semantics. True incremental
  /// parsing of the GLB container is out of scope for this factory.
  ///
  /// Accepts `Stream<List<int>>` for compatibility with `dart:io` and
  /// `package:http`; `Stream<Uint8List>` callers also work since
  /// `Uint8List` implements `List<int>`.
  ///
  /// ```dart
  /// final response = await http.Client().send(http.Request('GET', url));
  /// final node = await Node.fromGlbStream(response.stream);
  /// ```
  static Future<Node> fromGlbStream(Stream<List<int>> stream) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      builder.add(chunk);
    }
    return fromGlbBytes(builder.toBytes());
  }

  /// Convenience wrapper for [fromGlbBytes] that loads from the asset bundle.
  static Future<Node> fromGlbAsset(String assetPath) async {
    final byteData = await rootBundle.load(assetPath);
    return importGlb(
      byteData.buffer.asUint8List(
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      ),
    );
  }

  /// Load a multi-file glTF model from the raw bytes of its `.gltf`
  /// (JSON) file.
  ///
  /// Multi-file glTF keeps its geometry buffer and images in separate
  /// files referenced by relative URI. [resolveUri] fetches each of
  /// those resources by URI — for example downloading them relative to
  /// the `.gltf`'s own URL, or reading sibling files from disk.
  /// `data:` URIs are decoded internally and never reach [resolveUri].
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
  }) {
    return importGltf(gltfJson, resolveUri: resolveUri);
  }

  /// Deserialize a model from Flutter Scene's compact model format.
  ///
  /// If you're using [Flutter Scene's offline importer tool](https://pub.dev/packages/flutter_scene_importer),
  /// consider using [fromAsset] to load the model directly from the asset bundle instead.
  static Future<Node> fromFlatbuffer(ByteData byteData) async {
    ImportedScene importedScene = ImportedScene.fromFlatbuffer(byteData);
    fb.Scene fbScene = importedScene.flatbuffer;

    debugPrint(
      'Unpacking Scene (nodes: ${fbScene.nodes?.length}, '
      'textures: ${fbScene.textures?.length})',
    );

    // Unpack textures.
    List<gpu.Texture> textures = [];
    for (fb.Texture fbTexture in fbScene.textures ?? []) {
      if (fbTexture.embeddedImage == null) {
        if (fbTexture.uri == null) {
          debugPrint(
            'Texture ${textures.length} has no embedded image or URI. A white placeholder will be used instead.',
          );
          textures.add(Material.getWhitePlaceholderTexture());
          continue;
        }
        try {
          // If the texture has a URI, try to load it from the asset bundle.
          textures.add(await gpuTextureFromAsset(fbTexture.uri!));
          continue;
        } catch (e) {
          debugPrint(
            'Failed to load texture from asset URI: ${fbTexture.uri}. '
            'A white placeholder will be used instead. (Error: $e)',
          );
          textures.add(Material.getWhitePlaceholderTexture());
          continue;
        }
      }
      fb.EmbeddedImage image = fbTexture.embeddedImage!;
      gpu.Texture texture = gpu.gpuContext.createTexture(
        gpu.StorageMode.hostVisible,
        image.width,
        image.height,
      );
      Uint8List textureData = image.bytes! as Uint8List;
      texture.overwrite(ByteData.sublistView(textureData));
      textures.add(texture);
    }

    Node result = Node(
      name: 'root',
      localTransform: fbScene.transform?.toMatrix4() ?? Matrix4.identity(),
    );

    if (fbScene.nodes == null || fbScene.children == null) {
      return result; // The scene is empty. ¯\_(ツ)_/¯
    }

    // Initialize nodes for unpacking the entire scene.
    List<Node> sceneNodes = [];
    for (fb.Node _ in fbScene.nodes ?? []) {
      sceneNodes.add(Node());
    }

    // Connect children to the root node.
    for (int childIndex in fbScene.children ?? []) {
      if (childIndex < 0 || childIndex >= sceneNodes.length) {
        throw Exception('Scene child index out of range.');
      }
      result.add(sceneNodes[childIndex]);
    }

    // Unpack each node.
    for (int nodeIndex = 0; nodeIndex < sceneNodes.length; nodeIndex++) {
      sceneNodes[nodeIndex]._unpackFromFlatbuffer(
        fbScene.nodes![nodeIndex],
        sceneNodes,
        textures,
      );
    }

    // Unpack animations.
    if (fbScene.animations != null) {
      for (fb.Animation fbAnimation in fbScene.animations!) {
        result._animations.add(
          Animation.fromFlatbuffer(fbAnimation, sceneNodes),
        );
      }
    }

    return result;
  }

  void _unpackFromFlatbuffer(
    fb.Node fbNode,
    List<Node> sceneNodes,
    List<gpu.Texture> textures,
  ) {
    name = fbNode.name ?? '';
    // Assign the private field directly: the node is still being built,
    // and it already starts out transform-dirty.
    _localTransform = fbNode.transform?.toMatrix4() ?? Matrix4.identity();

    // Unpack mesh. Attach the mesh component directly: the node is still
    // being built and not yet mounted, so skip addComponent's mount and
    // bounds-invalidation path. The baked combined AABB is installed
    // below.
    if (fbNode.meshPrimitives != null) {
      List<MeshPrimitive> meshPrimitives = [];
      for (fb.MeshPrimitive fbPrimitive in fbNode.meshPrimitives!) {
        Geometry geometry = Geometry.fromFlatbuffer(fbPrimitive);
        Material material =
            fbPrimitive.material != null
                ? Material.fromFlatbuffer(fbPrimitive.material!, textures)
                : UnlitMaterial();
        meshPrimitives.add(MeshPrimitive(geometry, material));
      }
      final meshComponent = MeshComponent(
        Mesh.primitives(primitives: meshPrimitives),
      );
      _components.add(meshComponent);
      _meshComponents.add(meshComponent);
      meshComponent.attachTo(this);
    }

    // Connect children. Same private-field assignment to avoid
    // ancestor-chain invalidation churn while building the graph.
    for (int childIndex in fbNode.children ?? []) {
      if (childIndex < 0 || childIndex >= sceneNodes.length) {
        throw Exception('Node child index out of range.');
      }
      final child = sceneNodes[childIndex];
      if (child._parent != null) {
        throw Exception('Child already has a parent');
      }
      children.add(child);
      child._parent = this;
    }

    // Skin.
    if (fbNode.skin != null) {
      skin = Skin.fromFlatbuffer(fbNode.skin!, sceneNodes);
    }

    // Adopt the baked combined-local AABB when present so we don't
    // recompute it at runtime. When omitted (older files, or the bake
    // determined the subtree was unbounded), fall through to the lazy
    // compute path on first access.
    final fbAabb = fbNode.combinedLocalAabb;
    if (fbAabb != null) {
      _combinedBoundsCache = vm.Aabb3.minMax(
        Vector3(fbAabb.min.x, fbAabb.min.y, fbAabb.min.z),
        Vector3(fbAabb.max.x, fbAabb.max.y, fbAabb.max.z),
      );
      _combinedBoundsCached = true;
    }
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
    Node result = Node(name: name, localTransform: localTransform, mesh: mesh);
    result.isJoint = isJoint;
    result._animations.addAll(_animations);
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

    // Components tick whenever the node is mounted, independent of
    // visibility. An index loop tolerates a component adding or removing
    // a sibling component during its own update.
    for (int i = 0; i < _components.length; i++) {
      _components[i].tick(deltaSeconds);
    }

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
    for (final child in children) {
      child.scenePrePass(deltaSeconds, _effectiveVisible);
    }
  }
}
