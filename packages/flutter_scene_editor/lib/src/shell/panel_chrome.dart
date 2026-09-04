/// The editor's panel grammar: one header shape, one section shape, one
/// property row, one icon button.
///
/// Every docked surface is built from these, and that is the whole point. A
/// panel list reads as one program when the header is the same height in each
/// region, the labels line up down a single column, and nothing draws a box
/// around itself; it stops reading that way the moment one panel picks its own
/// padding. The reference editor is not clean because of what it contains --
/// it is clean because it contains six shapes and no others.
///
/// The rules these encode, so they can be checked rather than remembered:
///
/// * a region header is [editorHeaderHeight] and carries a marker, a name in
///   uppercase, and its actions inline;
/// * a property row is [editorPropertyRowHeight] with a fixed
///   [editorPropertyLabelWidth] label column, and labels take no colon;
/// * docked chrome has no corner radius and no shadow -- regions are told
///   apart by a single hairline, which is what keeps a dense panel quiet;
/// * four type sizes, and the accent means either "selected" or "you can edit
///   this", never a third thing.
library;

import 'package:flutter/material.dart';

import 'editor_theme.dart';

/// The height of a region header, and of the top strip beside it.
///
/// 28 rather than the 24 a pure text header would want: the viewport's header
/// carries dropdowns and the transport, and those are the widest thing the
/// band has to hold. One band height across every region is worth more than
/// four pixels, because the alignment across the top of the window is most of
/// what reads as clean.
const double editorHeaderHeight = 28;

/// The height of one property row.
const double editorPropertyRowHeight = 22;

/// The width of the label column every property row shares.
///
/// Wide enough for two words at eleven pixels. Property names longer than
/// that ellipsize and carry a tooltip: widening the column far enough for
/// "Shadow Cascade Distribution Exponent" would take the panel's width away
/// from every value in it to spell out one of them.
const double editorPropertyLabelWidth = 104;

/// The side of a bare icon button in panel chrome.
const double editorPanelIconButtonSize = 20;

/// The width of the tool rail down the left edge.
///
/// Wider than the panels' own controls, and deliberately: the rail is the
/// window's only chrome now, its buttons are the ones you hit dozens of times
/// an hour without looking, and a 20-pixel icon in a 44-pixel target is what
/// makes that possible.
const double editorRailWidth = 56;

/// The height of one rail button.
const double editorRailButtonHeight = 44;

/// The icon inside a rail button.
const double editorRailIconSize = 20;

/// The hover and active pill drawn behind a rail icon.
const double editorRailPillWidth = 40;
const double editorRailPillHeight = 36;
const double editorRailPillRadius = 10;

/// Horizontal padding inside a panel body.
///
/// Everything a panel holds starts here and ends here: headings, rows,
/// buttons, and the paragraphs that explain them. A block that adds its own
/// inset on top ends up a few pixels in from the rest, which is the specific
/// thing that makes a panel look assembled rather than laid out.
const double editorPanelInset = 8;

/// The gap between a row's label and its control.
const double editorRowGutter = 6;

/// The air above and below a row, inside its pitch.
///
/// Dense is not the same as cramped. Four pixels either side of a 22-pixel
/// row is a 30-pixel pitch: close enough that a panel of thirty properties
/// still fits on a screen, far enough apart that two rows are two rows.
const double editorRowGap = 4;

/// The air above a heading, and below it before the first row it covers.
///
/// A heading with nothing under it reads as a label on the row beneath rather
/// than as the name of the block, which is the specific thing that made the
/// hairline and the colour swatch look like one control.
const double editorHeadingGapAbove = 14;
const double editorHeadingGapBelow = 7;

/// The height of an input: a text field, a number field, a dropdown.
///
/// One height for every input in the editor. A panel of thirty rows reads as
/// a list when they all measure the same, and as a pile when three of them
/// are a pixel or two taller because of what is inside them.
const double editorFieldHeight = 20;

/// How round an input is. Small enough to read as a recess rather than a pill.
const double editorFieldRadius = 3;

/// The height of a full-width action button (Add Component, Download).
const double editorActionButtonHeight = 24;

/// The uppercase label style shared by region headers and section headers.
const TextStyle editorHeaderText = TextStyle(
  fontSize: 10.5,
  height: 1.1,
  fontWeight: FontWeight.w600,
  letterSpacing: 0.9,
  color: editorTextColor,
);

/// A property row's label: the same size as [editorDetailText], and never
/// followed by a colon. The column is the separator.
const TextStyle editorRowLabelText = TextStyle(
  fontSize: 11,
  height: 1.1,
  color: editorMutedTextColor,
);

/// The header strip at the top of a region.
///
/// [marker] is the dot at the left. It is a colour rather than an icon on
/// purpose: at this size an icon is noise, and the dot is enough to tell one
/// header from the next while scanning down a window.
class EditorPanelHeader extends StatelessWidget {
  const EditorPanelHeader({
    super.key,
    required this.label,
    this.marker = editorAccentColor,
    this.actions = const [],
    this.leading,
    this.onCollapse,
    this.collapsed = false,
    this.collapseTooltip,
    this.leadingInset = 0,
  });

  final String label;
  final Color marker;

  /// Inline at the right, before the collapse control.
  final List<Widget> actions;

  /// Between the marker and the label, for a header that needs a control of
  /// its own (the shelf's mode picker sits here).
  final Widget? leading;

  /// Collapses the region. Null leaves the control out entirely rather than
  /// showing a dead one.
  final VoidCallback? onCollapse;
  final bool collapsed;
  final String? collapseTooltip;

  /// Space before the marker, for a host that draws its own window controls
  /// over the content. The window's top-left corner belongs to the rail and
  /// the first region now, not to a menu bar, so this is where that space is
  /// paid for.
  final double leadingInset;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: editorHeaderHeight,
      padding: const EdgeInsets.symmetric(horizontal: editorPanelInset),
      decoration: const BoxDecoration(
        color: editorPanelColor,
        border: Border(bottom: BorderSide(color: editorLineColor)),
      ),
      child: Row(
        children: [
          if (leadingInset > 0) SizedBox(width: leadingInset),
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: marker, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          if (leading != null) ...[leading!, const SizedBox(width: 7)],
          Expanded(
            child: Text(
              label.toUpperCase(),
              style: editorHeaderText,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          ...actions,
          if (onCollapse != null)
            EditorPanelIconButton(
              icon: collapsed
                  ? Icons.keyboard_arrow_down
                  : Icons.keyboard_arrow_up,
              tooltip: collapseTooltip ?? (collapsed ? 'Expand' : 'Collapse'),
              onPressed: onCollapse,
            ),
        ],
      ),
    );
  }
}

/// A bare icon button sized for panel chrome: no background until it is
/// hovered, and no ink splash spilling past its box.
class EditorPanelIconButton extends StatelessWidget {
  const EditorPanelIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
  });

  final IconData icon;
  final String tooltip;

  /// Null disables the button, and the tooltip is expected to say why.
  final VoidCallback? onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: SizedBox(
        width: editorPanelIconButtonSize,
        height: editorPanelIconButtonSize,
        child: InkWell(
          onTap: onPressed,
          hoverColor: editorRaisedColor,
          child: Icon(
            icon,
            size: editorIconSize,
            color: !enabled
                ? editorMutedTextColor.withValues(alpha: 0.45)
                : selected
                ? editorAccentColor
                : editorMutedTextColor,
          ),
        ),
      ),
    );
  }
}

/// A collapsible group inside a panel: a chevron, an uppercase name, a
/// hairline under it, and the contents flush to the panel's edges.
///
/// Flush and unboxed on purpose. An inspector is thirty of these stacked; give
/// each one a border and a radius and the eye counts boxes instead of reading
/// values.
class EditorPanelSection extends StatefulWidget {
  const EditorPanelSection({
    super.key,
    required this.title,
    required this.children,
    this.initiallyExpanded = true,
    this.trailing,
    this.onExpansionChanged,
  });

  final String title;
  final List<Widget> children;
  final bool initiallyExpanded;

  /// Inline at the right of the section header (a component's enable box, a
  /// section's overflow menu).
  final Widget? trailing;

  final ValueChanged<bool>? onExpansionChanged;

  @override
  State<EditorPanelSection> createState() => _EditorPanelSectionState();
}

class _EditorPanelSectionState extends State<EditorPanelSection> {
  late bool _expanded = widget.initiallyExpanded;

  void _toggle() {
    setState(() => _expanded = !_expanded);
    widget.onExpansionChanged?.call(_expanded);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: _toggle,
          child: Container(
            height: editorHeaderHeight - 4,
            padding: const EdgeInsets.only(left: 4, right: editorPanelInset),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: editorLineColor)),
            ),
            child: Row(
              children: [
                Icon(
                  _expanded ? Icons.arrow_drop_down : Icons.arrow_right,
                  size: editorIconSizeLarge,
                  color: editorMutedTextColor,
                ),
                const SizedBox(width: 2),
                Expanded(
                  child: Text(
                    widget.title.toUpperCase(),
                    style: editorHeaderText,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (widget.trailing != null) widget.trailing!,
              ],
            ),
          ),
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.only(
              top: editorHeadingGapBelow,
              bottom: 6,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: widget.children,
            ),
          ),
      ],
    );
  }
}

/// One labelled property: the label in the shared column, the control in the
/// rest of the width.
///
/// The label takes no colon and no trailing space. Two columns already say
/// which is the name and which is the value, and a colon on every row of a
/// dense panel is thirty pieces of punctuation doing nothing.
class EditorPropertyRow extends StatelessWidget {
  const EditorPropertyRow({
    super.key,
    required this.label,
    required this.child,
    this.tooltip,
    this.height = editorPropertyRowHeight,
  });

  final String label;
  final Widget child;

  /// What the label means, where the name alone does not carry it.
  final String? tooltip;

  /// For a control that genuinely needs more room (a colour picker, a curve).
  /// Rows stay on the standard height unless they cannot.
  final double height;

  @override
  Widget build(BuildContext context) {
    Widget name = Text(
      label,
      style: editorRowLabelText,
      overflow: TextOverflow.ellipsis,
    );
    if (tooltip != null) {
      name = Tooltip(message: tooltip!, child: name);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: editorPanelInset),
      child: SizedBox(
        height: height,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(width: editorPropertyLabelWidth, child: name),
            const SizedBox(width: editorRowGutter),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

/// The hairline between two regions, and the drag target that resizes them.
///
/// One pixel of line and eight of grab: a divider you can see is chrome, and a
/// divider you can hit is a control, and they do not have to be the same size.
class EditorRegionDivider extends StatelessWidget {
  const EditorRegionDivider({
    super.key,
    required this.axis,
    this.onDrag,
    this.onDragEnd,
  });

  /// The axis the divider runs along: vertical between two columns.
  final Axis axis;

  /// Called with the pointer delta in pixels along the resize direction.
  final ValueChanged<double>? onDrag;
  final VoidCallback? onDragEnd;

  @override
  Widget build(BuildContext context) {
    final vertical = axis == Axis.vertical;
    final line = Container(
      width: vertical ? 1 : null,
      height: vertical ? null : 1,
      color: editorLineColor,
    );
    if (onDrag == null) return line;
    return MouseRegion(
      cursor: vertical
          ? SystemMouseCursors.resizeLeftRight
          : SystemMouseCursors.resizeUpDown,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: vertical
            ? (details) => onDrag!(details.delta.dx)
            : null,
        onVerticalDragUpdate: vertical
            ? null
            : (details) => onDrag!(details.delta.dy),
        onHorizontalDragEnd: vertical ? (_) => onDragEnd?.call() : null,
        onVerticalDragEnd: vertical ? null : (_) => onDragEnd?.call(),
        child: SizedBox(
          width: vertical ? 7 : null,
          height: vertical ? null : 7,
          child: Center(child: line),
        ),
      ),
    );
  }
}

/// The body of a panel: a background, and nothing else.
///
/// Deliberately not [editorPanelBox], whose radius and border belong to
/// dialogs. A docked panel is not a card sitting on a surface; it is a region
/// of the window.
class EditorPanelBody extends StatelessWidget {
  const EditorPanelBody({super.key, required this.child, this.padded = false});

  final Widget child;
  final bool padded;

  @override
  Widget build(BuildContext context) => Container(
    color: editorSurfaceColor,
    padding: padded
        ? const EdgeInsets.symmetric(horizontal: editorPanelInset, vertical: 6)
        : EdgeInsets.zero,
    child: child,
  );
}

/// The one input shape: a filled recess in the panel, and a border that only
/// shows when the field is being used.
///
/// Every text field, number field, dropdown and swatch sits in one of these.
/// A resting field is a fill and nothing else -- thirty outlined boxes down a
/// panel is thirty rectangles competing with the values inside them -- and the
/// border arrives on hover and focus, where it is telling you something.
class EditorFieldSurface extends StatelessWidget {
  const EditorFieldSurface({
    super.key,
    required this.child,
    this.height = editorFieldHeight,
    this.hovered = false,
    this.active = false,
    this.accent,
    this.padding = const EdgeInsets.symmetric(horizontal: 6),
  });

  final Widget child;
  final double height;
  final bool hovered;

  /// Focused, being dragged, or otherwise the thing you are working in.
  final bool active;

  /// The border colour when active. Defaults to the selection accent; an axis
  /// field passes its own axis colour.
  final Color? accent;

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final tint = accent ?? editorAccentColor;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 90),
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: active
            ? editorRaisedColor
            : hovered
            ? Color.alphaBlend(tint.withValues(alpha: 0.06), editorRaisedColor)
            : editorRaisedColor,
        border: Border.all(
          color: active
              ? tint
              : hovered
              ? tint.withValues(alpha: 0.45)
              : Colors.transparent,
        ),
        borderRadius: BorderRadius.circular(editorFieldRadius),
      ),
      child: child,
    );
  }
}

/// A full-width action at the end of a block: Add Component, Download, Bake.
///
/// Full width because it acts on the block above it rather than on a row, and
/// a button that spans the panel says so without a label explaining it.
class EditorActionButton extends StatefulWidget {
  const EditorActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.tooltip,
  });

  final String label;

  /// Null disables the button; [tooltip] is expected to say why.
  final VoidCallback? onPressed;
  final IconData? icon;
  final String? tooltip;

  @override
  State<EditorActionButton> createState() => _EditorActionButtonState();
}

class _EditorActionButtonState extends State<EditorActionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    // A control that does something reads brighter than the text explaining
    // it. The old fill sat a shade off the panel and the label was the same
    // grey as the paragraph above it, which is how a button ends up looking
    // like a caption with a box round it.
    final foreground = enabled
        ? editorTextColor
        : editorMutedTextColor.withValues(alpha: 0.45);
    final button = MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        child: Container(
          height: editorActionButtonHeight,
          margin: const EdgeInsets.symmetric(
            horizontal: editorPanelInset,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: enabled && _hovered
                ? Color.alphaBlend(
                    editorAccentColor.withValues(alpha: 0.22),
                    editorRaisedColor,
                  )
                : editorRaisedColor,
            border: Border.all(
              color: enabled
                  ? (_hovered ? editorAccentColor : editorLineColor)
                  : editorLineColor.withValues(alpha: 0.5),
            ),
            borderRadius: BorderRadius.circular(editorFieldRadius),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: editorIconSize, color: foreground),
                const SizedBox(width: 6),
              ],
              Text(
                widget.label.toUpperCase(),
                style: editorHeaderText.copyWith(color: foreground),
              ),
            ],
          ),
        ),
      ),
    );
    return widget.tooltip == null
        ? button
        : Tooltip(message: widget.tooltip!, child: button);
  }
}

/// The one text input: a bare field inside [EditorFieldSurface].
///
/// Its own borders and paddings are gone, so a row holding text measures the
/// same as a row holding a number or a dropdown. It commits on submit and on
/// losing focus, which is what an inspector field has to do -- clicking away
/// from a half-typed name and losing it is the oldest bug in property panels.
class EditorTextField extends StatefulWidget {
  const EditorTextField({
    super.key,
    required this.controller,
    required this.onSubmit,
    this.focusNode,
    this.hint,
    this.commitOnFocusLoss = true,
    this.textStyle,
  });

  final TextEditingController controller;
  final ValueChanged<String> onSubmit;
  final FocusNode? focusNode;
  final String? hint;
  final bool commitOnFocusLoss;
  final TextStyle? textStyle;

  @override
  State<EditorTextField> createState() => _EditorTextFieldState();
}

class _EditorTextFieldState extends State<EditorTextField> {
  late final FocusNode _focus = widget.focusNode ?? FocusNode();
  bool _ownsFocus = false;
  bool _hovered = false;
  bool _focused = false;

  /// What was last handed to [EditorTextField.onSubmit].
  ///
  /// Submitting also drops focus, so without this every typed value would
  /// commit twice -- once for the return key and once for the field going
  /// quiet behind it -- and land two entries in the history for one edit.
  late String _committed;

  @override
  void initState() {
    super.initState();
    _ownsFocus = widget.focusNode == null;
    _committed = widget.controller.text;
    _focus.addListener(_onFocusChanged);
  }

  void _commit(String text) {
    if (text == _committed) return;
    _committed = text;
    widget.onSubmit(text);
  }

  void _onFocusChanged() {
    if (!mounted) return;
    setState(() => _focused = _focus.hasFocus);
    if (!_focus.hasFocus && widget.commitOnFocusLoss) {
      _commit(widget.controller.text);
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChanged);
    if (_ownsFocus) _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: EditorFieldSurface(
        hovered: _hovered,
        active: _focused,
        child: Center(
          child: TextField(
            controller: widget.controller,
            focusNode: _focus,
            decoration: InputDecoration.collapsed(
              hintText: widget.hint,
              hintStyle: editorRowLabelText,
            ),
            style:
                widget.textStyle ??
                const TextStyle(fontSize: 11, color: editorTextColor),
            cursorColor: editorAccentColor,
            cursorWidth: 1,
            autocorrect: false,
            enableSuggestions: false,
            onSubmitted: _commit,
          ),
        ),
      ),
    );
  }
}

/// Splits an identifier into words for display: `castsShadows` reads as
/// "Casts Shadows", `directionalLight` as "Directional Light".
///
/// Component types and schema property names are written for code, and an
/// inspector is read by a person. Nothing is renamed -- only the way it is
/// spelled on screen.
String humanizeIdentifier(String raw) {
  if (raw.isEmpty) return raw;
  final spaced = raw
      .replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]} ${m[2]}')
      .replaceAll('_', ' ')
      .replaceAll('-', ' ');
  return spaced[0].toUpperCase() + spaced.substring(1);
}

/// The one dropdown: a value in the shared field, and the platform's own menu
/// under it.
///
/// Material's bare [DropdownButton] draws an underline and its own baseline
/// spacing, which is why a panel that mixes it with the editor's fields reads
/// as two programs. This keeps the menu -- it is the one people already know
/// how to drive -- and puts the closed state in the same recess every other
/// value sits in.
class EditorDropdown<T> extends StatefulWidget {
  const EditorDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.width,
  });

  final T? value;
  final List<DropdownMenuItem<T>> items;

  /// Null disables the control, which Material draws as a dimmed value.
  final ValueChanged<T?>? onChanged;

  /// A dropdown that should not take the whole value column (a unit picker
  /// beside a number, say). By default it fills the column, so a panel of
  /// dropdowns has one right edge rather than one per longest option.
  final double? width;

  @override
  State<EditorDropdown<T>> createState() => _EditorDropdownState<T>();
}

class _EditorDropdownState<T> extends State<EditorDropdown<T>> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    // Measured rather than assumed. A dropdown in a property row has a column
    // to fill; one in a scrolling toolbar strip is laid out against unbounded
    // width, where asking for infinity -- or for an expanded child -- throws
    // from inside layout and takes the rest of the frame with it.
    return LayoutBuilder(
      builder: (context, constraints) =>
          _field(bounded: constraints.hasBoundedWidth),
    );
  }

  Widget _field({required bool bounded}) {
    final field = MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: EditorFieldSurface(
        hovered: _hovered && widget.onChanged != null,
        padding: const EdgeInsets.only(left: 6, right: 2),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            value: widget.value,
            items: widget.items,
            onChanged: widget.onChanged,
            isDense: true,
            isExpanded: bounded,
            focusColor: Colors.transparent,
            borderRadius: BorderRadius.circular(editorFieldRadius),
            dropdownColor: editorRaisedColor,
            icon: const Icon(Icons.arrow_drop_down, size: editorIconSizeLarge),
            iconEnabledColor: editorMutedTextColor,
            iconDisabledColor: editorMutedTextColor.withValues(alpha: 0.4),
            style: const TextStyle(fontSize: 11, color: editorTextColor),
            selectedItemBuilder: (context) => [
              for (final item in widget.items)
                Align(
                  alignment: Alignment.centerLeft,
                  child: DefaultTextStyle.merge(
                    style: const TextStyle(
                      fontSize: 11,
                      color: editorTextColor,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    child: item.child,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (widget.width case final width?) {
      return SizedBox(width: width, child: field);
    }
    return bounded ? SizedBox(width: double.infinity, child: field) : field;
  }
}

/// An explanation inside a panel: what a block is for, or why a control is
/// unavailable.
///
/// Wraps, unlike a label, and carries [editorPanelInset] like every other
/// block, so it starts where the rows, headings and buttons around it start. A
/// paragraph indented differently from the block it explains reads as a
/// different block -- which is exactly how these panels looked.
class EditorNote extends StatelessWidget {
  const EditorNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(
      left: editorPanelInset,
      right: editorPanelInset,
      bottom: 8,
      top: 2,
    ),
    child: DefaultTextStyle(
      style: const TextStyle(
        fontSize: 11,
        height: 1.35,
        color: editorNoteColor,
      ),
      softWrap: true,
      overflow: TextOverflow.visible,
      child: Text(text),
    ),
  );
}
