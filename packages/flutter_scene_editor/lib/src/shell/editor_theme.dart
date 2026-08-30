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
/// Icon sizes. Two steps: the default that sits beside body text, and the
/// larger one for a standalone affordance. Anything between them is variation
/// nobody chose, and a row of icons at 13, 14 and 15 reads as misaligned even
/// when it is not.
/// A section that folds away, with an optional enable toggle and icon in its
/// header.
///
/// An inspector is a stack of sections and only one or two matter at a time,
/// so being able to fold the rest is what keeps a node with eight components
/// readable. The whole header is the hit target, since a disclosure triangle
/// alone is a small thing to aim at repeatedly.
class EditorCollapsibleSection extends StatefulWidget {
  /// Creates a section titled [label] wrapping [child].
  const EditorCollapsibleSection({
    required this.label,
    required this.child,
    this.icon,
    this.enabled,
    this.onEnabledChanged,
    this.trailing,
    this.initiallyExpanded = true,
    super.key,
  });

  /// The section's title.
  final String label;

  /// The section's body, built only while expanded.
  final Widget child;

  /// An optional glyph shown before the label.
  final IconData? icon;

  /// The state of the header's checkbox, or null for no checkbox.
  final bool? enabled;

  /// Called when the header's checkbox is toggled.
  final ValueChanged<bool>? onEnabledChanged;

  /// Actions shown at the end of the header.
  final Widget? trailing;

  /// Whether the section starts open.
  final bool initiallyExpanded;

  @override
  State<EditorCollapsibleSection> createState() =>
      _EditorCollapsibleSectionState();
}

class _EditorCollapsibleSectionState extends State<EditorCollapsibleSection> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Container(
            margin: const EdgeInsets.only(bottom: 3, top: 2),
            padding: const EdgeInsets.fromLTRB(4, 4, 2, 4),
            decoration: const BoxDecoration(
              border: Border(
                left: BorderSide(color: _signal, width: 2),
                bottom: BorderSide(color: _line),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _expanded ? Icons.arrow_drop_down : Icons.arrow_right,
                  size: editorIconSizeLarge,
                  color: _mutedText,
                ),
                if (enabled != null)
                  SizedBox(
                    width: 22,
                    height: 18,
                    child: Checkbox(
                      value: enabled,
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onChanged: (value) =>
                          widget.onEnabledChanged?.call(value ?? false),
                    ),
                  ),
                if (widget.icon case final icon?) ...[
                  Icon(icon, size: editorIconSize, color: _mutedText),
                  const SizedBox(width: 5),
                ],
                Expanded(
                  child: Text(
                    widget.label,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.15,
                      color: _text,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (widget.trailing case final trailing?) trailing,
              ],
            ),
          ),
        ),
        // Built only while open: a folded section of thirty property editors
        // should cost nothing to have around.
        if (_expanded) widget.child,
      ],
    );
  }
}

const double editorIconSize = 14;

/// A standalone or emphasised icon: a toolbar button, an empty-state glyph.
const double editorIconSizeLarge = 16;

/// The height of a panel's toolbar strip, so strips line up across panels
/// sitting side by side.
///
/// Tall enough for the tallest control a strip carries, which is forui's
/// small text field at 32. At 30 the Assets filter overflowed its strip by
/// the two pixels of difference, and drew the framework's overflow stripes
/// across the panel header. `editor_theme_test.dart` pins the two together.
const double editorToolbarHeight = 32;

/// A panel's toolbar strip: a fixed-height row whose left half scrolls
/// sideways rather than overflowing.
///
/// A docked panel can be dragged down to a twentieth of the shell, and a
/// toolbar's controls do not shrink with it. Left as a plain [Row] the
/// Animation strip ran out of room first and painted the framework's overflow
/// stripes over its own buttons.
///
/// [leading] scrolls; [trailing] is pinned to the right edge and does not.
/// The split is explicit rather than a [Spacer] because the two halves are
/// laid out by different rules, and because the scrolling half must contain
/// no flex child: a horizontal scroll view offers unbounded width, and
/// `Expanded` in unbounded width is an error.
///
/// This deliberately does **not** measure the row. It used to, with
/// [IntrinsicWidth], which reads beautifully until a child contains a
/// [LayoutBuilder] -- and then it throws "LayoutBuilder does not support
/// returning intrinsic dimensions" from inside layout. Thrown there it takes
/// the frame with it, and if the layout was running inside a mouse-tracker
/// update it leaves that tracker's debug flag latched, so every later pointer
/// move asserts too. One unmeasurable child, and the editor fills with
/// exceptions that name neither the widget nor the cause.
class EditorToolbar extends StatelessWidget {
  const EditorToolbar({
    super.key,
    this.leading = const [],
    this.trailing = const [],
    this.horizontalPadding = 8,
    this.height,
    this.color,
  });

  /// The controls at the left, which scroll when there is no room for them.
  ///
  /// Must contain no [Expanded] or [Spacer]; put anything that was pinned
  /// right into [trailing] instead.
  final List<Widget> leading;

  /// The controls pinned to the right edge.
  final List<Widget> trailing;

  /// Inset at each end of the strip.
  final double horizontalPadding;

  /// Defaults to [editorToolbarHeight]. The menu bar is its own height.
  final double? height;

  /// Defaults to the panel-header fill.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height ?? editorToolbarHeight,
      color: color ?? Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      child: Row(
        children: [
          Expanded(child: EditorToolbarScroller(children: leading)),
          ...trailing,
        ],
      ),
    );
  }
}

/// A run of controls that scrolls sideways rather than overflowing.
///
/// The child row is [MainAxisSize.min] and must hold no flex child, which is
/// what makes it safe inside a scroll view's unbounded width. [alignEnd]
/// starts it against the right edge, for a group that sits at one.
class EditorToolbarScroller extends StatelessWidget {
  const EditorToolbarScroller({
    super.key,
    required this.children,
    this.alignEnd = false,
  });

  final List<Widget> children;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    primary: false,
    // Reversed rather than aligned: a scroll view fills its viewport in the
    // scroll direction, so alignment inside it does nothing, while reversing
    // puts the content against the far edge and scrolls the right way when
    // there is too much of it.
    reverse: alignEnd,
    child: Row(mainAxisSize: MainAxisSize.min, children: children),
  );
}

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
