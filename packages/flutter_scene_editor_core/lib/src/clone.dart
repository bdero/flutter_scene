/// Subtree cloning for duplicate, copy, and paste.
///
/// [captureSubtree] lifts a node subtree out of a document into a detached,
/// deep-copied [NodeSubtree] that is immune to later edits (the shape a
/// clipboard holds). [instantiateSubtree] stamps a captured subtree back into a
/// document with fresh ids, remapping node references that stay inside the
/// subtree while sharing everything that points outside it (resources, skins,
/// external nodes). Duplicate clones share the same geometry and materials as
/// the original, which is the expected behavior.
library;

import 'package:flutter_scene/src/fscene/id.dart';
import 'package:flutter_scene/src/fscene/property_value.dart';
import 'package:flutter_scene/src/fscene/scene_document.dart';
import 'package:flutter_scene/src/fscene/specs.dart';

/// A detached, self-contained copy of a node subtree.
///
/// [nodes] holds the root and every descendant (deep-copied), keyed by id, so
/// the subtree survives edits or deletion of the document it came from.
class NodeSubtree {
  /// Creates a subtree rooted at [root] over the deep-copied [nodes].
  NodeSubtree(this.root, this.nodes);

  /// The subtree's root id (a key in [nodes]).
  final LocalId root;

  /// The root and all descendants, deep-copied, keyed by id.
  final Map<LocalId, NodeSpec> nodes;
}

/// Captures the subtree rooted at [rootId] in [doc] as a detached [NodeSubtree].
///
/// Every node is deep-copied (ids unchanged), so the result is independent of
/// later changes to [doc]. References that leave the subtree are kept as-is.
NodeSubtree captureSubtree(SceneDocument doc, LocalId rootId) {
  final nodes = <LocalId, NodeSpec>{};
  LocalId identity(LocalId id) => id;
  void visit(LocalId id) {
    final node = doc.nodes[id];
    if (node == null || nodes.containsKey(id)) return;
    nodes[id] = _copyNode(node, identity);
    for (final child in node.children) {
      visit(child);
    }
  }

  visit(rootId);
  return NodeSubtree(rootId, nodes);
}

/// Instantiates [subtree] with fresh ids minted by [newId].
///
/// Node references inside the subtree (child links, in-subtree node-ref
/// properties, a skin owned by the subtree) are remapped to the new ids;
/// references that point outside the subtree are shared. Returns the new nodes
/// (root first) ready to add to a document, and the new root id.
({List<NodeSpec> nodes, LocalId root}) instantiateSubtree(
  NodeSubtree subtree,
  LocalId Function() newId,
) {
  final idMap = <LocalId, LocalId>{
    for (final id in subtree.nodes.keys) id: newId(),
  };
  LocalId remap(LocalId id) => idMap[id] ?? id;

  final out = <NodeSpec>[];
  // Root first, then the rest in capture order.
  out.add(_copyNode(subtree.nodes[subtree.root]!, remap));
  for (final entry in subtree.nodes.entries) {
    if (entry.key == subtree.root) continue;
    out.add(_copyNode(entry.value, remap));
  }
  return (nodes: out, root: remap(subtree.root));
}

NodeSpec _copyNode(NodeSpec n, LocalId Function(LocalId) remap) => NodeSpec(
  id: remap(n.id),
  name: n.name,
  transform: _copyTransform(n.transform),
  children: [for (final c in n.children) remap(c)],
  components: [for (final c in n.components) _copyComponent(c, remap)],
  layers: n.layers,
  skin: n.skin == null ? null : remap(n.skin!),
  instance: n.instance == null ? null : _copyInstance(n.instance!, remap),
  excludeFromWindingParity: n.excludeFromWindingParity,
  visible: n.visible,
);

TransformSpec _copyTransform(TransformSpec t) => switch (t) {
  TrsTransform trs => TrsTransform(
    translation: trs.translation.clone(),
    rotation: trs.rotation.clone(),
    scale: trs.scale.clone(),
  ),
  MatrixTransform m => MatrixTransform(m.matrix.clone()),
};

ComponentSpec _copyComponent(
  ComponentSpec c,
  LocalId Function(LocalId) remap,
) => ComponentSpec(
  c.type,
  properties: {
    for (final e in c.properties.entries) e.key: _copyValue(e.value, remap),
  },
);

/// Deep-copies a property value, remapping node references through [remap].
/// Resource references are left untouched (a clone shares the original's
/// resources); scalar and vector values are immutable and shared as-is.
PropertyValue _copyValue(PropertyValue v, LocalId Function(LocalId) remap) =>
    switch (v) {
      NodeRefValue(:final id) => NodeRefValue(remap(id)),
      ListValue(:final values) => ListValue([
        for (final e in values) _copyValue(e, remap),
      ]),
      MapValue(:final values) => MapValue({
        for (final e in values.entries) e.key: _copyValue(e.value, remap),
      }),
      _ => v,
    };

PrefabInstanceSpec _copyInstance(
  PrefabInstanceSpec i,
  LocalId Function(LocalId) remap,
) => PrefabInstanceSpec(
  source: i.source,
  load: i.load,
  // Override targets are prefab-local ids (not document node ids), so they are
  // copied without remapping; added nodes carry instance-local ids that the
  // remap leaves alone, so they are simply deep-copied.
  overrides: [
    for (final o in i.overrides)
      PropertyOverride(target: o.target, path: o.path, value: o.value),
  ],
  attachments: [
    for (final a in i.attachments) Attachment(remap(a.node), parent: a.parent),
  ],
  removedNodes: List.of(i.removedNodes),
  addedComponents: [
    for (final c in i.addedComponents) _copyComponent(c, remap),
  ],
  removedComponentTypes: List.of(i.removedComponentTypes),
);
