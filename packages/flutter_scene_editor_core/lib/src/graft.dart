/// Cross-document graft for importing one document's content into another.
///
/// [graftDocumentRecords] copies every node, resource, skin, animation, and
/// payload from a source document into a target document with fresh ids,
/// remapping every id reference (child links, skins, node/resource refs in
/// component and material properties, payload chunks) so the grafted content
/// is self-consistent and independent of the source. The source's roots are
/// appended under a chosen parent (or the target's root list). Returned as
/// change records so the whole import is one reversible transaction.
library;

import 'package:scene/scene.dart' hide NodeChange;

import 'change.dart';

/// Builds the change records that graft [source]'s content into [target] with
/// fresh ids. When [parentId] names an existing node, the source roots are
/// appended as its children; otherwise they are appended to the document roots.
///
/// Returns the records (apply order: payloads, resources, skins, animations,
/// nodes, then the parent/root link) and the new root ids (for selection).
({List<ChangeRecord> records, List<LocalId> rootIds}) graftDocumentRecords(
  SceneDocument target,
  SceneDocument source, {
  LocalId? parentId,
}) {
  // A fresh target id for every id-keyed entity in the source.
  final idMap = <LocalId, LocalId>{};
  for (final id in source.nodes.keys) {
    idMap[id] = target.newId();
  }
  for (final id in source.resources.keys) {
    idMap[id] = target.newId();
  }
  for (final id in source.skins.keys) {
    idMap[id] = target.newId();
  }
  for (final id in source.animations.keys) {
    idMap[id] = target.newId();
  }
  for (final id in source.payloads.keys) {
    idMap[id] = target.newId();
  }
  LocalId remap(LocalId id) => idMap[id] ?? id;

  final records = <ChangeRecord>[];
  for (final payload in source.payloads.values) {
    records.add(
      ChangeRecord(
        targetId: remap(payload.id),
        slot: ChangeSlot.poolPayload,
        oldValue: const PayloadChange(null),
        newValue: PayloadChange(_copyPayload(payload, remap)),
      ),
    );
  }
  for (final resource in source.resources.values) {
    records.add(
      ChangeRecord(
        targetId: remap(resource.id),
        slot: ChangeSlot.poolResource,
        oldValue: const ResourceChange(null),
        newValue: ResourceChange(_copyResource(resource, remap)),
      ),
    );
  }
  for (final skin in source.skins.values) {
    records.add(
      ChangeRecord(
        targetId: remap(skin.id),
        slot: ChangeSlot.poolSkin,
        oldValue: const SkinChange(null),
        newValue: SkinChange(_copySkin(skin, remap)),
      ),
    );
  }
  for (final animation in source.animations.values) {
    records.add(
      ChangeRecord(
        targetId: remap(animation.id),
        slot: ChangeSlot.poolAnimation,
        oldValue: const AnimationChange(null),
        newValue: AnimationChange(_copyAnimation(animation, remap)),
      ),
    );
  }
  for (final node in source.nodes.values) {
    records.add(
      ChangeRecord(
        targetId: remap(node.id),
        slot: ChangeSlot.poolNode,
        oldValue: const NodeChange(null),
        newValue: NodeChange(_copyNode(node, remap)),
      ),
    );
  }

  final rootIds = [for (final id in source.roots) remap(id)];
  if (rootIds.isNotEmpty) {
    final parent = parentId != null ? target.nodes[parentId] : null;
    if (parent != null) {
      final old = List.of(parent.children);
      records.add(
        ChangeRecord(
          targetId: parentId!,
          slot: ChangeSlot.children,
          oldValue: IdListChange(old),
          newValue: IdListChange([...old, ...rootIds]),
        ),
      );
    } else {
      final old = List.of(target.roots);
      records.add(
        ChangeRecord(
          targetId: ChangeRecord.rootsTarget,
          slot: ChangeSlot.roots,
          oldValue: IdListChange(old),
          newValue: IdListChange([...old, ...rootIds]),
        ),
      );
    }
  }
  return (records: records, rootIds: rootIds);
}

/// Reparents [doc]'s current roots under a new group node named [name] that
/// carries [transform], and returns the new group's id. The former roots
/// become the group's children and the group becomes the document's sole root.
/// Used to apply a non-destructive import transform (a scale or axis fix lives
/// on an ordinary, editable node rather than baked into geometry).
LocalId wrapRootsUnderGroup(
  SceneDocument doc, {
  required String name,
  required TransformSpec transform,
}) {
  final group = doc.createNode(name: name, transform: transform);
  final formerRoots = List.of(doc.roots);
  group.children.addAll(formerRoots);
  doc.roots
    ..clear()
    ..add(group.id);
  return group.id;
}

typedef _Remap = LocalId Function(LocalId);

PayloadSpec _copyPayload(PayloadSpec p, _Remap remap) => PayloadSpec(
  remap(p.id),
  encoding: p.encoding,
  layout: p.layout,
  format: p.format,
  width: p.width,
  height: p.height,
  length: p.length,
  bytes: p.bytes,
);

ResourceSpec _copyResource(ResourceSpec r, _Remap remap) => switch (r) {
  GeometryResource g => GeometryResource(
    remap(g.id),
    vertices: g.vertices == null ? null : remap(g.vertices!),
    indices: g.indices == null ? null : remap(g.indices!),
    procedural: g.procedural,
    bounds: g.bounds,
    topology: g.topology,
  ),
  TextureResource t => TextureResource(
    remap(t.id),
    payload: t.payload == null ? null : remap(t.payload!),
    asset: t.asset,
  ),
  MaterialResource m => MaterialResource(
    remap(m.id),
    type: m.type,
    name: m.name,
    properties: {
      for (final e in m.properties.entries) e.key: _copyValue(e.value, remap),
    },
    asset: m.asset,
  ),
  RenderTextureResource rt => RenderTextureResource(
    remap(rt.id),
    width: rt.width,
    height: rt.height,
    update: rt.update,
    intervalMilliseconds: rt.intervalMilliseconds,
    filter: rt.filter,
    wrap: rt.wrap,
  ),
  EnvironmentResource e => EnvironmentResource(
    remap(e.id),
    name: e.name,
    environment: e.environment,
    environmentIntensity: e.environmentIntensity,
    exposure: e.exposure,
    toneMapping: e.toneMapping,
    radianceCubeSize: e.radianceCubeSize,
    skybox: e.skybox,
    skyEnvironment: e.skyEnvironment,
  ),
};

SkinSpec _copySkin(SkinSpec s, _Remap remap) => SkinSpec(
  remap(s.id),
  joints: [for (final j in s.joints) remap(j)],
  inverseBindMatrices: remap(s.inverseBindMatrices),
  skeleton: s.skeleton == null ? null : remap(s.skeleton!),
);

AnimationSpec _copyAnimation(AnimationSpec a, _Remap remap) => AnimationSpec(
  remap(a.id),
  name: a.name,
  channels: [
    for (final c in a.channels)
      AnimationChannelSpec(
        target: remap(c.target),
        targetName: c.targetName,
        property: c.property,
        timeline: remap(c.timeline),
        keyframes: remap(c.keyframes),
      ),
  ],
);

NodeSpec _copyNode(NodeSpec n, _Remap remap) => NodeSpec(
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

ComponentSpec _copyComponent(ComponentSpec c, _Remap remap) => ComponentSpec(
  c.type,
  properties: {
    for (final e in c.properties.entries) e.key: _copyValue(e.value, remap),
  },
);

// Remaps both node and resource references, since a grafted document brings
// its resources along (unlike an in-document clone, which shares them).
PropertyValue _copyValue(PropertyValue v, _Remap remap) => switch (v) {
  NodeRefValue(:final id) => NodeRefValue(remap(id)),
  ResourceRefValue(:final id) => ResourceRefValue(remap(id)),
  ListValue(:final values) => ListValue([
    for (final e in values) _copyValue(e, remap),
  ]),
  MapValue(:final values) => MapValue({
    for (final e in values.entries) e.key: _copyValue(e.value, remap),
  }),
  _ => v,
};

PrefabInstanceSpec _copyInstance(PrefabInstanceSpec i, _Remap remap) =>
    PrefabInstanceSpec(
      source: i.source,
      load: i.load,
      // Override targets are prefab-local ids, copied without remapping; added
      // and attached nodes carry document ids that the remap covers.
      overrides: [
        for (final o in i.overrides)
          PropertyOverride(target: o.target, path: o.path, value: o.value),
      ],
      attachments: [
        for (final a in i.attachments)
          Attachment(remap(a.node), parent: a.parent),
      ],
      removedNodes: List.of(i.removedNodes),
      addedComponents: [
        for (final c in i.addedComponents) _copyComponent(c, remap),
      ],
      removedComponentTypes: List.of(i.removedComponentTypes),
    );
