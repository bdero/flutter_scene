import 'package:flutter/material.dart';

/// A compact scene-operation hint shared by interactive examples.
class ExampleActionHint extends StatelessWidget {
  const ExampleActionHint({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Card(
    color: Colors.black54,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Text(
        message,
        style: const TextStyle(color: Colors.white70, fontSize: 12),
      ),
    ),
  );
}

/// A compact icon command that sits beside an [ExampleActionHint].
class ExampleActionButton extends StatelessWidget {
  const ExampleActionButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.black54,
    borderRadius: BorderRadius.circular(8),
    elevation: 2,
    child: IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon),
      color: Colors.white,
      disabledColor: Colors.white38,
    ),
  );
}

/// A compact dropdown matching the dark example-overlay surfaces.
class ExampleDropdown<T> extends StatelessWidget {
  const ExampleDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.triggerColor = Colors.black54,
    this.padding = const EdgeInsets.symmetric(horizontal: 12),
    this.isDense = false,
    this.iconSize,
    this.style = const TextStyle(color: Colors.white),
    this.selectedItemBuilder,
  });

  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final Color triggerColor;
  final EdgeInsetsGeometry padding;
  final bool isDense;
  final double? iconSize;
  final TextStyle style;

  /// Builds the closed-state trigger per item, so a long label can be
  /// ellipsized without truncating it in the open menu.
  final DropdownButtonBuilder? selectedItemBuilder;

  @override
  Widget build(BuildContext context) => ScrollbarTheme(
    key: const ValueKey('example-dropdown-scrollbar-theme'),
    data: const ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(Colors.transparent),
      trackColor: WidgetStatePropertyAll(Colors.transparent),
      trackBorderColor: WidgetStatePropertyAll(Colors.transparent),
    ),
    child: Material(
      key: const ValueKey('example-dropdown-surface'),
      color: triggerColor,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: padding,
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            isExpanded: true,
            isDense: isDense,
            value: value,
            items: items,
            onChanged: onChanged,
            selectedItemBuilder: selectedItemBuilder,
            dropdownColor: const Color(0xFF303030),
            borderRadius: BorderRadius.circular(8),
            icon: Icon(
              Icons.arrow_drop_down,
              color: Colors.white,
              size: iconSize,
            ),
            style: style,
          ),
        ),
      ),
    ),
  );
}

/// A compact, navigation-style button that switches between two camera modes.
class ExampleCameraToggle extends StatelessWidget {
  const ExampleCameraToggle({
    super.key,
    required this.active,
    required this.inactiveLabel,
    required this.activeLabel,
    required this.inactiveIcon,
    required this.activeIcon,
    required this.onToggle,
  });

  final bool active;
  final String inactiveLabel;
  final String activeLabel;
  final IconData inactiveIcon;
  final IconData activeIcon;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final label = active ? activeLabel : inactiveLabel;
    final icon = active ? activeIcon : inactiveIcon;
    final nextMode = active ? inactiveLabel : activeLabel;

    return Tooltip(
      message: 'Switch to $nextMode',
      child: Material(
        key: const ValueKey('example-camera-toggle-surface'),
        color: Colors.black54,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
