import 'dart:ui' hide Scene;

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' hide Matrix4;
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:flutter_scene/animation.dart';
import 'package:flutter_scene/geometry/geometry.dart';
import 'package:flutter_scene/material/material.dart';
import 'package:flutter_scene/material/unlit_material.dart';
import 'package:flutter_scene/mesh.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene/scene_encoder.dart';
import 'package:flutter_scene/skin.dart';
import 'package:flutter_scene_importer/flatbuffer.dart' as fb;
import 'package:flutter_scene_importer/importer.dart';
import 'package:vector_math/vector_math.dart';

/// A `Node` represents a single element in a 3D scene graph.
///
/// Each node can contain a transform (position, rotation, scale), a mesh (3D geometry and material),
/// and child nodes. Nodes are used to build complex scenes by establishing relationships
/// between different elements, allowing for transformations to propagate down the hierarchy.
base class Node implements SceneGraph {
  Node({String? name, Matrix4? localTransform, this.mesh})
      : localTransform = localTransform ?? Matrix4.identity();

  /// The name of this node, used for identification.
  String name = '';

  /// The transformation matrix representing the node's position, rotation, and scale relative to the parent node.
  ///
  /// If the node does not have a parent, `localTransform` and [globalTransform] share the same transformation matrix instance.
  Matrix4 localTransform = Matrix4.identity();

  Skin? _skin;

  set globalTransform(Matrix4 transform) {
    if (_parent == null) {
      localTransform = transform;
    } else {
      Matrix4 g = Matrix4.identity();
      _parent!.globalTransform.copyInverse(g);

      localTransform = transform * _parent!.globalTransform.invert();
    }
  }

  /// The transformation matrix representing the node's position, rotation, and scale in world space.
  ///
  /// If the node does not have a parent, `globalTransform` and [localTransform] share the same transformation matrix instance.
  Matrix4 get globalTransform {
    if (_parent == null) {
      return localTransform;
    }
    return localTransform * _parent!.globalTransform;
  }

  Node? _parent;

  /// The parent node of this node in the scene graph.
  Node? get parent => _parent;
  bool _isRoot = false;

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

  Node? findChildByName(String name, {bool excludeAnimationPlayers = false}) {
    for (var child in children) {
      if (excludeAnimationPlayers && child._animationPlayer != null) {
        continue;
      }
      if (child.name == name) {
        return child;
      }
      var result = child.findChildByName(name);
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
    return _animationPlayer!.addAnimation(animation, this);
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
  static Node fromFlatbuffer(ByteData byteData) {
    ImportedScene importedScene = ImportedScene.fromFlatbuffer(byteData);
    fb.Scene fbScene = importedScene.flatbuffer;

    debugPrint('Unpacking Scene (nodes: ${fbScene.nodes?.length}, '
        'textures: ${fbScene.textures?.length})');

    // Unpack textures.
    List<gpu.Texture> textures = [];
    for (fb.Texture fbTexture in fbScene.textures ?? []) {
      fb.EmbeddedImage image = fbTexture.embeddedImage!;
      gpu.Texture? texture = gpu.gpuContext.createTexture(
          gpu.StorageMode.hostVisible, image.width, image.height);
      if (texture == null) {
        throw Exception('Failed to allocate texture');
      }
      Uint8List textureData = image.bytes! as Uint8List;
      if (!texture.overwrite(ByteData.sublistView(textureData))) {
        throw Exception('Failed to overwrite texture data');
      }
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
    if (_isRoot) {
      throw Exception('Node is already a root');
    }
    if (_parent != null) {
      throw Exception('Node already has a parent');
    }
    _isRoot = true;
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

  /// Detaches this node from its parent in the scene graph.
  ///
  /// Once detached, this node is removed from its parent's list of children, effectively
  /// disconnecting this node and its subtree (all child nodes) from the scene graph.
  /// This operation is useful for temporarily removing nodes from the scene without deleting them.
  ///
  /// Throws an exception if this is the root node of the scene graph.
  /// No action is taken if the node already has no parent.
  void detach() {
    if (_isRoot) {
      throw Exception('Root node cannot be detached');
    }
    if (_parent != null) {
      _parent!.remove(this);
    }
  }

  /// Recursively records [Mesh] draw operations for this node and all its children.
  ///
  /// To display this node in a `dart:ui` [Canvas], add this node to a [Scene] and call [Scene.render] instead.
  void render(SceneEncoder encoder, Matrix4 parentWorldTransform) {
    if (_animationPlayer != null) {
      _animationPlayer!.update();
    }

    final worldTransform = localTransform * parentWorldTransform;
    if (mesh != null) {
      mesh!.render(encoder, worldTransform, _skin?.getJointsTexture(),
          _skin?.getTextureWidth() ?? 0);
    }
    for (var child in children) {
      child.render(encoder, worldTransform);
    }
  }
}
