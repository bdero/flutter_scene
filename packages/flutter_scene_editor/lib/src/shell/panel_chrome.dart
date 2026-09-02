/// The editor's panel grammar: one header shape, one section shape, one
/// property row, one icon button.
///
/// Every docked surface is built from these, and that is the whole point. A
/// panel list reads as one program when the header is the same height in each
/// region, the labels line up down a single column, and nothing draws a box
/// around itself; it stops reading that way the moment one panel picks its own
/// padding. The reference editor is not clean because of what it contains --
/// it is clean because it contains six shapes and no others.
///
/// The rules these encode, so they can be checked rather than remembered:
///
/// * a region header is [editorHeaderHeight] and carries a marker, a name in
///   uppercase, and its actions inline;
/// * a property row is [editorPropertyRowHeight] with a fixed
///   [editorPropertyLabelWidth] label column, and labels take no colon;
/// * docked chrome has no corner radius and no shadow -- regions are told
///   apart by a single hairline, which is what keeps a dense panel quiet;
/// * four type sizes, and the accent means either "selected" or "you can edit
///   this", never a third thing.
library;

import 'package:flutter/material.dart';

import 'editor_theme.dart';

/// The height of a region header, and of the top strip beside it.
///
/// 28 rather than the 24 a pure text header would want: the viewport's header
/// carries dropdowns and the transport, and those are the widest thing the
/// band has to hold. One band height across every region is worth more than
/// four pixels, because the alignment across the top of the window is most of
/// what reads as clean.
const double editorHeaderHeight = 28;

/// The height of one property row.
const double editorPropertyRowHeight = 22;

/// The width of the label column every property row shares.
const double editorPropertyLabelWidth = 96;

/// The side of a bare icon button in panel chrome.
const double editorPanelIconButtonSize = 20;

/// The width of the tool rail down the left edge.
const double editorRailWidth = 40;

/// Horizontal padding inside a panel body.
const double editorPanelInset = 8;

/// The gap between a row's label and its control.
const double editorRowGutter = 6;

/// The uppercase label style shared by region headers and section headers.
const TextStyle editorHeaderText = TextStyle(
  fontSize: 10.5,
  height: 1.1,
  fontWeight: FontWeight.w600,
  letterSpacing: 0.9,
  color: editorTextColor,
);

/// A property row's label: the same size as [editorDetailText], and never
/// followed by a colon. The column is the separator.
const TextStyle editorRowLabelText = TextStyle(
  fontSize: 11,
  height: 1.1,
  color: editorMutedTextColor,
);

/// The header strip at the top of a region.
///
/// [marker] is the dot at the left. It is a colour rather than an icon on
/// purpose: at this size an icon is noise, and the dot is enough to tell one
/// header from the next while scanning down a window.
class EditorPanelHeader extends StatelessWidget {
  const EditorPanelHeader({
    super.key,
    required this.label,
    this.marker = editorAccentColor,
    this.actions = const [],
    this.leading,
    this.onCollapse,
    this.collapsed = false,
    this.collapseTooltip,
    this.leadingInset = 0,
  });

  final String label;
  final Color marker;

  /// Inline at the right, before the collapse control.
  final List<Widget> actions;

  /// Between the marker and the label, for a header that needs a control of
  /// its own (the shelf's mode picker sits here).
  final Widget? leading;

  /// Collapses the region. Null leaves the control out entirely rather than
  /// showing a dead one.
  final VoidCallback? onCollapse;
  final bool collapsed;
  final String? collapseTooltip;

  /// Space before the marker, for a host that draws its own window controls
  /// over the content. The window's top-left corner belongs to the rail and
  /// the first region now, not to a menu bar, so this is where that space is
  /// paid for.
  final double leadingInset;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: editorHeaderHeight,
      padding: const EdgeInsets.symmetric(horizontal: editorPanelInset),
      decoration: const BoxDecoration(
        color: editorPanelColor,
        border: Border(bottom: BorderSide(color: editorLineColor)),
      ),
      child: Row(
        children: [
          if (leadingInset > 0) SizedBox(width: leadingInset),
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: marker, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          if (leading != null) ...[leading!, const SizedBox(width: 7)],
          Expanded(
            child: Text(
              label.toUpperCase(),
              style: editorHeaderText,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          ...actions,
          if (onCollapse != null)
            EditorPanelIconButton(
              icon: collapsed
                  ? Icons.keyboard_arrow_down
                  : Icons.keyboard_arrow_up,
              tooltip: collapseTooltip ?? (collapsed ? 'Expand' : 'Collapse'),
              onPressed: onCollapse,
            ),
        ],
      ),
    );
  }
}

/// A bare icon button sized for panel chrome: no background until it is
/// hovered, and no ink splash spilling past its box.
class EditorPanelIconButton extends StatelessWidget {
  const EditorPanelIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
  });

  final IconData icon;
  final String tooltip;

  /// Null disables the button, and the tooltip is expected to say why.
  final VoidCallback? onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: SizedBox(
        width: editorPanelIconButtonSize,
        height: editorPanelIconButtonSize,
        child: InkWell(
          onTap: onPressed,
          hoverColor: editorRaisedColor,
          child: Icon(
            icon,
            size: editorIconSize,
            color: !enabled
                ? editorMutedTextColor.withValues(alpha: 0.45)
                : selected
                ? editorAccentColor
                : editorMutedTextColor,
          ),
        ),
      ),
    );
  }
}

/// A collapsible group inside a panel: a chevron, an uppercase name, a
/// hairline under it, and the contents flush to the panel's edges.
///
/// Flush and unboxed on purpose. An inspector is thirty of these stacked; give
/// each one a border and a radius and the eye counts boxes instead of reading
/// values.
class EditorPanelSection extends StatefulWidget {
  const EditorPanelSection({
    super.key,
    required this.title,
    required this.children,
    this.initiallyExpanded = true,
    this.trailing,
    this.onExpansionChanged,
  });

  final String title;
  final List<Widget> children;
  final bool initiallyExpanded;

  /// Inline at the right of the section header (a component's enable box, a
  /// section's overflow menu).
  final Widget? trailing;

  final ValueChanged<bool>? onExpansionChanged;

  @override
  State<EditorPanelSection> createState() => _EditorPanelSectionState();
}

class _EditorPanelSectionState extends State<EditorPanelSection> {
  late bool _expanded = widget.initiallyExpanded;

  void _toggle() {
    setState(() => _expanded = !_expanded);
    widget.onExpansionChanged?.call(_expanded);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: _toggle,
          child: Container(
            height: editorHeaderHeight - 4,
            padding: const EdgeInsets.only(left: 4, right: editorPanelInset),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: editorLineColor)),
            ),
            child: Row(
              children: [
                Icon(
                  _expanded ? Icons.arrow_drop_down : Icons.arrow_right,
                  size: editorIconSizeLarge,
                  color: editorMutedTextColor,
                ),
                const SizedBox(width: 2),
                Expanded(
                  child: Text(
                    widget.title.toUpperCase(),
                    style: editorHeaderText,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (widget.trailing != null) widget.trailing!,
              ],
            ),
          ),
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: widget.children,
            ),
          ),
      ],
    );
  }
}

/// One labelled property: the label in the shared column, the control in the
/// rest of the width.
///
/// The label takes no colon and no trailing space. Two columns already say
/// which is the name and which is the value, and a colon on every row of a
/// dense panel is thirty pieces of punctuation doing nothing.
class EditorPropertyRow extends StatelessWidget {
  const EditorPropertyRow({
    super.key,
    required this.label,
    required this.child,
    this.tooltip,
    this.height = editorPropertyRowHeight,
  });

  final String label;
  final Widget child;

  /// What the label means, where the name alone does not carry it.
  final String? tooltip;

  /// For a control that genuinely needs more room (a colour picker, a curve).
  /// Rows stay on the standard height unless they cannot.
  final double height;

  @override
  Widget build(BuildContext context) {
    Widget name = Text(
      label,
      style: editorRowLabelText,
      overflow: TextOverflow.ellipsis,
    );
    if (tooltip != null) {
      name = Tooltip(message: tooltip!, child: name);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: editorPanelInset),
      child: SizedBox(
        height: height,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(width: editorPropertyLabelWidth, child: name),
            const SizedBox(width: editorRowGutter),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

/// The hairline between two regions, and the drag target that resizes them.
///
/// One pixel of line and eight of grab: a divider you can see is chrome, and a
/// divider you can hit is a control, and they do not have to be the same size.
class EditorRegionDivider extends StatelessWidget {
  const EditorRegionDivider({
    super.key,
    required this.axis,
    this.onDrag,
    this.onDragEnd,
  });

  /// The axis the divider runs along: vertical between two columns.
  final Axis axis;

  /// Called with the pointer delta in pixels along the resize direction.
  final ValueChanged<double>? onDrag;
  final VoidCallback? onDragEnd;

  @override
  Widget build(BuildContext context) {
    final vertical = axis == Axis.vertical;
    final line = Container(
      width: vertical ? 1 : null,
      height: vertical ? null : 1,
      color: editorLineColor,
    );
    if (onDrag == null) return line;
    return MouseRegion(
      cursor: vertical
          ? SystemMouseCursors.resizeLeftRight
          : SystemMouseCursors.resizeUpDown,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: vertical
            ? (details) => onDrag!(details.delta.dx)
            : null,
        onVerticalDragUpdate: vertical
            ? null
            : (details) => onDrag!(details.delta.dy),
        onHorizontalDragEnd: vertical ? (_) => onDragEnd?.call() : null,
        onVerticalDragEnd: vertical ? null : (_) => onDragEnd?.call(),
        child: SizedBox(
          width: vertical ? 7 : null,
          height: vertical ? null : 7,
          child: Center(child: line),
        ),
      ),
    );
  }
}

/// The body of a panel: a background, and nothing else.
///
/// Deliberately not [editorPanelBox], whose radius and border belong to
/// dialogs. A docked panel is not a card sitting on a surface; it is a region
/// of the window.
class EditorPanelBody extends StatelessWidget {
  const EditorPanelBody({super.key, required this.child, this.padded = false});

  final Widget child;
  final bool padded;

  @override
  Widget build(BuildContext context) => Container(
    color: editorSurfaceColor,
    padding: padded
        ? const EdgeInsets.symmetric(horizontal: editorPanelInset, vertical: 6)
        : EdgeInsets.zero,
    child: child,
  );
}
