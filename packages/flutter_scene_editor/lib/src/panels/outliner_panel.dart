import 'dart:math' as math;

// ignore: implementation_imports
import 'package:scene/scene.dart';
// ignore: implementation_imports
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controller/editor_controller.dart';

/// Scene-tree outliner panel.
///
/// Renders the controller's display tree (the composed document, so a prefab
/// instance's internal nodes appear as ordinary, expandable rows). Supports:
/// - click to select, Cmd/Ctrl+click to toggle, Shift+click to range-select;
/// - drag a plain row onto another to reparent, or onto an insertion line to
///   reorder/unparent. Prefab-internal rows are not drag-reorderable (their
///   structure is owned by the prefab); they are marked and editable in place.
///
/// TODO(virtualize-outliner): replace with a two_dimensional_scrollables
/// TreeView backed by a stable-id node model for scenes with 1000+ nodes.
class OutlinerPanel extends StatelessWidget {
  const OutlinerPanel({super.key, required this.controller});

  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final roots = controller.displayRoots();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: roots.isEmpty
                  ? const Center(
                      child: Text(
                        'Empty scene',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    )
                  : SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: buildContainer(
                          controller,
                          parentId: null,
                          childIds: roots,
                          depth: 0,
                          draggable: true,
                        ),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

/// Builds the rows of one container. When [draggable], rows carry drag handles
/// and insertion lines (plain scene content); prefab-internal containers pass
/// [draggable] false (their order is fixed by the prefab).
List<Widget> buildContainer(
  EditorController controller, {
  required LocalId? parentId,
  required List<LocalId> childIds,
  required int depth,
  required bool draggable,
}) {
  final rows = <Widget>[];
  for (final id in childIds) {
    final node = controller.displayNode(id);
    if (node == null) continue;
    if (draggable) {
      rows.add(
        _InsertionLine(
          controller: controller,
          container: parentId,
          beforeId: id,
          depth: depth,
        ),
      );
    }
    rows.add(
      _OutlinerNode(
        key: ValueKey(id.toToken()),
        node: node,
        controller: controller,
        depth: depth,
        draggable: draggable,
      ),
    );
  }
  if (draggable) {
    rows.add(
      _InsertionLine(
        controller: controller,
        container: parentId,
        beforeId: null,
        depth: depth,
      ),
    );
  }
  return rows;
}

/// The flattened, depth-first order of the display tree, for Shift+click range
/// selection.
List<LocalId> _flatten(EditorController c) {
  final out = <LocalId>[];
  void visit(LocalId id) {
    out.add(id);
    for (final child in c.displayChildren(id)) {
      visit(child);
    }
  }

  for (final root in c.displayRoots()) {
    visit(root);
  }
  return out;
}

/// Applies the platform selection gesture for a tap on [id].
void _handleTap(EditorController c, LocalId id) {
  final keys = HardwareKeyboard.instance;
  if (keys.isMetaPressed || keys.isControlPressed) {
    c.selection.toggle(id);
    return;
  }
  final primary = c.selection.primary;
  if (keys.isShiftPressed && primary != null && primary != id) {
    final flat = _flatten(c);
    final a = flat.indexOf(primary);
    final b = flat.indexOf(id);
    if (a >= 0 && b >= 0) {
      final range = flat.sublist(math.min(a, b), math.max(a, b) + 1);
      c.selection.set([
        for (final e in range)
          if (e != primary) e,
        primary,
      ]);
      return;
    }
  }
  c.selection.selectOnly(id);
}

/// A thin drop target between rows. Dropping a dragged node here moves it into
/// [container] (the root list when null) just before [beforeId] (or at the end
/// when [beforeId] is null), covering reordering and unparenting.
class _InsertionLine extends StatefulWidget {
  const _InsertionLine({
    required this.controller,
    required this.container,
    required this.beforeId,
    required this.depth,
  });

  final EditorController controller;
  final LocalId? container;
  final LocalId? beforeId;
  final int depth;

  @override
  State<_InsertionLine> createState() => _InsertionLineState();
}

class _InsertionLineState extends State<_InsertionLine> {
  bool _hovering = false;

  bool _accepts(LocalId dragged) {
    final container = widget.container;
    if (container != null &&
        widget.controller.query.subtreeOf(dragged).contains(container)) {
      return false;
    }
    return true;
  }

  void _drop(LocalId dragged) {
    final c = widget.controller;
    final ids = widget.container == null
        ? c.displayRoots()
        : c.displayChildren(widget.container!);
    final without = [
      for (final id in ids)
        if (id != dragged) id,
    ];
    final before = widget.beforeId;
    final at = (before == null || !without.contains(before))
        ? without.length
        : without.indexOf(before);
    c.reparentToContainer(dragged, widget.container, at);
  }

  @override
  Widget build(BuildContext context) {
    return DragTarget<LocalId>(
      onWillAcceptWithDetails: (details) => _accepts(details.data),
      onMove: (_) {
        if (!_hovering) setState(() => _hovering = true);
      },
      onLeave: (_) => setState(() => _hovering = false),
      onAcceptWithDetails: (details) {
        setState(() => _hovering = false);
        _drop(details.data);
      },
      builder: (context, candidate, rejected) {
        return Container(
          height: 6,
          padding: EdgeInsets.only(left: 4.0 + widget.depth * 16.0, right: 4),
          alignment: Alignment.center,
          child: Container(
            height: _hovering ? 2 : 0,
            color: _hovering
                ? Theme.of(context).colorScheme.primary
                : Colors.transparent,
          ),
        );
      },
    );
  }
}

/// One row in the outliner, possibly expanded to show children.
class _OutlinerNode extends StatefulWidget {
  const _OutlinerNode({
    super.key,
    required this.node,
    required this.controller,
    required this.depth,
    required this.draggable,
  });

  final NodeSpec node;
  final EditorController controller;
  final int depth;
  final bool draggable;

  @override
  State<_OutlinerNode> createState() => _OutlinerNodeState();
}

class _OutlinerNodeState extends State<_OutlinerNode> {
  bool _expanded = true;
  bool _dragTarget = false;

  @override
  Widget build(BuildContext context) {
    final node = widget.node;
    final ctrl = widget.controller;
    final isSelected = ctrl.selection.contains(node.id);
    final childIds = ctrl.displayChildren(node.id);
    final hasChildren = childIds.isNotEmpty;
    final isMember = ctrl.isPrefabMember(node.id);
    // The source document still carries the instance marker (the composed node
    // does not), so detect a prefab instance node there.
    final isInstance = ctrl.document.nodes[node.id]?.instance != null;
    // Children of a plain node are draggable; once inside a prefab they are not.
    final childrenDraggable = widget.draggable && !isInstance && !isMember;

    final accent = Theme.of(context).colorScheme.primary;
    final prefabTint = Theme.of(context).colorScheme.tertiary;
    final rowColor = _dragTarget
        ? accent.withValues(alpha: 0.2)
        : isSelected
        ? accent.withValues(alpha: 0.15)
        : null;

    Widget rowContent = Container(
      color: rowColor,
      padding: EdgeInsets.only(
        left: 4.0 + widget.depth * 16.0,
        right: 4,
        top: 2,
        bottom: 2,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 16,
            child: hasChildren
                ? GestureDetector(
                    onTap: () => setState(() => _expanded = !_expanded),
                    child: Icon(
                      _expanded ? Icons.arrow_drop_down : Icons.arrow_right,
                      size: 16,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 2),
          Icon(
            isInstance
                ? Icons.link
                : isMember
                ? Icons.subdirectory_arrow_right
                : hasChildren
                ? Icons.account_tree_outlined
                : Icons.circle_outlined,
            size: 12,
            color: isSelected
                ? accent
                : isMember
                ? prefabTint
                : Theme.of(context).colorScheme.onSurface,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              node.name.isEmpty ? '(${node.id.toToken()})' : node.name,
              style: TextStyle(
                fontSize: 12,
                fontStyle: isMember ? FontStyle.italic : FontStyle.normal,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected
                    ? accent
                    : isMember
                    ? prefabTint
                    : null,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Visibility toggle (prefab content records a visibility override).
          SizedBox(
            width: 20,
            height: 20,
            child: IconButton(
              padding: EdgeInsets.zero,
              iconSize: 14,
              icon: Icon(
                node.visible
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
              onPressed: () =>
                  ctrl.setNodeVisibleRouted(node.id, !node.visible),
            ),
          ),
        ],
      ),
    );

    rowContent = InkWell(
      onTap: () => _handleTap(ctrl, node.id),
      child: rowContent,
    );

    // Every row accepts a drop: onto a prefab-internal node it attaches the
    // dragged node there, onto any other node it reparents into it. A row can
    // be picked up when it is a real scene node (members are owned by the
    // prefab and are not dragged).
    final row = DragTarget<LocalId>(
      onWillAcceptWithDetails: (details) {
        final dragged = details.data;
        if (dragged == node.id) return false;
        // No cycles when reparenting into a source node; attaching under a
        // prefab member never forms a source cycle.
        if (!isMember && ctrl.query.subtreeOf(dragged).contains(node.id)) {
          return false;
        }
        return true;
      },
      onAcceptWithDetails: (details) {
        setState(() => _dragTarget = false);
        ctrl.dropOnNode(details.data, node.id);
      },
      onLeave: (_) => setState(() => _dragTarget = false),
      onMove: (_) => setState(() => _dragTarget = true),
      builder: (context, candidate, rejected) {
        if (isMember) return rowContent;
        return Draggable<LocalId>(
          data: node.id,
          feedback: Material(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                node.name.isEmpty ? node.id.toToken() : node.name,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
          child: rowContent,
        );
      },
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row,
        if (_expanded && hasChildren)
          ...buildContainer(
            ctrl,
            parentId: node.id,
            childIds: childIds,
            depth: widget.depth + 1,
            draggable: childrenDraggable,
          ),
      ],
    );
  }
}
