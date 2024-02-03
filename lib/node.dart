import 'package:flutter_scene/mesh.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';

base class Node implements SceneGraph {
  Node({localTransform, this.mesh})
      : localTransform = localTransform ?? Matrix4.identity();

  Matrix4 localTransform = Matrix4.identity();

  Node? _parent;
  bool _isRoot = false;

  Mesh? mesh;

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
