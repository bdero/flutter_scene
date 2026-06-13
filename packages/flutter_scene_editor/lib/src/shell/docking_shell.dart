import 'package:flutter/material.dart';
import 'package:multi_split_view/multi_split_view.dart';

/// 4-panel docked editor shell.
///
/// Layout (in-house on multi_split_view, not the `docking` package):
///
///   +---------------------------+-------------------+
///   |                           |   Outliner        |
///   |       Viewport            +-------------------+
///   |                           |   Inspector       |
///   +---------------------------+-------------------+
///   |   History (bottom strip)                      |
///   +-----------------------------------------------+
///
/// The `docking` package pins old `multi_split_view`/`tabbed_view` versions
/// (see spike 0.4 findings) and breaks host-project resolution. This in-house
/// layout covers the needed surfaces without the pin constraint.
///
/// TODO(docking-tabs): add a tab layer (tabbed_view ^3.x) for tabbed panel
/// groups when detachable panels are needed in a later phase.
class DockingShell extends StatefulWidget {
  const DockingShell({
    super.key,
    required this.viewportPane,
    required this.outlinerPane,
    required this.inspectorPane,
    required this.historyPane,
  });

  final Widget viewportPane;
  final Widget outlinerPane;
  final Widget inspectorPane;
  final Widget historyPane;

  @override
  State<DockingShell> createState() => _DockingShellState();
}

class _DockingShellState extends State<DockingShell> {
  late final MultiSplitViewController _hController;
  late final MultiSplitViewController _rightController;
  late final MultiSplitViewController _vController;

  @override
  void initState() {
    super.initState();
    _hController = MultiSplitViewController(
      areas: [
        Area(flex: 3, min: 200), // viewport
        Area(flex: 1, min: 160), // right column
      ],
    );
    _rightController = MultiSplitViewController(
      areas: [
        Area(flex: 1, min: 80), // outliner
        Area(flex: 1, min: 80), // inspector
      ],
    );
    _vController = MultiSplitViewController(
      areas: [
        Area(flex: 4, min: 200), // main area
        Area(flex: 1, min: 80), // history strip
      ],
    );
  }

  @override
  void dispose() {
    _hController.dispose();
    _rightController.dispose();
    _vController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = MultiSplitViewThemeData(
      // A wide, filled divider so the separation is clearly visible and easy
      // to grab. The band gets a solid background; a brighter groove and a
      // primary-tinted highlight show where to drag.
      dividerThickness: 8,
      dividerPainter: DividerPainters.grooved1(
        backgroundColor: scheme.outlineVariant,
        highlightedBackgroundColor: scheme.primary.withValues(alpha: 0.35),
        color: scheme.onSurfaceVariant,
        highlightedColor: scheme.primary,
        thickness: 2,
        highlightedThickness: 3,
      ),
    );

    final rightColumn = MultiSplitViewTheme(
      data: theme,
      child: MultiSplitView(
        axis: Axis.vertical,
        controller: _rightController,
        builder: (context, area) {
          return switch (area.index) {
            0 => _PanelContainer(child: widget.outlinerPane),
            _ => _PanelContainer(child: widget.inspectorPane),
          };
        },
      ),
    );

    final mainArea = MultiSplitViewTheme(
      data: theme,
      child: MultiSplitView(
        axis: Axis.horizontal,
        controller: _hController,
        builder: (context, area) {
          return switch (area.index) {
            0 => _PanelContainer(child: widget.viewportPane),
            _ => rightColumn,
          };
        },
      ),
    );

    return MultiSplitViewTheme(
      data: theme,
      child: MultiSplitView(
        axis: Axis.vertical,
        controller: _vController,
        builder: (context, area) {
          return switch (area.index) {
            0 => mainArea,
            _ => _PanelContainer(child: widget.historyPane),
          };
        },
      ),
    );
  }
}

class _PanelContainer extends StatelessWidget {
  const _PanelContainer({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Material provides ink effects for ListTile / InkWell inside panels.
    // RepaintBoundary isolates each panel's rebuilds from the rest of the
    // shell and from the viewport (the spike 0.1 stutter mitigation).
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: RepaintBoundary(child: ClipRect(child: child)),
    );
  }
}
