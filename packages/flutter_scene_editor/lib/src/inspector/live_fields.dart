/// Reusable inspector field widgets that preview continuously while the user
/// drags and commit one undoable value on release: [LiveSlider] and the inline
/// [ColorEditor] (RGBA + HSV).
library;

import 'package:flutter/material.dart';

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
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(widget.label, style: const TextStyle(fontSize: 13)),
      subtitle: Slider(
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
      trailing: Text(value.toStringAsFixed(2)),
    );
  }
}

/// An inline, expandable linear-RGBA color editor with both RGBA and HSV
/// sliders (kept in sync). [onPreview] fires live while dragging; [onCommit]
/// fires once on release.
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
  });

  final String label;
  final double r;
  final double g;
  final double b;
  final double a;
  final void Function(double r, double g, double b, double a) onPreview;
  final void Function(double r, double g, double b, double a) onCommit;

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
    return Row(
      children: [
        SizedBox(
          width: 18,
          child: Text(name, style: const TextStyle(fontSize: 12)),
        ),
        Expanded(
          child: Slider(
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
            max > 1 ? value.toStringAsFixed(0) : value.toStringAsFixed(2),
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
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(widget.label, style: const TextStyle(fontSize: 13)),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 28,
                height: 18,
                decoration: BoxDecoration(
                  color: _swatch,
                  border: Border.all(color: Theme.of(context).dividerColor),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              Icon(_expanded ? Icons.expand_less : Icons.expand_more, size: 18),
            ],
          ),
          onTap: () => setState(() => _expanded = !_expanded),
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 8),
            child: Column(
              children: [
                _slider('R', _r, 1, (v) => _r = v),
                _slider('G', _g, 1, (v) => _g = v),
                _slider('B', _b, 1, (v) => _b = v),
                _slider('A', _a, 1, (v) => _a = v),
                const Divider(height: 8),
                _slider('H', hsv[0], 360, (v) => _setHsv(v, hsv[1], hsv[2])),
                _slider('S', hsv[1], 1, (v) => _setHsv(hsv[0], v, hsv[2])),
                _slider('V', hsv[2], 1, (v) => _setHsv(hsv[0], hsv[1], v)),
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
