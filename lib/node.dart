import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' hide Matrix4;
import 'package:vector_math/vector_math.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;

import 'package:flutter_scene/geometry/geometry.dart';
import 'package:flutter_scene/material/material.dart';
import 'package:flutter_scene/material/mesh_unlit_material.dart';
import 'package:flutter_scene/mesh.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene/scene_encoder.dart';
import 'package:flutter_scene_importer/importer.dart';
import 'package:flutter_scene_importer/flatbuffer.dart' as fb;

base class Node implements SceneGraph {
  Node({String? name, Matrix4? localTransform, this.mesh})
      : localTransform = localTransform ?? Matrix4.identity();

  String name = '';

  Matrix4 localTransform = Matrix4.identity();

  Node? _parent;
  bool _isRoot = false;

  Mesh? mesh;

  static Future<Node> fromAsset(String assetPath) async {
    final buffer = await rootBundle.load(assetPath);
    return fromFlatbuffer(buffer);
  }

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
    for (fb.Node fbNode in fbScene.nodes ?? []) {
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
            : MeshUnlitMaterial();
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

    // TODO(bdero): Unpack skin.
  }

  final List<Node> children = [];

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

  void detach() {
    if (_isRoot) {
      throw Exception('Root node cannot be detached');
    }
    if (_parent != null) {
      _parent!.remove(this);
    }
  }

  void render(SceneEncoder encoder, Matrix4 parentWorldTransform) {
    final worldTransform = localTransform * parentWorldTransform;
    if (mesh != null) {
      mesh!.render(encoder, worldTransform);
    }
    for (var child in children) {
      child.render(encoder, worldTransform);
    }
  }
}
