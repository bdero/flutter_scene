/// The toolbar: what is being built on the left, the transport in the middle,
/// and the workspace controls on the right.
///
/// A row of its own rather than more things pushed onto the end of the menu
/// bar, and for one reason: the transport belongs dead centre of the window.
/// Every editor this one is measured against puts it there, which is why
/// people find it without looking, and it cannot be centred in a row whose
/// left half is five menus and whose right half is one button.
///
/// Centred by giving the two side groups equal flex, so the middle lands on
/// the window's midpoint whatever is beside it. A group with more in it than
/// its half can hold scrolls, rather than pushing the transport off centre.
library;

import 'package:flutter/material.dart';

import 'editor_theme.dart';

/// The height of the toolbar strip.
const double editorToolbarRowHeight = 34;

class EditorToolbarRow extends StatelessWidget {
  const EditorToolbarRow({
    super.key,
    required this.namedLayouts,
    required this.onApplyLayout,
    required this.onSaveCurrentLayout,
    required this.onManageLayouts,
    this.leading = const [],
    this.centre = const [],
  });

  /// What is being built, and for what.
  final List<Widget> leading;

  /// The transport.
  final List<Widget> centre;

  final Map<String, String> namedLayouts;
  final ValueChanged<String?> onApplyLayout;
  final VoidCallback onSaveCurrentLayout;
  final VoidCallback onManageLayouts;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: editorToolbarRowHeight,
      decoration: const BoxDecoration(
        color: editorPanelColor,
        border: Border(bottom: BorderSide(color: editorLineColor)),
      ),
      child: Row(
        children: [
          Expanded(
            child: EditorToolbarScroller(
              children: [const SizedBox(width: 8), ...leading],
            ),
          ),
          ...centre,
          Expanded(
            child: EditorToolbarScroller(
              alignEnd: true,
              children: [
                _LayoutMenu(
                  namedLayouts: namedLayouts,
                  onApplyLayout: onApplyLayout,
                  onSaveCurrentLayout: onSaveCurrentLayout,
                  onManageLayouts: onManageLayouts,
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The workspace picker: the saved arrangements, and the way to save one.
class _LayoutMenu extends StatelessWidget {
  const _LayoutMenu({
    required this.namedLayouts,
    required this.onApplyLayout,
    required this.onSaveCurrentLayout,
    required this.onManageLayouts,
  });

  final Map<String, String> namedLayouts;
  final ValueChanged<String?> onApplyLayout;
  final VoidCallback onSaveCurrentLayout;
  final VoidCallback onManageLayouts;

  @override
  Widget build(BuildContext context) => MenuAnchor(
    menuChildren: [
      MenuItemButton(
        onPressed: () => onApplyLayout(null),
        child: const Text('Default', style: editorMenuItemText),
      ),
      for (final entry in namedLayouts.entries)
        MenuItemButton(
          onPressed: () => onApplyLayout(entry.value),
          child: Text(entry.key, style: editorMenuItemText),
        ),
      const Divider(height: 1),
      MenuItemButton(
        onPressed: onSaveCurrentLayout,
        child: const Text('Save Layout…', style: editorMenuItemText),
      ),
      MenuItemButton(
        onPressed: onManageLayouts,
        child: const Text('Manage Layouts…', style: editorMenuItemText),
      ),
    ],
    builder: (context, controller, _) => Tooltip(
      message: 'Workspace layout',
      child: InkWell(
        borderRadius: BorderRadius.circular(3),
        onTap: () => controller.isOpen ? controller.close() : controller.open(),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.dashboard_outlined, size: 14),
              SizedBox(width: 5),
              Text('Layout', style: TextStyle(fontSize: 11)),
              Icon(Icons.arrow_drop_down, size: 14),
            ],
          ),
        ),
      ),
    ),
  );
}
