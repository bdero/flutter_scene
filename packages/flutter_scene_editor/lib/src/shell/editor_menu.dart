/// The editor's menus: one item model, one anchor, used by every surface that
/// drops a list of things down.
///
/// Extracted from the menu bar when the menu bar retired. The menus did not go
/// away with it -- they moved to where the thing they act on lives, which is
/// the project menu in the top strip, the add menu on the hierarchy's header,
/// and the view menu beside the viewport -- and all three want the same item
/// shape: a label, an optional second line, a checkmark slot, submenus, and a
/// remove affordance for lists you can prune.
library;

import 'package:flutter/material.dart';

import 'editor_theme.dart';
import 'panel_chrome.dart';

/// One entry in an [EditorMenu].
class EditorMenuItem {
  const EditorMenuItem({
    required this.label,
    this.detail,
    this.onTap,
    this.onRemove,
    this.removeTooltip = 'Remove',
    this.checked,
    this.children,
  }) : divider = false;

  const EditorMenuItem.divider()
    : label = '',
      detail = null,
      onTap = null,
      onRemove = null,
      removeTooltip = '',
      checked = null,
      children = null,
      divider = true;

  final String label;

  /// A quieter second line: where a recent file lives, what an effect does.
  final String? detail;
  final VoidCallback? onTap;

  /// Prunes this entry from the list it belongs to.
  final VoidCallback? onRemove;
  final String removeTooltip;

  /// Non-null renders a leading checkmark slot (checked or empty).
  final bool? checked;
  final List<EditorMenuItem>? children;
  final bool divider;
}

/// A menu anchored to a label, an icon, or any widget.
class EditorMenu extends StatefulWidget {
  const EditorMenu({
    super.key,
    this.label,
    this.icon,
    this.tooltip,
    this.items,
    this.itemsBuilder,
    this.trailingChevron = true,
    this.emphasis = false,
    this.railStyle = false,
    this.active = false,
  }) : assert((items == null) != (itemsBuilder == null));

  /// The trigger's text. Null draws [icon] alone.
  final String? label;
  final IconData? icon;
  final String? tooltip;
  final List<EditorMenuItem>? items;

  /// Deferred alternative to [items], invoked when the menu opens, for entries
  /// whose state can change without the trigger rebuilding.
  final List<EditorMenuItem> Function()? itemsBuilder;

  final bool trailingChevron;

  /// The strip's leftmost menu names the thing you are working on, and reads
  /// as a title rather than as one control among several.
  final bool emphasis;

  /// Draws as a rail button: full width, centred, with the accent bar a rail
  /// button uses to say it is the active one.
  final bool railStyle;
  final bool active;

  @override
  State<EditorMenu> createState() => _EditorMenuState();
}

class _EditorMenuState extends State<EditorMenu> {
  @override
  Widget build(BuildContext context) {
    final trigger = widget.railStyle
        ? Container(
            width: editorRailWidth,
            height: 30,
            decoration: BoxDecoration(
              color: widget.active ? editorRaisedColor : null,
              border: Border(
                left: BorderSide(
                  color: widget.active ? editorAccentColor : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: Icon(
              widget.icon,
              size: editorIconSizeLarge,
              color: widget.active ? editorTextColor : editorMutedTextColor,
            ),
          )
        : Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.icon != null)
                  Icon(
                    widget.icon,
                    size: editorIconSize,
                    color: editorMutedTextColor,
                  ),
                if (widget.icon != null && widget.label != null)
                  const SizedBox(width: 5),
                if (widget.label != null)
                  Text(
                    widget.label!,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: widget.emphasis
                          ? FontWeight.w600
                          : FontWeight.w400,
                      color: widget.emphasis
                          ? editorTextColor
                          : editorMutedTextColor,
                    ),
                  ),
                if (widget.trailingChevron)
                  const Icon(
                    Icons.arrow_drop_down,
                    size: editorIconSize,
                    color: editorMutedTextColor,
                  ),
              ],
            ),
          );
    return MenuAnchor(
      menuChildren: buildEditorMenuItems(
        widget.items ?? widget.itemsBuilder!(),
      ),
      builder: (context, controller, child) {
        final button = GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (controller.isOpen) {
              controller.close();
              return;
            }
            // Refresh deferred menu state before the overlay is built.
            setState(() {});
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) controller.open();
            });
          },
          child: trigger,
        );
        return widget.tooltip == null
            ? button
            : Tooltip(message: widget.tooltip!, child: button);
      },
    );
  }
}

/// Renders [source] as menu children, recursing into submenus.
List<Widget> buildEditorMenuItems(List<EditorMenuItem> source) => [
  for (final item in source)
    if (item.divider)
      const Divider(height: 8)
    else if (item.children != null)
      SubmenuButton(
        menuChildren: buildEditorMenuItems(item.children!),
        child: Text(item.label),
      )
    else
      MenuItemButton(
        onPressed: item.onTap,
        leadingIcon: item.checked == null
            ? null
            : editorMenuCheckmark(item.checked!),
        child: item.detail == null && item.onRemove == null
            ? Text(item.label)
            : SizedBox(
                width: 360,
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (item.detail != null)
                            Text(
                              item.detail!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: editorMenuItemDetailText,
                            ),
                        ],
                      ),
                    ),
                    if (item.onRemove != null)
                      IconButton(
                        tooltip: item.removeTooltip,
                        onPressed: item.onRemove,
                        icon: const Icon(Icons.close, size: 14),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ),
      ),
];
