/// Scene-structure hot reload: patches a live [Node] graph in place to match a
/// re-parsed document, using the node-id-keyed [diffScene].
///
/// A node whose id is unchanged keeps its identity (and any live animation
/// clips, custom state, or app-held reference); only added, removed, reparented,
/// and changed nodes are touched. New and changed components realize against
/// the new document, so this is async (it preloads any external textures /
/// `fmat` materials the new content references) and GPU-bound.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show AssetBundle;

import 'package:flutter_scene/src/components/component.dart';
import 'package:flutter_scene/src/fscene/id.dart';
import 'package:flutter_scene/src/fscene/realize/component_codec.dart';
import 'package:flutter_scene/src/fscene/realize/node_identity.dart';
import 'package:flutter_scene/src/fscene/realize/realize.dart';
import 'package:flutter_scene/src/fscene/realize/resource_realizer.dart';
import 'package:flutter_scene/src/fscene/reload/diff.dart';
import 'package:flutter_scene/src/fscene/scene_document.dart';
import 'package:flutter_scene/src/fscene/specs.dart';
import 'package:flutter_scene/src/node.dart';

/// Patches the live graph rooted at [liveRoot] (as returned by `realizeScene`,
/// or `loadScene`) from [oldDocument] to [newDocument] in place.
///
/// [liveRoot] must currently match [oldDocument]; both documents must be fully
/// composed. Nodes whose id is unchanged keep their identity. Returns the diff
/// that was applied (empty when nothing changed).
///
// TODO(fscene): re-bind changed skins and re-attach changed animations; today
// a skin/animation change is not patched.
Future<SceneDiff> reloadScene(
  Node liveRoot,
  SceneDocument oldDocument,
  SceneDocument newDocument, {
  FsceneComponentRegistry? registry,
  AssetBundle? bundle,
}) async {
  final diff = diffScene(oldDocument, newDocument);
  if (diff.isEmpty) return diff;

  final reg = registry ?? defaultComponentRegistry();
  final resources = ResourceRealizer(newDocument, bundle: bundle);
  await resources.preload();
  final context = RealizeContext(newDocument, resources: resources);

  // Index the live graph by document id.
  final live = <LocalId, Node>{};
  void collect(Node node) {
    final id = nodeFsceneId(node);
    if (id != null) live[id] = node;
    for (final child in node.children) {
      collect(child);
    }
  }

  collect(liveRoot);

  final newParents = _parents(newDocument);
  Node parentFor(LocalId id) => live[newParents[id]] ?? liveRoot;

  // 1. Detach removed nodes.
  for (final id in diff.removed) {
    live.remove(id)?.detach();
  }

  // 2. Create the added nodes (bare), then wire their children and components,
  // then attach those still without a parent under their document parent.
  for (final id in diff.added) {
    final spec = newDocument.nodes[id]!;
    live[id] = tagNodeId(
      Node(name: spec.name, localTransform: spec.transform.toMatrix4())
        ..layers = spec.layers,
      id,
    );
  }
  for (final id in diff.added) {
    final spec = newDocument.nodes[id]!;
    final node = live[id]!;
    for (final childId in spec.children) {
      final child = live[childId];
      if (child != null && child.parent == null) node.add(child);
    }
    _setComponents(node, spec.components, reg, context);
  }
  for (final id in diff.added) {
    final node = live[id]!;
    if (node.parent == null) parentFor(id).add(node);
  }

  // 3. Update surviving nodes.
  for (final change in diff.changed) {
    final node = live[change.id]!;
    final spec = newDocument.nodes[change.id]!;
    if (change.transform) node.localTransform = spec.transform.toMatrix4();
    if (change.name) node.name = spec.name;
    if (change.layers) node.layers = spec.layers;
    if (change.reparented) {
      node.detach();
      parentFor(change.id).add(node);
    }
    if (change.components) {
      _setComponents(node, spec.components, reg, context);
    }
    if (change.skin) {
      debugPrint(
        'fscene: skin change on node ${change.id} is not hot-reloaded',
      );
    }
  }

  return diff;
}

void _setComponents(
  Node node,
  List<ComponentSpec> specs,
  FsceneComponentRegistry registry,
  RealizeContext context,
) {
  for (final component in node.getComponents<Component>().toList()) {
    node.removeComponent(component);
  }
  for (final spec in specs) {
    final component = registry.realize(spec, context);
    if (component != null) node.addComponent(component);
  }
}

Map<LocalId, LocalId?> _parents(SceneDocument doc) {
  final parents = <LocalId, LocalId?>{};
  for (final node in doc.nodes.values) {
    for (final child in node.children) {
      parents[child] = node.id;
    }
  }
  return parents;
}
