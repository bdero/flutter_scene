import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

const _ink = Color(0xFF15191D);
const _graphite = Color(0xFF1B2025);
const _raised = Color(0xFF22282E);
const _line = Color(0xFF343B43);
const _text = Color(0xFFD4D9DE);
const _mutedText = Color(0xFF9099A2);
const _signal = Color(0xFF44B3E7);

// Prefab-linked content accents (outliner member rows, inspector banners),
// readable on _ink/_graphite and distinct from the _signal selection blue.
const _prefabTint = Color(0xFF64C2B2);
const _prefabShade = Color(0xFF1D3B35);

/// Axis colors shared by transform controls and gizmos.
const editorAxisColors = [
  Color(0xFFE05252),
  Color(0xFF58B95B),
  Color(0xFF4E86DE),
];

/// Shared menu metrics so every dropdown and context menu spaces identically.
const double editorMenuItemHeight = 28;
const EdgeInsets editorMenuItemPadding = EdgeInsets.symmetric(horizontal: 10);
const TextStyle editorMenuItemText = TextStyle(fontSize: 12);

/// Secondary text inside a menu row (paths, modes, platforms).
const TextStyle editorMenuItemDetailText = TextStyle(
  fontSize: 10,
  color: _mutedText,
);

/// The leading checkmark slot used by selectable menu rows.
Widget editorMenuCheckmark(bool checked) => SizedBox(
  width: 16,
  child: checked ? const Icon(Icons.check, size: 14) : null,
);

final FThemeData editorForuiDarkTheme = _buildForuiTheme();

FThemeData _buildForuiTheme() {
  final colors = FColors.neutralDark.copyWith(
    background: _ink,
    foreground: _text,
    primary: _signal,
    primaryForeground: _ink,
    secondary: _raised,
    secondaryForeground: _text,
    muted: _graphite,
    mutedForeground: _mutedText,
    card: _graphite,
    border: _line,
  );
  final typography = FTypography.inherit(
    colors: colors,
    touch: false,
  ).scale(sizeScalar: 0.88);
  final style =
      FStyle.inherit(
        colors: colors,
        typography: typography,
        touch: false,
      ).copyWith(
        borderRadius: const FBorderRadius(
          xs2: BorderRadius.all(Radius.circular(2)),
          xs: BorderRadius.all(Radius.circular(3)),
          sm: BorderRadius.all(Radius.circular(4)),
          md: BorderRadius.all(Radius.circular(5)),
          lg: BorderRadius.all(Radius.circular(6)),
          xl: BorderRadius.all(Radius.circular(8)),
          xl2: BorderRadius.all(Radius.circular(10)),
          xl3: BorderRadius.all(Radius.circular(12)),
        ),
        sizes: const FSizes(
          field: (xs: 24, sm: 32, md: 36, lg: 40),
          item: 26,
          tile: 34,
          calendar: 28,
        ),
        pagePadding: const EdgeInsetsDelta.value(
          EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        ),
        shadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      );
  return FThemeData(
    debugLabel: 'Flutter Scene Editor Dark',
    colors: colors,
    typography: typography,
    style: style,
    touch: false,
  );
}

/// Provides the editor's Forui theme and overlay services.
class EditorThemeScope extends StatelessWidget {
  const EditorThemeScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FTheme(
      data: editorForuiDarkTheme,
      child: FToaster(child: FTooltipGroup(child: child)),
    );
  }
}

/// The editor's compact dark Material compatibility theme.
///
/// Existing shell and viewport widgets keep using Material while controls move
/// behind the editor's Forui-backed component layer.
ThemeData editorDarkTheme() {
  final base = editorForuiDarkTheme.toApproximateMaterialTheme();
  return base.copyWith(
    // The Forui approximation maps tertiary to a near-background shade,
    // which made prefab-member rows unreadable.
    colorScheme: base.colorScheme.copyWith(
      tertiary: _prefabTint,
      tertiaryContainer: _prefabShade,
      onTertiaryContainer: _text,
    ),
    visualDensity: VisualDensity.compact,
    splashFactory: InkSparkle.splashFactory,
    scaffoldBackgroundColor: _ink,
    canvasColor: _graphite,
    dividerColor: _line,
    tooltipTheme: const TooltipThemeData(
      waitDuration: Duration(milliseconds: 500),
    ),
    // One density for every menu surface. The standard visual density opts
    // menu items out of the global compact density, which would otherwise
    // shrink them below editorMenuItemHeight.
    menuTheme: const MenuThemeData(
      style: MenuStyle(
        padding: WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 4)),
      ),
    ),
    menuButtonTheme: const MenuButtonThemeData(
      style: ButtonStyle(
        minimumSize: WidgetStatePropertyAll(Size(0, editorMenuItemHeight)),
        padding: WidgetStatePropertyAll(editorMenuItemPadding),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.standard,
        textStyle: WidgetStatePropertyAll(editorMenuItemText),
      ),
    ),
    popupMenuTheme: const PopupMenuThemeData(
      menuPadding: EdgeInsets.symmetric(vertical: 4),
      textStyle: TextStyle(fontSize: 12, color: _text),
    ),
  );
}
