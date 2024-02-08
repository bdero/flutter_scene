import 'package:flutter/services.dart' hide Matrix4;
import 'package:flutter_scene/mesh.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;

import 'package:flutter_scene/generated/scene_impeller.fb_flatbuffers.dart'
    as fb;

base class Node implements SceneGraph {
  Node({localTransform, this.mesh})
      : localTransform = localTransform ?? Matrix4.identity();

  Matrix4 localTransform = Matrix4.identity();

  Node? _parent;
  bool _isRoot = false;

  Mesh? mesh;

  static Future<Node> fromAsset(String asset) {
    return rootBundle.loadStructuredBinaryData<Node>(asset, (data) {
      return fromFlatbuffer(data);
    });
  }

  static Node fromFlatbuffer(ByteData byteData) {
    fb.Scene fbScene = fb.Scene(byteData.buffer.asInt8List());

    List<gpu.Texture> textures = [];
    for (fb.Texture fbTexture in fbScene.textures ?? []) {
      fb.EmbeddedImage image = fbTexture.embeddedImage!;
      gpu.Texture? texture = gpu.gpuContext.createTexture(
          gpu.StorageMode.hostVisible, image.width, image.height);
      if (texture == null) {
        throw Exception('Failed to allocate texture');
      }
      // TODO(bdero): 🤮
      Uint8List texture_data = Uint8List.fromList(image.bytes!);
      if (!texture.overwrite(texture_data.buffer.asByteData())) {
        throw Exception('Failed to overwrite texture data');
      }
      textures.add(texture);
    }

    return Node();
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
