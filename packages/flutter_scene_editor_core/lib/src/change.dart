/// The change-record model: the substrate every edit is expressed in.
///
/// A [ChangeRecord] is one reversible assignment, which entity changed, which
/// slot, and the value before and after. A [Transaction] is an ordered, named
/// batch of records that together form one user-visible edit. Apply replays
/// the records forward; revert replays them in reverse, restoring the prior
/// state exactly. Undo, redo, and (later) collaboration all build on this
/// uniform shape rather than on hand-written do/undo pairs.
///
/// All writes flow through [DocumentMutator], the single privileged seam onto
/// the [SceneDocument]. Commands never mutate the document any other way.
library;

import 'package:flutter_scene/src/fscene/id.dart';
import 'package:flutter_scene/src/fscene/scene_document.dart';
import 'package:flutter_scene/src/fscene/specs.dart';

/// The value at one end of a [ChangeRecord].
///
/// A closed (`sealed`) tagged union so the interpreter can switch over every
/// case exhaustively. It spans node scalar fields, whole-list snapshots, and
/// pool entries (a [NodeChangeValue] or [ResourceChangeValue] carrying the
/// full spec), so structural add and remove are ordinary records, not a
/// special transaction kind.
sealed class ChangeValue {
  const ChangeValue();
}

/// A string value (for example a node name).
class StringChange extends ChangeValue {
  const StringChange(this.value);
  final String value;
}

/// A boolean value (for example node visibility).
class BoolChange extends ChangeValue {
  const BoolChange(this.value);
  final bool value;
}

/// An integer value (for example a layer bitmask).
class IntChange extends ChangeValue {
  const IntChange(this.value);
  final int value;
}

/// A node transform.
class TransformChange extends ChangeValue {
  const TransformChange(this.value);
  final TransformSpec value;
}

/// A nullable [LocalId] reference (for example a node's bound skin).
class LocalIdChange extends ChangeValue {
  const LocalIdChange(this.value);
  final LocalId? value;
}

/// A nullable prefab-instance spec (a node's [NodeSpec.instance]).
class PrefabInstanceChange extends ChangeValue {
  const PrefabInstanceChange(this.value);
  final PrefabInstanceSpec? value;
}

/// A whole node spec, carried by a pool entry. A null [value] means the entry
/// is absent (the post-state of a remove, the pre-state of an add).
class NodeChange extends ChangeValue {
  const NodeChange(this.value);
  final NodeSpec? value;
}

/// A whole resource spec, carried by a pool entry. A null [value] means absent.
class ResourceChange extends ChangeValue {
  const ResourceChange(this.value);
  final ResourceSpec? value;
}

/// A whole skin spec, carried by a pool entry. A null [value] means absent.
class SkinChange extends ChangeValue {
  const SkinChange(this.value);
  final SkinSpec? value;
}

/// A whole animation spec, carried by a pool entry. A null [value] means
/// absent.
class AnimationChange extends ChangeValue {
  const AnimationChange(this.value);
  final AnimationSpec? value;
}

/// A whole payload (binary chunk) spec, carried by a pool entry. A null
/// [value] means absent.
class PayloadChange extends ChangeValue {
  const PayloadChange(this.value);
  final PayloadSpec? value;
}

/// The document's whole stage metadata (scene-wide render settings).
class StageMetadataChange extends ChangeValue {
  const StageMetadataChange(this.value);
  final StageMetadata value;
}

/// A snapshot of a node's component list, replaced wholesale (component add,
/// remove, and property edits all set the whole list, which keeps every list
/// edit trivially reversible).
class ComponentListChange extends ChangeValue {
  const ComponentListChange(this.value);
  final List<ComponentSpec> value;
}

/// A snapshot of an ordered id list (a node's children, or the document roots).
class IdListChange extends ChangeValue {
  const IdListChange(this.value);
  final List<LocalId> value;
}

/// The slot a [ChangeRecord] writes. The string form doubles as a stable,
/// human-readable path for diffs and logs.
enum ChangeSlot {
  /// The node-pool entry keyed by the record's target id.
  poolNode('pool.node'),

  /// The resource-pool entry keyed by the record's target id.
  poolResource('pool.resource'),

  /// The skin-pool entry keyed by the record's target id.
  poolSkin('pool.skin'),

  /// The animation-pool entry keyed by the record's target id.
  poolAnimation('pool.animation'),

  /// The payload-pool (binary chunk) entry keyed by the record's target id.
  poolPayload('pool.payload'),

  /// A node's name.
  name('name'),

  /// A node's visibility.
  visible('visible'),

  /// A node's render-layer bitmask.
  layers('layers'),

  /// A node's local transform.
  transform('transform'),

  /// A node's bound skin id.
  skin('skin'),

  /// A node's prefab-instance spec.
  instance('instance'),

  /// A node's component list (replaced wholesale).
  components('components'),

  /// A node's ordered child id list (replaced wholesale).
  children('children'),

  /// The document's ordered root id list (target id is [rootsTarget]).
  roots('roots'),

  /// The document's scene-wide stage metadata (target id is [rootsTarget]).
  stage('stage');

  const ChangeSlot(this.path);

  /// The stable dotted path for this slot.
  final String path;
}

/// One atomic, reversible assignment over a [SceneDocument].
class ChangeRecord {
  /// Creates a record assigning [slot] on [targetId] from [oldValue] to
  /// [newValue].
  const ChangeRecord({
    required this.targetId,
    required this.slot,
    required this.oldValue,
    required this.newValue,
  });

  /// The id of the node (or pool entry) this record targets, or [rootsTarget]
  /// for a [ChangeSlot.roots] record.
  final LocalId targetId;

  /// The slot being written.
  final ChangeSlot slot;

  /// The value before the change (restored on revert).
  final ChangeValue oldValue;

  /// The value after the change (written on apply).
  final ChangeValue newValue;

  /// The sentinel target id for document-level slots ([ChangeSlot.roots]).
  static const LocalId rootsTarget = LocalId(0, 0);
}

/// An ordered, named batch of [ChangeRecord]s forming one user-visible edit.
///
/// One user gesture is one transaction, so undo and redo move in
/// edit-sized steps. Records apply in order and revert in reverse.
class Transaction {
  /// Creates a transaction labelled [name] holding [records].
  Transaction({required this.name, required List<ChangeRecord> records})
    : records = List.unmodifiable(records);

  /// A human-readable label (shown in the undo-history UI).
  final String name;

  /// The records, in application order.
  final List<ChangeRecord> records;

  /// Whether this transaction makes no change (an empty record list).
  bool get isEmpty => records.isEmpty;

  /// Applies the records forward, advancing [mutator]'s document to the
  /// post-change state.
  void apply(DocumentMutator mutator) {
    for (final record in records) {
      _write(mutator, record.targetId, record.slot, record.newValue);
    }
  }

  /// Reverts the records in reverse, restoring the pre-change state.
  void revert(DocumentMutator mutator) {
    for (final record in records.reversed) {
      _write(mutator, record.targetId, record.slot, record.oldValue);
    }
  }

  static void _write(
    DocumentMutator mutator,
    LocalId targetId,
    ChangeSlot slot,
    ChangeValue value,
  ) {
    switch (slot) {
      case ChangeSlot.poolNode:
        mutator.setNodeEntry(targetId, (value as NodeChange).value);
      case ChangeSlot.poolResource:
        mutator.setResourceEntry(targetId, (value as ResourceChange).value);
      case ChangeSlot.poolSkin:
        mutator.setSkinEntry(targetId, (value as SkinChange).value);
      case ChangeSlot.poolAnimation:
        mutator.setAnimationEntry(targetId, (value as AnimationChange).value);
      case ChangeSlot.poolPayload:
        mutator.setPayloadEntry(targetId, (value as PayloadChange).value);
      case ChangeSlot.roots:
        mutator.setRoots((value as IdListChange).value);
      case ChangeSlot.stage:
        mutator.setStage((value as StageMetadataChange).value);
      case ChangeSlot.name:
        mutator.node(targetId)?.name = (value as StringChange).value;
      case ChangeSlot.visible:
        mutator.node(targetId)?.visible = (value as BoolChange).value;
      case ChangeSlot.layers:
        mutator.node(targetId)?.layers = (value as IntChange).value;
      case ChangeSlot.transform:
        mutator.node(targetId)?.transform = (value as TransformChange).value;
      case ChangeSlot.skin:
        mutator.node(targetId)?.skin = (value as LocalIdChange).value;
      case ChangeSlot.instance:
        mutator.node(targetId)?.instance =
            (value as PrefabInstanceChange).value;
      case ChangeSlot.components:
        mutator.setComponents(targetId, (value as ComponentListChange).value);
      case ChangeSlot.children:
        mutator.setChildren(targetId, (value as IdListChange).value);
    }
  }
}

/// The single privileged write surface onto a [SceneDocument].
///
/// The editor core mutates the document only through this seam (driven by
/// [Transaction.apply] and [Transaction.revert]), so undo, redo, and change
/// tracking can never be bypassed. Reads stay on the document's own API.
///
/// TODO(editor-mutation-surface): tighten flutter_scene so the document's
/// public fields are not directly mutable from outside, and route this seam
/// through an `@internal` API there. For now the discipline is enforced here.
class DocumentMutator {
  /// Wraps [document].
  DocumentMutator(this.document);

  /// The document being mutated.
  final SceneDocument document;

  /// The node with [id], or null.
  NodeSpec? node(LocalId id) => document.nodes[id];

  /// Sets (or, when [node] is null, removes) the node-pool entry for [id].
  /// Pool membership only; linkage lives in the children and roots slots.
  void setNodeEntry(LocalId id, NodeSpec? node) {
    if (node == null) {
      document.nodes.remove(id);
    } else {
      document.nodes[id] = node;
    }
  }

  /// Sets (or, when [resource] is null, removes) the resource-pool entry for
  /// [id].
  void setResourceEntry(LocalId id, ResourceSpec? resource) {
    if (resource == null) {
      document.resources.remove(id);
    } else {
      document.resources[id] = resource;
    }
  }

  /// Sets (or, when [skin] is null, removes) the skin-pool entry for [id].
  void setSkinEntry(LocalId id, SkinSpec? skin) {
    if (skin == null) {
      document.skins.remove(id);
    } else {
      document.skins[id] = skin;
    }
  }

  /// Sets (or, when [animation] is null, removes) the animation-pool entry for
  /// [id].
  void setAnimationEntry(LocalId id, AnimationSpec? animation) {
    if (animation == null) {
      document.animations.remove(id);
    } else {
      document.animations[id] = animation;
    }
  }

  /// Sets (or, when [payload] is null, removes) the payload-pool entry for
  /// [id].
  void setPayloadEntry(LocalId id, PayloadSpec? payload) {
    if (payload == null) {
      document.payloads.remove(id);
    } else {
      document.payloads[id] = payload;
    }
  }

  /// Replaces the document's root id list contents with [roots].
  void setRoots(List<LocalId> roots) {
    document.roots
      ..clear()
      ..addAll(roots);
  }

  /// Replaces the document's scene-wide stage metadata.
  void setStage(StageMetadata stage) => document.stage = stage;

  /// Replaces node [id]'s child id list contents with [children].
  void setChildren(LocalId id, List<LocalId> children) {
    document.nodes[id]?.children
      ?..clear()
      ..addAll(children);
  }

  /// Replaces node [id]'s component list contents with [components].
  void setComponents(LocalId id, List<ComponentSpec> components) {
    document.nodes[id]?.components
      ?..clear()
      ..addAll(components);
  }
}
