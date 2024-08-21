import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' hide Matrix4;
import 'package:vector_math/vector_math.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;

import 'package:flutter_scene/geometry/geometry.dart';
import 'package:flutter_scene/material/material.dart';
import 'package:flutter_scene/material/unlit_material.dart';
import 'package:flutter_scene/mesh.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene/skin.dart';
import 'package:flutter_scene/scene_encoder.dart';
import 'package:flutter_scene_importer/importer.dart';
import 'package:flutter_scene_importer/flatbuffer.dart' as fb;

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

  /// The collection of vertices, edges, and faces that represent the geometry of this node,
  /// along with the material that defines the object's appearance.
  ///
  /// The mesh defines the shape of the object through its geometry, which is composed of vertices,
  /// edges, and faces. The mesh may also include a material, which specifies how the surface
  /// of the object interacts with light, including properties like color, texture, and reflectivity.
  Mesh? mesh;

  /// Whether this node is a joint in a skeleton for animation.
  bool isJoint = false;

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

  /// FlatBuffers are a compact binary serialization format, commonly used for efficiently storing complex 3D data.
  ///
  /// If you have a file containing your 3d model, consider using [fromAsset] instead.
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

    // TODO(bdero): Unpack animations.

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

  /// Prepares and renders this node and its children within the scene graph.
  ///
  /// This method calculates the final world transform for the node by combining the
  /// parent's world transform with the node's local transform. It then renders the node's
  /// mesh primitives using the provided `SceneEncoder`, and recursively renders all child nodes.
  ///
  /// The rendering process involves encoding the node's geometry and material data into commands
  /// that are passed to the GPU for drawing. If the node has associated skinning data (for animated models),
  /// this data is also passed along to the rendering pipeline.
  void render(SceneEncoder encoder, Matrix4 parentWorldTransform) {
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
