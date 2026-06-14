import 'dart:math' as math;

// ignore: implementation_imports
import 'package:flutter_scene/src/fscene/id.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/fscene/specs.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controller/editor_controller.dart';

/// Scene-tree outliner panel.
///
/// Renders the hierarchy from [EditorController.query] and supports:
/// - click to select, Cmd/Ctrl+click to toggle, Shift+click to range-select
///   over the flattened tree order;
/// - drag a row onto another row to reparent into it;
/// - drag a row onto an insertion line between rows to reorder, or onto a
///   root-level line to unparent.
///
/// The tree is a custom recursive widget. The two_dimensional_scrollables
/// TreeView API requires a TreeController with a fixed node model that
/// conflicts with the live-document update pattern here (the document changes
/// identity on every realization); a custom widget is the correct call and
/// avoids fiddly adapter glue.
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
        final roots = controller.query.roots;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PanelHeader(
              label: 'Outliner',
              trailing: IconButton(
                icon: const Icon(Icons.add, size: 16),
                tooltip: 'Create node',
                onPressed: () => controller.run('createNode', {'name': 'Node'}),
              ),
            ),
            Expanded(
              child: roots.isEmpty
                  // An empty scene still accepts a drop (no-op, but consistent).
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
                          children: roots,
                          depth: 0,
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

/// Builds the rows of one container (the root list when [parentId] is null, or
/// a node's children otherwise): an insertion line before each child, the child
/// row, and a trailing insertion line at the end.
List<Widget> buildContainer(
  EditorController controller, {
  required LocalId? parentId,
  required List<NodeSpec> children,
  required int depth,
}) {
  return [
    for (final child in children) ...[
      _InsertionLine(
        controller: controller,
        container: parentId,
        beforeId: child.id,
        depth: depth,
      ),
      _OutlinerNode(
        key: ValueKey(child.id.toToken()),
        node: child,
        controller: controller,
        parentId: parentId,
        depth: depth,
      ),
    ],
    _InsertionLine(
      controller: controller,
      container: parentId,
      beforeId: null,
      depth: depth,
    ),
  ];
}

/// The flattened, depth-first order of every node id (ignoring collapse state),
/// used for Shift+click range selection.
List<LocalId> _flatten(EditorController c) {
  final out = <LocalId>[];
  void visit(LocalId id) {
    out.add(id);
    for (final child in c.query.childrenOf(id)) {
      visit(child.id);
    }
  }

  for (final root in c.query.roots) {
    visit(root.id);
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
      // Keep the anchor as the primary so a further Shift+click extends from it.
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
/// when [beforeId] is null), which covers reordering and unparenting.
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
    // Cannot move a node into its own subtree.
    if (container != null &&
        widget.controller.query.subtreeOf(dragged).contains(container)) {
      return false;
    }
    return true;
  }

  void _drop(LocalId dragged) {
    final c = widget.controller;
    final containerIds = widget.container == null
        ? [for (final n in c.query.roots) n.id]
        : [for (final n in c.query.childrenOf(widget.container!)) n.id];
    // The command removes the node from its container before inserting, so the
    // target index is computed against the list without the dragged node.
    final without = [
      for (final id in containerIds)
        if (id != dragged) id,
    ];
    final before = widget.beforeId;
    final at = (before == null || !without.contains(before))
        ? without.length
        : without.indexOf(before);
    c.run('reparentNode', {
      'nodeId': dragged.toToken(),
      if (widget.container != null) 'newParentId': widget.container!.toToken(),
      'index': at,
    });
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
    required this.parentId,
    required this.depth,
  });

  final NodeSpec node;
  final EditorController controller;
  final LocalId? parentId;
  final int depth;

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
    final children = ctrl.query.childrenOf(node.id);
    final hasChildren = children.isNotEmpty;

    final row = DragTarget<LocalId>(
      onWillAcceptWithDetails: (details) {
        final dragged = details.data;
        if (dragged == node.id) return false;
        // Prevent dragging a node onto one of its own descendants.
        final subtree = ctrl.query.subtreeOf(dragged);
        return !subtree.contains(node.id);
      },
      onAcceptWithDetails: (details) {
        setState(() => _dragTarget = false);
        // Drop onto a row reparents into that node (appended to its children).
        ctrl.run('reparentNode', {
          'nodeId': details.data.toToken(),
          'newParentId': node.id.toToken(),
        });
      },
      onLeave: (_) => setState(() => _dragTarget = false),
      onMove: (_) => setState(() => _dragTarget = true),
      builder: (context, candidateData, rejectedData) {
        // TODO(drag-multiselect): when the dragged node is part of a
        // multi-selection, move every top-level selected node together rather
        // than just this one.
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
          child: InkWell(
            onTap: () => _handleTap(ctrl, node.id),
            child: Container(
              color: _dragTarget
                  ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.2)
                  : isSelected
                  ? Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.15)
                  : null,
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
                              _expanded
                                  ? Icons.arrow_drop_down
                                  : Icons.arrow_right,
                              size: 16,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    node.instance != null
                        ? Icons.link
                        : hasChildren
                        ? Icons.account_tree_outlined
                        : Icons.circle_outlined,
                    size: 12,
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurface,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      node.name.isEmpty ? '(${node.id.toToken()})' : node.name,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.normal,
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // Visibility toggle.
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
                      onPressed: () => ctrl.run('setNodeVisible', {
                        'nodeId': node.id.toToken(),
                        'visible': !node.visible,
                      }),
                    ),
                  ),
                ],
              ),
            ),
          ),
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
            children: children,
            depth: widget.depth + 1,
          ),
      ],
    );
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({required this.label, this.trailing});
  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
