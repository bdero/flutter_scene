/// The top strip: the viewport's own header, and the only strip in the window.
///
/// What used to be two full-width bars -- five menus above a centred transport
/// -- is one band the same height as every other region header, so the window
/// has a single horizontal line across its top and the scene starts under it.
///
/// The menus did not survive intact, and should not have. File became the
/// project menu at the left, because everything in it was about the project or
/// the scene. Add moved to the hierarchy's header, next to the tree it adds
/// to. Edit became the keyboard and the command palette, which is where every
/// one of its items was already reached from. View became the panels menu and
/// the rail.
///
/// The middle stays empty. It is the window-drag region on a host that hides
/// the native title bar, and it is the space that makes the two clusters read
/// as two clusters.
library;

import 'package:flutter/material.dart';

import 'editor_menu.dart';
import 'editor_theme.dart';
import 'panel_chrome.dart';

/// What the viewport is showing: the editor's camera, or the game's.
enum ViewportMode {
  scene('Scene', Icons.videocam_outlined),
  game('Game', Icons.sports_esports_outlined);

  const ViewportMode(this.label, this.icon);

  final String label;
  final IconData icon;
}

class EditorTopStrip extends StatelessWidget {
  const EditorTopStrip({
    super.key,
    required this.title,
    required this.projectMenuItems,
    required this.panelsMenuItems,
    required this.mode,
    required this.onModeChanged,
    required this.onSceneSettings,
    required this.onToggleFocus,
    required this.focused,
    this.leading = const [],
    this.trailing = const [],
    this.leadingInset = 8,
    this.onDragStart,
  });

  /// What is open: the project name, or the scene's when there is no project.
  final String title;

  /// The retired File menu.
  final List<EditorMenuItem> Function() projectMenuItems;

  /// The retired View menu: the regions, the shelf's modes, the screens.
  final List<EditorMenuItem> Function() panelsMenuItems;

  final ViewportMode mode;
  final ValueChanged<ViewportMode> onModeChanged;

  /// The scene's own settings: its lighting, background and rendering.
  final VoidCallback onSceneSettings;

  /// Collapses every region but the viewport, and restores them.
  final VoidCallback onToggleFocus;
  final bool focused;

  /// The host's build selectors: what is being built, and for what.
  final List<Widget> leading;

  /// The host's transport: play, and what a running session turns it into.
  final List<Widget> trailing;

  /// Space before the first item, for a host that draws its own window
  /// controls over the content.
  final double leadingInset;

  /// Starts a window drag from the strip's empty middle.
  final VoidCallback? onDragStart;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: editorHeaderHeight,
      decoration: const BoxDecoration(
        color: editorPanelColor,
        border: Border(bottom: BorderSide(color: editorLineColor)),
      ),
      child: Row(
        children: [
          SizedBox(width: leadingInset),
          EditorMenu(
            label: title,
            emphasis: true,
            tooltip: 'Project and scene',
            itemsBuilder: projectMenuItems,
          ),
          // The project, what is being built, and the panels are three
          // groups, not seven controls.
          if (leading.isNotEmpty) const SizedBox(width: 10),
          ...leading,
          const SizedBox(width: 10),
          EditorMenu(
            icon: Icons.dashboard_outlined,
            tooltip: 'Panels',
            trailingChevron: false,
            itemsBuilder: panelsMenuItems,
          ),
          // The empty middle. A drag region, and the space that separates the
          // two clusters; nothing lives here.
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanStart: onDragStart == null ? null : (_) => onDragStart!(),
            ),
          ),
          EditorMenu(
            label: mode.label,
            icon: mode.icon,
            tooltip: 'What the viewport shows',
            items: [
              for (final option in ViewportMode.values)
                EditorMenuItem(
                  label: option.label,
                  checked: option == mode,
                  onTap: () => onModeChanged(option),
                ),
            ],
          ),
          EditorPanelIconButton(
            icon: Icons.tune,
            tooltip: 'Scene settings',
            onPressed: onSceneSettings,
          ),
          EditorPanelIconButton(
            icon: focused ? Icons.close_fullscreen : Icons.open_in_full,
            tooltip: focused ? 'Show the panels' : 'Viewport only',
            selected: focused,
            onPressed: onToggleFocus,
          ),
          if (trailing.isNotEmpty) const SizedBox(width: 10),
          ...trailing,
          const SizedBox(width: 6),
        ],
      ),
    );
  }
}
