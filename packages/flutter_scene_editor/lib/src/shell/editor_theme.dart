import 'package:flutter/material.dart';

/// The editor's dark theme.
///
/// Blue-seeded so the whole shell (panels, tabs, selection, gizmo-adjacent
/// chrome) reads as one palette, with compact density for desktop pointer
/// input.
ThemeData editorDarkTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF3B82F6),
    brightness: Brightness.dark,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    visualDensity: VisualDensity.compact,
    splashFactory: InkSparkle.splashFactory,
    tooltipTheme: const TooltipThemeData(
      waitDuration: Duration(milliseconds: 500),
    ),
  );
}
