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

/// Panel and dialog chrome tokens, so dialogs (settings, build
/// configurations, managed checkouts) match the docked panels' look instead
/// of falling back to approximated Material colors (whose outlineVariant
/// reads near-white against this palette).
const Color editorSurfaceColor = _ink;
const Color editorPanelColor = _graphite;
const Color editorRaisedColor = _raised;
const Color editorLineColor = _line;
const Color editorTextColor = _text;
const Color editorMutedTextColor = _mutedText;
const Color editorAccentColor = _signal;

/// Status accents for error and success text/borders, readable on the panel
/// palette; use these over ad-hoc reds and greens.
const Color editorErrorColor = Color(0xFFE57373);
const Color editorSuccessColor = Color(0xFF7BC67E);

/// Something that needs attention but is not broken: an unused resource, a
/// toolchain the build will limp along without.
const Color editorWarningColor = Color(0xFFE0A84E);

/// The bordered-box chrome panel lists and detail panes share.
BoxDecoration editorPanelBox({Color color = _graphite}) => BoxDecoration(
  color: color,
  border: Border.all(color: _line),
  borderRadius: BorderRadius.circular(5),
);

/// Dialog text metrics matching the inspector's rows.
const TextStyle editorDialogTitleText = TextStyle(
  fontSize: 15,
  fontWeight: FontWeight.w600,
);

/// The editor's type ramp. Four steps, and nothing between them: a panel
/// reads as part of one program when every label at the same level is the
/// same size, and stops when three dialogs pick three different title sizes.
///
/// micro (9) dense hints and axis letters, detail (11) secondary text,
/// body (12) the default, subhead (13) a group heading inside a panel, and
/// [editorDialogTitleText] (15) the title of a dialog or a panel.
const TextStyle editorBodyText = TextStyle(fontSize: 12);

/// A group heading inside a panel.
const TextStyle editorSubheadText = TextStyle(
  fontSize: 13,
  fontWeight: FontWeight.w600,
);

/// The smallest readable label: an axis letter, a unit, a count.
const TextStyle editorMicroText = TextStyle(fontSize: 9, color: _mutedText);
const TextStyle editorDetailText = TextStyle(fontSize: 11, color: _mutedText);

/// The accent-barred section header the inspector's sections use, shared so
/// dialog sections read as the same chrome.
class EditorSectionHeader extends StatelessWidget {
  const EditorSectionHeader({super.key, required this.label, this.trailing});

  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 5, top: 2),
      padding: const EdgeInsets.fromLTRB(7, 4, 2, 4),
      decoration: const BoxDecoration(
        border: Border(
          left: BorderSide(color: _signal, width: 2),
          bottom: BorderSide(color: _line),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.15,
                color: _text,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

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
