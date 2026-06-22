/// A structural diff between two `.fscene` documents, keyed by node id.
///
/// Scene-structure hot reload re-parses (and re-composes) the document after
/// its file changes, diffs it against the previous document by stable node id,
/// and patches the live graph: nodes whose id is unchanged keep their identity
/// (and their live animation clips), so only what actually changed is touched.
/// This layer is pure and GPU-free; applying the diff to a live graph lives in
/// the patch layer.
library;

import 'package:flutter/foundation.dart' show listEquals;

import 'package:flutter_scene/src/fscene/id.dart';
import 'package:flutter_scene/src/fscene/json/canonical.dart';
import 'package:flutter_scene/src/fscene/json/fscene_json.dart'
    show encodeResource, encodeStage;
import 'package:flutter_scene/src/fscene/json/property_json.dart';
import 'package:flutter_scene/src/fscene/property_value.dart';
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
    this.visible = false,
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

  /// The visibility flag changed.
  final bool visible;

  /// The node's parent changed (it moved in the hierarchy).
  final bool reparented;

  /// The component set or a component's properties changed, or a resource the
  /// components reference (directly or through other resources) changed, so
  /// the components must re-realize.
  final bool components;

  /// The bound skin must be rebuilt: the skin id changed, the skin's content
  /// (joints, skeleton, inverse-bind matrices) changed, or a joint node was
  /// added or removed (so the live joint bindings are stale).
  final bool skin;
}

/// The set of changes between two documents.
class SceneDiff {
  /// Creates a diff from its parts.
  SceneDiff({
    required this.added,
    required this.removed,
    required this.changed,
    this.animationsChanged = false,
    this.stageChanged = false,
  });

  /// Node ids present in the new document but not the old (to realize and
  /// attach).
  final List<LocalId> added;

  /// Node ids present in the old document but not the new (to detach).
  final List<LocalId> removed;

  /// Nodes present in both whose content changed.
  final List<NodeChange> changed;

  /// Whether the realized animations would differ: the animation pool changed
  /// (an animation or its keyframe payloads), or a channel-target node was
  /// added, removed, renamed, or had its rest transform changed (animations
  /// bind by target name and capture bind poses from rest transforms).
  final bool animationsChanged;

  /// Whether the stage render settings changed (environment, exposure, tone
  /// mapping, skybox, or sky lighting). The node patch does not apply these;
  /// callers holding a `Scene` re-apply the stage when set (see
  /// `realizeStage`).
  final bool stageChanged;

  /// Whether nothing changed.
  bool get isEmpty =>
      added.isEmpty &&
      removed.isEmpty &&
      changed.isEmpty &&
      !animationsChanged &&
      !stageChanged;
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
  final changedResources = _changedResources(oldDocument, newDocument);

  // Joints of these nodes are live Node objects that get recreated, so any
  // skin binding them must be rebuilt even when its spec is unchanged.
  final staleNodes = {...added, ...removed};

  final changed = <NodeChange>[];
  for (final id in newDocument.nodes.keys) {
    if (!oldIds.contains(id)) continue;
    final oldNode = oldDocument.nodes[id]!;
    final newNode = newDocument.nodes[id]!;

    final change = NodeChange(
      id,
      transform:
          !_transformsEqual(oldNode.transform, newNode.transform) ||
          oldNode.excludeFromWindingParity != newNode.excludeFromWindingParity,
      name: oldNode.name != newNode.name,
      layers: oldNode.layers != newNode.layers,
      visible: oldNode.visible != newNode.visible,
      reparented: oldParents[id] != newParents[id],
      components:
          !_componentsEqual(oldNode.components, newNode.components) ||
          _referencesAny(newNode.components, changedResources),
      skin: !_skinsEqual(
        oldDocument,
        newDocument,
        oldNode,
        newNode,
        staleNodes,
      ),
    );
    if (change.transform ||
        change.name ||
        change.layers ||
        change.visible ||
        change.reparented ||
        change.components ||
        change.skin) {
      changed.add(change);
    }
  }

  return SceneDiff(
    added: added,
    removed: removed,
    changed: changed,
    animationsChanged: _animationsChanged(
      oldDocument,
      newDocument,
      staleNodes,
      changed,
    ),
    // The stage changed when its own fields differ, or when the global
    // environment resource it references changed (the look lives there, not
    // inline), so editing the global look re-applies the stage on hot reload.
    stageChanged:
        canonicalJson(encodeStage(oldDocument.stage)) !=
            canonicalJson(encodeStage(newDocument.stage)) ||
        (newDocument.stage.environmentRef != null &&
            changedResources.contains(newDocument.stage.environmentRef)),
  );
}

/// Resource ids whose realized content would differ between the documents:
/// the resource's spec changed, a payload it references has different bytes,
/// it is new, or (transitively) a resource it references changed. Component
/// property diffs alone miss these, since components reference resources by
/// id and an edited resource keeps its id.
Set<LocalId> _changedResources(
  SceneDocument oldDocument,
  SceneDocument newDocument,
) {
  String encode(ResourceSpec r) =>
      canonicalJson(encodeResource(r, (id) => id.toToken()));

  final changed = <LocalId>{};
  for (final entry in newDocument.resources.entries) {
    final oldResource = oldDocument.resources[entry.key];
    if (oldResource == null || encode(oldResource) != encode(entry.value)) {
      changed.add(entry.key);
      continue;
    }
    for (final payloadId in _resourcePayloads(entry.value)) {
      if (!_payloadsEqual(
        oldDocument.payload(payloadId),
        newDocument.payload(payloadId),
      )) {
        changed.add(entry.key);
        break;
      }
    }
  }

  // Propagate through resource-to-resource references (a material referencing
  // a changed texture is itself changed) until a fixed point.
  var grew = changed.isNotEmpty;
  while (grew) {
    grew = false;
    for (final entry in newDocument.resources.entries) {
      if (changed.contains(entry.key)) continue;
      final refs = <LocalId>{};
      _collectRefs(_resourceProperties(entry.value), refs);
      if (refs.any(changed.contains)) {
        changed.add(entry.key);
        grew = true;
      }
    }
  }
  return changed;
}

List<LocalId> _resourcePayloads(ResourceSpec resource) => switch (resource) {
  GeometryResource() => [
    if (resource.vertices != null) resource.vertices!,
    if (resource.indices != null) resource.indices!,
  ],
  TextureResource() => [if (resource.payload != null) resource.payload!],
  _ => const [],
};

Map<String, PropertyValue> _resourceProperties(ResourceSpec resource) =>
    switch (resource) {
      MaterialResource() => resource.properties,
      _ => const {},
    };

/// Collects every [ResourceRefValue] id reachable through [properties]
/// (including nested lists and maps).
void _collectRefs(Map<String, PropertyValue> properties, Set<LocalId> out) {
  void walk(PropertyValue value) {
    switch (value) {
      case ResourceRefValue():
        out.add(value.id);
      case ListValue():
        value.values.forEach(walk);
      case MapValue():
        value.values.values.forEach(walk);
      default:
        break;
    }
  }

  properties.values.forEach(walk);
}

bool _referencesAny(List<ComponentSpec> components, Set<LocalId> resources) {
  if (resources.isEmpty) return false;
  final refs = <LocalId>{};
  for (final component in components) {
    _collectRefs(component.properties, refs);
  }
  return refs.any(resources.contains);
}

bool _skinsEqual(
  SceneDocument oldDocument,
  SceneDocument newDocument,
  NodeSpec oldNode,
  NodeSpec newNode,
  Set<LocalId> staleNodes,
) {
  if (oldNode.skin != newNode.skin) return false;
  final skinId = newNode.skin;
  if (skinId == null) return true;
  final oldSkin = oldDocument.skins[skinId];
  final newSkin = newDocument.skins[skinId];
  if (oldSkin == null || newSkin == null) {
    return identical(oldSkin, newSkin);
  }
  if (!listEquals(oldSkin.joints, newSkin.joints)) return false;
  if (oldSkin.skeleton != newSkin.skeleton) return false;
  if (newSkin.joints.any(staleNodes.contains)) return false;
  return _payloadsEqual(
    oldDocument.payload(oldSkin.inverseBindMatrices),
    newDocument.payload(newSkin.inverseBindMatrices),
  );
}

bool _animationsChanged(
  SceneDocument oldDocument,
  SceneDocument newDocument,
  Set<LocalId> staleNodes,
  List<NodeChange> changed,
) {
  if (oldDocument.animations.length != newDocument.animations.length) {
    return true;
  }
  // Channel targets whose live node was replaced, renamed, or whose rest
  // transform changed need a rebind (bindings resolve by name; bind poses
  // come from rest transforms).
  final retargeted = {
    ...staleNodes,
    for (final change in changed)
      if (change.name || change.transform) change.id,
  };
  for (final id in newDocument.animations.keys) {
    final oldAnimation = oldDocument.animations[id];
    final newAnimation = newDocument.animations[id]!;
    if (oldAnimation == null) return true;
    if (oldAnimation.name != newAnimation.name) return true;
    if (oldAnimation.channels.length != newAnimation.channels.length) {
      return true;
    }
    for (var i = 0; i < newAnimation.channels.length; i++) {
      final oldChannel = oldAnimation.channels[i];
      final newChannel = newAnimation.channels[i];
      if (oldChannel.target != newChannel.target ||
          oldChannel.targetName != newChannel.targetName ||
          oldChannel.property != newChannel.property) {
        return true;
      }
      if (retargeted.contains(newChannel.target)) return true;
      if (!_payloadsEqual(
            oldDocument.payload(oldChannel.timeline),
            newDocument.payload(newChannel.timeline),
          ) ||
          !_payloadsEqual(
            oldDocument.payload(oldChannel.keyframes),
            newDocument.payload(newChannel.keyframes),
          )) {
        return true;
      }
    }
  }
  return false;
}

bool _payloadsEqual(PayloadSpec? a, PayloadSpec? b) {
  final aBytes = a?.bytes;
  final bBytes = b?.bytes;
  if (aBytes == null || bBytes == null) {
    return identical(aBytes, bBytes);
  }
  if (aBytes.lengthInBytes != bBytes.lengthInBytes) return false;
  for (var i = 0; i < aBytes.lengthInBytes; i++) {
    if (aBytes[i] != bBytes[i]) return false;
  }
  return true;
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
