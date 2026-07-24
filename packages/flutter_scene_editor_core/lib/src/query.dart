/// Read-only perception queries over a [SceneDocument].
///
/// The UI and the MCP perception tools both read the scene through this one
/// surface, so they always see the same structure by stable id. Queries never
/// mutate; edits go through commands.
library;

import 'package:scene/scene.dart';

/// Read-only navigation and lookup over a document's scene graph.
class SceneQuery {
  /// Creates a query over [document].
  SceneQuery(this.document);

  /// The document being read.
  final SceneDocument document;

  /// The node with [id], or null.
  NodeSpec? node(LocalId id) => document.node(id);

  /// The document's root nodes, in order.
  List<NodeSpec> get roots => [
    for (final id in document.roots)
      if (document.node(id) != null) document.node(id)!,
  ];

  /// The direct children of [id], in order.
  List<NodeSpec> childrenOf(LocalId id) {
    final node = document.node(id);
    if (node == null) return const [];
    return [
      for (final childId in node.children)
        if (document.node(childId) != null) document.node(childId)!,
    ];
  }

  /// The parent of [id] (the node whose children contain it), or null when
  /// [id] is a root or absent.
  LocalId? parentOf(LocalId id) {
    for (final node in document.nodes.values) {
      if (node.children.contains(id)) return node.id;
    }
    return null;
  }

  /// All node ids in the subtree rooted at [id] (root first, depth first).
  List<LocalId> subtreeOf(LocalId id) {
    final out = <LocalId>[];
    final stack = <LocalId>[id];
    while (stack.isNotEmpty) {
      final current = stack.removeLast();
      final node = document.node(current);
      if (node == null) continue;
      out.add(current);
      stack.addAll(node.children.reversed);
    }
    return out;
  }

  /// The slash-joined name path from a root down to [id] (a readable label,
  /// not an identifier), or null when [id] is absent.
  String? namePathOf(LocalId id) {
    if (document.node(id) == null) return null;
    final parts = <String>[];
    var current = id;
    final seen = <LocalId>{};
    while (true) {
      if (!seen.add(current)) break; // guard against a cycle
      final node = document.node(current);
      if (node == null) break;
      parts.add(node.name.isEmpty ? node.id.toToken() : node.name);
      final parent = parentOf(current);
      if (parent == null) break;
      current = parent;
    }
    return parts.reversed.join('/');
  }

  /// The first node reached by walking [names] from the roots, or null.
  NodeSpec? nodeByNamePath(List<String> names) {
    if (names.isEmpty) return null;
    NodeSpec? match(Iterable<NodeSpec> candidates, String name) =>
        candidates.where((n) => n.name == name).firstOrNull;
    var current = match(roots, names.first);
    for (final name in names.skip(1)) {
      if (current == null) return null;
      current = match(childrenOf(current.id), name);
    }
    return current;
  }

  /// The component of [type] on [id], or null.
  ComponentSpec? componentOf(LocalId id, String type) =>
      document.node(id)?.components.where((c) => c.type == type).firstOrNull;

  /// The local-space bounds of [id]'s mesh geometry, or null when the node has
  /// no mesh component or the geometry carries no bounds.
  BoundsSpec? geometryBoundsOf(LocalId id) {
    final mesh = componentOf(id, 'mesh');
    final geometryRef = mesh?.properties['geometry'];
    if (geometryRef is! ResourceRefValue) return null;
    final geometry = document.resource(geometryRef.id);
    return geometry is GeometryResource ? geometry.bounds : null;
  }
}
