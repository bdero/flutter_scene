/// The built-in command set.
///
/// Each command reads the document, validates its params, and returns a
/// [Transaction] of change records. Structural edits (create, delete,
/// reparent) are ordinary record batches thanks to the [NodeChange] pool slot,
/// so undo and redo come for free. Register them all with
/// [registerBuiltinCommands].
library;

import 'dart:typed_data';

import 'package:flutter_scene/src/fscene/id.dart';
import 'package:flutter_scene/src/fscene/property_value.dart';
import 'package:flutter_scene/src/fscene/scene_document.dart';
import 'package:flutter_scene/src/fscene/specs.dart';
import 'package:vector_math/vector_math.dart';

import 'change.dart';
import 'clone.dart';
import 'command.dart';
import 'params.dart';

// ---------------------------------------------------------------------------
// Shared helpers.
// ---------------------------------------------------------------------------

NodeSpec _requireNode(CommandContext ctx, LocalId id) =>
    ctx.document.node(id) ??
    (throw CommandException('Node not found: ${id.toToken()}'));

/// The parent of [id] (the node whose children contain it), or null when [id]
/// is a root.
LocalId? _parentOf(SceneDocument doc, LocalId id) {
  for (final node in doc.nodes.values) {
    if (node.children.contains(id)) return node.id;
  }
  return null;
}

/// The world-space matrix of [id], composed from local transforms up the
/// source hierarchy (identity for a missing node).
Matrix4 _worldMatrix(SceneDocument doc, LocalId id) {
  final node = doc.nodes[id];
  if (node == null) return Matrix4.identity();
  final local = node.transform.toMatrix4();
  final parent = _parentOf(doc, id);
  if (parent == null) return local;
  return _worldMatrix(doc, parent).multiplied(local);
}

/// The local transform [id] needs under [newParent] (the root when null) to
/// keep its current world transform, as a decomposed [TrsTransform].
TrsTransform _worldPreservingLocal(
  SceneDocument doc,
  LocalId id,
  LocalId? newParent,
) {
  final world = _worldMatrix(doc, id);
  final parentWorld = newParent == null
      ? Matrix4.identity()
      : _worldMatrix(doc, newParent);
  final local = Matrix4.inverted(parentWorld)..multiply(world);
  final translation = Vector3.zero();
  final rotation = Quaternion.identity();
  final scale = Vector3.zero();
  local.decompose(translation, rotation, scale);
  return TrsTransform(
    translation: translation,
    rotation: rotation,
    scale: scale,
  );
}

/// All node ids in the subtree rooted at [root] (root first).
List<LocalId> _subtree(SceneDocument doc, LocalId root) {
  final out = <LocalId>[];
  final stack = <LocalId>[root];
  while (stack.isNotEmpty) {
    final id = stack.removeLast();
    final node = doc.nodes[id];
    if (node == null) continue;
    out.add(id);
    stack.addAll(node.children);
  }
  return out;
}

/// A record removing [id] from its container ([parent]'s children, or roots).
ChangeRecord _detach(SceneDocument doc, LocalId id, LocalId? parent) {
  if (parent == null) {
    final old = List.of(doc.roots);
    return ChangeRecord(
      targetId: ChangeRecord.rootsTarget,
      slot: ChangeSlot.roots,
      oldValue: IdListChange(old),
      newValue: IdListChange([
        for (final e in old)
          if (e != id) e,
      ]),
    );
  }
  final old = List.of(doc.nodes[parent]!.children);
  return ChangeRecord(
    targetId: parent,
    slot: ChangeSlot.children,
    oldValue: IdListChange(old),
    newValue: IdListChange([
      for (final e in old)
        if (e != id) e,
    ]),
  );
}

/// A record adding [id] to its container ([parent]'s children, or roots).
ChangeRecord _attach(SceneDocument doc, LocalId id, LocalId? parent) {
  if (parent == null) {
    final old = List.of(doc.roots);
    return ChangeRecord(
      targetId: ChangeRecord.rootsTarget,
      slot: ChangeSlot.roots,
      oldValue: IdListChange(old),
      newValue: IdListChange([...old, id]),
    );
  }
  final old = List.of(doc.nodes[parent]!.children);
  return ChangeRecord(
    targetId: parent,
    slot: ChangeSlot.children,
    oldValue: IdListChange(old),
    newValue: IdListChange([...old, id]),
  );
}

/// The current ordered id list of [parent]'s container (its children, or the
/// document roots when [parent] is null).
List<LocalId> _containerOf(SceneDocument doc, LocalId? parent) =>
    parent == null ? doc.roots : doc.nodes[parent]!.children;

/// A record replacing [parent]'s container (children, or roots) with [next].
ChangeRecord _containerRecord(
  SceneDocument doc,
  LocalId? parent,
  List<LocalId> old,
  List<LocalId> next,
) => parent == null
    ? ChangeRecord(
        targetId: ChangeRecord.rootsTarget,
        slot: ChangeSlot.roots,
        oldValue: IdListChange(old),
        newValue: IdListChange(next),
      )
    : ChangeRecord(
        targetId: parent,
        slot: ChangeSlot.children,
        oldValue: IdListChange(old),
        newValue: IdListChange(next),
      );

/// A record placing [id] into [parent]'s container at [index] (appended when
/// [index] is null), removing any existing occurrence first so this doubles as
/// a same-container reorder. Returns null when the container is unchanged.
ChangeRecord? _attachAt(
  SceneDocument doc,
  LocalId id,
  LocalId? parent,
  int? index,
) {
  final old = List.of(_containerOf(doc, parent));
  final next = [
    for (final e in old)
      if (e != id) e,
  ];
  final at = index == null ? next.length : index.clamp(0, next.length);
  next.insert(at, id);
  if (_sameOrder(old, next)) return null;
  return _containerRecord(doc, parent, old, next);
}

bool _sameOrder(List<LocalId> a, List<LocalId> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Whether any ancestor of [id] is itself in [set] (so [id] is not a top-level
/// member of a selection and should be skipped to avoid double-processing).
bool _hasAncestorIn(SceneDocument doc, LocalId id, Set<LocalId> set) {
  var parent = _parentOf(doc, id);
  while (parent != null) {
    if (set.contains(parent)) return true;
    parent = _parentOf(doc, parent);
  }
  return false;
}

/// The top-level members of [ids] (those with no ancestor also in [ids]),
/// returned in document order (roots first, depth-first), with duplicates
/// dropped.
List<LocalId> _topLevel(SceneDocument doc, List<LocalId> ids) {
  final set = ids.toSet();
  final tops = {
    for (final id in ids)
      if (doc.nodes.containsKey(id) && !_hasAncestorIn(doc, id, set)) id,
  };
  final ordered = <LocalId>[];
  void visit(LocalId id) {
    if (tops.contains(id)) ordered.add(id);
    final node = doc.nodes[id];
    if (node == null) return;
    for (final child in node.children) {
      visit(child);
    }
  }

  for (final root in doc.roots) {
    visit(root);
  }
  return ordered;
}

ChangeRecord _componentsRecord(NodeSpec node, List<ComponentSpec> next) =>
    ChangeRecord(
      targetId: node.id,
      slot: ChangeSlot.components,
      oldValue: ComponentListChange(List.of(node.components)),
      newValue: ComponentListChange(next),
    );

const _empty = <ChangeRecord>[];

// ---------------------------------------------------------------------------
// Node field commands.
// ---------------------------------------------------------------------------

final setNodeName = CommandEntry(
  name: 'setNodeName',
  doc: 'Set a node\'s name.',
  category: 'Node',
  paramSchema: const [
    ParamSpec(name: 'nodeId', type: ParamType.nodeRef, label: 'Node'),
    ParamSpec(name: 'name', type: ParamType.string, label: 'Name'),
  ],
  execute: (ctx, params) {
    final id = requireNodeId(params, 'nodeId');
    final node = _requireNode(ctx, id);
    return Transaction(
      name: 'Rename node',
      records: [
        ChangeRecord(
          targetId: id,
          slot: ChangeSlot.name,
          oldValue: StringChange(node.name),
          newValue: StringChange(requireString(params, 'name')),
        ),
      ],
    );
  },
);

final setNodeVisible = CommandEntry(
  name: 'setNodeVisible',
  doc: 'Show or hide a node.',
  category: 'Node',
  paramSchema: const [
    ParamSpec(name: 'nodeId', type: ParamType.nodeRef, label: 'Node'),
    ParamSpec(name: 'visible', type: ParamType.boolean, label: 'Visible'),
  ],
  execute: (ctx, params) {
    final id = requireNodeId(params, 'nodeId');
    final node = _requireNode(ctx, id);
    return Transaction(
      name: 'Set visibility',
      records: [
        ChangeRecord(
          targetId: id,
          slot: ChangeSlot.visible,
          oldValue: BoolChange(node.visible),
          newValue: BoolChange(requireBool(params, 'visible')),
        ),
      ],
    );
  },
);

final setNodeLayers = CommandEntry(
  name: 'setNodeLayers',
  doc: 'Set a node\'s render-layer bitmask.',
  category: 'Node',
  paramSchema: const [
    ParamSpec(name: 'nodeId', type: ParamType.nodeRef, label: 'Node'),
    ParamSpec(name: 'layers', type: ParamType.integer, label: 'Layers'),
  ],
  execute: (ctx, params) {
    final id = requireNodeId(params, 'nodeId');
    final node = _requireNode(ctx, id);
    return Transaction(
      name: 'Set layers',
      records: [
        ChangeRecord(
          targetId: id,
          slot: ChangeSlot.layers,
          oldValue: IntChange(node.layers),
          newValue: IntChange(requireInt(params, 'layers')),
        ),
      ],
    );
  },
);

final setNodeTransform = CommandEntry(
  name: 'setNodeTransform',
  doc:
      'Set a node\'s local transform. Omitted components keep their current '
      'value.',
  category: 'Node',
  paramSchema: const [
    ParamSpec(name: 'nodeId', type: ParamType.nodeRef, label: 'Node'),
    ParamSpec(
      name: 'translation',
      type: ParamType.vec3,
      label: 'Translation',
      required: false,
    ),
    ParamSpec(
      name: 'rotation',
      type: ParamType.quaternion,
      label: 'Rotation',
      required: false,
    ),
    ParamSpec(
      name: 'scale',
      type: ParamType.vec3,
      label: 'Scale',
      required: false,
    ),
  ],
  execute: (ctx, params) {
    final id = requireNodeId(params, 'nodeId');
    final node = _requireNode(ctx, id);
    final current = node.transform;
    final trs = current is TrsTransform ? current : null;
    final next = TrsTransform(
      translation:
          optionalVec3(params, 'translation') ??
          trs?.translation ??
          Vector3.zero(),
      rotation:
          optionalQuaternion(params, 'rotation') ??
          trs?.rotation ??
          Quaternion.identity(),
      scale: optionalVec3(params, 'scale') ?? trs?.scale ?? Vector3(1, 1, 1),
    );
    return Transaction(
      name: 'Set transform',
      records: [
        ChangeRecord(
          targetId: id,
          slot: ChangeSlot.transform,
          oldValue: TransformChange(current),
          newValue: TransformChange(next),
        ),
      ],
    );
  },
);

// ---------------------------------------------------------------------------
// Structural commands.
// ---------------------------------------------------------------------------

final createNode = CommandEntry(
  name: 'createNode',
  doc: 'Create an empty node, optionally parented under another node.',
  category: 'Node',
  paramSchema: const [
    ParamSpec(
      name: 'name',
      type: ParamType.string,
      label: 'Name',
      required: false,
    ),
    ParamSpec(
      name: 'parentId',
      type: ParamType.nodeRef,
      label: 'Parent',
      required: false,
    ),
  ],
  execute: (ctx, params) {
    final parentId = optionalNodeId(params, 'parentId');
    if (parentId != null) _requireNode(ctx, parentId);
    final node = NodeSpec(
      id: ctx.document.newId(),
      name: optionalString(params, 'name', orElse: '')!,
    );
    return Transaction(
      name: 'Create node',
      records: [
        ChangeRecord(
          targetId: node.id,
          slot: ChangeSlot.poolNode,
          oldValue: const NodeChange(null),
          newValue: NodeChange(node),
        ),
        _attach(ctx.document, node.id, parentId),
      ],
    );
  },
);

final deleteNode = CommandEntry(
  name: 'deleteNode',
  doc: 'Delete a node and its entire subtree.',
  category: 'Node',
  paramSchema: const [
    ParamSpec(name: 'nodeId', type: ParamType.nodeRef, label: 'Node'),
  ],
  execute: (ctx, params) {
    final id = requireNodeId(params, 'nodeId');
    _requireNode(ctx, id);
    final doc = ctx.document;
    final parent = _parentOf(doc, id);
    return Transaction(
      name: 'Delete node',
      records: [
        _detach(doc, id, parent),
        for (final nid in _subtree(doc, id))
          ChangeRecord(
            targetId: nid,
            slot: ChangeSlot.poolNode,
            oldValue: NodeChange(doc.nodes[nid]),
            newValue: const NodeChange(null),
          ),
      ],
    );
  },
);

final reparentNode = CommandEntry(
  name: 'reparentNode',
  doc:
      'Move a node under a new parent (or to the root list), optionally at a '
      'specific index. Passing the current parent with an index reorders the '
      'node among its siblings.',
  category: 'Node',
  paramSchema: const [
    ParamSpec(name: 'nodeId', type: ParamType.nodeRef, label: 'Node'),
    ParamSpec(
      name: 'newParentId',
      type: ParamType.nodeRef,
      label: 'New parent',
      required: false,
    ),
    ParamSpec(
      name: 'index',
      type: ParamType.integer,
      label: 'Index',
      required: false,
    ),
    ParamSpec(
      name: 'keepWorldTransform',
      type: ParamType.boolean,
      label: 'Keep world transform',
      required: false,
    ),
  ],
  execute: (ctx, params) {
    final id = requireNodeId(params, 'nodeId');
    final node = _requireNode(ctx, id);
    final doc = ctx.document;
    final newParent = optionalNodeId(params, 'newParentId');
    final index = optionalInt(params, 'index');
    if (newParent != null) {
      _requireNode(ctx, newParent);
      if (_subtree(doc, id).contains(newParent)) {
        throw const CommandException(
          'Cannot reparent a node under itself or a descendant',
        );
      }
    }
    final oldParent = _parentOf(doc, id);
    if (oldParent == newParent) {
      // Same container: a pure reorder (or a no-op when the index is omitted
      // or already correct).
      final record = _attachAt(doc, id, newParent, index);
      return Transaction(
        name: 'Reorder node',
        records: record == null ? _empty : [record],
      );
    }
    // By default the node keeps its world transform across the move, so it does
    // not visually jump (its local transform is recomputed under the new
    // parent). Pass keepWorldTransform false to keep the local transform.
    final keepWorld = params['keepWorldTransform'] != false;
    final attach = _attachAt(doc, id, newParent, index)!;
    return Transaction(
      name: 'Reparent node',
      records: [
        _detach(doc, id, oldParent),
        attach,
        if (keepWorld)
          ChangeRecord(
            targetId: id,
            slot: ChangeSlot.transform,
            oldValue: TransformChange(node.transform),
            newValue: TransformChange(
              _worldPreservingLocal(doc, id, newParent),
            ),
          ),
      ],
    );
  },
);

/// Clones one or more node subtrees in place. Each top-level node in [nodeIds]
/// is deep-copied with fresh ids and inserted right after the original among
/// its siblings; nodes nested under another selected node are skipped.
final duplicateNodes = CommandEntry(
  name: 'duplicateNodes',
  doc: 'Duplicate node subtrees in place, each after its original.',
  category: 'Node',
  paramSchema: const [
    ParamSpec(name: 'nodeIds', type: ParamType.nodeRefList, label: 'Nodes'),
  ],
  execute: (ctx, params) {
    final doc = ctx.document;
    final tops = _topLevel(doc, requireNodeIdList(params, 'nodeIds'));
    if (tops.isEmpty) {
      return Transaction(name: 'Duplicate', records: _empty);
    }
    final records = <ChangeRecord>[];
    // One working copy per touched container, so multiple clones in the same
    // parent land in a single id-list record (records on the same slot would
    // otherwise overwrite each other).
    final oldLists = <LocalId?, List<LocalId>>{};
    final working = <LocalId?, List<LocalId>>{};
    List<LocalId> containerFor(LocalId? parent) =>
        working.putIfAbsent(parent, () {
          final src = List.of(_containerOf(doc, parent));
          oldLists[parent] = List.of(src);
          return src;
        });

    for (final id in tops) {
      final subtree = captureSubtree(doc, id);
      final inst = instantiateSubtree(subtree, doc.newId);
      for (final node in inst.nodes) {
        records.add(
          ChangeRecord(
            targetId: node.id,
            slot: ChangeSlot.poolNode,
            oldValue: const NodeChange(null),
            newValue: NodeChange(node),
          ),
        );
      }
      final parent = _parentOf(doc, id);
      final list = containerFor(parent);
      list.insert(list.indexOf(id) + 1, inst.root);
    }
    for (final entry in working.entries) {
      records.add(
        _containerRecord(doc, entry.key, oldLists[entry.key]!, entry.value),
      );
    }
    return Transaction(name: 'Duplicate', records: records);
  },
);

/// Inserts detached subtrees (clipboard content) into the document with fresh
/// ids, appended under [parentId] (the root list when omitted). The `subtrees`
/// param carries in-memory [NodeSubtree] objects, so this command is driven by
/// the editor rather than serialized agent calls.
///
/// TODO(paste-agent-schema): accept a serialized subtree form so an agent can
/// paste through the MCP surface, not just the in-process editor.
final pasteNodes = CommandEntry(
  name: 'pasteNodes',
  doc: 'Insert copied node subtrees with fresh ids under a parent.',
  category: 'Node',
  paramSchema: const [
    ParamSpec(
      name: 'parentId',
      type: ParamType.nodeRef,
      label: 'Parent',
      required: false,
    ),
  ],
  execute: (ctx, params) {
    final doc = ctx.document;
    final parent = optionalNodeId(params, 'parentId');
    if (parent != null) _requireNode(ctx, parent);
    final raw = params['subtrees'];
    if (raw is! List) {
      throw const CommandException('Param subtrees must be a list');
    }
    final records = <ChangeRecord>[];
    final old = List.of(_containerOf(doc, parent));
    final next = List.of(old);
    for (final item in raw) {
      if (item is! NodeSubtree) {
        throw const CommandException('Each subtree must be a NodeSubtree');
      }
      final inst = instantiateSubtree(item, doc.newId);
      for (final node in inst.nodes) {
        records.add(
          ChangeRecord(
            targetId: node.id,
            slot: ChangeSlot.poolNode,
            oldValue: const NodeChange(null),
            newValue: NodeChange(node),
          ),
        );
      }
      next.add(inst.root);
    }
    if (records.isEmpty) return Transaction(name: 'Paste', records: _empty);
    records.add(_containerRecord(doc, parent, old, next));
    return Transaction(name: 'Paste', records: records);
  },
);

/// Deletes one or more node subtrees in a single transaction. Nodes nested
/// under another deleted node are skipped (the subtree removal covers them).
final deleteNodes = CommandEntry(
  name: 'deleteNodes',
  doc: 'Delete node subtrees in one undoable step.',
  category: 'Node',
  paramSchema: const [
    ParamSpec(name: 'nodeIds', type: ParamType.nodeRefList, label: 'Nodes'),
  ],
  execute: (ctx, params) {
    final doc = ctx.document;
    final tops = _topLevel(doc, requireNodeIdList(params, 'nodeIds'));
    if (tops.isEmpty) {
      return Transaction(name: 'Delete', records: _empty);
    }
    final records = <ChangeRecord>[];
    // Detach each top-level node from its container in one record per
    // container, then drop every node in every subtree from the pool.
    final oldLists = <LocalId?, List<LocalId>>{};
    final working = <LocalId?, List<LocalId>>{};
    List<LocalId> containerFor(LocalId? parent) =>
        working.putIfAbsent(parent, () {
          final src = List.of(_containerOf(doc, parent));
          oldLists[parent] = List.of(src);
          return src;
        });
    for (final id in tops) {
      containerFor(_parentOf(doc, id)).remove(id);
    }
    for (final entry in working.entries) {
      records.add(
        _containerRecord(doc, entry.key, oldLists[entry.key]!, entry.value),
      );
    }
    for (final id in tops) {
      for (final nid in _subtree(doc, id)) {
        records.add(
          ChangeRecord(
            targetId: nid,
            slot: ChangeSlot.poolNode,
            oldValue: NodeChange(doc.nodes[nid]),
            newValue: const NodeChange(null),
          ),
        );
      }
    }
    return Transaction(name: 'Delete', records: records);
  },
);

// ---------------------------------------------------------------------------
// Component commands.
// ---------------------------------------------------------------------------

final addComponent = CommandEntry(
  name: 'addComponent',
  doc:
      'Attach a component to a node, replacing any existing one of the same '
      'type.',
  category: 'Component',
  paramSchema: const [
    ParamSpec(name: 'nodeId', type: ParamType.nodeRef, label: 'Node'),
    ParamSpec(name: 'componentType', type: ParamType.string, label: 'Type'),
    ParamSpec(
      name: 'properties',
      type: ParamType.propertyMap,
      label: 'Properties',
      required: false,
    ),
  ],
  execute: (ctx, params) {
    final id = requireNodeId(params, 'nodeId');
    final node = _requireNode(ctx, id);
    final type = requireString(params, 'componentType');
    final component = ComponentSpec(
      type,
      properties: optionalPropertyMap(params, 'properties'),
    );
    return Transaction(
      name: 'Add component ($type)',
      records: [
        _componentsRecord(node, [
          for (final c in node.components)
            if (c.type != type) c,
          component,
        ]),
      ],
    );
  },
);

final removeComponent = CommandEntry(
  name: 'removeComponent',
  doc: 'Remove the component of a given type from a node.',
  category: 'Component',
  paramSchema: const [
    ParamSpec(name: 'nodeId', type: ParamType.nodeRef, label: 'Node'),
    ParamSpec(name: 'componentType', type: ParamType.string, label: 'Type'),
  ],
  execute: (ctx, params) {
    final id = requireNodeId(params, 'nodeId');
    final node = _requireNode(ctx, id);
    final type = requireString(params, 'componentType');
    if (!node.components.any((c) => c.type == type)) {
      return Transaction(name: 'Remove component', records: _empty);
    }
    return Transaction(
      name: 'Remove component ($type)',
      records: [
        _componentsRecord(node, [
          for (final c in node.components)
            if (c.type != type) c,
        ]),
      ],
    );
  },
);

final setComponentProperties = CommandEntry(
  name: 'setComponentProperties',
  doc: 'Merge properties into an existing component on a node.',
  category: 'Component',
  paramSchema: const [
    ParamSpec(name: 'nodeId', type: ParamType.nodeRef, label: 'Node'),
    ParamSpec(name: 'componentType', type: ParamType.string, label: 'Type'),
    ParamSpec(
      name: 'properties',
      type: ParamType.propertyMap,
      label: 'Properties',
    ),
  ],
  execute: (ctx, params) {
    final id = requireNodeId(params, 'nodeId');
    final node = _requireNode(ctx, id);
    final type = requireString(params, 'componentType');
    final existing = node.components.where((c) => c.type == type).firstOrNull;
    if (existing == null) {
      throw CommandException('Node has no component of type: $type');
    }
    final merged = ComponentSpec(
      type,
      properties: {
        ...existing.properties,
        ...optionalPropertyMap(params, 'properties'),
      },
    );
    return Transaction(
      name: 'Set component properties ($type)',
      records: [
        _componentsRecord(node, [
          for (final c in node.components)
            if (c.type != type) c else merged,
        ]),
      ],
    );
  },
);

// ---------------------------------------------------------------------------
// Resource commands.
// ---------------------------------------------------------------------------

ChangeRecord _addResourceRecord(ResourceSpec resource) => ChangeRecord(
  targetId: resource.id,
  slot: ChangeSlot.poolResource,
  oldValue: const ResourceChange(null),
  newValue: ResourceChange(resource),
);

final createCuboidGeometry = CommandEntry(
  name: 'createCuboidGeometry',
  doc: 'Create a procedural cuboid geometry resource.',
  category: 'Resource',
  paramSchema: const [
    ParamSpec(
      name: 'extents',
      type: ParamType.vec3,
      label: 'Extents',
      required: false,
    ),
  ],
  execute: (ctx, params) {
    final resource = GeometryResource(
      ctx.document.newId(),
      procedural: CuboidGeometrySpec(
        extents: optionalVec3(params, 'extents') ?? Vector3(1, 1, 1),
      ),
    );
    return Transaction(
      name: 'Create cuboid',
      records: [_addResourceRecord(resource)],
    );
  },
);

final createSphereGeometry = CommandEntry(
  name: 'createSphereGeometry',
  doc: 'Create a procedural sphere geometry resource.',
  category: 'Resource',
  paramSchema: const [
    ParamSpec(
      name: 'radius',
      type: ParamType.number,
      label: 'Radius',
      required: false,
    ),
  ],
  execute: (ctx, params) {
    final radius = params['radius'] == null
        ? 0.5
        : requireDouble(params, 'radius');
    final resource = GeometryResource(
      ctx.document.newId(),
      procedural: SphereGeometrySpec(radius: radius),
    );
    return Transaction(
      name: 'Create sphere',
      records: [_addResourceRecord(resource)],
    );
  },
);

final createMaterial = CommandEntry(
  name: 'createMaterial',
  doc: 'Create a material resource of the given type.',
  category: 'Resource',
  paramSchema: const [
    ParamSpec(name: 'type', type: ParamType.string, label: 'Type'),
    ParamSpec(
      name: 'properties',
      type: ParamType.propertyMap,
      label: 'Properties',
      required: false,
    ),
    ParamSpec(
      name: 'asset',
      type: ParamType.assetRef,
      label: 'Asset (.fmat)',
      required: false,
    ),
  ],
  execute: (ctx, params) {
    final assetKey = optionalString(params, 'asset');
    final resource = MaterialResource(
      ctx.document.newId(),
      type: requireString(params, 'type'),
      properties: optionalPropertyMap(params, 'properties'),
      asset: assetKey == null ? null : AssetRef(assetKey),
    );
    return Transaction(
      name: 'Create material',
      records: [_addResourceRecord(resource)],
    );
  },
);

/// Creates a texture resource from raw RGBA8 image bytes (`width * height * 4`
/// bytes, row-major, passed as the `bytes` param). UI-driven (an importer
/// decodes the image); not practical over MCP. Returns nothing; the caller
/// finds the new resource id by diffing the resource pool.
final createTextureResource = CommandEntry(
  name: 'createTextureResource',
  doc: 'Create a texture resource from raw RGBA8 image bytes.',
  category: 'Resource',
  paramSchema: const [
    ParamSpec(name: 'width', type: ParamType.integer, label: 'Width'),
    ParamSpec(name: 'height', type: ParamType.integer, label: 'Height'),
  ],
  execute: (ctx, params) {
    final width = requireInt(params, 'width');
    final height = requireInt(params, 'height');
    final bytes = params['bytes'];
    if (bytes is! Uint8List) {
      throw const CommandException(
        'createTextureResource requires rgba8 bytes (Uint8List)',
      );
    }
    final expected = width * height * 4;
    if (bytes.length != expected) {
      throw CommandException(
        'bytes length ${bytes.length} != width*height*4 ($expected)',
      );
    }
    final payload = PayloadSpec(
      ctx.document.newId(),
      encoding: PayloadEncoding.image,
      format: 'rgba8',
      width: width,
      height: height,
      length: bytes.length,
      bytes: bytes,
    );
    final resource = TextureResource(ctx.document.newId(), payload: payload.id);
    return Transaction(
      name: 'Create texture',
      records: [
        ChangeRecord(
          targetId: payload.id,
          slot: ChangeSlot.poolPayload,
          oldValue: const PayloadChange(null),
          newValue: PayloadChange(payload),
        ),
        _addResourceRecord(resource),
      ],
    );
  },
);

/// Merges [properties] into an existing material resource (base color, PBR
/// factors, alpha mode, texture refs, ...), the resource-pool counterpart of
/// [setComponentProperties].
final setMaterialProperties = CommandEntry(
  name: 'setMaterialProperties',
  doc: 'Merge properties into a material resource.',
  category: 'Resource',
  paramSchema: const [
    ParamSpec(
      name: 'materialId',
      type: ParamType.resourceRef,
      label: 'Material',
    ),
    ParamSpec(
      name: 'properties',
      type: ParamType.propertyMap,
      label: 'Properties',
    ),
  ],
  execute: (ctx, params) {
    final id = requireResourceId(params, 'materialId');
    final existing = ctx.document.resource(id);
    if (existing is! MaterialResource) {
      throw CommandException('Resource is not a material: ${id.toToken()}');
    }
    final merged = MaterialResource(
      existing.id,
      type: existing.type,
      properties: {
        ...existing.properties,
        ...optionalPropertyMap(params, 'properties'),
      },
      asset: existing.asset,
    );
    return Transaction(
      name: 'Set material properties',
      records: [
        ChangeRecord(
          targetId: id,
          slot: ChangeSlot.poolResource,
          oldValue: ResourceChange(existing),
          newValue: ResourceChange(merged),
        ),
      ],
    );
  },
);

final removeResource = CommandEntry(
  name: 'removeResource',
  doc: 'Remove a resource from the document.',
  category: 'Resource',
  paramSchema: const [
    ParamSpec(
      name: 'resourceId',
      type: ParamType.resourceRef,
      label: 'Resource',
    ),
  ],
  execute: (ctx, params) {
    final id = requireResourceId(params, 'resourceId');
    final resource = ctx.document.resource(id);
    if (resource == null) {
      throw CommandException('Resource not found: ${id.toToken()}');
    }
    // TODO(dangling-resource-refs): scrub references to this resource from
    // node components and material properties so removal cannot leave a
    // dangling ResourceRefValue.
    return Transaction(
      name: 'Remove resource',
      records: [
        ChangeRecord(
          targetId: id,
          slot: ChangeSlot.poolResource,
          oldValue: ResourceChange(resource),
          newValue: const ResourceChange(null),
        ),
      ],
    );
  },
);

// ---------------------------------------------------------------------------
// Stage (scene-wide settings) commands.
// ---------------------------------------------------------------------------

StageMetadata _copyStage(StageMetadata s) => StageMetadata(
  upAxis: s.upAxis,
  handedness: s.handedness,
  unitsPerMeter: s.unitsPerMeter,
  environment: s.environment,
  environmentIntensity: s.environmentIntensity,
  exposure: s.exposure,
  toneMapping: s.toneMapping,
  antiAliasingMode: s.antiAliasingMode,
  renderScale: s.renderScale,
  filterQuality: s.filterQuality,
  skybox: s.skybox,
  skyEnvironment: s.skyEnvironment,
);

double _stageDouble(PropertyValue? v, double fallback) => switch (v) {
  DoubleValue(:final value) => value,
  IntValue(:final value) => value.toDouble(),
  _ => fallback,
};

String _stageString(PropertyValue? v, String fallback) =>
    v is StringValue ? v.value : fallback;

/// Updates scene-wide stage settings (exposure, environment intensity, tone
/// mapping, environment, anti-aliasing, render scale, filter quality). Only the
/// keys present in `properties` change; the rest keep their values. The whole
/// stage is one reversible record, so the edit is undoable. `environment` is a
/// name (`studio`/`empty`/`asset`); for `asset`, pass `environmentAsset` (path).
final setStageProperties = CommandEntry(
  name: 'setStageProperties',
  doc: 'Update scene-wide stage settings.',
  category: 'Stage',
  paramSchema: const [
    ParamSpec(
      name: 'properties',
      type: ParamType.propertyMap,
      label: 'Settings',
    ),
  ],
  execute: (ctx, params) {
    final props = optionalPropertyMap(params, 'properties');
    final old = ctx.document.stage;
    final next = _copyStage(old);
    if (props.containsKey('exposure')) {
      next.exposure = _stageDouble(props['exposure'], old.exposure);
    }
    if (props.containsKey('environmentIntensity')) {
      next.environmentIntensity = _stageDouble(
        props['environmentIntensity'],
        old.environmentIntensity,
      );
    }
    if (props.containsKey('toneMapping')) {
      next.toneMapping = _stageString(props['toneMapping'], old.toneMapping);
    }
    if (props.containsKey('antiAliasingMode')) {
      next.antiAliasingMode = _stageString(
        props['antiAliasingMode'],
        old.antiAliasingMode,
      );
    }
    if (props.containsKey('renderScale')) {
      next.renderScale = _stageDouble(props['renderScale'], old.renderScale);
    }
    if (props.containsKey('filterQuality')) {
      next.filterQuality = _stageString(
        props['filterQuality'],
        old.filterQuality,
      );
    }
    if (props.containsKey('environment')) {
      next.environment = switch (_stageString(props['environment'], 'studio')) {
        'empty' => const EmptyEnvironment(),
        'asset' => AssetEnvironment(
          AssetRef(_stageString(props['environmentAsset'], '')),
        ),
        _ => const StudioEnvironment(),
      };
    }
    return Transaction(
      name: 'Set stage settings',
      records: [
        ChangeRecord(
          targetId: ChangeRecord.rootsTarget,
          slot: ChangeSlot.stage,
          oldValue: StageMetadataChange(old),
          newValue: StageMetadataChange(next),
        ),
      ],
    );
  },
);

// Builds a sky source spec of [base]'s type, overriding any field named in
// [overrides] (a property map keyed by parameter name). Vectors are cloned so
// the result never aliases [base]'s (or another spec's) mutable vectors;
// unknown keys are ignored.
SkySourceSpec _skySourceFrom(
  SkySourceSpec base, [
  Map<String, PropertyValue> overrides = const {},
]) {
  Vector3 vec(String key, Vector3 fallback) => switch (overrides[key]) {
    Vec3Value(:final value) => value.clone(),
    ColorValue(:final r, :final g, :final b) => Vector3(r, g, b),
    _ => fallback.clone(),
  };
  double dbl(String key, double fallback) => switch (overrides[key]) {
    DoubleValue(:final value) => value,
    IntValue(:final value) => value.toDouble(),
    _ => fallback,
  };
  return switch (base) {
    GradientSkySpec g => GradientSkySpec(
      zenithColor: vec('zenithColor', g.zenithColor),
      horizonColor: vec('horizonColor', g.horizonColor),
      groundColor: vec('groundColor', g.groundColor),
      sunDirection: vec('sunDirection', g.sunDirection),
      sunColor: vec('sunColor', g.sunColor),
      sunSharpness: dbl('sunSharpness', g.sunSharpness),
    ),
    PhysicalSkySpec p => PhysicalSkySpec(
      sunDirection: vec('sunDirection', p.sunDirection),
      sunAngularRadius: dbl('sunAngularRadius', p.sunAngularRadius),
      rayleighCoefficient: dbl('rayleighCoefficient', p.rayleighCoefficient),
      rayleighColor: vec('rayleighColor', p.rayleighColor),
      mieCoefficient: dbl('mieCoefficient', p.mieCoefficient),
      mieEccentricity: dbl('mieEccentricity', p.mieEccentricity),
      mieColor: vec('mieColor', p.mieColor),
      turbidity: dbl('turbidity', p.turbidity),
      groundColor: vec('groundColor', p.groundColor),
      energy: dbl('energy', p.energy),
    ),
    EnvironmentSkySpec e => EnvironmentSkySpec(
      blurriness: dbl('blurriness', e.blurriness),
    ),
    _ => base,
  };
}

SkySourceSpec? _defaultSkySource(String type) => switch (type) {
  'gradient' => GradientSkySpec(),
  'physical' => PhysicalSkySpec(),
  'environment' => EnvironmentSkySpec(),
  _ => null,
};

Vector3? _specSunDirection(SkySourceSpec? source) => switch (source) {
  GradientSkySpec(:final sunDirection) => sunDirection,
  PhysicalSkySpec(:final sunDirection) => sunDirection,
  _ => null,
};

/// Sets the scene skybox (`none`/`environment`/`gradient`/`physical`) and,
/// when [lightScene] and a procedural sky are chosen, binds that sky as the
/// scene's image-based lighting. Choosing the type the scene already has keeps
/// its tuned parameters; switching type starts from that type's defaults (the
/// sun direction carries across a gradient/physical switch). [sunDirection]
/// optionally seeds the sun; finer parameter tuning goes through
/// `setSkyParameters`. [lightScene] defaults to the scene's current
/// sky-lighting state when omitted. [castShadows] enables a sky-driven sun
/// light (hard shadows tracking the sun) and applies only while [lightScene]
/// is on; it defaults to the scene's current state when omitted.
final setSkybox = CommandEntry(
  name: 'setSkybox',
  doc: 'Set the scene skybox and optional sky-driven lighting.',
  category: 'Stage',
  paramSchema: const [
    ParamSpec(name: 'sky', type: ParamType.string, label: 'Sky'),
    ParamSpec(
      name: 'sunDirection',
      type: ParamType.vec3,
      label: 'Sun direction',
      required: false,
    ),
    ParamSpec(
      name: 'lightScene',
      type: ParamType.boolean,
      label: 'Light scene with sky',
      required: false,
    ),
    ParamSpec(
      name: 'castShadows',
      type: ParamType.boolean,
      label: 'Cast sun shadows',
      required: false,
    ),
  ],
  execute: (ctx, params) {
    final sky = requireString(params, 'sky');
    final sun = optionalVec3(params, 'sunDirection');
    final old = ctx.document.stage;
    final lightScene = params.containsKey('lightScene')
        ? params['lightScene'] == true
        : old.skyEnvironment != null;
    final castShadows = params.containsKey('castShadows')
        ? params['castShadows'] == true
        : (old.skyEnvironment?.castShadows ?? false);
    // Preserve the current sky's parameters when the type is unchanged;
    // otherwise start from the new type's defaults.
    final current = old.skybox?.source;
    final sameType =
        (sky == 'gradient' && current is GradientSkySpec) ||
        (sky == 'physical' && current is PhysicalSkySpec) ||
        (sky == 'environment' && current is EnvironmentSkySpec);
    final base = sameType ? current! : _defaultSkySource(sky);
    // An explicit sun wins; otherwise carry the sun across a type switch.
    final seedSun = sun ?? (sameType ? null : _specSunDirection(current));
    final overrides = <String, PropertyValue>{
      if (seedSun != null) 'sunDirection': Vec3Value(seedSun.clone()),
    };
    SkySourceSpec? makeSource() =>
        base == null ? null : _skySourceFrom(base, overrides);

    final next = _copyStage(old);
    final skySource = makeSource();
    next.skybox = skySource == null
        ? null
        : SkyboxSpec(skySource, intensity: old.skybox?.intensity ?? 1.0);
    final canLight = sky == 'gradient' || sky == 'physical';
    final priorEnv = old.skyEnvironment;
    // The sky-lighting binding needs its own shader-sky source instance.
    next.skyEnvironment = (lightScene && canLight)
        ? SkyEnvironmentSpec(
            makeSource()!,
            refresh: priorEnv?.refresh ?? 'manual',
            intervalSeconds: priorEnv?.intervalSeconds ?? 1.0,
            faceResolution: priorEnv?.faceResolution ?? 128,
            equirectWidth: priorEnv?.equirectWidth ?? 512,
            castShadows: castShadows,
          )
        : null;
    return Transaction(
      name: 'Set skybox',
      records: [
        ChangeRecord(
          targetId: ChangeRecord.rootsTarget,
          slot: ChangeSlot.stage,
          oldValue: StageMetadataChange(old),
          newValue: StageMetadataChange(next),
        ),
      ],
    );
  },
);

/// Tunes the current procedural sky's parameters (colors, sun size, scattering,
/// energy). Only the keys present in `properties` change; the rest are kept.
/// Both the visible skybox and the sky-lighting binding (when present) are
/// updated, so the background and the baked lighting stay in sync. Requires a
/// skybox; choose one with `setSkybox` first.
final setSkyParameters = CommandEntry(
  name: 'setSkyParameters',
  doc: 'Tune the current procedural sky parameters.',
  category: 'Stage',
  paramSchema: const [
    ParamSpec(
      name: 'properties',
      type: ParamType.propertyMap,
      label: 'Sky parameters',
    ),
  ],
  execute: (ctx, params) {
    final props = optionalPropertyMap(params, 'properties');
    final old = ctx.document.stage;
    final skybox = old.skybox;
    if (skybox == null) {
      throw const CommandException(
        'No sky to tune; choose a skybox with setSkybox first.',
      );
    }
    final next = _copyStage(old);
    // `intensity` is a skybox-level property (not a sky source field); the rest
    // of the properties patch the source via _skySourceFrom.
    next.skybox = SkyboxSpec(
      _skySourceFrom(skybox.source, props),
      intensity: _stageDouble(props['intensity'], skybox.intensity),
    );
    final priorEnv = old.skyEnvironment;
    if (priorEnv != null) {
      next.skyEnvironment = SkyEnvironmentSpec(
        _skySourceFrom(priorEnv.source, props),
        refresh: priorEnv.refresh,
        intervalSeconds: priorEnv.intervalSeconds,
        faceResolution: priorEnv.faceResolution,
        equirectWidth: priorEnv.equirectWidth,
        castShadows: priorEnv.castShadows,
      );
    }
    return Transaction(
      name: 'Tune sky',
      records: [
        ChangeRecord(
          targetId: ChangeRecord.rootsTarget,
          slot: ChangeSlot.stage,
          oldValue: StageMetadataChange(old),
          newValue: StageMetadataChange(next),
        ),
      ],
    );
  },
);

// ---------------------------------------------------------------------------
// Prefab commands.
// ---------------------------------------------------------------------------

PrefabInstanceSpec _withDelta(
  PrefabInstanceSpec i, {
  List<PropertyOverride>? overrides,
  List<Attachment>? attachments,
  List<LocalId>? removedNodes,
}) => PrefabInstanceSpec(
  source: i.source,
  load: i.load,
  overrides: overrides ?? i.overrides,
  attachments: attachments ?? i.attachments,
  removedNodes: removedNodes ?? i.removedNodes,
  addedComponents: i.addedComponents,
  removedComponentTypes: i.removedComponentTypes,
);

PrefabInstanceSpec _withOverrides(
  PrefabInstanceSpec instance,
  List<PropertyOverride> overrides,
) => _withDelta(instance, overrides: overrides);

ChangeRecord _instanceRecord(
  LocalId id,
  PrefabInstanceSpec from,
  PrefabInstanceSpec to,
) => ChangeRecord(
  targetId: id,
  slot: ChangeSlot.instance,
  oldValue: PrefabInstanceChange(from),
  newValue: PrefabInstanceChange(to),
);

final instantiatePrefab = CommandEntry(
  name: 'instantiatePrefab',
  doc: 'Add a prefab-instance node referencing another .fscene.',
  category: 'Prefab',
  paramSchema: const [
    ParamSpec(name: 'prefabAsset', type: ParamType.assetRef, label: 'Prefab'),
    ParamSpec(
      name: 'name',
      type: ParamType.string,
      label: 'Name',
      required: false,
    ),
    ParamSpec(
      name: 'parentId',
      type: ParamType.nodeRef,
      label: 'Parent',
      required: false,
    ),
    ParamSpec(
      name: 'overrides',
      type: ParamType.overrideList,
      label: 'Overrides',
      required: false,
    ),
  ],
  execute: (ctx, params) {
    final parentId = optionalNodeId(params, 'parentId');
    if (parentId != null) _requireNode(ctx, parentId);
    final node = NodeSpec(
      id: ctx.document.newId(),
      name: optionalString(params, 'name', orElse: '')!,
      instance: PrefabInstanceSpec(
        source: requireAssetRef(params, 'prefabAsset'),
        overrides: optionalOverrides(params, 'overrides'),
      ),
    );
    return Transaction(
      name: 'Instantiate prefab',
      records: [
        ChangeRecord(
          targetId: node.id,
          slot: ChangeSlot.poolNode,
          oldValue: const NodeChange(null),
          newValue: NodeChange(node),
        ),
        _attach(ctx.document, node.id, parentId),
      ],
    );
  },
);

final setPrefabOverride = CommandEntry(
  name: 'setPrefabOverride',
  doc: 'Add or replace one per-instance override on a prefab instance node.',
  category: 'Prefab',
  paramSchema: const [
    ParamSpec(name: 'nodeId', type: ParamType.nodeRef, label: 'Instance'),
    ParamSpec(name: 'target', type: ParamType.nodeRef, label: 'Target'),
    ParamSpec(name: 'path', type: ParamType.string, label: 'Property path'),
    ParamSpec(name: 'value', type: ParamType.propertyMap, label: 'Value'),
  ],
  execute: (ctx, params) {
    final id = requireNodeId(params, 'nodeId');
    final node = _requireNode(ctx, id);
    final instance = node.instance;
    if (instance == null) {
      throw const CommandException('Node is not a prefab instance');
    }
    final target = requireNodeId(params, 'target');
    final path = requireString(params, 'path');
    if (!params.containsKey('value')) {
      throw const CommandException('Missing param: value');
    }
    final next = [
      for (final o in instance.overrides)
        if (!(o.target == target && o.path == path)) o,
      PropertyOverride(
        target: target,
        path: path,
        value: coercePropertyValue(params['value']),
      ),
    ];
    return Transaction(
      name: 'Set prefab override',
      records: [
        ChangeRecord(
          targetId: id,
          slot: ChangeSlot.instance,
          oldValue: PrefabInstanceChange(instance),
          newValue: PrefabInstanceChange(_withOverrides(instance, next)),
        ),
      ],
    );
  },
);

final removePrefabOverride = CommandEntry(
  name: 'removePrefabOverride',
  doc: 'Remove one per-instance override from a prefab instance node.',
  category: 'Prefab',
  paramSchema: const [
    ParamSpec(name: 'nodeId', type: ParamType.nodeRef, label: 'Instance'),
    ParamSpec(name: 'target', type: ParamType.nodeRef, label: 'Target'),
    ParamSpec(name: 'path', type: ParamType.string, label: 'Property path'),
  ],
  execute: (ctx, params) {
    final id = requireNodeId(params, 'nodeId');
    final node = _requireNode(ctx, id);
    final instance = node.instance;
    if (instance == null) {
      throw const CommandException('Node is not a prefab instance');
    }
    final target = requireNodeId(params, 'target');
    final path = requireString(params, 'path');
    final next = [
      for (final o in instance.overrides)
        if (!(o.target == target && o.path == path)) o,
    ];
    if (next.length == instance.overrides.length) {
      return Transaction(name: 'Remove prefab override', records: _empty);
    }
    return Transaction(
      name: 'Remove prefab override',
      records: [
        ChangeRecord(
          targetId: id,
          slot: ChangeSlot.instance,
          oldValue: PrefabInstanceChange(instance),
          newValue: PrefabInstanceChange(_withOverrides(instance, next)),
        ),
      ],
    );
  },
);

final clearPrefabOverrides = CommandEntry(
  name: 'clearPrefabOverrides',
  doc: 'Remove all per-instance overrides from a prefab instance node.',
  category: 'Prefab',
  paramSchema: const [
    ParamSpec(name: 'nodeId', type: ParamType.nodeRef, label: 'Instance'),
  ],
  execute: (ctx, params) {
    final id = requireNodeId(params, 'nodeId');
    final node = _requireNode(ctx, id);
    final instance = node.instance;
    if (instance == null) {
      throw const CommandException('Node is not a prefab instance');
    }
    if (instance.overrides.isEmpty) {
      return Transaction(name: 'Clear prefab overrides', records: _empty);
    }
    return Transaction(
      name: 'Clear prefab overrides',
      records: [
        ChangeRecord(
          targetId: id,
          slot: ChangeSlot.instance,
          oldValue: PrefabInstanceChange(instance),
          newValue: PrefabInstanceChange(_withOverrides(instance, const [])),
        ),
      ],
    );
  },
);

/// Hides a prefab-internal node on this instance (records it as a removed node
/// in the instance delta). [target] is the node's prefab-local id.
final removePrefabMember = CommandEntry(
  name: 'removePrefabMember',
  doc: 'Remove a prefab-internal node from this instance.',
  category: 'Prefab',
  paramSchema: const [
    ParamSpec(name: 'nodeId', type: ParamType.nodeRef, label: 'Instance'),
    ParamSpec(name: 'target', type: ParamType.nodeRef, label: 'Prefab node'),
  ],
  execute: (ctx, params) {
    final id = requireNodeId(params, 'nodeId');
    final node = _requireNode(ctx, id);
    final instance = node.instance;
    if (instance == null) {
      throw const CommandException('Node is not a prefab instance');
    }
    final target = requireNodeId(params, 'target');
    if (instance.removedNodes.contains(target)) {
      return Transaction(name: 'Remove prefab member', records: _empty);
    }
    return Transaction(
      name: 'Remove prefab member',
      records: [
        _instanceRecord(
          id,
          instance,
          _withDelta(
            instance,
            removedNodes: [...instance.removedNodes, target],
          ),
        ),
      ],
    );
  },
);

/// Attaches a new host node under a prefab-internal node of this instance
/// (a prop on a rig bone). The node is created as a real child of the instance
/// and grafted under [parent] (the prefab-local id, omitted for the instance
/// root) at compose time, so it edits and deletes like any other node.
final attachToPrefabMember = CommandEntry(
  name: 'attachToPrefabMember',
  doc: 'Add a node attached under a prefab-internal node of this instance.',
  category: 'Prefab',
  paramSchema: const [
    ParamSpec(name: 'nodeId', type: ParamType.nodeRef, label: 'Instance'),
    ParamSpec(
      name: 'parent',
      type: ParamType.nodeRef,
      label: 'Prefab node',
      required: false,
    ),
    ParamSpec(
      name: 'name',
      type: ParamType.string,
      label: 'Name',
      required: false,
    ),
  ],
  execute: (ctx, params) {
    final id = requireNodeId(params, 'nodeId');
    final node = _requireNode(ctx, id);
    final instance = node.instance;
    if (instance == null) {
      throw const CommandException('Node is not a prefab instance');
    }
    final parent = optionalNodeId(params, 'parent');
    final newNode = NodeSpec(
      id: ctx.document.newId(),
      name: optionalString(params, 'name', orElse: 'Node')!,
    );
    return Transaction(
      name: 'Attach to prefab',
      records: [
        ChangeRecord(
          targetId: newNode.id,
          slot: ChangeSlot.poolNode,
          oldValue: const NodeChange(null),
          newValue: NodeChange(newNode),
        ),
        _attach(ctx.document, newNode.id, id),
        _instanceRecord(
          id,
          instance,
          _withDelta(
            instance,
            attachments: [
              ...instance.attachments,
              Attachment(newNode.id, parent: parent),
            ],
          ),
        ),
      ],
    );
  },
);

/// Attaches an existing host node under a prefab-internal node of this instance
/// (or the instance root when [target] is omitted), by recording an attachment.
/// The node stays where it is in the source document; composition grafts it
/// under the prefab node, so it edits and deletes like any other node.
final attachExistingToPrefabMember = CommandEntry(
  name: 'attachExistingToPrefabMember',
  doc: 'Attach an existing node under a prefab-internal node of this instance.',
  category: 'Prefab',
  paramSchema: const [
    ParamSpec(name: 'nodeId', type: ParamType.nodeRef, label: 'Instance'),
    ParamSpec(
      name: 'target',
      type: ParamType.nodeRef,
      label: 'Prefab node',
      required: false,
    ),
    ParamSpec(name: 'node', type: ParamType.nodeRef, label: 'Node'),
  ],
  execute: (ctx, params) {
    final id = requireNodeId(params, 'nodeId');
    final node = _requireNode(ctx, id);
    final instance = node.instance;
    if (instance == null) {
      throw const CommandException('Node is not a prefab instance');
    }
    final target = optionalNodeId(params, 'target');
    final existing = requireNodeId(params, 'node');
    _requireNode(ctx, existing);
    final attachments = [
      for (final a in instance.attachments)
        if (a.node != existing) a,
      Attachment(existing, parent: target),
    ];
    return Transaction(
      name: 'Attach to prefab',
      records: [
        _instanceRecord(
          id,
          instance,
          _withDelta(instance, attachments: attachments),
        ),
      ],
    );
  },
);

/// Removes the attachment of [node] from this instance, so the node returns to
/// its source position (used when dragging an attached node back out).
final detachFromPrefab = CommandEntry(
  name: 'detachFromPrefab',
  doc: 'Remove an attached node from this prefab instance.',
  category: 'Prefab',
  paramSchema: const [
    ParamSpec(name: 'nodeId', type: ParamType.nodeRef, label: 'Instance'),
    ParamSpec(name: 'node', type: ParamType.nodeRef, label: 'Node'),
  ],
  execute: (ctx, params) {
    final id = requireNodeId(params, 'nodeId');
    final node = _requireNode(ctx, id);
    final instance = node.instance;
    if (instance == null) {
      throw const CommandException('Node is not a prefab instance');
    }
    final target = requireNodeId(params, 'node');
    if (!instance.attachments.any((a) => a.node == target)) {
      return Transaction(name: 'Detach from prefab', records: _empty);
    }
    final attachments = [
      for (final a in instance.attachments)
        if (a.node != target) a,
    ];
    return Transaction(
      name: 'Detach from prefab',
      records: [
        _instanceRecord(
          id,
          instance,
          _withDelta(instance, attachments: attachments),
        ),
      ],
    );
  },
);

// ---------------------------------------------------------------------------
// Registration.
// ---------------------------------------------------------------------------

/// Registers all built-in commands into [registry].
void registerBuiltinCommands(CommandRegistry registry) {
  for (final command in builtinCommands) {
    registry.register(command);
  }
}

/// The built-in command set.
final List<CommandEntry> builtinCommands = [
  setNodeName,
  setNodeVisible,
  setNodeLayers,
  setNodeTransform,
  createNode,
  deleteNode,
  deleteNodes,
  reparentNode,
  duplicateNodes,
  pasteNodes,
  addComponent,
  removeComponent,
  setComponentProperties,
  createCuboidGeometry,
  createSphereGeometry,
  createMaterial,
  createTextureResource,
  setMaterialProperties,
  removeResource,
  setStageProperties,
  setSkybox,
  setSkyParameters,
  instantiatePrefab,
  setPrefabOverride,
  removePrefabOverride,
  clearPrefabOverrides,
  removePrefabMember,
  attachToPrefabMember,
  attachExistingToPrefabMember,
  detachFromPrefab,
];
