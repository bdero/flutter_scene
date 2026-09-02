import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

// A deep blue-violet rather than the neutral graphite this started as. The
// hue is doing work: a 3D viewport is full of neutral grey -- untextured
// geometry, the grid, gizmo shafts -- and chrome in the same neutral competes
// with it. Pushing the chrome off-neutral lets the scene keep the greys.
//
// The four surfaces step by roughly equal lightness so depth reads without
// borders doing all of it, and the line sits just above the raised surface so
// a border separates without drawing itself.
const _ink = Color(0xFF14152B);
const _graphite = Color(0xFF1B1D38);
const _raised = Color(0xFF262949);
const _line = Color(0xFF343863);
const _text = Color(0xFFE6E7F5);
const _mutedText = Color(0xFF8B8FB5);
const _signal = Color(0xFF4A9EFF);

/// A number you can edit, as opposed to one being reported.
///
/// Amber against the blue accent, which is the one pairing in this palette
/// that cannot be confused at a glance: an editable field and a selected
/// thing should never read alike, and every transform row is full of both.
const Color editorValueColor = Color(0xFFF0A742);

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

/// How round a card is.
///
/// Larger than the 5 this started at, which is the single change that most
/// separates chrome that looks drawn from chrome that looks assembled. Small
/// controls keep [editorControlRadius]: the same radius on a 20-pixel button
/// reads as a lozenge rather than a button.
const double editorCardRadius = 8;

/// How round a control is: a button, a field, a segment.
const double editorControlRadius = 4;

/// The bordered-box chrome panel lists and detail panes share.
BoxDecoration editorPanelBox({Color color = _graphite}) => BoxDecoration(
  color: color,
  border: Border.all(color: _line),
  borderRadius: BorderRadius.circular(editorCardRadius),
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

/// The heading above a group of rows, shared so dialogs read as the same
/// chrome as the panels.
///
/// Flush, uppercase, and separated by a hairline rather than by a bar and a
/// box. An inspector is thirty of these stacked: give each one a border, a
/// radius and an accent stripe and the eye counts blocks instead of reading
/// values. The accent is spent on selection and on numbers you can drag, and
/// a heading is neither.
class EditorSectionHeader extends StatelessWidget {
  const EditorSectionHeader({super.key, required this.label, this.trailing});

  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 24,
      // Air above it, and air under the rule before the first row it covers.
      // Without the second, the rule and the row beneath it read as one
      // control with a line through it.
      margin: const EdgeInsets.only(top: 10, bottom: 5),
      padding: const EdgeInsets.only(left: 8, right: 4),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10.5,
                height: 1.1,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.9,
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
            // The same band, margins and rule as every other heading: a
            // section that folds is still a section, and a panel that spells
            // one heading three ways is a panel that reads as three panels.
            height: 24,
            margin: const EdgeInsets.only(top: 10, bottom: 5),
            padding: const EdgeInsets.only(left: 4, right: 4),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: _line)),
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
                    widget.label.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 10.5,
                      height: 1.1,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.9,
                      color: _text,
                    ),
                    maxLines: 1,
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
///
/// The no-flex rule is asserted rather than left to the reader. A stray
/// [Expanded] here throws from inside layout, and an exception thrown there
/// takes the rest of the frame's layout with it: every sibling panel is left
/// unlaid-out, and if the layout was running inside a mouse-tracker update it
/// leaves that tracker's debug flag latched, so every later pointer move
/// asserts too. The editor fills with thousands of exceptions naming neither
/// this widget nor the panel that supplied the child. Caught here it is one
/// error, at the call site, in plain words.
class EditorToolbarScroller extends StatelessWidget {
  const EditorToolbarScroller({
    super.key,
    required this.children,
    this.alignEnd = false,
  });

  final List<Widget> children;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    assert(() {
      final flexed = children.whereType<Flexible>().toList();
      if (flexed.isEmpty) return true;
      throw FlutterError.fromParts([
        ErrorSummary(
          'EditorToolbarScroller was given ${flexed.length} flex '
          '${flexed.length == 1 ? "child" : "children"}.',
        ),
        ErrorDescription(
          'This strip scrolls sideways, so its row is laid out against '
          'unbounded width. Expanded and Flexible ask to fill the space that '
          'is left over, and there is no such thing in unbounded width.',
        ),
        ErrorHint(
          'Give the child a width instead (a SizedBox), or, if it belongs '
          'against the right edge rather than in the scrolling run, pass it '
          "as the toolbar's trailing instead of its leading.",
        ),
      ]);
    }());

    return SingleChildScrollView(
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
    // Thin track, round handle, accent fill. Material's default slider is
    // built for a phone: at this density its handle covers the value it is
    // setting, and every inspector row is a slider beside its number.
    sliderTheme: SliderThemeData(
      trackHeight: 3,
      activeTrackColor: _signal,
      inactiveTrackColor: _raised,
      thumbColor: _signal,
      overlayColor: _signal.withValues(alpha: 0.14),
      thumbShape: const RoundSliderThumbShape(
        enabledThumbRadius: 6,
        pressedElevation: 0,
        elevation: 0,
      ),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
      trackShape: const RoundedRectSliderTrackShape(),
      showValueIndicator: ShowValueIndicator.never,
    ),
    // A switch small enough to sit at the right of a property row without
    // setting that row's height.
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? _text : _mutedText,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? _signal : _raised,
      ),
      trackOutlineColor: WidgetStatePropertyAll(_line),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: _ink,
      hintStyle: const TextStyle(fontSize: 11, color: _mutedText),
      contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(editorControlRadius),
        borderSide: const BorderSide(color: _line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(editorControlRadius),
        borderSide: const BorderSide(color: _line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(editorControlRadius),
        borderSide: const BorderSide(color: _signal),
      ),
    ),
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
