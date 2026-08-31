import 'dart:math' as math;

// ignore: implementation_imports
import 'package:scene/scene.dart';
// ignore: implementation_imports
import 'package:forui/forui.dart';
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

/// Fixed row heights, so the list lays out only what is visible and scroll
/// offsets are exact. Variable extents made a scroll jump through a large
/// scene lay out thousands of rows in one frame (seconds in the Bistro).
const double _kRowExtent = 24;
const double _kInsertionExtent = 6;

class _OutlinerPanelState extends State<OutlinerPanel> {
  final Set<LocalId> _collapsed = {};
  final ScrollController _scroll = ScrollController();

  EditorController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    controller.outlinerReveal.addListener(_onRevealRequest);
  }

  @override
  void dispose() {
    controller.outlinerReveal.removeListener(_onRevealRequest);
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  // Expands ancestors of the requested node and scrolls its row into view
  // (centered), after the post-reveal frame has rebuilt the list.
  void _onRevealRequest() {
    final id = controller.outlinerReveal.value;
    if (id == null) return;
    var ancestor = controller.query.parentOf(id);
    var expandedAny = false;
    while (ancestor != null) {
      expandedAny |= _collapsed.remove(ancestor);
      ancestor = controller.query.parentOf(ancestor);
    }
    if (expandedAny) setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final entries = _visibleEntries(
        controller,
        roots: controller.displayRoots(),
        collapsed: _collapsed,
      );
      var offset = 0.0;
      var found = false;
      for (final entry in entries) {
        if (entry is _VisibleNode && entry.node.id == id) {
          found = true;
          break;
        }
        offset += entry is _VisibleInsertion ? _kInsertionExtent : _kRowExtent;
      }
      if (!found) return;
      final viewport = _scroll.position.viewportDimension;
      final target = (offset - (viewport - _kRowExtent) / 2).clamp(
        0.0,
        _scroll.position.maxScrollExtent,
      );
      _scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void didUpdateWidget(OutlinerPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) _collapsed.clear();
  }

  final TextEditingController _search = TextEditingController();
  String _query = '';

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
        final filtering = _query.trim().isNotEmpty;
        final filter = filtering
            ? outlinerFilterMatches(
                roots: roots,
                childrenOf: controller.displayChildren,
                nameOf: (id) => controller.displayNode(id)?.name ?? '',
                query: _query,
              )
            : null;
        final entries = _visibleEntries(
          controller,
          roots: roots,
          collapsed: _collapsed,
          filter: filter,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (roots.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
                child: FTextField(
                  control: FTextFieldControl.managed(
                    controller: _search,
                    onChange: (value) => setState(() => _query = value.text),
                  ),
                  hint: 'Filter by name',
                  prefixBuilder: (context, styles, child) => const Padding(
                    padding: EdgeInsets.only(left: 8, right: 4),
                    child: Icon(
                      Icons.search,
                      size: 14,
                      color: editorMutedTextColor,
                    ),
                  ),
                ),
              ),
            Expanded(
              child: roots.isEmpty
                  ? const Center(
                      child: Text('Empty scene', style: editorDetailText),
                    )
                  : filtering && entries.isEmpty
                  ? Center(
                      child: Text(
                        'No node matches "${_query.trim()}"',
                        style: editorDetailText,
                      ),
                    )
                  : ListView.builder(
                      controller: _scroll,
                      itemCount: entries.length,
                      itemExtentBuilder: (index, dimensions) =>
                          entries[index] is _VisibleInsertion
                          ? _kInsertionExtent
                          : _kRowExtent,
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

/// The nodes an outliner filter keeps: every node whose name matches [query],
/// plus their ancestors and their descendants.
///
/// Ancestors are kept so a match is shown where it actually lives rather than
/// as a flat list — the tree is most of what the outliner is for, and a hit
/// three levels down means nothing without the branch above it. Descendants
/// are kept because filtering to a container is how you look *inside* one;
/// showing "lights" with nothing under it answers the wrong question.
///
/// An empty or blank query keeps everything, so the caller does not have to
/// special-case "not filtering".
Set<LocalId> outlinerFilterMatches({
  required List<LocalId> roots,
  required List<LocalId> Function(LocalId id) childrenOf,
  required String Function(LocalId id) nameOf,
  required String query,
}) {
  final needle = query.trim().toLowerCase();
  final keep = <LocalId>{};
  if (needle.isEmpty) {
    void keepAll(LocalId id) {
      keep.add(id);
      for (final child in childrenOf(id)) {
        keepAll(child);
      }
    }

    for (final root in roots) {
      keepAll(root);
    }
    return keep;
  }

  void keepSubtree(LocalId id) {
    keep.add(id);
    for (final child in childrenOf(id)) {
      keepSubtree(child);
    }
  }

  // Returns whether anything at or below [id] matched, so a parent learns it
  // has to stay from the same walk that tested its children.
  bool visit(LocalId id, List<LocalId> ancestors) {
    final matched = nameOf(id).toLowerCase().contains(needle);
    var descendantMatched = false;
    final path = [...ancestors, id];
    for (final child in childrenOf(id)) {
      if (visit(child, path)) descendantMatched = true;
    }
    if (!matched && !descendantMatched) return false;
    if (matched) {
      keepSubtree(id);
    } else {
      keep.add(id);
    }
    keep.addAll(ancestors);
    return true;
  }

  for (final root in roots) {
    visit(root, const []);
  }
  return keep;
}

List<_VisibleEntry> _visibleEntries(
  EditorController controller, {
  required List<LocalId> roots,
  required Set<LocalId> collapsed,
  Set<LocalId>? filter,
}) {
  final entries = <_VisibleEntry>[];
  // While filtering, the tree is a result list: reordering it would drop a
  // node against a view that hides its siblings, and collapsing it would hide
  // the very match being looked for.
  final filtering = filter != null;

  void addContainer(
    LocalId? parentId,
    List<LocalId> childIds,
    int depth,
    bool draggable,
  ) {
    for (final id in childIds) {
      if (filtering && !filter.contains(id)) continue;
      final node = controller.displayNode(id);
      if (node == null) continue;
      if (draggable && !filtering) {
        entries.add(
          _VisibleInsertion(container: parentId, beforeId: id, depth: depth),
        );
      }
      final children = controller.displayChildren(id);
      final expanded = filtering || !collapsed.contains(id);
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
    if (draggable && !filtering) {
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

/// The nodes a drag carries, the whole top-level selection when the dragged
/// row is part of it, otherwise just the dragged row. Ordered as the
/// outliner shows them.
List<LocalId> _dragGroup(EditorController c, LocalId dragged) {
  if (!c.selection.contains(dragged) || c.selection.ids.length < 2) {
    return [dragged];
  }
  final tops = c.topLevelSelection().toSet();
  final ordered = [
    for (final id in _flatten(c))
      if (tops.contains(id)) id,
  ];
  return ordered.isEmpty ? [dragged] : ordered;
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
    final group = _dragGroup(c, dragged);
    final groupSet = group.toSet();
    final ids = widget.container == null
        ? c.displayRoots()
        : c.displayChildren(widget.container!);
    final without = [
      for (final id in ids)
        if (!groupSet.contains(id)) id,
    ];
    final before = widget.beforeId;
    final at = (before == null || !without.contains(before))
        ? without.length
        : without.indexOf(before);
    c.reparentGroupToContainer(group, widget.container, at);
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
          height: _kInsertionExtent,
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
  bool _hovered = false;

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
    // Drag target, then selection, then hover: the strongest signal wins,
    // and a hovered row that is already selected should not change under the
    // pointer.
    final rowColor = _dragTarget
        ? accent.withValues(alpha: 0.2)
        : isSelected
        ? accent.withValues(alpha: 0.15)
        : _hovered
        ? accent.withValues(alpha: 0.06)
        : null;

    Widget rowContent = Container(
      color: rowColor,
      height: _kRowExtent,
      padding: EdgeInsets.only(left: 4.0 + widget.depth * 16.0, right: 4),
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
      // Double-click frames the node, for when the view has wandered far
      // enough that finding it by hand is the harder job. It selects first,
      // so the result matches what the F key would do from here.
      onDoubleTap: () {
        ctrl.selection.selectOnly(node.id);
        ctrl.nodeFramer?.call(node.id);
      },
      // The row paints its own background, which sits over the ink overlay,
      // so hover has to be tracked rather than left to the splash.
      onHover: (hovered) {
        if (_hovered == hovered) return;
        setState(() => _hovered = hovered);
      },
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
        final group = _dragGroup(ctrl, details.data);
        if (group.length == 1 || ctrl.isPrefabMember(node.id)) {
          // Prefab targets graft one node at a time through the attach path.
          for (final id in group) {
            ctrl.dropOnNode(id, node.id);
          }
        } else {
          ctrl.reparentGroupToContainer(group, node.id, null);
        }
      },
      onLeave: (_) => setState(() => _dragTarget = false),
      onMove: (_) => setState(() => _dragTarget = true),
      builder: (context, candidate, rejected) {
        if (!widget.draggable || isMember) return rowContent;
        return Draggable<LocalId>(
          data: node.id,
          // Built when the drag starts, so a multi-selection drag labels
          // itself with the group size without per-row cost per rebuild.
          feedback: Builder(
            builder: (context) {
              final count = _dragGroup(ctrl, node.id).length;
              return Material(
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Text(
                    count > 1
                        ? '$count nodes'
                        : node.name.isEmpty
                        ? node.id.toToken()
                        : node.name,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              );
            },
          ),
          child: rowContent,
        );
      },
    );

    return row;
  }
}
