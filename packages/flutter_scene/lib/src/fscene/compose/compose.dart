/// Prefab composition: expands a document's prefab instances into a flat,
/// fully-realized document.
///
/// A [NodeSpec] whose [NodeSpec.instance] is set is a prefab instance: a
/// reference to another `.fscene` plus a per-instance delta (overrides, added
/// and removed nodes/components). [composeScene] resolves each reference,
/// recursively composes the referenced prefab, remaps its document-local id
/// space deterministically (nodes per instance, so two instances of one
/// prefab are distinct and a recompose keeps stable ids; resources and
/// payloads per prefab, so instances share one copy), inlines it, and applies
/// the delta. The result has no eager instance nodes left and feeds straight
/// into `realizeScene`; lazy instances pass through as placeholders for the
/// streaming layer.
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

/// Where a composed node came from: the instance it was expanded under, the
/// node's id in the prefab document, and that prefab's source.
///
/// An editor uses this to map a composed node back to the instance and the
/// prefab-local id an override targets, so prefab content can be edited in
/// place. For the single-root merge the instance node itself appears here with
/// [prefabLocalId] set to the prefab root.
class PrefabMemberOrigin {
  /// Creates an origin record.
  PrefabMemberOrigin({
    required this.instanceId,
    required this.prefabLocalId,
    required this.source,
  });

  /// The composed instance node this member was expanded under.
  final LocalId instanceId;

  /// The member's id within the prefab document (the id an override targets).
  final LocalId prefabLocalId;

  /// The prefab the member came from.
  final AssetRef source;
}

/// Expands every prefab instance in [document], returning a new document with
/// no instance nodes. A document with no instances is returned unchanged.
///
/// [resolve] loads a referenced prefab document. A cyclic reference (a prefab
/// that instantiates itself, directly or transitively) is broken with a
/// warning rather than recursing forever.
///
/// When [memberOrigins] is given, it is filled with one entry per composed node
/// that came from an instance (keyed by composed id), so a caller can map
/// composed content back to the instance and prefab-local id it edits.
SceneDocument composeScene(
  SceneDocument document, {
  required PrefabResolver resolve,
  Map<LocalId, PrefabMemberOrigin>? memberOrigins,
}) => _compose(document, resolve, <String>{}, memberOrigins);

/// Loads every prefab document [document] references (transitively, breadth
/// first, each source loaded once) via [load], then composes synchronously.
///
/// The async counterpart of [composeScene]: the asset loaders call this so a
/// scene that references prefab files by source path is expanded before
/// realizing. A reference that fails to load throws.
Future<SceneDocument> composeSceneAsync(
  SceneDocument document, {
  required AsyncPrefabLoader load,
  Map<LocalId, PrefabMemberOrigin>? memberOrigins,
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
    memberOrigins: memberOrigins,
  );
}

Iterable<AssetRef> _prefabRefs(SceneDocument doc) =>
    doc.nodes.values.where(_isEager).map((node) => node.instance!.source);

bool _isEager(NodeSpec node) =>
    node.instance != null && node.instance!.load == LoadPolicy.eager;

SceneDocument _compose(
  SceneDocument document,
  PrefabResolver resolve,
  Set<String> visiting, [
  Map<LocalId, PrefabMemberOrigin>? memberOrigins,
]) {
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
    _expandInstance(out, instance, resolve, visiting, memberOrigins);
  }
  return out;
}

void _expandInstance(
  SceneDocument out,
  NodeSpec instance,
  PrefabResolver resolve,
  Set<String> visiting,
  Map<LocalId, PrefabMemberOrigin>? memberOrigins,
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

  // A prefab authored in the opposite handedness gets a mirror adapter node
  // between the instance and the prefab content (so it realizes correctly in
  // the host's space); the adapter suppresses the single-root merge.
  final needsAdapter = prefab.stage.handedness != out.stage.handedness;

  // Deterministic remapping: nodes, skins, and animations derive their id
  // from (instance id, prefab id), so the same node keeps the same id across
  // recomposes and a prefab edit hot-reloads as a fine-grained patch.
  // Resources and payloads derive from the prefab document's identity alone,
  // so every instance of one prefab shares a single copy (and the realizer
  // uploads its GPU resources once). A single-root prefab merges its root
  // into the instance node (so the instance node "is" the prefab root, which
  // is what overrides and added/removed components target).
  final singleRoot = !needsAdapter && prefab.roots.length == 1
      ? prefab.roots.single
      : null;
  final remap = <LocalId, LocalId>{};
  for (final id in prefab.nodes.keys) {
    remap[id] = id == singleRoot ? instance.id : _instanceId(instance.id, id);
  }
  if (memberOrigins != null) {
    for (final id in prefab.nodes.keys) {
      memberOrigins[remap[id]!] = PrefabMemberOrigin(
        instanceId: instance.id,
        prefabLocalId: id,
        source: spec.source,
      );
    }
  }
  for (final id in prefab.skins.keys) {
    remap[id] = _instanceId(instance.id, id);
  }
  for (final id in prefab.animations.keys) {
    remap[id] = _instanceId(instance.id, id);
  }
  for (final id in prefab.resources.keys) {
    remap[id] = _sharedId(prefab.documentId, id);
  }
  for (final id in prefab.payloads.keys) {
    remap[id] = _sharedId(prefab.documentId, id);
  }
  LocalId remapId(LocalId id) => remap[id] ?? id;

  for (final resource in prefab.resources.values) {
    final id = remapId(resource.id);
    if (!out.resources.containsKey(id)) {
      out.addResource(_remapResource(resource, remapId));
    }
  }
  for (final payload in prefab.payloads.values) {
    final id = remapId(payload.id);
    if (!out.payloads.containsKey(id)) {
      out.addPayload(_remapPayload(payload, remapId));
    }
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
      // own transform, name, and layers (its placement in the host). An
      // unnamed instance inherits the prefab root's name.
      if (instance.name.isEmpty) instance.name = node.name;
      instance.components.addAll([
        for (final c in node.components) _remapComponent(c, remapId),
      ]);
      instance.children.addAll([for (final c in node.children) remapId(c)]);
      instance.skin ??= node.skin == null ? null : remapId(node.skin!);
    } else {
      // A nested lazy instance survives composition as a placeholder; its
      // spec stays unremapped (its overrides target the lazy prefab's own
      // id space, resolved when the subtree streams in via loadSubtree).
      out.addNode(
        _remapNode(
          node,
          remapId,
          keepInstance: node.instance?.load == LoadPolicy.lazy,
        ),
      );
    }
  }
  if (needsAdapter) {
    final adapter = NodeSpec(
      id: _instanceId(instance.id, const LocalId(0, 0), domain: 1),
      name: 'handedness',
      transform: MatrixTransform(Matrix4.diagonal3Values(1.0, 1.0, -1.0)),
      children: [for (final r in prefab.roots) remapId(r)],
      excludeFromWindingParity: true,
    );
    out.addNode(adapter);
    instance.children.add(adapter.id);
  } else if (singleRoot == null) {
    instance.children.addAll([for (final r in prefab.roots) remapId(r)]);
  }

  _applyDelta(out, instance, spec, remapId);
}

/// Derives the composed id of a per-instance entity (node, skin, animation)
/// from the instance node's id plus the entity's id in the prefab. Stable
/// across recomposes; distinct per instance. [domain] separates synthesized
/// ids (the handedness adapter) from remapped prefab ids.
LocalId _instanceId(LocalId instance, LocalId target, {int domain = 0}) =>
    _hashedId([
      instance.session,
      instance.index,
      target.session,
      target.index,
      domain,
    ]);

/// Derives the composed id of a shared entity (resource, payload) from the
/// prefab document's identity plus the entity's id, so every instance of one
/// prefab maps it to the same id.
LocalId _sharedId(DocumentId document, LocalId target) => _hashedId([
  for (var i = 0; i < document.bytes.length; i += 4)
    document.bytes[i] |
        (document.bytes[i + 1] << 8) |
        (document.bytes[i + 2] << 16) |
        (document.bytes[i + 3] << 24),
  target.session,
  target.index,
]);

LocalId _hashedId(List<int> words) =>
    LocalId(_jenkins(words, 0x811c9dc5), _jenkins(words, 0x9e3779b9));

// Jenkins one-at-a-time over the words' bytes; shift-and-add only, so the
// arithmetic stays exact on the web (no 32-bit multiplications).
int _jenkins(List<int> words, int seed) {
  var hash = seed & 0xffffffff;
  for (final word in words) {
    for (var shift = 0; shift < 32; shift += 8) {
      hash = (hash + ((word >> shift) & 0xff)) & 0xffffffff;
      hash = (hash + ((hash << 10) & 0xffffffff)) & 0xffffffff;
      hash ^= hash >> 6;
    }
  }
  hash = (hash + ((hash << 3) & 0xffffffff)) & 0xffffffff;
  hash ^= hash >> 11;
  hash = (hash + ((hash << 15) & 0xffffffff)) & 0xffffffff;
  return hash;
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
  // Graft attached host nodes (already present in [out] as real nodes) under
  // their prefab-local parent: detach from wherever they sit, then re-parent
  // under the composed parent (or the instance node when parent is null or
  // missing). A dangling attachment (its node was deleted) is skipped.
  for (final attachment in spec.attachments) {
    final child = attachment.node;
    if (!out.nodes.containsKey(child)) continue;
    out.roots.remove(child);
    for (final n in out.nodes.values) {
      n.children.remove(child);
    }
    final parent = attachment.parent;
    final parentNode = parent == null ? instance : out.node(remapId(parent));
    (parentNode ?? instance).children.add(child);
  }
  instance.components.addAll(spec.addedComponents);
  if (spec.removedComponentTypes.isNotEmpty) {
    instance.components.removeWhere(
      (c) => spec.removedComponentTypes.contains(c.type),
    );
  }
}

// ---- property-path override application ----

/// Applies a single [override] to [document] by resolving the target node
/// (by its prefab-local id) and mutating the property at [override.path].
///
/// Call this to bake an instance override back into the prefab source document,
/// one override at a time. The document is mutated in place. If the target node
/// is not found the call is a no-op (a warning is printed via [debugPrint]).
///
/// The grammar for [PropertyOverride.path] is the same as the override grammar
/// used during composition: `name`, `layers`, `visible`, `transform.matrix`,
/// `transform.trs.t`, `transform.trs.r`, `transform.trs.s`, and
/// `components.<type>.<prop>`.
void applyPrefabOverride(SceneDocument document, PropertyOverride override) {
  final node = document.node(override.target);
  if (node == null) {
    debugPrint(
      'fscene: applyPrefabOverride target "${override.target.toToken()}" not found',
    );
    return;
  }
  _setProperty(node, override.path, override.value);
}

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
    if (parts[0] == 'visible' && value is BoolValue) {
      node.visible = value.value;
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
  excludeFromWindingParity: node.excludeFromWindingParity,
  visible: node.visible,
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
        topology: r.topology,
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
      RenderTextureResource() => RenderTextureResource(
        remap(r.id),
        width: r.width,
        height: r.height,
        update: r.update,
        intervalMilliseconds: r.intervalMilliseconds,
        filter: r.filter,
        wrap: r.wrap,
      ),
      EnvironmentResource() => EnvironmentResource(
        remap(r.id),
        name: r.name,
        environment: r.environment,
        environmentIntensity: r.environmentIntensity,
        exposure: r.exposure,
        toneMapping: r.toneMapping,
        radianceCubeSize: r.radianceCubeSize,
        skybox: r.skybox == null ? null : _copySkybox(r.skybox!),
        skyEnvironment: r.skyEnvironment == null
            ? null
            : _copySkyEnvironment(r.skyEnvironment!),
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
  antiAliasingMode: s.antiAliasingMode,
  renderScale: s.renderScale,
  filterQuality: s.filterQuality,
  environmentRef: s.environmentRef,
);

SkyboxSpec _copySkybox(SkyboxSpec s) =>
    SkyboxSpec(_copySkySource(s.source), intensity: s.intensity);

SkyEnvironmentSpec _copySkyEnvironment(SkyEnvironmentSpec s) =>
    SkyEnvironmentSpec(
      _copySkySource(s.source),
      refresh: s.refresh,
      intervalSeconds: s.intervalSeconds,
      faceResolution: s.faceResolution,
      equirectWidth: s.equirectWidth,
      castShadows: s.castShadows,
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
