/// Scene-structure hot reload: patches a live [Node] graph in place to match a
/// re-parsed document, using the node-id-keyed [diffScene].
///
/// A node whose id is unchanged keeps its identity (and any live animation
/// clips, custom state, or app-held reference); only added, removed, reparented,
/// and changed nodes are touched. Changed skins are rebuilt and changed
/// animations re-bound (clips keep their playback state). New and changed
/// components realize against the new document, so this is async (it preloads
/// any external textures / `fmat` materials the new content references) and
/// GPU-bound.
library;

import 'package:flutter/services.dart' show AssetBundle;

import 'package:flutter_scene/src/animation.dart' show Animation;
import 'package:flutter_scene/src/components/component.dart';
import 'package:flutter_scene/src/fscene/id.dart';
import 'package:flutter_scene/src/fscene/realize/component_codec.dart';
import 'package:flutter_scene/src/fscene/realize/node_identity.dart';
import 'package:flutter_scene/src/fscene/realize/realize.dart';
import 'package:flutter_scene/src/fscene/realize/resource_realizer.dart';
import 'package:flutter_scene/src/fscene/realize/skin_animation.dart';
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
  context.resolveNode = (id) => live[id];

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
    final node = tagNodeId(
      Node(name: spec.name)
        ..layers = spec.layers
        ..excludeFromWindingParity = spec.excludeFromWindingParity
        ..visible = spec.visible,
      id,
    );
    applyTransformSpec(node, spec.transform);
    live[id] = node;
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
    if (change.transform) {
      applyTransformSpec(node, spec.transform);
      node.excludeFromWindingParity = spec.excludeFromWindingParity;
    }
    if (change.name) node.name = spec.name;
    if (change.layers) node.layers = spec.layers;
    if (change.visible) node.visible = spec.visible;
    if (change.reparented) {
      node.detach();
      parentFor(change.id).add(node);
    }
    if (change.components) {
      _setComponents(node, spec.components, reg, context);
    }
  }

  // 4. Rebuild skins on added nodes and on nodes whose skin changed. The
  // renderer rebuilds the joints texture from the bound skin each frame, so
  // swapping the skin is enough.
  final skinNodes = <LocalId>{
    for (final id in diff.added)
      if (newDocument.nodes[id]!.skin != null) id,
    for (final change in diff.changed)
      if (change.skin) change.id,
  };
  for (final id in skinNodes) {
    final node = live[id];
    if (node == null) continue;
    final spec = newDocument.skins[newDocument.nodes[id]!.skin];
    node.skin = spec == null ? null : buildSkin(newDocument, spec, live);
  }

  // 5. Rebuild and re-bind animations. Clips created from the old animations
  // keep playing (matched by name); rest poses come from the document so a
  // node frozen mid-playback is not captured at its animated pose. Applying
  // the transform specs directly (rather than via `restPoseOf` matrices)
  // keeps authored TRS decompositions for the rebound bind poses.
  if (diff.animationsChanged) {
    for (final spec in newDocument.animations.values) {
      for (final channel in spec.channels) {
        final node = live[channel.target];
        final nodeSpec = newDocument.nodes[channel.target];
        if (node == null || nodeSpec == null) continue;
        applyTransformSpec(node, nodeSpec.transform);
      }
    }
    final animations = [
      for (final spec in newDocument.animations.values)
        buildAnimation(newDocument, spec, live),
    ].whereType<Animation>().toList();
    liveRoot.reloadParsedAnimations(animations);
  }

  // Cross-node component resolution for components realized in this pass.
  context.runAfterRealize();

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
