/// The built-in command set.
///
/// Each command reads the document, validates its params, and returns a
/// [Transaction] of change records. Structural edits (create, delete,
/// reparent) are ordinary record batches thanks to the [NodeChange] pool slot,
/// so undo and redo come for free. Register them all with
/// [registerBuiltinCommands].
library;

import 'dart:convert';

import 'dart:typed_data';

import 'package:scene/scene.dart' hide NodeChange;
import 'package:vector_math/vector_math.dart';

import 'animation_commands.dart';
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
      properties: optionalPropertyMap(
        params,
        'properties',
        schema: ctx.componentSchema?.call(type),
      ),
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
        ...optionalPropertyMap(
          params,
          'properties',
          schema: ctx.componentSchema?.call(type),
        ),
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

final createPlaneGeometry = CommandEntry(
  name: 'createPlaneGeometry',
  doc: 'Create a procedural plane geometry resource.',
  category: 'Resource',
  paramSchema: const [
    ParamSpec(
      name: 'width',
      type: ParamType.number,
      label: 'Width',
      required: false,
    ),
    ParamSpec(
      name: 'depth',
      type: ParamType.number,
      label: 'Depth',
      required: false,
    ),
  ],
  execute: (ctx, params) {
    final resource = GeometryResource(
      ctx.document.newId(),
      procedural: PlaneGeometrySpec(
        width: params['width'] == null ? 1.0 : requireDouble(params, 'width'),
        depth: params['depth'] == null ? 1.0 : requireDouble(params, 'depth'),
      ),
    );
    return Transaction(
      name: 'Create plane',
      records: [_addResourceRecord(resource)],
    );
  },
);

final createCylinderGeometry = CommandEntry(
  name: 'createCylinderGeometry',
  doc: 'Create a procedural cylinder geometry resource.',
  category: 'Resource',
  paramSchema: const [
    ParamSpec(
      name: 'radius',
      type: ParamType.number,
      label: 'Radius',
      required: false,
    ),
    ParamSpec(
      name: 'height',
      type: ParamType.number,
      label: 'Height',
      required: false,
    ),
    ParamSpec(
      name: 'topRadius',
      type: ParamType.number,
      label: 'Top radius',
      required: false,
    ),
  ],
  execute: (ctx, params) {
    // One radius drives both ends unless a top radius is given, so the common
    // case is a cylinder and a cone is one field away.
    final radius = params['radius'] == null
        ? 0.5
        : requireDouble(params, 'radius');
    final resource = GeometryResource(
      ctx.document.newId(),
      procedural: CylinderGeometrySpec(
        bottomRadius: radius,
        topRadius: params['topRadius'] == null
            ? radius
            : requireDouble(params, 'topRadius'),
        height: params['height'] == null
            ? 1.0
            : requireDouble(params, 'height'),
      ),
    );
    return Transaction(
      name: 'Create cylinder',
      records: [_addResourceRecord(resource)],
    );
  },
);

final createCapsuleGeometry = CommandEntry(
  name: 'createCapsuleGeometry',
  doc: 'Create a procedural capsule geometry resource.',
  category: 'Resource',
  paramSchema: const [
    ParamSpec(
      name: 'radius',
      type: ParamType.number,
      label: 'Radius',
      required: false,
    ),
    ParamSpec(
      name: 'height',
      type: ParamType.number,
      label: 'Height',
      required: false,
    ),
  ],
  execute: (ctx, params) {
    final resource = GeometryResource(
      ctx.document.newId(),
      procedural: CapsuleGeometrySpec(
        radius: params['radius'] == null
            ? 0.5
            : requireDouble(params, 'radius'),
        height: params['height'] == null
            ? 1.0
            : requireDouble(params, 'height'),
      ),
    );
    return Transaction(
      name: 'Create capsule',
      records: [_addResourceRecord(resource)],
    );
  },
);

final createTorusGeometry = CommandEntry(
  name: 'createTorusGeometry',
  doc: 'Create a procedural torus geometry resource.',
  category: 'Resource',
  paramSchema: const [
    ParamSpec(
      name: 'radius',
      type: ParamType.number,
      label: 'Radius',
      required: false,
    ),
    ParamSpec(
      name: 'tubeRadius',
      type: ParamType.number,
      label: 'Tube radius',
      required: false,
    ),
  ],
  execute: (ctx, params) {
    final resource = GeometryResource(
      ctx.document.newId(),
      procedural: TorusGeometrySpec(
        radius: params['radius'] == null
            ? 0.5
            : requireDouble(params, 'radius'),
        tubeRadius: params['tubeRadius'] == null
            ? 0.15
            : requireDouble(params, 'tubeRadius'),
      ),
    );
    return Transaction(
      name: 'Create torus',
      records: [_addResourceRecord(resource)],
    );
  },
);

final createDiscGeometry = CommandEntry(
  name: 'createDiscGeometry',
  doc: 'Create a procedural disc geometry resource.',
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
    final resource = GeometryResource(
      ctx.document.newId(),
      procedural: DiscGeometrySpec(
        radius: params['radius'] == null
            ? 0.5
            : requireDouble(params, 'radius'),
      ),
    );
    return Transaction(
      name: 'Create disc',
      records: [_addResourceRecord(resource)],
    );
  },
);

final createIcosphereGeometry = CommandEntry(
  name: 'createIcosphereGeometry',
  doc: 'Create a procedural icosphere geometry resource.',
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
    final resource = GeometryResource(
      ctx.document.newId(),
      procedural: IcosphereGeometrySpec(
        radius: params['radius'] == null
            ? 0.5
            : requireDouble(params, 'radius'),
      ),
    );
    return Transaction(
      name: 'Create icosphere',
      records: [_addResourceRecord(resource)],
    );
  },
);

final createWedgeGeometry = CommandEntry(
  name: 'createWedgeGeometry',
  doc: 'Create a procedural wedge geometry resource.',
  category: 'Resource',
  paramSchema: const [
    ParamSpec(
      name: 'size',
      type: ParamType.vec3,
      label: 'Size',
      required: false,
    ),
  ],
  execute: (ctx, params) {
    final resource = GeometryResource(
      ctx.document.newId(),
      procedural: WedgeGeometrySpec(
        size: optionalVec3(params, 'size') ?? Vector3(1, 1, 1),
      ),
    );
    return Transaction(
      name: 'Create wedge',
      records: [_addResourceRecord(resource)],
    );
  },
);

final createTerrainGeometry = CommandEntry(
  name: 'createTerrainGeometry',
  doc: 'Create a procedural noise terrain geometry resource.',
  category: 'Resource',
  paramSchema: const [
    ParamSpec(
      name: 'size',
      type: ParamType.number,
      label: 'Size',
      required: false,
    ),
    ParamSpec(
      name: 'amplitude',
      type: ParamType.number,
      label: 'Height',
      required: false,
    ),
    ParamSpec(
      name: 'seed',
      type: ParamType.number,
      label: 'Seed',
      required: false,
    ),
  ],
  execute: (ctx, params) {
    // One size drives both axes: a square patch is the common case, and an
    // oblong one is a scale on the node.
    final size = params['size'] == null ? 64.0 : requireDouble(params, 'size');
    final resource = GeometryResource(
      ctx.document.newId(),
      procedural: TerrainGeometrySpec(
        width: size,
        depth: size,
        amplitude: params['amplitude'] == null
            ? 8.0
            : requireDouble(params, 'amplitude'),
        seed: params['seed'] == null
            ? 1337
            : requireDouble(params, 'seed').round(),
      ),
    );
    return Transaction(
      name: 'Create terrain',
      records: [_addResourceRecord(resource)],
    );
  },
);

/// Turns a plane geometry into a flat terrain so it can be sculpted.
///
/// A plane is two triangles by default: there is nowhere to put a hill. This
/// swaps its spec for a terrain of the same size at a grid fine enough to
/// sculpt, with no noise, so the shape on screen does not change -- it just
/// becomes something that can be pushed around.
///
/// A plane that was already subdivided keeps its own resolution rather than
/// being coarsened or refined behind the user's back.
final makeTerrainSculptable = CommandEntry(
  name: 'makeTerrainSculptable',
  doc: 'Convert a plane geometry into a flat, sculptable terrain.',
  category: 'Resource',
  paramSchema: const [
    ParamSpec(name: 'resourceId', type: ParamType.resourceRef, label: 'Plane'),
    ParamSpec(
      name: 'resolution',
      type: ParamType.number,
      label: 'Samples per side',
      required: false,
    ),
  ],
  execute: (ctx, params) {
    final resourceId = requireResourceId(params, 'resourceId');
    final resource = ctx.document.resource(resourceId);
    if (resource is! GeometryResource) {
      throw CommandException('Resource $resourceId is not a geometry');
    }
    final plane = resource.procedural;
    if (plane is TerrainGeometrySpec) {
      throw const CommandException('That geometry is already sculptable');
    }
    if (plane is! PlaneGeometrySpec) {
      throw CommandException('Resource $resourceId is not a plane');
    }

    final requested = params['resolution'] == null
        ? 0
        : requireDouble(params, 'resolution').round();
    // A subdivided plane already says how fine it wants to be; an
    // unsubdivided one needs a grid that can hold a shape at all.
    final columns = requested > 1
        ? requested
        : (plane.segmentsX > 1 ? plane.segmentsX + 1 : 65);
    final rows = requested > 1
        ? requested
        : (plane.segmentsZ > 1 ? plane.segmentsZ + 1 : 65);

    return Transaction(
      name: 'Make sculptable',
      records: [
        ChangeRecord(
          targetId: resourceId,
          slot: ChangeSlot.poolResource,
          oldValue: ResourceChange(resource),
          newValue: ResourceChange(
            GeometryResource(
              resourceId,
              procedural: TerrainGeometrySpec(
                width: plane.width,
                depth: plane.depth,
                columns: columns,
                rows: rows,
                // Flat: converting must not change what is on screen.
                amplitude: 0,
              ),
            ),
          ),
        ),
      ],
    );
  },
);

/// Replaces a terrain's height samples.
///
/// One command per stroke rather than per pointer move: a stroke is many
/// brush dabs and only one thing the user did, so this takes the finished
/// samples rather than a brush to replay. Undo is the previous heightmap,
/// which is the whole map — heightmaps are the one thing in a scene big
/// enough for that to be worth saying out loud.
final setTerrainHeights = CommandEntry(
  name: 'setTerrainHeights',
  doc: "Replace a terrain geometry's height samples.",
  category: 'Resource',
  paramSchema: const [
    ParamSpec(
      name: 'resourceId',
      type: ParamType.resourceRef,
      label: 'Terrain',
    ),
    ParamSpec(name: 'heights', type: ParamType.string, label: 'Samples'),
  ],
  execute: (ctx, params) {
    final resourceId = requireResourceId(params, 'resourceId');
    final resource = ctx.document.resource(resourceId);
    if (resource is! GeometryResource) {
      throw CommandException('Resource $resourceId is not a geometry');
    }
    final terrain = resource.procedural;
    if (terrain is! TerrainGeometrySpec) {
      throw CommandException('Resource $resourceId is not a terrain');
    }

    final bytes = base64Decode(requireString(params, 'heights'));
    final expected = terrain.columns * terrain.rows * 4;
    if (bytes.lengthInBytes != expected) {
      throw CommandException(
        'Expected $expected bytes for a ${terrain.columns} by '
        '${terrain.rows} terrain, got ${bytes.lengthInBytes}',
      );
    }

    // The first stroke on a generated terrain mints its heightmap; later
    // ones replace the bytes in the payload it already has.
    final payloadId = terrain.heights ?? ctx.document.newId();
    final records = <ChangeRecord>[
      ChangeRecord(
        targetId: payloadId,
        slot: ChangeSlot.poolPayload,
        oldValue: PayloadChange(ctx.document.payload(payloadId)),
        newValue: PayloadChange(
          PayloadSpec(
            payloadId,
            encoding: PayloadEncoding.floats,
            length: terrain.columns * terrain.rows,
            bytes: bytes,
          ),
        ),
      ),
    ];
    if (terrain.heights == null) {
      records.add(
        ChangeRecord(
          targetId: resourceId,
          slot: ChangeSlot.poolResource,
          oldValue: ResourceChange(resource),
          newValue: ResourceChange(
            GeometryResource(
              resourceId,
              // copyWith, so a terrain that was painted before it was first
              // sculpted keeps its painting.
              procedural: terrain.copyWith(heights: payloadId),
            ),
          ),
        ),
      );
    }
    return Transaction(name: 'Sculpt terrain', records: records);
  },
);

/// Replaces a terrain's painted surface layers.
///
/// The sibling of [setTerrainHeights], and the same bargain: one command per
/// stroke rather than per pointer move, taking the finished control map rather
/// than a brush to replay, with undo holding the previous map whole.
///
/// The control map is four bytes a texel — the same RGBA the shader samples —
/// so it is stored as an image payload rather than as opaque bytes. That makes
/// it something a tool other than this one can open.
final setTerrainSplat = CommandEntry(
  name: 'setTerrainSplat',
  doc: "Replace a terrain geometry's painted surface layers.",
  category: 'Resource',
  paramSchema: const [
    ParamSpec(
      name: 'resourceId',
      type: ParamType.resourceRef,
      label: 'Terrain',
    ),
    ParamSpec(name: 'splat', type: ParamType.string, label: 'Control map'),
    ParamSpec(
      name: 'columns',
      type: ParamType.integer,
      label: 'Texels across X',
      required: false,
    ),
    ParamSpec(
      name: 'rows',
      type: ParamType.integer,
      label: 'Texels across Z',
      required: false,
    ),
  ],
  execute: (ctx, params) {
    final resourceId = requireResourceId(params, 'resourceId');
    final resource = ctx.document.resource(resourceId);
    if (resource is! GeometryResource) {
      throw CommandException('Resource $resourceId is not a geometry');
    }
    final terrain = resource.procedural;
    if (terrain is! TerrainGeometrySpec) {
      throw CommandException('Resource $resourceId is not a terrain');
    }

    // A terrain painted for the first time may be establishing its control-map
    // resolution; afterwards the map has to match what the document says it
    // is, or the painting would be stretched across the ground on reload.
    final columns = optionalInt(params, 'columns') ?? terrain.splatColumns;
    final rows = optionalInt(params, 'rows') ?? terrain.splatRows;
    if (terrain.splat != null &&
        (columns != terrain.splatColumns || rows != terrain.splatRows)) {
      throw CommandException(
        'This terrain is painted at ${terrain.splatColumns} by '
        '${terrain.splatRows}; resizing a control map would resample the '
        'painting, which this command does not do',
      );
    }

    final bytes = base64Decode(requireString(params, 'splat'));
    final expected = columns * rows * 4;
    if (bytes.lengthInBytes != expected) {
      throw CommandException(
        'Expected $expected bytes for a $columns by $rows control map, got '
        '${bytes.lengthInBytes}',
      );
    }

    final payloadId = terrain.splat ?? ctx.document.newId();
    final records = <ChangeRecord>[
      ChangeRecord(
        targetId: payloadId,
        slot: ChangeSlot.poolPayload,
        oldValue: PayloadChange(ctx.document.payload(payloadId)),
        newValue: PayloadChange(
          PayloadSpec(
            payloadId,
            encoding: PayloadEncoding.image,
            format: 'rgba8',
            width: columns,
            height: rows,
            bytes: bytes,
          ),
        ),
      ),
    ];
    if (terrain.splat == null) {
      records.add(
        ChangeRecord(
          targetId: resourceId,
          slot: ChangeSlot.poolResource,
          oldValue: ResourceChange(resource),
          newValue: ResourceChange(
            GeometryResource(
              resourceId,
              procedural: terrain.copyWith(
                splat: payloadId,
                splatColumns: columns,
                splatRows: rows,
              ),
            ),
          ),
        ),
      );
    }
    return Transaction(name: 'Paint terrain', records: records);
  },
);

/// The `.fmat` the painted layers blend through, as flutter_scene ships it.
/// The path is relative to the root of the package that compiled the material,
/// which is what the generated material index records as its `source` and what
/// `loadFmatMaterial` looks one up by — not an asset-bundle key. A bundle-style
/// `packages/flutter_scene/...` key resolves to nothing, silently, at load, and
/// the ground draws as though it had no material at all.
///
/// flutter_scene is only a dev dependency here (this package is the headless
/// command core and does not pull in the renderer), so the string is spelled
/// again rather than imported; a test pins it to the engine's
/// `terrainMaterialSource` so the two cannot drift.
const terrainMaterialAsset = 'assets/materials/terrain_splat.fmat';

/// Gives a painted terrain a material that shows the painting.
///
/// Painting writes a control map; nothing draws it until the terrain is using
/// the terrain material with that map bound. This is the step between, and it
/// is one command because it is one thing the user did: a texture over the
/// control-map payload, an fmat material pointing at it, and the mesh switched
/// to that material, all undone together.
///
/// The control map is texture content `data`, not `color`. Its four channels
/// are weights, so they must not be sRGB-decoded on the way in, and mip levels
/// must average as numbers rather than as colour — a mip that gamma-averaged
/// the weights would drift the blend at distance.
final addTerrainLayers = CommandEntry(
  name: 'addTerrainLayers',
  doc: 'Give a painted terrain the material its layers blend through.',
  category: 'Resource',
  paramSchema: const [
    ParamSpec(name: 'nodeId', type: ParamType.nodeRef, label: 'Terrain node'),
  ],
  execute: (ctx, params) {
    final nodeId = requireNodeId(params, 'nodeId');
    final node = ctx.document.node(nodeId);
    if (node == null) throw CommandException('No node $nodeId');

    final meshIndex = node.components.indexWhere((c) => c.type == 'mesh');
    if (meshIndex < 0) {
      throw CommandException('That node has no mesh to give a material to');
    }
    final mesh = node.components[meshIndex];

    final geometryId = switch (mesh.properties['geometry']) {
      ResourceRefValue(:final id) => id,
      _ => null,
    };
    if (geometryId == null) {
      throw CommandException('That mesh has no geometry');
    }
    final geometry = ctx.document.resource(geometryId);
    final terrain = geometry is GeometryResource ? geometry.procedural : null;
    if (terrain is! TerrainGeometrySpec) {
      throw CommandException('That node is not a terrain');
    }
    final splat = terrain.splat;
    if (splat == null) {
      throw CommandException(
        'That terrain has nothing painted on it yet, so there is no control '
        'map for a material to blend by. Paint a stroke first.',
      );
    }

    final texture = TextureResource(
      ctx.document.newId(),
      payload: splat,
      // Weights, not colour: no sRGB decode, and mips that average as numbers.
      content: 'data',
    );
    final material = MaterialResource(
      ctx.document.newId(),
      type: 'fmat',
      name: 'Terrain layers',
      asset: const AssetRef(terrainMaterialAsset),
      properties: {'control_map': ResourceRefValue(texture.id)},
    );

    final components = List.of(node.components);
    components[meshIndex] = ComponentSpec(
      mesh.type,
      properties: {
        ...mesh.properties,
        'material': ResourceRefValue(material.id),
      },
    );

    return Transaction(
      name: 'Add terrain layers',
      records: [
        _addResourceRecord(texture),
        _addResourceRecord(material),
        _componentsRecord(node, components),
      ],
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
///
/// TODO(externalize-embedded-textures): a payload-backed texture is embedded in
/// the document, and `.fscene` (lean text) does not persist payload bytes, so
/// it is lost on save/reopen. Prefer createTextureResourceFromAsset (an
/// external image file under `imported/`), and externalize any remaining
/// embedded image payloads to files at save time.
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

/// Creates a texture resource backed by an external image file (the `asset`
/// param, a source-path key like `imported/foo.png`). The heavy image bytes
/// live in the referenced file, not in the document, so the texture survives a
/// lean `.fscene` save. The realizer decodes the asset (from the asset bundle,
/// or from disk via the editor's texture loader). Returns nothing; the caller
/// finds the new resource id by diffing the resource pool.
final createTextureResourceFromAsset = CommandEntry(
  name: 'createTextureResourceFromAsset',
  doc: 'Create a texture resource from an external image asset.',
  category: 'Resource',
  paramSchema: const [
    ParamSpec(name: 'asset', type: ParamType.assetRef, label: 'Image asset'),
  ],
  execute: (ctx, params) {
    final resource = TextureResource(
      ctx.document.newId(),
      asset: requireAssetRef(params, 'asset'),
    );
    return Transaction(
      name: 'Create texture',
      records: [_addResourceRecord(resource)],
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
      name: existing.name,
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

final setMaterialType = CommandEntry(
  name: 'setMaterialType',
  doc:
      'Change a material resource type in place, resetting its parameters. '
      'Pass an fmat source asset when type is "fmat".',
  category: 'Resource',
  paramSchema: const [
    ParamSpec(
      name: 'materialId',
      type: ParamType.resourceRef,
      label: 'Material',
    ),
    ParamSpec(name: 'type', type: ParamType.string, label: 'Type'),
    ParamSpec(
      name: 'asset',
      type: ParamType.assetRef,
      label: 'Asset (.fmat)',
      required: false,
    ),
  ],
  execute: (ctx, params) {
    final id = requireResourceId(params, 'materialId');
    final existing = ctx.document.resource(id);
    if (existing is! MaterialResource) {
      throw CommandException('Resource is not a material: ${id.toToken()}');
    }
    final type = requireString(params, 'type');
    final assetKey = optionalString(params, 'asset');
    if (type == 'fmat' && (assetKey == null || assetKey.isEmpty)) {
      throw const CommandException(
        'An fmat material needs an asset (the .fmat source path).',
      );
    }
    // Parameters are type-specific, so a type change starts from the type's
    // defaults rather than carrying stale keys.
    final replaced = MaterialResource(
      existing.id,
      type: type,
      name: existing.name,
      asset: type == 'fmat' ? AssetRef(assetKey!) : null,
    );
    return Transaction(
      name: 'Set material type',
      records: [
        ChangeRecord(
          targetId: id,
          slot: ChangeSlot.poolResource,
          oldValue: ResourceChange(existing),
          newValue: ResourceChange(replaced),
        ),
      ],
    );
  },
);

final clearMaterialProperty = CommandEntry(
  name: 'clearMaterialProperty',
  doc: 'Remove a single property (for example a texture slot) from a material.',
  category: 'Resource',
  paramSchema: const [
    ParamSpec(
      name: 'materialId',
      type: ParamType.resourceRef,
      label: 'Material',
    ),
    ParamSpec(name: 'key', type: ParamType.string, label: 'Property'),
  ],
  execute: (ctx, params) {
    final id = requireResourceId(params, 'materialId');
    final existing = ctx.document.resource(id);
    if (existing is! MaterialResource) {
      throw CommandException('Resource is not a material: ${id.toToken()}');
    }
    final key = requireString(params, 'key');
    if (!existing.properties.containsKey(key)) {
      return Transaction(name: 'Clear material property', records: _empty);
    }
    final next = Map<String, PropertyValue>.of(existing.properties)
      ..remove(key);
    final replaced = MaterialResource(
      existing.id,
      type: existing.type,
      name: existing.name,
      properties: next,
      asset: existing.asset,
    );
    return Transaction(
      name: 'Clear material property',
      records: [
        ChangeRecord(
          targetId: id,
          slot: ChangeSlot.poolResource,
          oldValue: ResourceChange(existing),
          newValue: ResourceChange(replaced),
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
  antiAliasingMode: s.antiAliasingMode,
  renderScale: s.renderScale,
  filterQuality: s.filterQuality,
  environmentRef: s.environmentRef,
);

/// A unified read/write view over the look fields the base stage and an
/// environment resource share, so the look-editing commands can target either.
abstract class _LookView {
  EnvironmentSpec get environment;
  set environment(EnvironmentSpec v);
  double get environmentIntensity;
  set environmentIntensity(double v);
  double get exposure;
  set exposure(double v);
  String get toneMapping;
  set toneMapping(String v);
  int? get radianceCubeSize;
  set radianceCubeSize(int? v);
  SkyboxSpec? get skybox;
  set skybox(SkyboxSpec? v);
  SkyEnvironmentSpec? get skyEnvironment;
  set skyEnvironment(SkyEnvironmentSpec? v);
}

class _EnvResourceLook implements _LookView {
  _EnvResourceLook(this.r);
  final EnvironmentResource r;
  @override
  EnvironmentSpec get environment => r.environment;
  @override
  set environment(EnvironmentSpec value) => r.environment = value;
  @override
  double get environmentIntensity => r.environmentIntensity;
  @override
  set environmentIntensity(double value) => r.environmentIntensity = value;
  @override
  double get exposure => r.exposure;
  @override
  set exposure(double value) => r.exposure = value;
  @override
  String get toneMapping => r.toneMapping;
  @override
  set toneMapping(String value) => r.toneMapping = value;
  @override
  int? get radianceCubeSize => r.radianceCubeSize;
  @override
  set radianceCubeSize(int? value) => r.radianceCubeSize = value;
  @override
  SkyboxSpec? get skybox => r.skybox;
  @override
  set skybox(SkyboxSpec? value) => r.skybox = value;
  @override
  SkyEnvironmentSpec? get skyEnvironment => r.skyEnvironment;
  @override
  set skyEnvironment(SkyEnvironmentSpec? value) => r.skyEnvironment = value;
}

EnvironmentResource _copyEnvironmentResource(EnvironmentResource r) =>
    EnvironmentResource(
      r.id,
      name: r.name,
      environment: r.environment,
      environmentIntensity: r.environmentIntensity,
      exposure: r.exposure,
      toneMapping: r.toneMapping,
      agxWhite: r.agxWhite,
      agxContrast: r.agxContrast,
      environmentRotationY: r.environmentRotationY,
      radianceCubeSize: r.radianceCubeSize,
      skybox: r.skybox,
      skyEnvironment: r.skyEnvironment == null
          ? null
          : _copySkyEnvironment(r.skyEnvironment!),
      effects: EnvironmentEffectsSpec.copy(r.effects),
      overridesEffects: r.overridesEffects,
    );

SkyEnvironmentSpec _copySkyEnvironment(SkyEnvironmentSpec s) =>
    SkyEnvironmentSpec(
      s.source,
      refresh: s.refresh,
      intervalSeconds: s.intervalSeconds,
      faceResolution: s.faceResolution,
      equirectWidth: s.equirectWidth,
      sunLight: s.sunLight == null ? null : _copySunLight(s.sunLight!),
    );

SunLightSpec _copySunLight(SunLightSpec s) => SunLightSpec(
  castsShadow: s.castsShadow,
  intensityScale: s.intensityScale,
  priority: s.priority,
  cacheStaticShadows: s.cacheStaticShadows,
  shadowSoftness: s.shadowSoftness,
  shadowMaxDistance: s.shadowMaxDistance,
  shadowCascadeCount: s.shadowCascadeCount,
  shadowMapResolution: s.shadowMapResolution,
  shadowDepthBias: s.shadowDepthBias,
  shadowNormalBias: s.shadowNormalBias,
  shadowFadeRange: s.shadowFadeRange,
  shadowCascadeSplitLambda: s.shadowCascadeSplitLambda,
  shadowAmbientStrength: s.shadowAmbientStrength,
  shadowFilter: s.shadowFilter,
  shadowCasterFaces: s.shadowCasterFaces,
);

EnvironmentResource _requireEnvironment(CommandContext ctx, LocalId id) {
  final existing = ctx.document.resource(id);
  if (existing is! EnvironmentResource) {
    throw CommandException('Resource is not an environment: ${id.toToken()}');
  }
  return existing;
}

// Applies the look-scalar/environment property keys to [look]. Shared by the
// stage and environment-resource look commands.
void _applyLookProperties(_LookView look, Map<String, PropertyValue> props) {
  if (props.containsKey('exposure')) {
    look.exposure = _stageDouble(props['exposure'], look.exposure);
  }
  if (props.containsKey('environmentIntensity')) {
    look.environmentIntensity = _stageDouble(
      props['environmentIntensity'],
      look.environmentIntensity,
    );
  }
  if (props.containsKey('toneMapping')) {
    look.toneMapping = _stageString(props['toneMapping'], look.toneMapping);
  }
  if (props.containsKey('radianceCubeSize')) {
    // A non-positive value clears the override back to the engine default.
    final size = _stageInt(props['radianceCubeSize']);
    look.radianceCubeSize = (size == null || size <= 0) ? null : size;
  }
  if (props.containsKey('environment')) {
    look.environment = switch (_stageString(props['environment'], 'studio')) {
      'empty' => const EmptyEnvironment(),
      'asset' => AssetEnvironment(
        AssetRef(_stageString(props['environmentAsset'], '')),
      ),
      'constant' => ConstantEnvironment(switch (props['environmentColor']) {
        Vec3Value(:final value) => value,
        ColorValue(:final r, :final g, :final b) => Vector3(r, g, b),
        _ => Vector3.all(0.1),
      }),
      _ => const StudioEnvironment(),
    };
  } else if (props['environmentColor'] case final value?) {
    final color = switch (value) {
      Vec3Value(:final value) => value,
      ColorValue(:final r, :final g, :final b) => Vector3(r, g, b),
      _ => null,
    };
    if (color != null && look.environment is ConstantEnvironment) {
      look.environment = ConstantEnvironment(color);
    }
  }
  if (look case _EnvResourceLook(:final r)) {
    if (props.containsKey('agxWhite')) {
      r.agxWhite = _stageDouble(props['agxWhite'], r.agxWhite);
    }
    if (props.containsKey('agxContrast')) {
      r.agxContrast = _stageDouble(props['agxContrast'], r.agxContrast);
    }
    if (props.containsKey('environmentRotationY')) {
      r.environmentRotationY = _stageDouble(
        props['environmentRotationY'],
        r.environmentRotationY,
      );
    }
    if (_applyEnvironmentEffects(r.effects, props)) {
      r.overridesEffects = true;
    }
  }
}

bool _applyEnvironmentEffects(
  EnvironmentEffectsSpec e,
  Map<String, PropertyValue> props,
) {
  var changed = false;
  void boolean(String key, void Function(bool) assign) {
    if (props[key] case BoolValue(:final value)) {
      changed = true;
      assign(value);
    }
  }

  void number(String key, double current, void Function(double) assign) {
    if (props.containsKey(key)) {
      changed = true;
      assign(_stageDouble(props[key], current));
    }
  }

  void integer(String key, int current, void Function(int) assign) {
    if (!props.containsKey(key)) return;
    changed = true;
    assign(_stageInt(props[key]) ?? current);
  }

  void string(String key, String current, void Function(String) assign) {
    if (props.containsKey(key)) {
      changed = true;
      assign(_stageString(props[key], current));
    }
  }

  void vector(String key, Vector3 current, void Function(Vector3) assign) {
    switch (props[key]) {
      case Vec3Value(:final value):
        changed = true;
        assign(value.clone());
      case ColorValue(:final r, :final g, :final b):
        changed = true;
        assign(Vector3(r, g, b));
      default:
        break;
    }
  }

  boolean('colorGradingEnabled', (v) => e.colorGradingEnabled = v);
  number('brightness', e.brightness, (v) => e.brightness = v);
  number('contrast', e.contrast, (v) => e.contrast = v);
  number('saturation', e.saturation, (v) => e.saturation = v);
  number('temperature', e.temperature, (v) => e.temperature = v);
  number('tint', e.tint, (v) => e.tint = v);
  vector('lift', e.lift, (v) => e.lift = v);
  vector('gamma', e.gamma, (v) => e.gamma = v);
  vector('gain', e.gain, (v) => e.gain = v);
  boolean('bloomEnabled', (v) => e.bloomEnabled = v);
  number('bloomThreshold', e.bloomThreshold, (v) => e.bloomThreshold = v);
  number('bloomIntensity', e.bloomIntensity, (v) => e.bloomIntensity = v);
  number('bloomScatter', e.bloomScatter, (v) => e.bloomScatter = v);
  boolean('lensFlareEnabled', (v) => e.lensFlareEnabled = v);
  number(
    'lensFlareIntensity',
    e.lensFlareIntensity,
    (v) => e.lensFlareIntensity = v,
  );
  number(
    'lensFlareGhostCount',
    e.lensFlareGhostCount.toDouble(),
    (v) => e.lensFlareGhostCount = v.round(),
  );
  number(
    'lensFlareGhostSpacing',
    e.lensFlareGhostSpacing,
    (v) => e.lensFlareGhostSpacing = v,
  );
  number(
    'lensFlareHaloRadius',
    e.lensFlareHaloRadius,
    (v) => e.lensFlareHaloRadius = v,
  );
  number(
    'lensFlareHaloIntensity',
    e.lensFlareHaloIntensity,
    (v) => e.lensFlareHaloIntensity = v,
  );
  number(
    'lensFlareChromaticAberration',
    e.lensFlareChromaticAberration,
    (v) => e.lensFlareChromaticAberration = v,
  );
  boolean('vignetteEnabled', (v) => e.vignetteEnabled = v);
  number(
    'vignetteIntensity',
    e.vignetteIntensity,
    (v) => e.vignetteIntensity = v,
  );
  number('vignetteRadius', e.vignetteRadius, (v) => e.vignetteRadius = v);
  number(
    'vignetteSmoothness',
    e.vignetteSmoothness,
    (v) => e.vignetteSmoothness = v,
  );
  boolean(
    'chromaticAberrationEnabled',
    (v) => e.chromaticAberrationEnabled = v,
  );
  number(
    'chromaticAberrationIntensity',
    e.chromaticAberrationIntensity,
    (v) => e.chromaticAberrationIntensity = v,
  );
  boolean('filmGrainEnabled', (v) => e.filmGrainEnabled = v);
  number(
    'filmGrainIntensity',
    e.filmGrainIntensity,
    (v) => e.filmGrainIntensity = v,
  );
  boolean('ambientOcclusionEnabled', (v) => e.ambientOcclusionEnabled = v);
  number(
    'ambientOcclusionRadius',
    e.ambientOcclusionRadius,
    (v) => e.ambientOcclusionRadius = v,
  );
  number(
    'ambientOcclusionIntensity',
    e.ambientOcclusionIntensity,
    (v) => e.ambientOcclusionIntensity = v,
  );
  number(
    'ambientOcclusionBias',
    e.ambientOcclusionBias,
    (v) => e.ambientOcclusionBias = v,
  );
  number(
    'ambientOcclusionPower',
    e.ambientOcclusionPower,
    (v) => e.ambientOcclusionPower = v,
  );
  number(
    'ambientOcclusionDetail',
    e.ambientOcclusionDetail,
    (v) => e.ambientOcclusionDetail = v,
  );
  number(
    'ambientOcclusionHorizonAngle',
    e.ambientOcclusionHorizonAngle,
    (v) => e.ambientOcclusionHorizonAngle = v,
  );
  number(
    'ambientOcclusionDirectLightAffect',
    e.ambientOcclusionDirectLightAffect,
    (v) => e.ambientOcclusionDirectLightAffect = v,
  );
  integer(
    'ambientOcclusionSampleCount',
    e.ambientOcclusionSampleCount,
    (v) => e.ambientOcclusionSampleCount = v,
  );
  string(
    'ambientOcclusionMethod',
    e.ambientOcclusionMethod,
    (v) => e.ambientOcclusionMethod = v,
  );
  number(
    'ambientOcclusionMultiBounce',
    e.ambientOcclusionMultiBounce,
    (v) => e.ambientOcclusionMultiBounce = v,
  );
  integer(
    'ambientOcclusionSliceCount',
    e.ambientOcclusionSliceCount,
    (v) => e.ambientOcclusionSliceCount = v,
  );
  integer(
    'ambientOcclusionStepsPerSlice',
    e.ambientOcclusionStepsPerSlice,
    (v) => e.ambientOcclusionStepsPerSlice = v,
  );
  boolean(
    'ambientOcclusionVisibilityBitmask',
    (v) => e.ambientOcclusionVisibilityBitmask = v,
  );
  number(
    'ambientOcclusionThickness',
    e.ambientOcclusionThickness,
    (v) => e.ambientOcclusionThickness = v,
  );
  number(
    'ambientOcclusionThicknessHeuristic',
    e.ambientOcclusionThicknessHeuristic,
    (v) => e.ambientOcclusionThicknessHeuristic = v,
  );
  boolean(
    'ambientOcclusionBentNormals',
    (v) => e.ambientOcclusionBentNormals = v,
  );
  number(
    'ambientOcclusionIndirectLight',
    e.ambientOcclusionIndirectLight,
    (v) => e.ambientOcclusionIndirectLight = v,
  );
  boolean(
    'ambientOcclusionHalfResolution',
    (v) => e.ambientOcclusionHalfResolution = v,
  );
  boolean(
    'ambientOcclusionDepthMipChain',
    (v) => e.ambientOcclusionDepthMipChain = v,
  );
  string(
    'ambientOcclusionSpecularMode',
    e.ambientOcclusionSpecularMode,
    (v) => e.ambientOcclusionSpecularMode = v,
  );
  boolean(
    'screenSpaceReflectionsEnabled',
    (v) => e.screenSpaceReflectionsEnabled = v,
  );
  number(
    'screenSpaceReflectionsIntensity',
    e.screenSpaceReflectionsIntensity,
    (v) => e.screenSpaceReflectionsIntensity = v,
  );
  number(
    'screenSpaceReflectionsMaxDistance',
    e.screenSpaceReflectionsMaxDistance,
    (v) => e.screenSpaceReflectionsMaxDistance = v,
  );
  number(
    'screenSpaceReflectionsThickness',
    e.screenSpaceReflectionsThickness,
    (v) => e.screenSpaceReflectionsThickness = v,
  );
  number(
    'screenSpaceReflectionsStride',
    e.screenSpaceReflectionsStride,
    (v) => e.screenSpaceReflectionsStride = v,
  );
  integer(
    'screenSpaceReflectionsMaxSteps',
    e.screenSpaceReflectionsMaxSteps,
    (v) => e.screenSpaceReflectionsMaxSteps = v,
  );
  number(
    'screenSpaceReflectionsBlur',
    e.screenSpaceReflectionsBlur,
    (v) => e.screenSpaceReflectionsBlur = v,
  );
  number(
    'screenSpaceReflectionsDistanceFadeStart',
    e.screenSpaceReflectionsDistanceFadeStart,
    (v) => e.screenSpaceReflectionsDistanceFadeStart = v,
  );
  number(
    'screenSpaceReflectionsResolutionScale',
    e.screenSpaceReflectionsResolutionScale,
    (v) => e.screenSpaceReflectionsResolutionScale = v,
  );
  boolean('fogEnabled', (v) => e.fogEnabled = v);
  string('fogMode', e.fogMode, (v) => e.fogMode = v);
  vector('fogColor', e.fogColor, (v) => e.fogColor = v);
  number(
    'fogSkyColorInfluence',
    e.fogSkyColorInfluence,
    (v) => e.fogSkyColorInfluence = v,
  );
  number('fogDensity', e.fogDensity, (v) => e.fogDensity = v);
  number('fogStart', e.fogStart, (v) => e.fogStart = v);
  number('fogEnd', e.fogEnd, (v) => e.fogEnd = v);
  number('fogMaxOpacity', e.fogMaxOpacity, (v) => e.fogMaxOpacity = v);
  number(
    'fogCutoffDistance',
    e.fogCutoffDistance,
    (v) => e.fogCutoffDistance = v,
  );
  number('fogHeight', e.fogHeight, (v) => e.fogHeight = v);
  number('fogHeightFalloff', e.fogHeightFalloff, (v) => e.fogHeightFalloff = v);
  number('fogSunInScatter', e.fogSunInScatter, (v) => e.fogSunInScatter = v);
  number(
    'fogSunInScatterExponent',
    e.fogSunInScatterExponent,
    (v) => e.fogSunInScatterExponent = v,
  );
  boolean('godRaysEnabled', (v) => e.godRaysEnabled = v);
  number('godRaysIntensity', e.godRaysIntensity, (v) => e.godRaysIntensity = v);
  number('godRaysDensity', e.godRaysDensity, (v) => e.godRaysDensity = v);
  number(
    'godRaysAnisotropy',
    e.godRaysAnisotropy,
    (v) => e.godRaysAnisotropy = v,
  );
  integer(
    'godRaysStepCount',
    e.godRaysStepCount,
    (v) => e.godRaysStepCount = v,
  );
  number(
    'godRaysMaxDistance',
    e.godRaysMaxDistance,
    (v) => e.godRaysMaxDistance = v,
  );
  number('godRaysJitter', e.godRaysJitter, (v) => e.godRaysJitter = v);
  vector('godRaysColor', e.godRaysColor, (v) => e.godRaysColor = v);
  boolean('depthOfFieldEnabled', (v) => e.depthOfFieldEnabled = v);
  number(
    'depthOfFieldFocusDistance',
    e.depthOfFieldFocusDistance,
    (v) => e.depthOfFieldFocusDistance = v,
  );
  number(
    'depthOfFieldFStop',
    e.depthOfFieldFStop,
    (v) => e.depthOfFieldFStop = v,
  );
  number(
    'depthOfFieldFocalLength',
    e.depthOfFieldFocalLength,
    (v) => e.depthOfFieldFocalLength = v,
  );
  number(
    'depthOfFieldSensorHeight',
    e.depthOfFieldSensorHeight,
    (v) => e.depthOfFieldSensorHeight = v,
  );
  number(
    'depthOfFieldBlurScale',
    e.depthOfFieldBlurScale,
    (v) => e.depthOfFieldBlurScale = v,
  );
  number(
    'depthOfFieldMaxForegroundBlur',
    e.depthOfFieldMaxForegroundBlur,
    (v) => e.depthOfFieldMaxForegroundBlur = v,
  );
  number(
    'depthOfFieldMaxBackgroundBlur',
    e.depthOfFieldMaxBackgroundBlur,
    (v) => e.depthOfFieldMaxBackgroundBlur = v,
  );
  integer(
    'depthOfFieldBladeCount',
    e.depthOfFieldBladeCount,
    (v) => e.depthOfFieldBladeCount = v,
  );
  number(
    'depthOfFieldBladeRotation',
    e.depthOfFieldBladeRotation,
    (v) => e.depthOfFieldBladeRotation = v,
  );
  number(
    'depthOfFieldBladeCurvature',
    e.depthOfFieldBladeCurvature,
    (v) => e.depthOfFieldBladeCurvature = v,
  );
  string(
    'depthOfFieldQuality',
    e.depthOfFieldQuality,
    (v) => e.depthOfFieldQuality = v,
  );
  boolean('autoExposureEnabled', (v) => e.autoExposureEnabled = v);
  number(
    'autoExposureStrength',
    e.autoExposureStrength,
    (v) => e.autoExposureStrength = v,
  );
  number(
    'autoExposureCompensation',
    e.autoExposureCompensation,
    (v) => e.autoExposureCompensation = v,
  );
  number(
    'autoExposureMinEv',
    e.autoExposureMinEv,
    (v) => e.autoExposureMinEv = v,
  );
  number(
    'autoExposureMaxEv',
    e.autoExposureMaxEv,
    (v) => e.autoExposureMaxEv = v,
  );
  number(
    'autoExposureSpeedUp',
    e.autoExposureSpeedUp,
    (v) => e.autoExposureSpeedUp = v,
  );
  number(
    'autoExposureSpeedDown',
    e.autoExposureSpeedDown,
    (v) => e.autoExposureSpeedDown = v,
  );
  return changed;
}

// Applies a skybox/sky-lighting change to [next], reading the prior look from
// [old]. Mirrors setSkybox; shared by the stage, volume, and environment
// commands.
void _applyLookSkybox(
  _LookView next,
  _LookView old, {
  required String sky,
  String? asset,
  Vector3? sun,
  required bool lightScene,
  required bool castShadows,
}) {
  final current = old.skybox?.source;
  final sameType =
      (sky == 'gradient' && current is GradientSkySpec) ||
      (sky == 'physical' && current is PhysicalSkySpec) ||
      (sky == 'weather' && current is WeatherSkySpec) ||
      (sky == 'environment' && current is EnvironmentSkySpec) ||
      (sky == 'fmat' &&
          current is FmatSkySpec &&
          (asset == null || current.asset.key == asset));
  final SkySourceSpec? base;
  if (sameType) {
    base = current!;
  } else if (sky == 'fmat') {
    if (asset == null) {
      throw const CommandException(
        'A shader sky needs an asset (the .fmat source path).',
      );
    }
    base = FmatSkySpec(AssetRef(asset));
  } else {
    base = _defaultSkySource(sky);
  }
  final seedSun = sun ?? (sameType ? null : _specSunDirection(current));
  final overrides = <String, PropertyValue>{
    if (seedSun != null) 'sunDirection': Vec3Value(seedSun.clone()),
  };
  SkySourceSpec? makeSource() =>
      base == null ? null : _skySourceFrom(base, overrides);

  final skySource = makeSource();
  next.skybox = skySource == null
      ? null
      : SkyboxSpec(skySource, intensity: old.skybox?.intensity ?? 1.0);
  // Procedural and shader skies can drive image-based lighting (a shader sky
  // realizes as a ShaderSkySource).
  final canLight =
      sky == 'gradient' ||
      sky == 'physical' ||
      sky == 'weather' ||
      sky == 'fmat';
  final priorEnv = old.skyEnvironment;
  next.skyEnvironment = (lightScene && canLight)
      ? SkyEnvironmentSpec(
          makeSource()!,
          refresh: priorEnv?.refresh ?? 'manual',
          intervalSeconds: priorEnv?.intervalSeconds ?? 1.0,
          faceResolution: priorEnv?.faceResolution ?? 128,
          equirectWidth: priorEnv?.equirectWidth ?? 512,
          sunLight: castShadows
              ? (_copySunLight(priorEnv?.sunLight ?? SunLightSpec())
                  ..castsShadow = true)
              : null,
        )
      : null;
}

// Patches the current sky's parameters on [next] (both the skybox and a sky
// lighting binding). Mirrors setSkyParameters; throws when there is no sky.
void _applyLookSkyParameters(_LookView next, Map<String, PropertyValue> props) {
  final skybox = next.skybox;
  if (skybox == null) {
    throw const CommandException(
      'No sky to tune; choose a skybox with setSkybox first.',
    );
  }
  next.skybox = SkyboxSpec(
    _skySourceFrom(skybox.source, props),
    intensity: _stageDouble(props['intensity'], skybox.intensity),
  );
  final priorEnv = next.skyEnvironment;
  if (priorEnv != null) {
    next.skyEnvironment = SkyEnvironmentSpec(
      _skySourceFrom(priorEnv.source, props),
      refresh: priorEnv.refresh,
      intervalSeconds: priorEnv.intervalSeconds,
      faceResolution: priorEnv.faceResolution,
      equirectWidth: priorEnv.equirectWidth,
      sunLight: priorEnv.sunLight == null
          ? null
          : _copySunLight(priorEnv.sunLight!),
    );
  }
}

double _stageDouble(PropertyValue? v, double fallback) => switch (v) {
  DoubleValue(:final value) => value,
  IntValue(:final value) => value.toDouble(),
  _ => fallback,
};

String _stageString(PropertyValue? v, String fallback) =>
    v is StringValue ? v.value : fallback;

int? _stageInt(PropertyValue? v) => switch (v) {
  IntValue(:final value) => value,
  DoubleValue(:final value) => value.round(),
  _ => null,
};

/// Updates scene-wide stage render settings (anti-aliasing, render scale, filter
/// quality). Only the keys present in `properties` change; the rest keep their
/// values. The whole stage is one reversible record, so the edit is undoable.
/// The scene look (environment, exposure, tone mapping, sky) lives in the stage's
/// environment resource; edit it with `setEnvironmentProperties` /
/// `setSkybox` / `setSkyParameters`.
final setStageProperties = CommandEntry(
  name: 'setStageProperties',
  doc: 'Update scene-wide stage render settings.',
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
    WeatherSkySpec w => WeatherSkySpec(
      sunDirection: vec('sunDirection', w.sunDirection),
      sunAngularRadius: dbl('sunAngularRadius', w.sunAngularRadius),
      rayleighCoefficient: dbl('rayleighCoefficient', w.rayleighCoefficient),
      rayleighColor: vec('rayleighColor', w.rayleighColor),
      mieCoefficient: dbl('mieCoefficient', w.mieCoefficient),
      mieEccentricity: dbl('mieEccentricity', w.mieEccentricity),
      mieColor: vec('mieColor', w.mieColor),
      turbidity: dbl('turbidity', w.turbidity),
      groundColor: vec('groundColor', w.groundColor),
      energy: dbl('energy', w.energy),
      coverage: dbl('coverage', w.coverage),
      density: dbl('density', w.density),
      altitude: dbl('altitude', w.altitude),
      detail: dbl('detail', w.detail),
      softness: dbl('softness', w.softness),
      seed: switch (overrides['seed']) {
        IntValue(:final value) => value,
        DoubleValue(:final value) => value.round(),
        _ => w.seed,
      },
      wind: Vector2(dbl('windX', w.wind.x), dbl('windY', w.wind.y)),
      cloudColor: vec('cloudColor', w.cloudColor),
      cloudShading: dbl('cloudShading', w.cloudShading),
      stormDarkening: dbl('stormDarkening', w.stormDarkening),
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
  'weather' => WeatherSkySpec(),
  'environment' => EnvironmentSkySpec(),
  _ => null,
};

Vector3? _specSunDirection(SkySourceSpec? source) => switch (source) {
  GradientSkySpec(:final sunDirection) => sunDirection,
  PhysicalSkySpec(:final sunDirection) => sunDirection,
  WeatherSkySpec(:final sunDirection) => sunDirection,
  _ => null,
};

/// Sets the scene skybox
/// (`none`/`environment`/`gradient`/`physical`/`weather`) and,
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
      name: 'asset',
      type: ParamType.string,
      label: 'Asset (.fmat)',
      required: false,
    ),
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
    return _editStageLook(ctx, 'Set skybox', (next, old) {
      final lightScene = params.containsKey('lightScene')
          ? params['lightScene'] == true
          : old.skyEnvironment != null;
      final castShadows = params.containsKey('castShadows')
          ? params['castShadows'] == true
          : (old.skyEnvironment?.sunLight?.castsShadow ?? false);
      _applyLookSkybox(
        next,
        old,
        sky: sky,
        asset: optionalString(params, 'asset'),
        sun: sun,
        lightScene: lightScene,
        castShadows: castShadows,
      );
    });
  },
);

// Edits the stage's global environment resource, creating and linking a studio
// default when the stage references none, so the stage-look commands (skybox,
// sky tuning) always target a resource. [mutate] gets the working copy to write
// and the prior look to read defaults from.
Transaction _editStageLook(
  CommandContext ctx,
  String name,
  void Function(_EnvResourceLook next, _EnvResourceLook old) mutate,
) {
  final stage = ctx.document.stage;
  final ref = stage.environmentRef;
  final existing = ref == null ? null : ctx.document.resource(ref);
  final base = existing is EnvironmentResource
      ? existing
      : EnvironmentResource(ctx.document.newId(), name: 'Environment');
  final next = _copyEnvironmentResource(base);
  mutate(_EnvResourceLook(next), _EnvResourceLook(base));
  if (existing is EnvironmentResource) {
    return _environmentTransaction(name, base.id, base, next);
  }
  // No stage environment yet: add the new resource and link the stage to it.
  final stageNext = _copyStage(stage)..environmentRef = base.id;
  return Transaction(
    name: name,
    records: [
      _addResourceRecord(next),
      ChangeRecord(
        targetId: ChangeRecord.rootsTarget,
        slot: ChangeSlot.stage,
        oldValue: StageMetadataChange(stage),
        newValue: StageMetadataChange(stageNext),
      ),
    ],
  );
}

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
    return _editStageLook(
      ctx,
      'Tune sky',
      (next, old) => _applyLookSkyParameters(next, props),
    );
  },
);

Transaction _environmentTransaction(
  String name,
  LocalId id,
  EnvironmentResource old,
  EnvironmentResource next,
) => Transaction(
  name: name,
  records: [
    ChangeRecord(
      targetId: id,
      slot: ChangeSlot.poolResource,
      oldValue: ResourceChange(old),
      newValue: ResourceChange(next),
    ),
  ],
);

/// Points the stage's global environment at an environment resource (or clears
/// the reference when `environmentId` is omitted, leaving the stage on the
/// studio default until one is set).
final setStageEnvironment = CommandEntry(
  name: 'setStageEnvironment',
  doc: 'Set the stage global environment resource.',
  category: 'Stage',
  paramSchema: const [
    ParamSpec(
      name: 'environmentId',
      type: ParamType.resourceRef,
      label: 'Environment',
      required: false,
    ),
  ],
  execute: (ctx, params) {
    final old = ctx.document.stage;
    final next = _copyStage(old);
    next.environmentRef = optionalResourceId(params, 'environmentId');
    return Transaction(
      name: 'Set stage environment',
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

/// Creates an environment resource (a reusable scene look) in the pool. The new
/// resource's id is the created record's target id. Edit its look with the
/// `setEnvironment*` commands and reference it from an environment-volume
/// component or the stage.
final createEnvironmentResource = CommandEntry(
  name: 'createEnvironmentResource',
  doc: 'Create an environment resource.',
  category: 'Resource',
  paramSchema: const [
    ParamSpec(
      name: 'name',
      type: ParamType.string,
      label: 'Name',
      required: false,
    ),
  ],
  execute: (ctx, params) {
    final resource = EnvironmentResource(
      ctx.document.newId(),
      name: optionalString(params, 'name') ?? '',
    );
    return Transaction(
      name: 'Create environment',
      records: [_addResourceRecord(resource)],
    );
  },
);

/// Updates an environment resource's scalar look (exposure, environment
/// intensity, tone mapping, the environment kind, reflection size). Only the
/// keys present in `properties` change.
/// A copy of [base] with look [properties] applied, using the same coercion
/// and key set as `setEnvironmentProperties`; for previewing a slider drag
/// on the live scene without a document transaction.
EnvironmentResource environmentResourceWithProperties(
  EnvironmentResource base,
  Map<String, Object?> properties,
) {
  final next = _copyEnvironmentResource(base);
  _applyLookProperties(_EnvResourceLook(next), {
    for (final entry in properties.entries)
      entry.key: coercePropertyValue(entry.value),
  });
  return next;
}

final setEnvironmentProperties = CommandEntry(
  name: 'setEnvironmentProperties',
  doc: 'Update an environment resource look.',
  category: 'Resource',
  paramSchema: const [
    ParamSpec(
      name: 'environmentId',
      type: ParamType.resourceRef,
      label: 'Environment',
    ),
    ParamSpec(
      name: 'properties',
      type: ParamType.propertyMap,
      label: 'Settings',
    ),
  ],
  execute: (ctx, params) {
    final id = requireResourceId(params, 'environmentId');
    final existing = _requireEnvironment(ctx, id);
    final next = _copyEnvironmentResource(existing);
    _applyLookProperties(
      _EnvResourceLook(next),
      optionalPropertyMap(params, 'properties'),
    );
    return _environmentTransaction(
      'Set environment settings',
      id,
      existing,
      next,
    );
  },
);

/// Assigns or removes an environment image as one undoable operation.
///
/// An empty `asset` removes the image. If the visible background uses the
/// lighting environment, removal clears that background as well.
final setEnvironmentImage = CommandEntry(
  name: 'setEnvironmentImage',
  doc: 'Assign or remove an environment image.',
  category: 'Resource',
  paramSchema: const [
    ParamSpec(
      name: 'environmentId',
      type: ParamType.resourceRef,
      label: 'Environment',
    ),
    ParamSpec(name: 'asset', type: ParamType.assetRef, label: 'Image'),
    ParamSpec(
      name: 'showAsBackground',
      type: ParamType.boolean,
      label: 'Show as background',
      required: false,
    ),
  ],
  execute: (ctx, params) {
    final id = requireResourceId(params, 'environmentId');
    final existing = _requireEnvironment(ctx, id);
    final next = _copyEnvironmentResource(existing);
    final asset = requireString(params, 'asset').trim();
    final showAsBackground = params.containsKey('showAsBackground')
        ? params['showAsBackground'] == true
        : next.skybox?.source is EnvironmentSkySpec;
    if (asset.isEmpty) {
      next.environment = const EmptyEnvironment();
      if (next.skybox?.source is EnvironmentSkySpec) next.skybox = null;
    } else {
      next.environment = AssetEnvironment(AssetRef(asset));
      if (showAsBackground) {
        next.skybox = SkyboxSpec(
          EnvironmentSkySpec(
            blurriness: switch (next.skybox?.source) {
              EnvironmentSkySpec(:final blurriness) => blurriness,
              _ => 0.0,
            },
          ),
          intensity: next.skybox?.intensity ?? 1.0,
        );
      } else if (next.skybox?.source is EnvironmentSkySpec) {
        next.skybox = null;
      }
    }
    return _environmentTransaction(
      asset.isEmpty ? 'Remove environment image' : 'Set environment image',
      id,
      existing,
      next,
    );
  },
);

/// Sets an environment resource's skybox and optional sky lighting, mirroring
/// `setSkybox` for the stage.
final setEnvironmentSkybox = CommandEntry(
  name: 'setEnvironmentSkybox',
  doc: 'Set an environment resource skybox and sky lighting.',
  category: 'Resource',
  paramSchema: const [
    ParamSpec(
      name: 'environmentId',
      type: ParamType.resourceRef,
      label: 'Environment',
    ),
    ParamSpec(name: 'sky', type: ParamType.string, label: 'Sky'),
    ParamSpec(
      name: 'asset',
      type: ParamType.string,
      label: 'Asset (.fmat)',
      required: false,
    ),
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
    final id = requireResourceId(params, 'environmentId');
    final existing = _requireEnvironment(ctx, id);
    final oldLook = _EnvResourceLook(existing);
    final lightScene = params.containsKey('lightScene')
        ? params['lightScene'] == true
        : oldLook.skyEnvironment != null;
    final castShadows = params.containsKey('castShadows')
        ? params['castShadows'] == true
        : (oldLook.skyEnvironment?.sunLight?.castsShadow ?? false);
    final next = _copyEnvironmentResource(existing);
    _applyLookSkybox(
      _EnvResourceLook(next),
      oldLook,
      sky: requireString(params, 'sky'),
      asset: optionalString(params, 'asset'),
      sun: optionalVec3(params, 'sunDirection'),
      lightScene: lightScene,
      castShadows: castShadows,
    );
    return _environmentTransaction(
      'Set environment skybox',
      id,
      existing,
      next,
    );
  },
);

/// Tunes an environment resource's procedural sky parameters, mirroring
/// `setSkyParameters` for the stage.
final setEnvironmentSkyParameters = CommandEntry(
  name: 'setEnvironmentSkyParameters',
  doc: 'Tune an environment resource sky parameters.',
  category: 'Resource',
  paramSchema: const [
    ParamSpec(
      name: 'environmentId',
      type: ParamType.resourceRef,
      label: 'Environment',
    ),
    ParamSpec(
      name: 'properties',
      type: ParamType.propertyMap,
      label: 'Sky parameters',
    ),
  ],
  execute: (ctx, params) {
    final id = requireResourceId(params, 'environmentId');
    final existing = _requireEnvironment(ctx, id);
    final next = _copyEnvironmentResource(existing);
    _applyLookSkyParameters(
      _EnvResourceLook(next),
      optionalPropertyMap(params, 'properties'),
    );
    return _environmentTransaction('Tune environment sky', id, existing, next);
  },
);

/// Tunes a sky-driven sun and its cascaded shadows.
/// A copy of [base] with sun-light [properties] applied, using the same
/// coercion and key set as `setEnvironmentSunLightProperties`; null when the
/// environment has no analytic sun. For previewing slider drags on the live
/// scene without a document transaction.
EnvironmentResource? environmentResourceWithSunProperties(
  EnvironmentResource base,
  Map<String, Object?> properties,
) {
  final next = _copyEnvironmentResource(base);
  final sun = next.skyEnvironment?.sunLight;
  if (sun == null) return null;
  _applySunLightProperties(sun, {
    for (final entry in properties.entries)
      entry.key: coercePropertyValue(entry.value),
  });
  return next;
}

final setEnvironmentSunLightProperties = CommandEntry(
  name: 'setEnvironmentSunLightProperties',
  doc: 'Tune an environment resource sun light.',
  category: 'Resource',
  paramSchema: const [
    ParamSpec(
      name: 'environmentId',
      type: ParamType.resourceRef,
      label: 'Environment',
    ),
    ParamSpec(
      name: 'properties',
      type: ParamType.propertyMap,
      label: 'Sun light settings',
    ),
  ],
  execute: (ctx, params) {
    final id = requireResourceId(params, 'environmentId');
    final existing = _requireEnvironment(ctx, id);
    final next = _copyEnvironmentResource(existing);
    final sun = next.skyEnvironment?.sunLight;
    if (sun == null) {
      throw const CommandException('The environment has no analytic sun.');
    }
    _applySunLightProperties(sun, optionalPropertyMap(params, 'properties'));
    return _environmentTransaction('Tune environment sun', id, existing, next);
  },
);

void _applySunLightProperties(
  SunLightSpec sun,
  Map<String, PropertyValue> properties,
) {
  double number(String key, double current) =>
      _stageDouble(properties[key], current);
  int integer(String key, int current) => _stageInt(properties[key]) ?? current;
  bool boolean(String key, bool current) => switch (properties[key]) {
    BoolValue(:final value) => value,
    _ => current,
  };
  String text(String key, String current) =>
      _stageString(properties[key], current);

  sun
    ..castsShadow = boolean('castsShadow', sun.castsShadow)
    ..intensityScale = number('intensityScale', sun.intensityScale)
    ..priority = integer('priority', sun.priority)
    ..cacheStaticShadows = boolean('cacheStaticShadows', sun.cacheStaticShadows)
    ..shadowSoftness = number('shadowSoftness', sun.shadowSoftness)
    ..shadowMaxDistance = number('shadowMaxDistance', sun.shadowMaxDistance)
    ..shadowCascadeCount = integer('shadowCascadeCount', sun.shadowCascadeCount)
    ..shadowMapResolution = integer(
      'shadowMapResolution',
      sun.shadowMapResolution,
    )
    ..shadowDepthBias = number('shadowDepthBias', sun.shadowDepthBias)
    ..shadowNormalBias = number('shadowNormalBias', sun.shadowNormalBias)
    ..shadowFadeRange = number('shadowFadeRange', sun.shadowFadeRange)
    ..shadowCascadeSplitLambda = number(
      'shadowCascadeSplitLambda',
      sun.shadowCascadeSplitLambda,
    )
    ..shadowAmbientStrength = number(
      'shadowAmbientStrength',
      sun.shadowAmbientStrength,
    )
    ..shadowFilter = text('shadowFilter', sun.shadowFilter)
    ..shadowCasterFaces = text('shadowCasterFaces', sun.shadowCasterFaces);
}

// ---------------------------------------------------------------------------
// Prefab commands.
// ---------------------------------------------------------------------------

PrefabInstanceSpec _withDelta(
  PrefabInstanceSpec i, {
  List<PropertyOverride>? overrides,
  List<Attachment>? attachments,
  List<LocalId>? removedNodes,
  List<MemberComponent>? memberComponents,
}) => i.copyWith(
  overrides: overrides,
  attachments: attachments,
  removedNodes: removedNodes,
  memberComponents: memberComponents,
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

/// Attaches a component to a prefab member node, recorded on the enclosing
/// instance's delta, so it composes onto the member and survives saves.
/// Replaces an existing record for the same member and type, matching
/// `addComponent`.
final addPrefabMemberComponent = CommandEntry(
  name: 'addPrefabMemberComponent',
  doc: 'Attach a component to a prefab member node.',
  category: 'Prefab',
  paramSchema: const [
    ParamSpec(name: 'nodeId', type: ParamType.nodeRef, label: 'Instance'),
    ParamSpec(name: 'memberId', type: ParamType.nodeRef, label: 'Member'),
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
    final instance = node.instance;
    if (instance == null) {
      throw const CommandException('Node is not a prefab instance');
    }
    final member = requireNodeId(params, 'memberId');
    final type = requireString(params, 'componentType');
    final component = ComponentSpec(
      type,
      properties: optionalPropertyMap(
        params,
        'properties',
        schema: ctx.componentSchema?.call(type),
      ),
    );
    final next = [
      for (final mc in instance.memberComponents)
        if (!(mc.member == member && mc.component.type == type)) mc,
      MemberComponent(member: member, component: component),
    ];
    return Transaction(
      name: 'Add component ($type)',
      records: [
        _instanceRecord(
          id,
          instance,
          _withDelta(instance, memberComponents: next),
        ),
      ],
    );
  },
);

/// Removes a component this instance added to a prefab member node.
final removePrefabMemberComponent = CommandEntry(
  name: 'removePrefabMemberComponent',
  doc: 'Remove a component added to a prefab member node.',
  category: 'Prefab',
  paramSchema: const [
    ParamSpec(name: 'nodeId', type: ParamType.nodeRef, label: 'Instance'),
    ParamSpec(name: 'memberId', type: ParamType.nodeRef, label: 'Member'),
    ParamSpec(name: 'componentType', type: ParamType.string, label: 'Type'),
  ],
  execute: (ctx, params) {
    final id = requireNodeId(params, 'nodeId');
    final node = _requireNode(ctx, id);
    final instance = node.instance;
    if (instance == null) {
      throw const CommandException('Node is not a prefab instance');
    }
    final member = requireNodeId(params, 'memberId');
    final type = requireString(params, 'componentType');
    final next = [
      for (final mc in instance.memberComponents)
        if (!(mc.member == member && mc.component.type == type)) mc,
    ];
    if (next.length == instance.memberComponents.length) {
      return Transaction(name: 'Remove component ($type)', records: _empty);
    }
    // Drop overrides that addressed the removed component. Left behind, a
    // "components.<type>.<prop>" override targets a component that no longer
    // composes, so compose logs it as unresolved on every load.
    final prefix = 'components.$type';
    final overrides = [
      for (final o in instance.overrides)
        if (!(o.target == member &&
            (o.path == prefix || o.path.startsWith('$prefix.'))))
          o,
    ];
    return Transaction(
      name: 'Remove component ($type)',
      records: [
        _instanceRecord(
          id,
          instance,
          _withDelta(instance, memberComponents: next, overrides: overrides),
        ),
      ],
    );
  },
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
  createPlaneGeometry,
  createCylinderGeometry,
  createCapsuleGeometry,
  createTorusGeometry,
  createDiscGeometry,
  createIcosphereGeometry,
  createWedgeGeometry,
  createTerrainGeometry,
  setTerrainHeights,
  makeTerrainSculptable,
  setTerrainSplat,
  addTerrainLayers,
  createMaterial,
  createTextureResource,
  createTextureResourceFromAsset,
  setMaterialProperties,
  setMaterialType,
  clearMaterialProperty,
  createEnvironmentResource,
  setEnvironmentProperties,
  setEnvironmentImage,
  setEnvironmentSkybox,
  setEnvironmentSkyParameters,
  setEnvironmentSunLightProperties,
  setStageEnvironment,
  removeResource,
  setStageProperties,
  setSkybox,
  setSkyParameters,
  instantiatePrefab,
  setPrefabOverride,
  removePrefabOverride,
  addPrefabMemberComponent,
  removePrefabMemberComponent,
  clearPrefabOverrides,
  removePrefabMember,
  attachToPrefabMember,
  attachExistingToPrefabMember,
  detachFromPrefab,
  ...animationCommands,
];
