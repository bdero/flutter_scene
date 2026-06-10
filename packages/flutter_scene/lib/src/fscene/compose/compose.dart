/// Prefab composition: expands a document's prefab instances into a flat,
/// fully-realized document.
///
/// A [NodeSpec] whose [NodeSpec.instance] is set is a prefab instance: a
/// reference to another `.fscene` plus a per-instance delta (overrides, added
/// and removed nodes/components). [composeScene] resolves each reference,
/// recursively composes the referenced prefab, remaps its document-local id
/// space into fresh ids (so two instances of one prefab are distinct,
/// Bevy-style), inlines it, and applies the delta. The result has no instance
/// nodes left and feeds straight into `realizeScene`.
///
/// Pure Dart and GPU-free. Resolution of a prefab reference is delegated to a
/// caller-supplied `resolve` (a runtime wrapper loads the referenced document
/// from the asset bundle; tests pass an in-memory map).
library;

import 'package:flutter/foundation.dart';
import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/fscene/id.dart';
import 'package:flutter_scene/src/fscene/json/fscene_json.dart';
import 'package:flutter_scene/src/fscene/property_value.dart';
import 'package:flutter_scene/src/fscene/scene_document.dart';
import 'package:flutter_scene/src/fscene/specs.dart';

/// Resolves a prefab [AssetRef] to its (uncomposed) [SceneDocument].
typedef PrefabResolver = SceneDocument Function(AssetRef ref);

/// Asynchronously loads a prefab [AssetRef]'s (uncomposed) [SceneDocument].
typedef AsyncPrefabLoader = Future<SceneDocument> Function(AssetRef ref);

/// Expands every prefab instance in [document], returning a new document with
/// no instance nodes. A document with no instances is returned unchanged.
///
/// [resolve] loads a referenced prefab document. A cyclic reference (a prefab
/// that instantiates itself, directly or transitively) is broken with a
/// warning rather than recursing forever.
SceneDocument composeScene(
  SceneDocument document, {
  required PrefabResolver resolve,
}) => _compose(document, resolve, <String>{});

/// Loads every prefab document [document] references (transitively, breadth
/// first, each source loaded once) via [load], then composes synchronously.
///
/// The async counterpart of [composeScene]: the asset loaders call this so a
/// scene that references prefab files by source path is expanded before
/// realizing. A reference that fails to load throws.
Future<SceneDocument> composeSceneAsync(
  SceneDocument document, {
  required AsyncPrefabLoader load,
}) async {
  final loaded = <String, SceneDocument>{};
  final queue = [..._prefabRefs(document)];
  while (queue.isNotEmpty) {
    final ref = queue.removeLast();
    if (loaded.containsKey(ref.key)) continue;
    final prefab = await load(ref);
    loaded[ref.key] = prefab;
    queue.addAll(_prefabRefs(prefab));
  }
  return composeScene(
    document,
    resolve: (ref) {
      final prefab = loaded[ref.key];
      if (prefab == null) {
        throw FsceneFormatException('Unresolved prefab "${ref.key}"');
      }
      return prefab;
    },
  );
}

Iterable<AssetRef> _prefabRefs(SceneDocument doc) =>
    doc.nodes.values.where(_isEager).map((node) => node.instance!.source);

bool _isEager(NodeSpec node) =>
    node.instance != null && node.instance!.load == LoadPolicy.eager;

SceneDocument _compose(
  SceneDocument document,
  PrefabResolver resolve,
  Set<String> visiting,
) {
  // Only eager instances are expanded here; lazy instances pass through as
  // placeholders for the streaming layer to load on demand.
  if (!document.nodes.values.any(_isEager)) {
    return document;
  }

  final out = SceneDocument(
    documentId: document.documentId,
    allocator: IdAllocator(excludedSessions: document.usedSessions()),
    stage: _copyStage(document.stage),
  );
  out.formatVersion = document.formatVersion;
  out.generator = document.generator;
  out.featuresUsed.addAll(document.featuresUsed);
  out.featuresRequired.addAll(document.featuresRequired);

  // Copy the host's own content verbatim (ids preserved); instances are
  // expanded below.
  LocalId identity(LocalId id) => id;
  for (final resource in document.resources.values) {
    out.addResource(_remapResource(resource, identity));
  }
  for (final payload in document.payloads.values) {
    out.addPayload(_remapPayload(payload, identity));
  }
  for (final skin in document.skins.values) {
    out.addSkin(_remapSkin(skin, identity));
  }
  for (final animation in document.animations.values) {
    out.addAnimation(_remapAnimation(animation, identity));
  }
  for (final node in document.nodes.values) {
    out.addNode(_remapNode(node, identity, keepInstance: true));
  }
  out.roots.addAll(document.roots);

  for (final instance in out.nodes.values.where(_isEager).toList()) {
    _expandInstance(out, instance, resolve, visiting);
  }
  return out;
}

void _expandInstance(
  SceneDocument out,
  NodeSpec instance,
  PrefabResolver resolve,
  Set<String> visiting,
) {
  final spec = instance.instance!;
  instance.instance = null; // mark expanded regardless of outcome
  final sourceKey = spec.source.key;
  if (visiting.contains(sourceKey)) {
    debugPrint('fscene: cyclic prefab reference to "$sourceKey"; skipping');
    return;
  }

  visiting.add(sourceKey);
  final prefab = _compose(resolve(spec.source), resolve, visiting);
  visiting.remove(sourceKey);

  // Fresh id for every prefab id; a single-root prefab merges its root into
  // the instance node (so the instance node "is" the prefab root, which is
  // what overrides and added/removed components target).
  // TODO(fscene): derive the remapped ids deterministically from the instance
  // id + prefab id instead of allocating fresh ones, so recomposing after a
  // prefab edit keeps ids stable and hot reload patches the prefab subtree
  // fine-grained instead of rebuilding it.
  final singleRoot = prefab.roots.length == 1 ? prefab.roots.single : null;
  final remap = <LocalId, LocalId>{};
  for (final id in _allIds(prefab)) {
    remap[id] = id == singleRoot ? instance.id : out.newId();
  }
  LocalId remapId(LocalId id) => remap[id] ?? id;

  for (final resource in prefab.resources.values) {
    out.addResource(_remapResource(resource, remapId));
  }
  for (final payload in prefab.payloads.values) {
    out.addPayload(_remapPayload(payload, remapId));
  }
  for (final skin in prefab.skins.values) {
    out.addSkin(_remapSkin(skin, remapId));
  }
  for (final animation in prefab.animations.values) {
    out.addAnimation(_remapAnimation(animation, remapId));
  }
  for (final node in prefab.nodes.values) {
    if (node.id == singleRoot) {
      // Merge the prefab root into the instance node, keeping the instance's
      // own transform, name, and layers (its placement in the host).
      instance.components.addAll([
        for (final c in node.components) _remapComponent(c, remapId),
      ]);
      instance.children.addAll([for (final c in node.children) remapId(c)]);
      instance.skin ??= node.skin == null ? null : remapId(node.skin!);
    } else {
      out.addNode(_remapNode(node, remapId, keepInstance: false));
    }
  }
  if (singleRoot == null) {
    instance.children.addAll([for (final r in prefab.roots) remapId(r)]);
  }

  _applyDelta(out, instance, spec, remapId);
}

void _applyDelta(
  SceneDocument out,
  NodeSpec instance,
  PrefabInstanceSpec spec,
  LocalId Function(LocalId) remapId,
) {
  for (final override in spec.overrides) {
    final node = out.node(remapId(override.target));
    if (node == null) {
      debugPrint('fscene: override target ${override.target} not found');
      continue;
    }
    _setProperty(node, override.path, override.value);
  }
  for (final removed in spec.removedNodes) {
    _removeNode(out, remapId(removed));
  }
  // Added nodes keep their authored ids; subtree roots (those not referenced as
  // another added node's child) parent under the instance node.
  final addedChildren = {for (final n in spec.addedNodes) ...n.children};
  for (final node in spec.addedNodes) {
    out.addNode(node);
    if (!addedChildren.contains(node.id)) instance.children.add(node.id);
  }
  instance.components.addAll(spec.addedComponents);
  if (spec.removedComponentTypes.isNotEmpty) {
    instance.components.removeWhere(
      (c) => spec.removedComponentTypes.contains(c.type),
    );
  }
}

// ---- property-path override application ----

void _setProperty(NodeSpec node, String path, PropertyValue value) {
  final parts = path.split('.');
  if (parts.length == 1) {
    if (parts[0] == 'name' && value is StringValue) {
      node.name = value.value;
      return;
    }
    if (parts[0] == 'layers' && value is IntValue) {
      node.layers = value.value;
      return;
    }
  }
  if (parts.length >= 2 && parts[0] == 'transform') {
    if (parts[1] == 'matrix' && value is Matrix4Value) {
      node.transform = MatrixTransform(value.value.clone());
      return;
    }
    if (parts[1] == 'trs' && parts.length == 3) {
      _setTrs(node, parts[2], value);
      return;
    }
  }
  if (parts.length == 3 && parts[0] == 'components') {
    for (final component in node.components) {
      if (component.type == parts[1]) {
        component.properties[parts[2]] = value;
        return;
      }
    }
    debugPrint('fscene: override "$path" found no "${parts[1]}" component');
    return;
  }
  debugPrint('fscene: unsupported override path "$path"');
}

void _setTrs(NodeSpec node, String component, PropertyValue value) {
  final current = node.transform;
  var translation = Vector3.zero();
  var rotation = Quaternion.identity();
  var scale = Vector3(1, 1, 1);
  if (current is TrsTransform) {
    translation = current.translation.clone();
    rotation = current.rotation.clone();
    scale = current.scale.clone();
  }
  switch (component) {
    case 't' when value is Vec3Value:
      translation = value.value.clone();
    case 'r' when value is QuaternionValue:
      rotation = value.value.clone();
    case 's' when value is Vec3Value:
      scale = value.value.clone();
    default:
      debugPrint('fscene: bad transform override "trs.$component"');
      return;
  }
  node.transform = TrsTransform(
    translation: translation,
    rotation: rotation,
    scale: scale,
  );
}

void _removeNode(SceneDocument out, LocalId id) {
  out.nodes.remove(id);
  out.roots.remove(id);
  for (final node in out.nodes.values) {
    node.children.remove(id);
  }
}

// ---- id-remapping copies ----

Iterable<LocalId> _allIds(SceneDocument doc) sync* {
  yield* doc.nodes.keys;
  yield* doc.resources.keys;
  yield* doc.payloads.keys;
  yield* doc.skins.keys;
  yield* doc.animations.keys;
}

NodeSpec _remapNode(
  NodeSpec node,
  LocalId Function(LocalId) remap, {
  required bool keepInstance,
}) => NodeSpec(
  id: remap(node.id),
  name: node.name,
  transform: node.transform,
  children: [for (final c in node.children) remap(c)],
  components: [for (final c in node.components) _remapComponent(c, remap)],
  layers: node.layers,
  skin: node.skin == null ? null : remap(node.skin!),
  instance: keepInstance ? node.instance : null,
);

ComponentSpec _remapComponent(
  ComponentSpec c,
  LocalId Function(LocalId) remap,
) => ComponentSpec(c.type, properties: _remapProperties(c.properties, remap));

Map<String, PropertyValue> _remapProperties(
  Map<String, PropertyValue> props,
  LocalId Function(LocalId) remap,
) => {for (final e in props.entries) e.key: _remapValue(e.value, remap)};

PropertyValue _remapValue(PropertyValue v, LocalId Function(LocalId) remap) =>
    switch (v) {
      ResourceRefValue(:final id) => ResourceRefValue(remap(id)),
      NodeRefValue(:final id) => NodeRefValue(remap(id)),
      ListValue(:final values) => ListValue([
        for (final e in values) _remapValue(e, remap),
      ]),
      MapValue(:final values) => MapValue({
        for (final e in values.entries) e.key: _remapValue(e.value, remap),
      }),
      _ => v,
    };

ResourceSpec _remapResource(ResourceSpec r, LocalId Function(LocalId) remap) =>
    switch (r) {
      GeometryResource() => GeometryResource(
        remap(r.id),
        vertices: r.vertices == null ? null : remap(r.vertices!),
        indices: r.indices == null ? null : remap(r.indices!),
        procedural: r.procedural,
        bounds: r.bounds,
      ),
      TextureResource() => TextureResource(
        remap(r.id),
        payload: r.payload == null ? null : remap(r.payload!),
        asset: r.asset,
      ),
      MaterialResource() => MaterialResource(
        remap(r.id),
        type: r.type,
        properties: _remapProperties(r.properties, remap),
        asset: r.asset,
      ),
    };

PayloadSpec _remapPayload(PayloadSpec p, LocalId Function(LocalId) remap) =>
    PayloadSpec(
      remap(p.id),
      encoding: p.encoding,
      layout: p.layout,
      format: p.format,
      width: p.width,
      height: p.height,
      length: p.length,
      bytes: p.bytes,
    );

SkinSpec _remapSkin(SkinSpec s, LocalId Function(LocalId) remap) => SkinSpec(
  remap(s.id),
  joints: [for (final j in s.joints) remap(j)],
  inverseBindMatrices: remap(s.inverseBindMatrices),
  skeleton: s.skeleton == null ? null : remap(s.skeleton!),
);

AnimationSpec _remapAnimation(
  AnimationSpec a,
  LocalId Function(LocalId) remap,
) => AnimationSpec(
  remap(a.id),
  name: a.name,
  channels: [
    for (final ch in a.channels)
      AnimationChannelSpec(
        target: remap(ch.target),
        targetName: ch.targetName,
        property: ch.property,
        timeline: remap(ch.timeline),
        keyframes: remap(ch.keyframes),
      ),
  ],
);

StageMetadata _copyStage(StageMetadata s) => StageMetadata(
  upAxis: s.upAxis,
  handedness: s.handedness,
  unitsPerMeter: s.unitsPerMeter,
  environment: s.environment,
  environmentIntensity: s.environmentIntensity,
  exposure: s.exposure,
  toneMapping: s.toneMapping,
  skybox: s.skybox == null
      ? null
      : SkyboxSpec(
          _copySkySource(s.skybox!.source),
          intensity: s.skybox!.intensity,
        ),
  skyEnvironment: s.skyEnvironment == null
      ? null
      : SkyEnvironmentSpec(
          _copySkySource(s.skyEnvironment!.source),
          refresh: s.skyEnvironment!.refresh,
          intervalSeconds: s.skyEnvironment!.intervalSeconds,
          faceResolution: s.skyEnvironment!.faceResolution,
          equirectWidth: s.skyEnvironment!.equirectWidth,
        ),
);

SkySourceSpec _copySkySource(SkySourceSpec source) => switch (source) {
  EnvironmentSkySpec(:final blurriness) => EnvironmentSkySpec(
    blurriness: blurriness,
  ),
  FmatSkySpec(:final asset, :final properties) => FmatSkySpec(
    asset,
    properties: Map.of(properties),
  ),
  GradientSkySpec s => GradientSkySpec(
    zenithColor: s.zenithColor.clone(),
    horizonColor: s.horizonColor.clone(),
    groundColor: s.groundColor.clone(),
    sunDirection: s.sunDirection.clone(),
    sunColor: s.sunColor.clone(),
    sunSharpness: s.sunSharpness,
  ),
  PhysicalSkySpec s => PhysicalSkySpec(
    sunDirection: s.sunDirection.clone(),
    sunAngularRadius: s.sunAngularRadius,
    rayleighCoefficient: s.rayleighCoefficient,
    rayleighColor: s.rayleighColor.clone(),
    mieCoefficient: s.mieCoefficient,
    mieEccentricity: s.mieEccentricity,
    mieColor: s.mieColor.clone(),
    turbidity: s.turbidity,
    groundColor: s.groundColor.clone(),
    energy: s.energy,
  ),
};
