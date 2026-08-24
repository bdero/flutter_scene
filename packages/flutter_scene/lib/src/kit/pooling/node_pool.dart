import 'package:flutter_scene/src/node.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// High-performance object recycler for transient nodes (projectiles, damage numbers, effects).
/// {@category Gameplay kit}
class NodePool {
  /// Factory function creating a new node instance when the idle pool is exhausted.
  final Node Function() factory;

  /// Maximum number of idle nodes retained in the pool for reuse.
  final int maxSize;

  final List<Node> _idle = [];
  final Set<Node> _active = {};

  /// Creates a node pool, pre-warming [initialSize] idle instances.
  NodePool(this.factory, {int initialSize = 8, this.maxSize = 128}) {
    for (var i = 0; i < initialSize; i++) {
      _idle.add(factory());
    }
  }

  /// Number of currently active spawned nodes.
  int get activeCount => _active.length;

  /// Number of pre-warmed idle nodes ready for immediate reuse.
  int get idleCount => _idle.length;

  /// Total count of managed nodes (active + idle).
  int get totalCount => _active.length + _idle.length;

  /// Acquires a node from the pool and attaches it to [parent].
  Node spawn({
    Node? parent,
    vm.Matrix4? transform,
    void Function(Node node)? onSpawn,
  }) {
    final Node node;
    if (_idle.isNotEmpty) {
      node = _idle.removeLast();
    } else {
      node = factory();
    }

    if (transform != null) {
      node.localTransform = transform.clone();
    }

    if (parent != null) {
      parent.add(node);
    }

    _active.add(node);
    onSpawn?.call(node);
    return node;
  }

  /// Returns [node] back to the idle pool, removing it from its parent.
  ///
  /// If the idle pool has reached [maxSize], excess nodes are dropped for garbage collection.
  void despawn(Node node) {
    if (!_active.remove(node)) return;

    final parent = node.parent;
    if (parent != null) {
      parent.remove(node);
    }

    if (_idle.length < maxSize) {
      _idle.add(node);
    }
  }

  /// Despawns all active nodes managed by this pool.
  void despawnAll() {
    final activeList = List.of(_active);
    for (final node in activeList) {
      despawn(node);
    }
  }
}
