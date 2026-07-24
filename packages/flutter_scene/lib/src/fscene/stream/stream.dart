/// Level streaming: loading and unloading lazy prefab subtrees on demand.
///
/// A prefab instance authored with `LoadPolicy.lazy` survives composition and
/// realizes as a lightweight placeholder ([lazyInstanceOf] is set, the node has
/// no content). [loadSubtree] instantiates the prefab under the placeholder
/// when needed; [unloadSubtree] detaches it again. A spatial auto-streamer
/// (load/unload by camera distance) can be built on top of these.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show AssetBundle;

import 'package:scene/scene.dart';
import 'package:flutter_scene/src/fscene/realize/component_codec.dart';
import 'package:flutter_scene/src/fscene/realize/lazy_subtree.dart';
import 'package:flutter_scene/src/fscene/realize/realize.dart';
import 'package:flutter_scene/src/node.dart';

/// Whether [node] is a lazy prefab placeholder.
bool isLazySubtree(Node node) => lazyInstanceOf(node) != null;

/// Whether [node] is a lazy placeholder whose content is currently loaded.
bool isSubtreeLoaded(Node node) =>
    lazyInstanceOf(node) != null && node.children.isNotEmpty;

/// Instantiates a lazy placeholder [node]'s prefab content under it.
///
/// [load] resolves the referenced prefab document (the same loader `loadScene`
/// uses). No-op if [node] is not a lazy placeholder or is already loaded.
Future<void> loadSubtree(
  Node node, {
  required AsyncPrefabLoader load,
  FsceneComponentRegistry? registry,
  AssetBundle? bundle,
}) async {
  final spec = lazyInstanceOf(node);
  if (spec == null) {
    debugPrint('fscene: loadSubtree on a node that is not a lazy placeholder');
    return;
  }
  if (node.children.isNotEmpty) return; // already loaded

  // Expand the instance in isolation, in engine space (no handedness mirror)
  // and at identity: the placeholder already carries the placement, and the
  // realized content inherits the placeholder's frame from its ancestors.
  final host = SceneDocument(stage: StageMetadata(handedness: Handedness.left));
  host.addNode(NodeSpec(id: host.newId(), instance: _eager(spec)), root: true);
  final composed = await composeSceneAsync(host, load: load);
  final realized = await realizeSceneAsync(
    composed,
    registry: registry,
    bundle: bundle,
  );
  for (final child in List<Node>.of(realized.children)) {
    realized.remove(child);
    node.add(child);
  }
}

/// Detaches a loaded lazy subtree [node]'s content; it can be loaded again with
/// [loadSubtree]. No-op if [node] is not a lazy placeholder.
void unloadSubtree(Node node) {
  if (lazyInstanceOf(node) == null) {
    debugPrint(
      'fscene: unloadSubtree on a node that is not a lazy placeholder',
    );
    return;
  }
  node.removeAll();
}

// The same instance, but eager, so composeScene expands it.
PrefabInstanceSpec _eager(PrefabInstanceSpec spec) => PrefabInstanceSpec(
  source: spec.source,
  overrides: spec.overrides,
  attachments: spec.attachments,
  removedNodes: spec.removedNodes,
  addedComponents: spec.addedComponents,
  removedComponentTypes: spec.removedComponentTypes,
);
