// Floating panel windows use the framework's experimental windowing API,
// which is not yet exported from the public barrels (see the framework's own
// examples/api/lib/widgets/windows/, which import it the same way).
// TODO(docking): drop these ignores when the windowing API is stable.
// ignore_for_file: invalid_use_of_internal_member
// ignore_for_file: implementation_imports
import 'package:flutter/material.dart';
import 'package:flutter/src/foundation/_features.dart' show isWindowingEnabled;
import 'package:flutter/src/widgets/_window.dart';

import 'dock_layout.dart';

/// A panel hosted by the [DockingShell].
class DockPanel {
  const DockPanel({
    required this.id,
    required this.title,
    required this.child,
    this.actions,
    this.closable = false,
  });

  /// Stable identifier the layout tree references.
  final String id;

  /// Label shown on the panel's tab.
  final String title;

  final Widget child;

  /// Shown at the right end of the tab strip while this panel is active.
  final Widget? actions;

  /// A runtime-created panel (an extra viewport). Its tab menu offers Close
  /// (removing it outright) instead of Hide, since hidden panels are only
  /// reachable again through the View menu, which lists the fixed set.
  final bool closable;
}

/// Dockable editor shell.
///
/// Renders [layout] (splits with draggable dividers; leaves are tab groups).
/// Panels rearrange by dragging a tab onto another group, the center zone
/// adds it as a tab and the edge zones split the group. Layout changes are
/// reported through [onLayoutChanged] so hosts can persist them.
///
/// The split dividers stay hand-rolled (the `docking` and `multi_split_view`
/// packages did not give reliably draggable dividers in this nesting).
///
/// When the `windowing` feature flag is enabled, a tab's context menu offers
/// "Move to New Window", which floats the panel into its own OS window
/// (rendered as a [RegularWindow] sibling view via [ViewAnchor]). Closing the
/// window re-docks the panel. Without the flag the menu item is absent and
/// floating panels persisted in the layout are re-docked.
class DockingShell extends StatefulWidget {
  const DockingShell({
    super.key,
    required this.panels,
    required this.layout,
    this.onLayoutChanged,
  });

  final List<DockPanel> panels;

  /// The starting arrangement. Captured once when the shell is first built;
  /// later mutations flow out through [onLayoutChanged].
  final DockLayout layout;

  final ValueChanged<DockLayout>? onLayoutChanged;

  @override
  State<DockingShell> createState() => _DockingShellState();
}

class _DockingShellState extends State<DockingShell> {
  late final DockLayout _layout = widget.layout;

  // One key per panel so its subtree state (viewport camera, scroll
  // positions) survives docking moves, tab switches, and float/dock moves.
  final Map<String, GlobalKey> _panelKeys = {};

  // One native window per floating panel, keyed by panel id and kept in sync
  // with the layout's floating list.
  final Map<String, RegularWindowController> _floatControllers = {};

  @override
  void initState() {
    super.initState();
    // A layout persisted with floats can be restored on a build without the
    // windowing flag; re-dock those panels instead of losing them.
    if (!isWindowingEnabled && _layout.floating.isNotEmpty) {
      for (final id in List.of(_layout.floating)) {
        _layout.showPanel(id);
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _floatControllers.values) {
      controller.destroy();
    }
    _floatControllers.clear();
    super.dispose();
  }

  DockPanel? _panelById(String id) {
    for (final panel in widget.panels) {
      if (panel.id == id) return panel;
    }
    return null;
  }

  void _mutate(VoidCallback edit, {bool persist = true}) {
    setState(edit);
    if (persist) widget.onLayoutChanged?.call(_layout);
  }

  void _redock(String id) => _mutate(() => _layout.showPanel(id));

  /// Creates windows for newly floating panels and tears down windows whose
  /// panels re-docked. Stale windows are destroyed a frame later so their
  /// [RegularWindow] view unmounts first.
  void _syncFloatWindows() {
    if (!isWindowingEnabled) return;
    for (final id in _layout.floating) {
      _floatControllers.putIfAbsent(
        id,
        () => RegularWindowController(
          size: const Size(480, 640),
          title: _panelById(id)?.title ?? id,
          delegate: _FloatWindowDelegate(() => _redock(id)),
        ),
      );
    }
    final stale = _floatControllers.keys
        .where((id) => !_layout.floating.contains(id))
        .toList();
    for (final id in stale) {
      final controller = _floatControllers.remove(id)!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        controller.destroy();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    _syncFloatWindows();
    final tree = _buildNode(_layout.root);
    if (_floatControllers.isEmpty) return tree;
    final theme = Theme.of(context);
    return ViewAnchor(
      view: ViewCollection(
        views: [
          for (final id in _layout.floating)
            if (_floatControllers[id] != null)
              RegularWindow(
                controller: _floatControllers[id]!,
                child: _FloatWindowScaffold(
                  theme: theme,
                  child: _panelContent(id),
                ),
              ),
        ],
      ),
      child: tree,
    );
  }

  Widget _panelContent(String id) {
    return _PanelContainer(
      child: KeyedSubtree(
        key: _panelKeys.putIfAbsent(id, GlobalKey.new),
        child: _panelById(id)?.child ?? const SizedBox(),
      ),
    );
  }

  Widget _buildNode(DockNode node) {
    switch (node) {
      case DockTabs():
        return _TabGroup(
          group: node,
          panelById: _panelById,
          contentKeyFor: (id) => _panelKeys.putIfAbsent(id, GlobalKey.new),
          onSelect: (index) => _mutate(() => node.active = index),
          onDock: (id, zone) => _mutate(() => _layout.dock(id, node, zone)),
          // Closable (runtime-created) panels are removed outright; hiding
          // them would strand them, since only fixed panels appear in the
          // host's View menu.
          onHide: (id) => _mutate(() {
            if (_panelById(id)?.closable ?? false) {
              _layout.removePanel(id);
            } else {
              _layout.hidePanel(id);
            }
          }),
          onFloat: isWindowingEnabled
              ? (id) => _mutate(() => _layout.floatPanel(id))
              : null,
        );
      case DockSplit():
        return _WeightedSplit(
          split: node,
          children: [for (final child in node.children) _buildNode(child)],
          onWeightsEdited: () => _mutate(() {}, persist: false),
          onWeightsCommitted: () => _mutate(() {}),
        );
    }
  }
}

/// Re-docks the panel instead of destroying the window outright when the user
/// clicks the native close button; the shell then tears the window down.
class _FloatWindowDelegate with RegularWindowControllerDelegate {
  _FloatWindowDelegate(this.onCloseRequested);

  final VoidCallback onCloseRequested;

  @override
  void onWindowCloseRequested(RegularWindowController controller) {
    onCloseRequested();
  }
}

/// Root widget of a floating panel window. Each window is its own view tree,
/// so material app scaffolding (theme, localizations, overlay for tooltips
/// and menus) is re-established here.
///
/// TODO(docking): the editor's keyboard shortcuts are only bound in the main
/// window's shell; route them here too so panels stay fully usable while
/// floating.
class _FloatWindowScaffold extends StatelessWidget {
  const _FloatWindowScaffold({required this.theme, required this.child});

  final ThemeData theme;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: Scaffold(body: child),
    );
  }
}

/// A dragged dock tab. Typed so the shell's drop targets ignore the other
/// drags that fly around the editor (outliner rows, asset tiles).
class _DockDrag {
  const _DockDrag(this.panelId);
  final String panelId;
}

class _TabGroup extends StatefulWidget {
  const _TabGroup({
    required this.group,
    required this.panelById,
    required this.contentKeyFor,
    required this.onSelect,
    required this.onDock,
    required this.onHide,
    this.onFloat,
  });

  final DockTabs group;
  final DockPanel? Function(String id) panelById;
  final GlobalKey Function(String id) contentKeyFor;
  final ValueChanged<int> onSelect;
  final void Function(String panelId, DockZone zone) onDock;
  final ValueChanged<String> onHide;

  /// Floats the panel into its own OS window; null when windowing is
  /// unavailable (the menu item is omitted).
  final ValueChanged<String>? onFloat;

  @override
  State<_TabGroup> createState() => _TabGroupState();
}

class _TabGroupState extends State<_TabGroup> {
  DockZone? _hoverZone;

  DockZone _zoneAt(Offset local, Size size) {
    final dx = local.dx / size.width;
    final dy = local.dy / size.height;
    if (dx > 0.25 && dx < 0.75 && dy > 0.25 && dy < 0.75) {
      return DockZone.center;
    }
    // Outside the center box, pick the nearest edge.
    final toEdge = <DockZone, double>{
      DockZone.left: dx,
      DockZone.right: 1 - dx,
      DockZone.top: dy,
      DockZone.bottom: 1 - dy,
    };
    return toEdge.entries.reduce((a, b) => a.value <= b.value ? a : b).key;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final group = widget.group;
    final active = group.activePanel;
    final activePanel = active == null ? null : widget.panelById(active);

    final strip = Container(
      height: 30,
      color: scheme.surfaceContainerLow,
      child: Row(
        children: [
          for (final id in group.panels)
            _DockTab(
              panel: widget.panelById(id),
              id: id,
              selected: id == active,
              closable: widget.panelById(id)?.closable ?? false,
              onTap: () => widget.onSelect(group.panels.indexOf(id)),
              onHide: () => widget.onHide(id),
              onFloat: widget.onFloat == null
                  ? null
                  : () => widget.onFloat!(id),
            ),
          const Spacer(),
          if (activePanel?.actions != null) activePanel!.actions!,
        ],
      ),
    );

    final content = Expanded(
      child: Stack(
        fit: StackFit.expand,
        children: [
          for (final id in group.panels)
            Offstage(
              offstage: id != active,
              child: _PanelContainer(
                child: KeyedSubtree(
                  key: widget.contentKeyFor(id),
                  child: widget.panelById(id)?.child ?? const SizedBox(),
                ),
              ),
            ),
        ],
      ),
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        Column(children: [strip, content]),
        Positioned.fill(
          child: DragTarget<_DockDrag>(
            builder: (context, candidates, _) {
              if (candidates.isEmpty || _hoverZone == null) {
                return const IgnorePointer(child: SizedBox.expand());
              }
              return IgnorePointer(
                child: Align(
                  alignment: switch (_hoverZone!) {
                    DockZone.center => Alignment.center,
                    DockZone.left => Alignment.centerLeft,
                    DockZone.right => Alignment.centerRight,
                    DockZone.top => Alignment.topCenter,
                    DockZone.bottom => Alignment.bottomCenter,
                  },
                  child: FractionallySizedBox(
                    widthFactor:
                        _hoverZone == DockZone.left ||
                            _hoverZone == DockZone.right
                        ? 0.5
                        : 1.0,
                    heightFactor:
                        _hoverZone == DockZone.top ||
                            _hoverZone == DockZone.bottom
                        ? 0.5
                        : 1.0,
                    child: Container(
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.12),
                        border: Border.all(color: scheme.primary, width: 2),
                      ),
                    ),
                  ),
                ),
              );
            },
            onMove: (details) {
              final box = context.findRenderObject() as RenderBox?;
              if (box == null) return;
              final zone = _zoneAt(box.globalToLocal(details.offset), box.size);
              if (zone != _hoverZone) setState(() => _hoverZone = zone);
            },
            onLeave: (_) => setState(() => _hoverZone = null),
            onAcceptWithDetails: (details) {
              final zone = _hoverZone ?? DockZone.center;
              setState(() => _hoverZone = null);
              widget.onDock(details.data.panelId, zone);
            },
          ),
        ),
      ],
    );
  }
}

class _DockTab extends StatelessWidget {
  const _DockTab({
    required this.panel,
    required this.id,
    required this.selected,
    required this.closable,
    required this.onTap,
    required this.onHide,
    this.onFloat,
  });

  final DockPanel? panel;
  final String id;
  final bool selected;
  final bool closable;
  final VoidCallback onTap;
  final VoidCallback onHide;
  final VoidCallback? onFloat;

  Future<void> _showContextMenu(BuildContext context, Offset position) async {
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final action = await showMenu<VoidCallback>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        if (onFloat != null)
          PopupMenuItem(
            value: onFloat,
            height: 28,
            child: const Text(
              'Move to New Window',
              style: TextStyle(fontSize: 12),
            ),
          ),
        PopupMenuItem(
          value: onHide,
          height: 28,
          child: Text(
            closable ? 'Close' : 'Hide',
            style: const TextStyle(fontSize: 12),
          ),
        ),
      ],
    );
    action?.call();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = panel?.title ?? id;
    final label = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected ? scheme.surface : null,
        border: Border(
          top: BorderSide(
            color: selected ? scheme.primary : Colors.transparent,
            width: 2,
          ),
        ),
      ),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
        ),
      ),
    );

    return Draggable<_DockDrag>(
      data: _DockDrag(id),
      feedback: Material(
        elevation: 4,
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(title, style: Theme.of(context).textTheme.labelSmall),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.4, child: label),
      child: GestureDetector(
        onSecondaryTapUp: (details) =>
            _showContextMenu(context, details.globalPosition),
        child: InkWell(onTap: onTap, child: label),
      ),
    );
  }
}

/// [split]'s children laid out along its axis with draggable dividers.
/// Dragging divider i transfers weight between children i and i+1.
class _WeightedSplit extends StatelessWidget {
  const _WeightedSplit({
    required this.split,
    required this.children,
    required this.onWeightsEdited,
    required this.onWeightsCommitted,
  });

  static const double _thickness = 8;
  static const double _minWeight = 0.05;

  final DockSplit split;
  final List<Widget> children;
  final VoidCallback onWeightsEdited;
  final VoidCallback onWeightsCommitted;

  @override
  Widget build(BuildContext context) {
    final horizontal = split.axis == Axis.horizontal;
    final scheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final total = horizontal ? constraints.maxWidth : constraints.maxHeight;
        final usable = (total - _thickness * (children.length - 1)).clamp(
          0.0,
          double.infinity,
        );

        void onDrag(int index, double delta) {
          if (usable <= 0) return;
          final weights = split.weights;
          final pair = weights[index] + weights[index + 1];
          final low = _minWeight.clamp(0.0, pair / 2);
          weights[index] = (weights[index] + delta / usable).clamp(
            low,
            pair - low,
          );
          weights[index + 1] = pair - weights[index];
          onWeightsEdited();
        }

        final row = <Widget>[];
        for (var i = 0; i < children.length; i++) {
          if (i > 0) {
            final index = i - 1;
            row.add(
              MouseRegion(
                cursor: horizontal
                    ? SystemMouseCursors.resizeColumn
                    : SystemMouseCursors.resizeRow,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragUpdate: horizontal
                      ? (d) => onDrag(index, d.delta.dx)
                      : null,
                  onHorizontalDragEnd: horizontal
                      ? (_) => onWeightsCommitted()
                      : null,
                  onVerticalDragUpdate: horizontal
                      ? null
                      : (d) => onDrag(index, d.delta.dy),
                  onVerticalDragEnd: horizontal
                      ? null
                      : (_) => onWeightsCommitted(),
                  child: Container(
                    width: horizontal ? _thickness : null,
                    height: horizontal ? null : _thickness,
                    color: scheme.outlineVariant,
                    alignment: Alignment.center,
                    child: Container(
                      width: horizontal ? 2 : 24,
                      height: horizontal ? 24 : 2,
                      decoration: BoxDecoration(
                        color: scheme.onSurfaceVariant,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }
          // The last child flexes to absorb rounding from the fixed extents.
          row.add(
            i == children.length - 1
                ? Expanded(child: children[i])
                : SizedBox(
                    width: horizontal ? usable * split.weights[i] : null,
                    height: horizontal ? null : usable * split.weights[i],
                    child: children[i],
                  ),
          );
        }

        return horizontal ? Row(children: row) : Column(children: row);
      },
    );
  }
}

class _PanelContainer extends StatefulWidget {
  const _PanelContainer({required this.child});
  final Widget child;

  @override
  State<_PanelContainer> createState() => _PanelContainerState();
}

class _PanelContainerState extends State<_PanelContainer> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Material provides ink effects for ListTile / InkWell inside panels.
    // RepaintBoundary isolates each panel's rebuilds from the rest of the
    // shell and from the viewport (the spike 0.1 stutter mitigation).
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: scheme.surface,
        // The hovered panel is the one receiving pointer-routed interactions
        // (viewport modal keys among them), so mark it visibly.
        shape: Border.all(
          color: _hovered
              ? scheme.primary.withValues(alpha: 0.45)
              : Colors.transparent,
          width: 1,
        ),
        child: RepaintBoundary(child: ClipRect(child: widget.child)),
      ),
    );
  }
}
