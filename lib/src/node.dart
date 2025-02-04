import 'dart:ui' hide Scene;

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' hide Matrix4;
import 'package:flutter_gpu/gpu.dart' as gpu;
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

/// A `Node` represents a single element in a 3D scene graph.
///
/// Each node can contain a transform (position, rotation, scale), a mesh (3D geometry and material),
/// and child nodes. Nodes are used to build complex scenes by establishing relationships
/// between different elements, allowing for transformations to propagate down the hierarchy.
base class Node implements SceneGraph {
  Node({this.name = '', Matrix4? localTransform, this.mesh})
      : localTransform = localTransform ?? Matrix4.identity();

  /// The name of this node, used for identification.
  String name;

  /// Whether this node is visible in the scene. If false, the node and its children will not be rendered.
  bool visible = true;

  /// The transformation matrix representing the node's position, rotation, and scale relative to the parent node.
  ///
  /// If the node does not have a parent, `localTransform` and [globalTransform] share the same transformation matrix instance.
  Matrix4 localTransform = Matrix4.identity();

  Skin? _skin;

  set globalTransform(Matrix4 transform) {
    final parent = _parent;
    if (parent == null) {
      localTransform = transform;
    } else {
      Matrix4 g = Matrix4.identity();
      parent.globalTransform.copyInverse(g);

      localTransform = transform * parent.globalTransform.invert();
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
    return localTransform * parent.globalTransform;
  }

  Node? _parent;

  /// The parent node of this node in the scene graph.
  Node? get parent => _parent;
  bool _isSceneRoot = false;

  /// The collection of [MeshPrimitive] objects that represent the 3D geometry and material properties of this node.
  ///
  /// This property is `null` if this node does not have any associated geometry or material.
  Mesh? mesh;

  /// Whether this node is a joint in a skeleton for animation.
  bool isJoint = false;

  final List<Animation> _animations = [];

  /// The list of animations parsed when this node was deserialized.
  ///
  /// To instantiate an animation on a node, use [createAnimationClip].
  /// To search for an animation by name, use [findAnimationByName].
  List<Animation> get parsedAnimations => _animations;

  AnimationPlayer? _animationPlayer;

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

  /// Deserialize a model from Flutter Scene's compact model format.
  ///
  /// If you're using [Flutter Scene's offline importer tool](https://pub.dev/packages/flutter_scene_importer),
  /// consider using [fromAsset] to load the model directly from the asset bundle instead.
  static Future<Node> fromFlatbuffer(ByteData byteData) async {
    ImportedScene importedScene = ImportedScene.fromFlatbuffer(byteData);
    fb.Scene fbScene = importedScene.flatbuffer;

    debugPrint('Unpacking Scene (nodes: ${fbScene.nodes?.length}, '
        'textures: ${fbScene.textures?.length})');

    // Unpack textures.
    List<gpu.Texture> textures = [];
    for (fb.Texture fbTexture in fbScene.textures ?? []) {
      if (fbTexture.embeddedImage == null) {
        if (fbTexture.uri == null) {
          debugPrint(
              'Texture ${textures.length} has no embedded image or URI. A white placeholder will be used instead.');
          textures.add(Material.getWhitePlaceholderTexture());
          continue;
        }
        try {
          // If the texture has a URI, try to load it from the asset bundle.
          textures.add(await gpuTextureFromAsset(fbTexture.uri!));
          continue;
        } catch (e) {
          debugPrint('Failed to load texture from asset URI: ${fbTexture.uri}. '
              'A white placeholder will be used instead. (Error: $e)');
          textures.add(Material.getWhitePlaceholderTexture());
          continue;
        }
      }
      fb.EmbeddedImage image = fbTexture.embeddedImage!;
      gpu.Texture texture = gpu.gpuContext.createTexture(
          gpu.StorageMode.hostVisible, image.width, image.height);
      Uint8List textureData = image.bytes! as Uint8List;
      texture.overwrite(ByteData.sublistView(textureData));
      textures.add(texture);
    }

    Node result = Node(
        name: 'root',
        localTransform: fbScene.transform?.toMatrix4() ?? Matrix4.identity());

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
          fbScene.nodes![nodeIndex], sceneNodes, textures);
    }

    // Unpack animations.
    if (fbScene.animations != null) {
      for (fb.Animation fbAnimation in fbScene.animations!) {
        result._animations
            .add(Animation.fromFlatbuffer(fbAnimation, sceneNodes));
      }
    }

    return result;
  }

  void _unpackFromFlatbuffer(
      fb.Node fbNode, List<Node> sceneNodes, List<gpu.Texture> textures) {
    name = fbNode.name ?? '';
    localTransform = fbNode.transform?.toMatrix4() ?? Matrix4.identity();

    // Unpack mesh.
    if (fbNode.meshPrimitives != null) {
      List<MeshPrimitive> meshPrimitives = [];
      for (fb.MeshPrimitive fbPrimitive in fbNode.meshPrimitives!) {
        Geometry geometry = Geometry.fromFlatbuffer(fbPrimitive);
        Material material = fbPrimitive.material != null
            ? Material.fromFlatbuffer(fbPrimitive.material!, textures)
            : UnlitMaterial();
        meshPrimitives.add(MeshPrimitive(geometry, material));
      }
      mesh = Mesh.primitives(primitives: meshPrimitives);
    }

    // Connect children.
    for (int childIndex in fbNode.children ?? []) {
      if (childIndex < 0 || childIndex >= sceneNodes.length) {
        throw Exception('Node child index out of range.');
      }
      add(sceneNodes[childIndex]);
    }

    // Skin.
    if (fbNode.skin != null) {
      _skin = Skin.fromFlatbuffer(fbNode.skin!, sceneNodes);
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
  }

  @override
  void removeAll() {
    while (children.isNotEmpty) {
      remove(children.last);
    }
  }

  /// Returns the name lookup path from the ancestor node to the child node.
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
        'Name path formation failed because the given ancestor was not an ancestor of the given child.');
    return null;
  }

  /// Returns the index lookup path from the ancestor node to the child node.
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
        'Index path formation failed because the given ancestor was not an ancestor of the given child.');
    return null;
  }

  /// Returns the child node at the specified name path.
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

  /// Returns the child node at the specified index path.
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
      for (int jointIndex = 0;
          jointIndex < clonedSkin.joints.length;
          jointIndex++) {
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

    if (_skin != null) {
      result._skin = Skin();
      for (Matrix4 inverseBindMatrix in _skin!.inverseBindMatrices) {
        result._skin!.inverseBindMatrices.add(Matrix4.copy(inverseBindMatrix));
      }
      // Initially copy all the original joints. All of these will be replaced
      // with the cloned joints in Node.clone().
      result._skin!.joints.addAll(_skin!.joints);
      clonedSkins.add(result._skin!);
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
      mesh!.render(encoder, worldTransform, _skin?.getJointsTexture(),
          _skin?.getTextureWidth() ?? 0);
    }
    for (var child in children) {
      child.render(encoder, worldTransform);
    }
  }
}
