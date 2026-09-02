/// Reusable inspector field widgets that preview continuously while the user
/// drags and commit one undoable value on release: [LiveSlider] and the inline
/// [ColorEditor] (RGBA + HSV).
library;

import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../shell/editor_theme.dart';
import '../shell/panel_chrome.dart';

/// Keeps inspector labels and values on one line unless a child opts out.
class InspectorTextScope extends StatelessWidget {
  const InspectorTextScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => DefaultTextStyle.merge(
    maxLines: 1,
    softWrap: false,
    overflow: TextOverflow.ellipsis,
    child: child,
  );
}

/// Inspector copy that may wrap because it explains a property or state.
class InspectorDescriptionText extends StatelessWidget {
  const InspectorDescriptionText(this.data, {super.key, this.style});

  final String data;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final inherited = DefaultTextStyle.of(context);
    return DefaultTextStyle(
      style: inherited.style,
      textAlign: inherited.textAlign,
      softWrap: true,
      overflow: TextOverflow.visible,
      maxLines: null,
      textWidthBasis: inherited.textWidthBasis,
      textHeightBehavior: inherited.textHeightBehavior,
      child: Text(data, style: style),
    );
  }
}

/// A compact Forui slider that maps an arbitrary numeric range to the
/// normalized value used by [FSlider].
class InspectorSlider extends StatelessWidget {
  const InspectorSlider({
    super.key,
    required this.value,
    this.min = 0,
    this.max = 1,
    required this.onChanged,
    this.onChangeEnd,
  }) : assert(max > min);

  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;

  double _fromUnit(double value) => min + value * (max - min);

  @override
  Widget build(BuildContext context) {
    final unit = ((value - min) / (max - min)).clamp(0.0, 1.0);
    // Sized down rather than boxed in. Left at its defaults the slider lays
    // out nearly twice as tall as every other control, which turns a run of
    // numeric properties into a run of rows that pitch differently from the
    // rest of the panel; forcing it into a short box instead only clips it,
    // so the thumb and the track are what shrink.
    return FSlider(
      style: const FSliderStyleDelta.delta(thumbSize: 13, crossAxisExtent: 4),
      control: FSliderControl.liftedContinuous(
        value: FSliderValue(max: unit),
        onChange: (value) => onChanged(_fromUnit(value.max)),
      ),
      tooltipBuilder: (_, value) =>
          Text(_fromUnit(value).toStringAsFixed(max >= 100 ? 0 : 2)),
      semanticValueFormatterCallback: (value) =>
          _fromUnit(value).toStringAsFixed(2),
      onEnd: onChangeEnd == null
          ? null
          : (value) => onChangeEnd!(_fromUnit(value.max)),
    );
  }
}

/// A compact inspector row backed by Forui's switch implementation.
class InspectorSwitch extends StatelessWidget {
  const InspectorSwitch({
    super.key,
    required this.label,
    this.description,
    required this.value,
    required this.onChanged,
    this.padding = EdgeInsets.zero,
  });

  final String label;
  final String? description;
  final bool value;
  final ValueChanged<bool> onChanged;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
                if (description case final description?)
                  InspectorDescriptionText(
                    description,
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          InspectorToggleSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

/// A compact desktop toggle built on Forui's interaction layer.
class InspectorToggleSwitch extends StatelessWidget {
  const InspectorToggleSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return FTappable(
      selected: value,
      semanticsButton: false,
      semanticsChecked: value,
      semanticsLabel: value ? 'On' : 'Off',
      onPress: () => onChanged(!value),
      builder: (context, variants, _) {
        final colors = context.theme.colors;
        final interactive =
            variants.contains(FTappableVariant.hovered) ||
            variants.contains(FTappableVariant.focused) ||
            variants.contains(FTappableVariant.pressed);
        return AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          width: 44,
          height: 22,
          decoration: BoxDecoration(
            color: value
                ? colors.primary.withValues(alpha: 0.16)
                : colors.secondary,
            border: Border.all(
              color: value || interactive ? colors.primary : colors.border,
            ),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Row(
            children: [
              Container(
                width: 4,
                height: double.infinity,
                color: value ? colors.primary : colors.border,
              ),
              Expanded(
                child: Center(
                  child: Text(
                    value ? 'ON' : 'OFF',
                    style: TextStyle(
                      color: value ? colors.primary : colors.mutedForeground,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// One titled section in an [InspectorAccordion].
class InspectorAccordionItem {
  const InspectorAccordionItem({
    required this.title,
    required this.child,
    this.enabled,
    this.trailing,
  });

  /// The heading, spelled by the accordion rather than by the caller: a panel
  /// where one section is Title Case and the next is CAPS reads as two
  /// panels.

  final String title;

  /// Non-null draws the on/off state a section can be switched by: a dot
  /// before the name and a word after it. Null is a section that is simply
  /// open or closed.
  final bool? enabled;

  /// Anything else the header carries, at its right.
  final Widget? trailing;
  final Widget child;
}

/// A desktop inspector accordion with persistent expansion state.
class InspectorAccordion extends StatefulWidget {
  const InspectorAccordion({
    super.key,
    required this.children,
    this.initiallyExpanded = const {},
    this.identity,
  });

  final List<InspectorAccordionItem> children;
  final Set<int> initiallyExpanded;

  /// Resets expansion when the inspected object changes.
  final Object? identity;

  @override
  State<InspectorAccordion> createState() => _InspectorAccordionState();
}

class _InspectorAccordionState extends State<InspectorAccordion> {
  late Set<int> _expanded = Set.of(widget.initiallyExpanded);

  @override
  void didUpdateWidget(InspectorAccordion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identity != widget.identity) {
      _expanded = Set.of(widget.initiallyExpanded);
    } else {
      _expanded.removeWhere((index) => index >= widget.children.length);
    }
  }

  void _toggle(int index) => setState(() {
    if (!_expanded.remove(index)) _expanded.add(index);
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final (index, item) in widget.children.indexed)
        _InspectorAccordionSection(
          title: item.title,
          enabled: item.enabled,
          trailing: item.trailing,
          expanded: _expanded.contains(index),
          onToggle: () => _toggle(index),
          child: item.child,
        ),
    ],
  );
}

class _InspectorAccordionSection extends StatelessWidget {
  const _InspectorAccordionSection({
    required this.title,
    required this.expanded,
    required this.onToggle,
    required this.child,
    this.enabled,
    this.trailing,
  });

  final bool? enabled;
  final Widget? trailing;

  final String title;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FTappable(
          selected: expanded,
          semanticsExpanded: expanded,
          onPress: onToggle,
          builder: (context, variants, _) {
            final highlighted =
                variants.contains(FTappableVariant.hovered) ||
                variants.contains(FTappableVariant.pressed);
            return AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              height: 24,
              margin: const EdgeInsets.only(top: 6),
              color: highlighted ? editorRaisedColor : Colors.transparent,
              padding: const EdgeInsets.only(left: 4, right: 8),
              child: Row(
                children: [
                  Icon(
                    expanded ? Icons.arrow_drop_down : Icons.arrow_right,
                    size: 16,
                    color: editorMutedTextColor,
                  ),
                  const SizedBox(width: 2),
                  if (enabled case final on?) ...[
                    Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: on ? editorAccentColor : editorMutedTextColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 7),
                  ],
                  Expanded(
                    child: Text(
                      title.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: editorTextColor,
                        fontSize: 10.5,
                        height: 1.1,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.9,
                      ),
                    ),
                  ),
                  if (enabled case final on?)
                    Text(
                      on ? 'ON' : 'OFF',
                      style: TextStyle(
                        color: on ? editorAccentColor : editorMutedTextColor,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.7,
                      ),
                    ),
                  if (trailing case final trailing?) trailing,
                ],
              ),
            );
          },
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: expanded
              // No inset of its own: a group's rows line up with the rows
              // above it rather than stepping in, so the label column stays
              // one column down the whole panel.
              ? Padding(
                  padding: const EdgeInsets.only(
                    top: editorHeadingGapBelow,
                    bottom: 8,
                  ),
                  child: child,
                )
              : const SizedBox.shrink(),
        ),
        ColoredBox(color: colors.border, child: const SizedBox(height: 1)),
      ],
    );
  }
}

/// A slider that calls [onPreview] on every change (live, no undo step) and
/// [onCommit] once when the drag ends (one undo step).
class LiveSlider extends StatefulWidget {
  const LiveSlider({
    super.key,
    required this.label,
    required this.value,
    this.min = 0,
    this.max = 1,
    required this.onPreview,
    required this.onCommit,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onPreview;
  final ValueChanged<double> onCommit;

  @override
  State<LiveSlider> createState() => _LiveSliderState();
}

class _LiveSliderState extends State<LiveSlider> {
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final value = (_dragging ?? widget.value).clamp(widget.min, widget.max);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(widget.label, style: const TextStyle(fontSize: 13)),
              ),
              Text(value.toStringAsFixed(2)),
            ],
          ),
          const SizedBox(height: 4),
          InspectorSlider(
            value: value,
            min: widget.min,
            max: widget.max,
            onChanged: (v) {
              setState(() => _dragging = v);
              widget.onPreview(v);
            },
            onChangeEnd: (v) {
              setState(() => _dragging = null);
              widget.onCommit(v);
            },
          ),
        ],
      ),
    );
  }
}

/// An inline, expandable linear-RGBA color editor with both RGBA and HSV
/// sliders (kept in sync). [onPreview] fires live while dragging; [onCommit]
/// fires once on release.
typedef ColorChannelBuilder =
    Widget Function({
      required String label,
      required double value,
      required double min,
      required double max,
      required ValueChanged<double> onPreview,
      required ValueChanged<double> onCommit,
    });

class ColorEditor extends StatefulWidget {
  const ColorEditor({
    super.key,
    required this.label,
    required this.r,
    required this.g,
    required this.b,
    required this.a,
    required this.onPreview,
    required this.onCommit,
    this.channelMax = 1.0,
    this.showAlpha = true,
    this.channelBuilder,
    this.mixed = false,
  });

  final String label;
  final double r;
  final double g;
  final double b;
  final double a;
  final void Function(double r, double g, double b, double a) onPreview;
  final void Function(double r, double g, double b, double a) onCommit;

  /// Upper bound of the R/G/B (and HSV value) sliders. Raise above `1.0` for
  /// HDR colors whose channels exceed display white.
  final double channelMax;

  /// Whether to show the alpha slider. Off for opaque colors (a sky tint).
  final bool showAlpha;

  /// Optional compact numeric editor used instead of a read-only value.
  final ColorChannelBuilder? channelBuilder;

  /// A multi-selection whose colors disagree; the editor still seeds from
  /// the given channels and a commit applies to the whole selection.
  /// TODO(multi-mixed-color): dash the channel readouts until edited.
  final bool mixed;

  @override
  State<ColorEditor> createState() => _ColorEditorState();
}

class _ColorEditorState extends State<ColorEditor> {
  late double _r = widget.r;
  late double _g = widget.g;
  late double _b = widget.b;
  late double _a = widget.a;
  bool _expanded = false;
  bool _editing = false;

  @override
  void didUpdateWidget(ColorEditor old) {
    super.didUpdateWidget(old);
    // Sync from an external change (e.g. undo) when not actively dragging.
    if (!_editing) {
      _r = widget.r;
      _g = widget.g;
      _b = widget.b;
      _a = widget.a;
    }
  }

  Color get _swatch => Color.fromARGB(
    (_a.clamp(0.0, 1.0) * 255).round(),
    (_r.clamp(0.0, 1.0) * 255).round(),
    (_g.clamp(0.0, 1.0) * 255).round(),
    (_b.clamp(0.0, 1.0) * 255).round(),
  );

  void _preview() => widget.onPreview(_r, _g, _b, _a);
  void _commit() => widget.onCommit(_r, _g, _b, _a);

  // A channel slider: live preview on change, one commit on release.
  Widget _slider(
    String name,
    double value,
    double max,
    ValueChanged<double> set,
  ) {
    final builder = widget.channelBuilder;
    if (builder != null) {
      return builder(
        label: name,
        value: value,
        min: 0,
        max: max,
        onPreview: (value) {
          setState(() {
            _editing = true;
            set(value);
          });
          _preview();
        },
        onCommit: (value) {
          setState(() {
            _editing = false;
            set(value);
          });
          _commit();
        },
      );
    }
    return Row(
      children: [
        SizedBox(
          width: 18,
          child: Text(name, style: const TextStyle(fontSize: 12)),
        ),
        Expanded(
          child: InspectorSlider(
            value: value.clamp(0.0, max),
            max: max,
            onChanged: (v) {
              setState(() {
                _editing = true;
                set(v);
              });
              _preview();
            },
            onChangeEnd: (_) {
              _editing = false;
              _commit();
            },
          ),
        ),
        SizedBox(
          width: 38,
          child: Text(
            // Hue runs 0..360 and reads better as a whole number; channel and
            // value sliders keep two decimals even when HDR-scaled.
            max >= 100 ? value.toStringAsFixed(0) : value.toStringAsFixed(2),
            style: const TextStyle(fontSize: 11),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final hsv = _rgbToHsv(_r, _g, _b);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The label in the shared column and the swatch at the head of the
        // value column, like every other row: a colour is a property, not a
        // section, and it should not read as one.
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: SizedBox(
            height: editorPropertyRowHeight,
            child: Row(
              children: [
                SizedBox(
                  width: editorPropertyLabelWidth,
                  child: Text(
                    widget.label,
                    style: editorRowLabelText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: editorRowGutter),
                Container(
                  width: 34,
                  height: 14,
                  decoration: BoxDecoration(
                    color: _swatch,
                    border: Border.all(color: editorLineColor),
                    borderRadius: BorderRadius.circular(editorFieldRadius),
                  ),
                ),
                Icon(
                  _expanded ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                  size: editorIconSizeLarge,
                  color: editorMutedTextColor,
                ),
              ],
            ),
          ),
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 8),
            child: Column(
              children: [
                _slider('R', _r, widget.channelMax, (v) => _r = v),
                _slider('G', _g, widget.channelMax, (v) => _g = v),
                _slider('B', _b, widget.channelMax, (v) => _b = v),
                if (widget.showAlpha) _slider('A', _a, 1, (v) => _a = v),
                const Divider(height: 8),
                _slider('H', hsv[0], 360, (v) => _setHsv(v, hsv[1], hsv[2])),
                _slider('S', hsv[1], 1, (v) => _setHsv(hsv[0], v, hsv[2])),
                _slider(
                  'V',
                  hsv[2],
                  widget.channelMax,
                  (v) => _setHsv(hsv[0], hsv[1], v),
                ),
              ],
            ),
          ),
      ],
    );
  }

  void _setHsv(double h, double s, double v) {
    final rgb = _hsvToRgb(h, s, v);
    _r = rgb[0];
    _g = rgb[1];
    _b = rgb[2];
  }
}

// Linear-RGB <-> HSV on 0..1 doubles (h in 0..360). Editing the linear color in
// HSV is a convenience; it operates on the linear channel values directly.
List<double> _rgbToHsv(double r, double g, double b) {
  final maxC = [r, g, b].reduce((a, b) => a > b ? a : b);
  final minC = [r, g, b].reduce((a, b) => a < b ? a : b);
  final d = maxC - minC;
  double h;
  if (d == 0) {
    h = 0;
  } else if (maxC == r) {
    h = 60 * (((g - b) / d) % 6);
  } else if (maxC == g) {
    h = 60 * ((b - r) / d + 2);
  } else {
    h = 60 * ((r - g) / d + 4);
  }
  if (h < 0) h += 360;
  final s = maxC == 0 ? 0.0 : d / maxC;
  return [h, s, maxC];
}

List<double> _hsvToRgb(double h, double s, double v) {
  final c = v * s;
  final x = c * (1 - ((h / 60) % 2 - 1).abs());
  final m = v - c;
  double r, g, b;
  if (h < 60) {
    (r, g, b) = (c, x, 0);
  } else if (h < 120) {
    (r, g, b) = (x, c, 0);
  } else if (h < 180) {
    (r, g, b) = (0, c, x);
  } else if (h < 240) {
    (r, g, b) = (0, x, c);
  } else if (h < 300) {
    (r, g, b) = (x, 0, c);
  } else {
    (r, g, b) = (c, 0, x);
  }
  return [r + m, g + m, b + m];
}
