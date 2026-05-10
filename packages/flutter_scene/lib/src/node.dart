import 'dart:ui' hide Scene;

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' hide Matrix4;
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/runtime_importer/runtime_importer.dart';
import 'package:flutter_scene/src/scene.dart';
import 'package:flutter_scene/src/animation.dart';
import 'package:flutter_scene/src/asset_helpers.dart';
import 'package:flutter_scene/src/geometry/geometry.dart';
import 'package:flutter_scene/src/material/material.dart';
import 'package:flutter_scene/src/material/unlit_material.dart';
import 'package:flutter_scene/src/mesh.dart';
import 'package:flutter_scene/src/scene_encoder.dart';
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
  /// node has no associated geometry.
  Node({this.name = '', Matrix4? localTransform, Mesh? mesh})
    : localTransform = localTransform ?? Matrix4.identity(),
      _mesh = mesh;

  /// The name of this node, used for identification.
  String name;

  /// Whether this node is visible in the scene. If false, the node and its children will not be rendered.
  bool visible = true;

  /// The transformation matrix representing the node's position, rotation, and scale relative to the parent node.
  ///
  /// If the node does not have a parent, `localTransform` and [globalTransform] share the same transformation matrix instance.
  Matrix4 localTransform = Matrix4.identity();

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

  /// The transformation matrix representing the node's position, rotation, and scale in world space.
  ///
  /// If the node does not have a parent, `globalTransform` and [localTransform] share the same transformation matrix instance.
  Matrix4 get globalTransform {
    final parent = _parent;
    if (parent == null) {
      return localTransform;
    }
    return parent.globalTransform * localTransform;
  }

  Node? _parent;

  /// The parent node of this node in the scene graph.
  Node? get parent => _parent;
  bool _isSceneRoot = false;

  Mesh? _mesh;

  /// The collection of [MeshPrimitive] objects that represent the 3D geometry and material properties of this node.
  ///
  /// This property is `null` if this node does not have any associated geometry or material.
  Mesh? get mesh => _mesh;
  set mesh(Mesh? value) {
    if (identical(_mesh, value)) return;
    _mesh = value;
    markBoundsDirty();
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
    // A node with a skin can't be soundly bounded by its bind-pose
    // mesh extents; the rendered pose can extend arbitrarily far when
    // joints animate. PR 3 will replace this branch with a baked
    // pose-union AABB.
    if (skin != null) {
      _combinedBoundsCache = null;
      _combinedBoundsCached = true;
      return;
    }

    vm.Aabb3? result;
    bool subtreeBounded = true;

    final m = _mesh;
    if (m != null) {
      final mb = m.localBounds;
      if (mb != null) {
        result = vm.Aabb3.copy(mb);
      } else if (m.primitives.isNotEmpty) {
        // Mesh with primitives but no localBounds (caller-managed
        // buffers without an override) acts as unbounded.
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
    localTransform = fbNode.transform?.toMatrix4() ?? Matrix4.identity();

    // Unpack mesh. Assign through the private field so we don't trip
    // markBoundsDirty before we install the baked combined AABB below.
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
      _mesh = Mesh.primitives(primitives: meshPrimitives);
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
  }

  @override
  void add(Node child) {
    if (child._parent != null) {
      throw Exception('Child already has a parent');
    }
    children.add(child);
    child._parent = this;
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

  /// Recursively records [Mesh] draw operations for this node and all its children.
  ///
  /// To display this node in a `dart:ui` [Canvas], add this node to a [Scene] and call [Scene.render] instead.
  void render(SceneEncoder encoder, Matrix4 parentWorldTransform) {
    if (!visible) {
      return;
    }

    if (_animationPlayer != null) {
      _animationPlayer!.update();
    }

    final worldTransform = parentWorldTransform * localTransform;
    if (mesh != null) {
      mesh!.render(
        encoder,
        worldTransform,
        skin?.getJointsTexture(),
        skin?.getTextureWidth() ?? 0,
      );
    }
    for (var child in children) {
      child.render(encoder, worldTransform);
    }
  }
}
