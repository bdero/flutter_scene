/// A structural diff between two `.fscene` documents, keyed by node id.
///
/// Scene-structure hot reload re-parses (and re-composes) the document after
/// its file changes, diffs it against the previous document by stable node id,
/// and patches the live graph: nodes whose id is unchanged keep their identity
/// (and their live animation clips), so only what actually changed is touched.
/// This layer is pure and GPU-free; applying the diff to a live graph lives in
/// the patch layer.
library;

import 'package:flutter_scene/src/fscene/id.dart';
import 'package:flutter_scene/src/fscene/json/canonical.dart';
import 'package:flutter_scene/src/fscene/json/property_json.dart';
import 'package:flutter_scene/src/fscene/scene_document.dart';
import 'package:flutter_scene/src/fscene/specs.dart';

/// What changed about a node present in both documents.
class NodeChange {
  /// Records the changed aspects of node [id].
  NodeChange(
    this.id, {
    this.transform = false,
    this.name = false,
    this.layers = false,
    this.reparented = false,
    this.components = false,
    this.skin = false,
  });

  /// The node's id (the same in both documents).
  final LocalId id;

  /// The local transform changed.
  final bool transform;

  /// The name changed.
  final bool name;

  /// The render-layer mask changed.
  final bool layers;

  /// The node's parent changed (it moved in the hierarchy).
  final bool reparented;

  /// The component set or a component's properties changed.
  final bool components;

  /// The bound skin changed.
  final bool skin;
}

/// The set of changes between two documents.
class SceneDiff {
  /// Creates a diff from its parts.
  SceneDiff({
    required this.added,
    required this.removed,
    required this.changed,
  });

  /// Node ids present in the new document but not the old (to realize and
  /// attach).
  final List<LocalId> added;

  /// Node ids present in the old document but not the new (to detach).
  final List<LocalId> removed;

  /// Nodes present in both whose content changed.
  final List<NodeChange> changed;

  /// Whether nothing changed.
  bool get isEmpty => added.isEmpty && removed.isEmpty && changed.isEmpty;
}

/// Computes the node-id-keyed diff turning [oldDocument] into [newDocument].
///
/// Both documents must be fully composed (no prefab instances); ids are assumed
/// stable across the two (the same node keeps its id when its file is edited).
SceneDiff diffScene(SceneDocument oldDocument, SceneDocument newDocument) {
  final oldIds = oldDocument.nodes.keys.toSet();
  final newIds = newDocument.nodes.keys.toSet();

  final added = [
    for (final id in newDocument.nodes.keys)
      if (!oldIds.contains(id)) id,
  ];
  final removed = [
    for (final id in oldDocument.nodes.keys)
      if (!newIds.contains(id)) id,
  ];

  final oldParents = _parents(oldDocument);
  final newParents = _parents(newDocument);

  final changed = <NodeChange>[];
  for (final id in newDocument.nodes.keys) {
    if (!oldIds.contains(id)) continue;
    final oldNode = oldDocument.nodes[id]!;
    final newNode = newDocument.nodes[id]!;

    final change = NodeChange(
      id,
      transform: !_transformsEqual(oldNode.transform, newNode.transform),
      name: oldNode.name != newNode.name,
      layers: oldNode.layers != newNode.layers,
      reparented: oldParents[id] != newParents[id],
      components: !_componentsEqual(oldNode.components, newNode.components),
      skin: oldNode.skin != newNode.skin,
    );
    if (change.transform ||
        change.name ||
        change.layers ||
        change.reparented ||
        change.components ||
        change.skin) {
      changed.add(change);
    }
  }

  return SceneDiff(added: added, removed: removed, changed: changed);
}

Map<LocalId, LocalId?> _parents(SceneDocument doc) {
  final parents = <LocalId, LocalId?>{
    for (final id in doc.nodes.keys) id: null,
  };
  for (final node in doc.nodes.values) {
    for (final child in node.children) {
      parents[child] = node.id;
    }
  }
  return parents;
}

bool _transformsEqual(TransformSpec a, TransformSpec b) {
  final sa = a.toMatrix4().storage;
  final sb = b.toMatrix4().storage;
  for (var i = 0; i < 16; i++) {
    if (sa[i] != sb[i]) return false;
  }
  return true;
}

// Compares component lists by their canonical encoded form, so any
// PropertyValue change (factor, reference, nested list/map) is detected without
// a bespoke value-equality walk.
bool _componentsEqual(List<ComponentSpec> a, List<ComponentSpec> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (_encodeComponent(a[i]) != _encodeComponent(b[i])) return false;
  }
  return true;
}

String _encodeComponent(ComponentSpec component) => canonicalJson({
  'type': component.type,
  'properties': {
    for (final e in component.properties.entries)
      e.key: encodePropertyValue(e.value, (id) => id.toToken()),
  },
});
