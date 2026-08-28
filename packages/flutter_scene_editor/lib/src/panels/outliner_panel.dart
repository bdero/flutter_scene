import 'dart:math' as math;

// ignore: implementation_imports
import 'package:scene/scene.dart';
// ignore: implementation_imports
import 'package:flutter/material.dart';
// Not re-exported through material.dart on 3.47 stable.
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';

import '../shell/editor_theme.dart';
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
class OutlinerPanel extends StatefulWidget {
  const OutlinerPanel({super.key, required this.controller});

  final EditorController controller;

  @override
  State<OutlinerPanel> createState() => _OutlinerPanelState();
}

class _OutlinerPanelState extends State<OutlinerPanel> {
  final Set<LocalId> _collapsed = {};

  EditorController get controller => widget.controller;

  @override
  void didUpdateWidget(OutlinerPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) _collapsed.clear();
  }

  void _setExpanded(LocalId id, bool expanded) {
    setState(() {
      if (expanded) {
        _collapsed.remove(id);
      } else {
        _collapsed.add(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final roots = controller.displayRoots();
        final entries = _visibleEntries(
          controller,
          roots: roots,
          collapsed: _collapsed,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: roots.isEmpty
                  ? const Center(
                      child: Text(
                        'Empty scene',
                        style: TextStyle(
                          fontSize: 12,
                          color: editorMutedTextColor,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: entries.length,
                      scrollCacheExtent: const ScrollCacheExtent.pixels(400),
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        return switch (entry) {
                          _VisibleInsertion(
                            :final container,
                            :final beforeId,
                            :final depth,
                          ) =>
                            _InsertionLine(
                              key: ValueKey(
                                'insert:${container?.toToken() ?? 'root'}:'
                                '${beforeId?.toToken() ?? 'end'}',
                              ),
                              controller: controller,
                              container: container,
                              beforeId: beforeId,
                              depth: depth,
                            ),
                          _VisibleNode(
                            :final node,
                            :final depth,
                            :final draggable,
                            :final expanded,
                          ) =>
                            _OutlinerNode(
                              key: ValueKey(node.id.toToken()),
                              node: node,
                              controller: controller,
                              depth: depth,
                              draggable: draggable,
                              expanded: expanded,
                              onExpandedChanged: (value) =>
                                  _setExpanded(node.id, value),
                            ),
                        };
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

sealed class _VisibleEntry {
  const _VisibleEntry();
}

class _VisibleNode extends _VisibleEntry {
  const _VisibleNode({
    required this.node,
    required this.depth,
    required this.draggable,
    required this.expanded,
  });

  final NodeSpec node;
  final int depth;
  final bool draggable;
  final bool expanded;
}

class _VisibleInsertion extends _VisibleEntry {
  const _VisibleInsertion({
    required this.container,
    required this.beforeId,
    required this.depth,
  });

  final LocalId? container;
  final LocalId? beforeId;
  final int depth;
}

List<_VisibleEntry> _visibleEntries(
  EditorController controller, {
  required List<LocalId> roots,
  required Set<LocalId> collapsed,
}) {
  final entries = <_VisibleEntry>[];

  void addContainer(
    LocalId? parentId,
    List<LocalId> childIds,
    int depth,
    bool draggable,
  ) {
    for (final id in childIds) {
      final node = controller.displayNode(id);
      if (node == null) continue;
      if (draggable) {
        entries.add(
          _VisibleInsertion(container: parentId, beforeId: id, depth: depth),
        );
      }
      final children = controller.displayChildren(id);
      final expanded = !collapsed.contains(id);
      entries.add(
        _VisibleNode(
          node: node,
          depth: depth,
          draggable: draggable,
          expanded: expanded,
        ),
      );
      if (expanded && children.isNotEmpty) {
        final isMember = controller.isPrefabMember(id);
        final isInstance = controller.document.nodes[id]?.instance != null;
        addContainer(
          id,
          children,
          depth + 1,
          draggable && !isInstance && !isMember,
        );
      }
    }
    if (draggable) {
      entries.add(
        _VisibleInsertion(container: parentId, beforeId: null, depth: depth),
      );
    }
  }

  addContainer(null, roots, 0, true);
  return entries;
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
    super.key,
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
    required this.expanded,
    required this.onExpandedChanged,
  });

  final NodeSpec node;
  final EditorController controller;
  final int depth;
  final bool draggable;
  final bool expanded;
  final ValueChanged<bool> onExpandedChanged;

  @override
  State<_OutlinerNode> createState() => _OutlinerNodeState();
}

class _OutlinerNodeState extends State<_OutlinerNode> {
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
                    onTap: () => widget.onExpandedChanged(!widget.expanded),
                    child: Icon(
                      widget.expanded
                          ? Icons.arrow_drop_down
                          : Icons.arrow_right,
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
        if (!widget.draggable || isMember) return rowContent;
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

    return row;
  }
}
