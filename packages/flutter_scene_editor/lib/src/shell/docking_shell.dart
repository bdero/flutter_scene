import 'package:flutter/material.dart';

/// 4-panel docked editor shell.
///
/// Layout (in-house resizable splits, the `docking` and `multi_split_view`
/// packages did not give reliably draggable dividers in this nesting, so the
/// split is hand-rolled with a gesture this code controls directly):
///
///   +---------------------------+-------------------+
///   |                           |   Outliner        |
///   |       Viewport            +-------------------+
///   |                           |   Inspector       |
///   +---------------------------+-------------------+
///   |   History (bottom strip)                      |
///   +-----------------------------------------------+
///
/// TODO(docking-tabs): drag-to-redock and tab groups belong with the editor
/// UX design pass.
class DockingShell extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final rightColumn = ResizableSplit(
      axis: Axis.vertical,
      initialFraction: 0.5,
      first: _PanelContainer(child: outlinerPane),
      second: _PanelContainer(child: inspectorPane),
    );
    final mainArea = ResizableSplit(
      axis: Axis.horizontal,
      initialFraction: 0.72,
      first: _PanelContainer(child: viewportPane),
      second: rightColumn,
    );
    return ResizableSplit(
      axis: Axis.vertical,
      initialFraction: 0.78,
      first: mainArea,
      second: _PanelContainer(child: historyPane),
    );
  }
}

/// Two panes split along [axis] with a draggable divider between them. The
/// first pane's share of the space is [initialFraction]; dragging the divider
/// adjusts it, clamped to [minFraction] and [maxFraction].
class ResizableSplit extends StatefulWidget {
  const ResizableSplit({
    super.key,
    required this.axis,
    required this.first,
    required this.second,
    this.initialFraction = 0.5,
    this.minFraction = 0.1,
    this.maxFraction = 0.9,
  });

  final Axis axis;
  final Widget first;
  final Widget second;
  final double initialFraction;
  final double minFraction;
  final double maxFraction;

  @override
  State<ResizableSplit> createState() => _ResizableSplitState();
}

class _ResizableSplitState extends State<ResizableSplit> {
  static const double _thickness = 8;

  late double _fraction = widget.initialFraction;

  @override
  Widget build(BuildContext context) {
    final horizontal = widget.axis == Axis.horizontal;
    final scheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final total = horizontal ? constraints.maxWidth : constraints.maxHeight;
        final usable = (total - _thickness).clamp(0.0, double.infinity);
        final firstExtent = (usable * _fraction).clamp(0.0, usable);

        void onDrag(double delta) {
          if (usable <= 0) return;
          setState(() {
            _fraction = (_fraction + delta / usable).clamp(
              widget.minFraction,
              widget.maxFraction,
            );
          });
        }

        final divider = MouseRegion(
          cursor: horizontal
              ? SystemMouseCursors.resizeColumn
              : SystemMouseCursors.resizeRow,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: horizontal
                ? (d) => onDrag(d.delta.dx)
                : null,
            onVerticalDragUpdate: horizontal ? null : (d) => onDrag(d.delta.dy),
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
        );

        final children = <Widget>[
          SizedBox(
            width: horizontal ? firstExtent : null,
            height: horizontal ? null : firstExtent,
            child: widget.first,
          ),
          divider,
          Expanded(child: widget.second),
        ];

        return horizontal
            ? Row(children: children)
            : Column(children: children);
      },
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
