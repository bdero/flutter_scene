/// The tool rail: the strip down the left edge that holds what you are doing,
/// what you are building, and what you press to run it.
///
/// Forty pixels, never hidden, never resized, and the only horizontal chrome
/// in the window -- there is no top bar, because everything that would have
/// been in one is here. Tools at the top, the project and its build below
/// them, and the things that are not about the scene pinned to the bottom.
///
/// Groups are separated by air and a hairline rather than by labels: at this
/// width a label is noise, and the gap is enough to say "these five belong
/// together". The middle scrolls when a short window cannot hold everything,
/// so the rail never overflows and never pushes the utility group off the
/// bottom.
library;

import 'package:flutter/material.dart';

import '../viewport/transform_gizmo.dart';
import '../viewport/viewport_tools.dart';
import 'editor_menu.dart';
import 'editor_theme.dart';
import 'panel_chrome.dart';

/// One button in the rail.
class EditorRailItem {
  const EditorRailItem({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.active = false,
    this.shortcut,
  });

  final IconData icon;
  final String tooltip;

  /// Null disables the button; [tooltip] is then expected to say why, which
  /// is the rail's half of the rule that no control is dead without a reason.
  final VoidCallback? onPressed;
  final bool active;

  /// Shown after the tooltip, so the keyboard way is learned from the mouse
  /// way.
  final String? shortcut;
}

/// The rail down the left edge.
class EditorToolRail extends StatelessWidget {
  const EditorToolRail({
    super.key,
    required this.groups,
    required this.utility,
    this.leading,
    this.onDragStart,
  });

  /// The rail's contents, already interleaved with [EditorRailDivider]s by
  /// the caller that knows what belongs together.
  final List<Widget> groups;

  /// Pinned to the bottom: the things that are not about the scene.
  final List<Widget> utility;

  /// Drawn at the very top. The window's mark sits here, in the corner the
  /// window controls take when the host draws its own.
  final Widget? leading;

  /// Starts a window drag from the rail's empty middle. With no top bar there
  /// is nowhere else to grab a window whose title bar is hidden.
  final VoidCallback? onDragStart;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: editorRailWidth,
      decoration: const BoxDecoration(
        color: editorPanelColor,
        border: Border(right: BorderSide(color: editorLineColor)),
      ),
      child: Column(
        children: [
          if (leading != null)
            SizedBox(
              height: editorHeaderHeight,
              child: Center(child: leading),
            ),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanStart: onDragStart == null ? null : (_) => onDragStart!(),
              child: SingleChildScrollView(
                child: Column(children: [const SizedBox(height: 4), ...groups]),
              ),
            ),
          ),
          const EditorRailDivider(),
          ...utility,
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  /// The transform tools, bound to the shared [state].
  ///
  /// Kept here rather than in the shell so the rail's contents and the rail's
  /// shape stay in one file, and so a second host (the viewer, a future
  /// standalone tool) gets the same buttons for free.
  static List<EditorRailItem> transformTools(ViewportToolState state) => [
    EditorRailItem(
      icon: Icons.open_with,
      tooltip: 'Move',
      shortcut: 'W',
      active:
          state.brush == ViewportBrush.none &&
          state.mode == GizmoMode.translate,
      onPressed: () {
        state.brush = ViewportBrush.none;
        state.mode = GizmoMode.translate;
      },
    ),
    EditorRailItem(
      icon: Icons.threesixty,
      tooltip: 'Rotate',
      shortcut: 'E',
      active:
          state.brush == ViewportBrush.none && state.mode == GizmoMode.rotate,
      onPressed: () {
        state.brush = ViewportBrush.none;
        state.mode = GizmoMode.rotate;
      },
    ),
    EditorRailItem(
      icon: Icons.aspect_ratio,
      tooltip: 'Scale',
      shortcut: 'R',
      active:
          state.brush == ViewportBrush.none && state.mode == GizmoMode.scale,
      onPressed: () {
        state.brush = ViewportBrush.none;
        state.mode = GizmoMode.scale;
      },
    ),
  ];

  /// How the handles behave: what frame they work in, whether a drag lands on
  /// a step, and what several selected nodes turn about.
  static List<EditorRailItem> handleOptions(ViewportToolState state) => [
    EditorRailItem(
      icon: state.space == TransformSpace.global
          ? Icons.public
          : Icons.crop_free,
      tooltip: state.space == TransformSpace.global
          ? 'Global space — handles follow the world'
          : 'Local space — handles follow the object',
      shortcut: 'X',
      onPressed: state.toggleSpace,
    ),
    EditorRailItem(
      icon: Icons.grid_4x4,
      tooltip: state.snap
          ? 'Snapping on — ${state.translateStep} units, '
                '${state.rotateStepDegrees.round()}°'
          : 'Snap drags to a step',
      active: state.snap,
      onPressed: () => state.snap = !state.snap,
    ),
    EditorRailItem(
      icon: state.pivot == PivotMode.medianPoint
          ? Icons.center_focus_strong
          : Icons.scatter_plot_outlined,
      tooltip: state.pivot == PivotMode.medianPoint
          ? 'Turning about the selection’s middle'
          : 'Turning about each object’s own origin',
      onPressed: state.togglePivot,
    ),
  ];

  /// The brushes, which are gated on what the selection is. Disabled with the
  /// reason rather than hidden: a tool that appears and disappears as you
  /// click around is a tool nobody learns is there.
  static List<EditorRailItem> brushes(ViewportToolState state) => [
    EditorRailItem(
      icon: Icons.terrain,
      tooltip: state.canSculpt
          ? 'Sculpt terrain'
          : 'Select a terrain (or a plane) to sculpt it',
      active: state.brush == ViewportBrush.terrain,
      onPressed: state.canSculpt
          ? () => state.brush = state.brush == ViewportBrush.terrain
                ? ViewportBrush.none
                : ViewportBrush.terrain
          : null,
    ),
    EditorRailItem(
      icon: Icons.grass,
      tooltip: state.canScatter
          ? 'Scatter'
          : 'Select something with a scatter layer to paint into it',
      active: state.brush == ViewportBrush.scatter,
      onPressed: state.canScatter
          ? () => state.brush = state.brush == ViewportBrush.scatter
                ? ViewportBrush.none
                : ViewportBrush.scatter
          : null,
    ),
  ];
}

/// The hairline between two groups of rail buttons.
class EditorRailDivider extends StatelessWidget {
  const EditorRailDivider({super.key});

  @override
  Widget build(BuildContext context) => Container(
    height: 1,
    margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    color: editorLineColor,
  );
}

/// A rail button.
class EditorRailButton extends StatelessWidget {
  const EditorRailButton({super.key, required this.item});

  final EditorRailItem item;

  @override
  Widget build(BuildContext context) {
    final enabled = item.onPressed != null;
    final shortcut = item.shortcut;
    return Tooltip(
      message: shortcut == null ? item.tooltip : '${item.tooltip}  ($shortcut)',
      waitDuration: const Duration(milliseconds: 400),
      child: InkWell(
        onTap: item.onPressed,
        hoverColor: editorRaisedColor,
        child: Container(
          width: editorRailWidth,
          height: 30,
          decoration: BoxDecoration(
            color: item.active ? editorRaisedColor : null,
            border: Border(
              left: BorderSide(
                color: item.active ? editorAccentColor : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Icon(
            item.icon,
            size: editorIconSizeLarge,
            color: !enabled
                ? editorMutedTextColor.withValues(alpha: 0.4)
                : item.active
                ? editorTextColor
                : editorMutedTextColor,
          ),
        ),
      ),
    );
  }
}

/// A rail button that opens a menu: the retired File and View menus, the
/// camera, the toolchain.
class EditorRailMenu extends StatelessWidget {
  const EditorRailMenu({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.itemsBuilder,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final List<EditorMenuItem> Function() itemsBuilder;
  final bool active;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: editorRailWidth,
    height: 30,
    child: EditorMenu(
      icon: icon,
      tooltip: tooltip,
      trailingChevron: false,
      itemsBuilder: itemsBuilder,
      railStyle: true,
      active: active,
    ),
  );
}
