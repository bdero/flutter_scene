/// The tool rail: the strip down the left edge that holds what you are doing.
///
/// Forty pixels, never hidden, never resized, and the only place in the window
/// where a tool lives. Tools at the top, the things that are not tools at the
/// bottom, and a gap between them that does the separating so no divider has
/// to. Exactly one tool is active at any moment -- a rail with nothing lit is
/// a rail that is lying about the state of the pointer.
library;

import 'package:flutter/material.dart';

import '../viewport/transform_gizmo.dart';
import '../viewport/viewport_tools.dart';
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
    required this.tools,
    required this.utility,
    this.leading,
  });

  /// The tool group at the top. Exactly one is expected to be active.
  final List<EditorRailItem> tools;

  /// The group pinned to the bottom: help, shortcuts, settings.
  final List<EditorRailItem> utility;

  /// Drawn above the tools, at the very top of the rail. The window's mark
  /// sits here, in the corner the reference editor puts it.
  final Widget? leading;

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
          const SizedBox(height: 4),
          for (final item in tools) _RailButton(item: item),
          const Spacer(),
          for (final item in utility) _RailButton(item: item),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  /// The transform tools, bound to the shared [state].
  ///
  /// Kept here rather than in the shell so the rail's contents and the rail's
  /// shape stay in one file, and so a second host (the viewer, a future
  /// standalone tool) gets the same five buttons for free.
  static List<EditorRailItem> transformTools(ViewportToolState state) => [
    EditorRailItem(
      icon: Icons.open_with,
      tooltip: 'Move',
      shortcut: 'W',
      active: state.mode == GizmoMode.translate,
      onPressed: () => state.mode = GizmoMode.translate,
    ),
    EditorRailItem(
      icon: Icons.threesixty,
      tooltip: 'Rotate',
      shortcut: 'E',
      active: state.mode == GizmoMode.rotate,
      onPressed: () => state.mode = GizmoMode.rotate,
    ),
    EditorRailItem(
      icon: Icons.aspect_ratio,
      tooltip: 'Scale',
      shortcut: 'R',
      active: state.mode == GizmoMode.scale,
      onPressed: () => state.mode = GizmoMode.scale,
    ),
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
  ];
}

class _RailButton extends StatelessWidget {
  const _RailButton({required this.item});

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
