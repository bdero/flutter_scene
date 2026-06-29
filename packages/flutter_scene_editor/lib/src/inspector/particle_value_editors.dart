// Inspector widgets for the particle `distribution`, `curve`, and `gradient`
// property kinds. They decode the current value with the engine's helpers and
// emit plain Map/List values (which the command layer coerces back into the
// structured property value).
// ignore: implementation_imports
import 'package:flutter_scene/src/fscene/property_value.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/fscene/realize/particle_property_values.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/particles/distribution.dart';
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math.dart' show Vector4;

const _labelWidth = 90.0;
const _labelStyle = TextStyle(fontSize: 11);

// --- Distribution ---

/// Edits a scalar [FloatDistribution] property: a mode dropdown plus the fields
/// for the selected mode. Emits `{kind, ...}` on every change.
class DistributionField extends StatelessWidget {
  const DistributionField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final PropertyValue? value;
  final void Function(Object?) onChanged;

  @override
  Widget build(BuildContext context) {
    final dist = decodeFloatDistribution(value);
    final mode = switch (dist) {
      ConstantFloat() => 'constant',
      UniformFloat() => 'uniform',
      CurveFloat() => 'curve',
      UniformCurveFloat() => 'uniformCurve',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(
                width: _labelWidth,
                child: Text(label, style: _labelStyle),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _ModeDropdown(
                  value: mode,
                  options: const [
                    'constant',
                    'uniform',
                    'curve',
                    'uniformCurve',
                  ],
                  onChanged: (m) => onChanged(_seedForMode(m, dist)),
                ),
              ),
            ],
          ),
          ..._fieldsForMode(dist),
        ],
      ),
    );
  }

  List<Widget> _fieldsForMode(FloatDistribution dist) {
    switch (dist) {
      case ConstantFloat(:final value):
        return [
          _InlineNumber(
            label: 'value',
            value: value,
            onChanged: (v) => onChanged({'kind': 'constant', 'value': v}),
          ),
        ];
      case UniformFloat(:final min, :final max):
        return [
          _InlineNumber(
            label: 'min',
            value: min,
            onChanged: (v) =>
                onChanged({'kind': 'uniform', 'min': v, 'max': max}),
          ),
          _InlineNumber(
            label: 'max',
            value: max,
            onChanged: (v) =>
                onChanged({'kind': 'uniform', 'min': min, 'max': v}),
          ),
        ];
      case CurveFloat(:final curve, :final scale):
        return [
          _InlineNumber(
            label: 'scale',
            value: scale,
            onChanged: (v) => onChanged({
              'kind': 'curve',
              'curve': _curveToJson(curve),
              'scale': v,
            }),
          ),
          CurveEditor(
            label: 'curve',
            curve: curve,
            onChanged: (json) =>
                onChanged({'kind': 'curve', 'curve': json, 'scale': scale}),
          ),
        ];
      case UniformCurveFloat(:final min, :final max):
        return [
          CurveEditor(
            label: 'min',
            curve: min,
            onChanged: (json) => onChanged({
              'kind': 'uniformCurve',
              'min': json,
              'max': _curveToJson(max),
            }),
          ),
          CurveEditor(
            label: 'max',
            curve: max,
            onChanged: (json) => onChanged({
              'kind': 'uniformCurve',
              'min': _curveToJson(min),
              'max': json,
            }),
          ),
        ];
    }
  }

  // A reasonable starting value when the user switches modes, carrying the
  // current constant level across where it makes sense.
  Map<String, Object> _seedForMode(String mode, FloatDistribution from) {
    final level = switch (from) {
      ConstantFloat(:final value) => value,
      UniformFloat(:final max) => max,
      _ => 1.0,
    };
    return switch (mode) {
      'uniform' => {'kind': 'uniform', 'min': 0.0, 'max': level},
      'curve' => {
        'kind': 'curve',
        'curve': {
          'keys': [
            {'t': 0.0, 'v': level},
            {'t': 1.0, 'v': 0.0},
          ],
        },
        'scale': 1.0,
      },
      'uniformCurve' => {
        'kind': 'uniformCurve',
        'min': {
          'keys': [
            {'t': 0.0, 'v': 0.0},
            {'t': 1.0, 'v': 0.0},
          ],
        },
        'max': {
          'keys': [
            {'t': 0.0, 'v': level},
            {'t': 1.0, 'v': level},
          ],
        },
      },
      _ => {'kind': 'constant', 'value': level},
    };
  }
}

// --- Curve ---

/// Edits a [ParticleCurve] as a keyframe table with a live preview. Emits a
/// `{keys: [{t, v}, ...]}` map on every change.
class CurveEditor extends StatelessWidget {
  const CurveEditor({
    super.key,
    required this.label,
    required this.curve,
    required this.onChanged,
  });

  final String label;
  final ParticleCurve curve;
  final void Function(Map<String, Object>) onChanged;

  void _emit(List<ParticleKeyframe> keys) =>
      onChanged(_curveToJson(ParticleCurve(keys)));

  @override
  Widget build(BuildContext context) {
    final keys = curve.keyframes.toList();
    return Padding(
      padding: const EdgeInsets.only(left: 12, top: 2, bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(
                width: _labelWidth - 12,
                child: Text(label, style: _labelStyle),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: SizedBox(
                  height: 32,
                  child: CustomPaint(painter: _CurvePainter(curve)),
                ),
              ),
              _AddButton(
                tooltip: 'Add keyframe',
                onPressed: () =>
                    _emit([...keys, const ParticleKeyframe(0.5, 0.5)]),
              ),
            ],
          ),
          for (var i = 0; i < keys.length; i++)
            _KeyframeRow(
              t: keys[i].t,
              v: keys[i].value,
              onChanged: (t, v) {
                final next = keys.toList();
                next[i] = ParticleKeyframe(t, v);
                _emit(next);
              },
              onRemove: keys.length > 1
                  ? () => _emit([...keys]..removeAt(i))
                  : null,
            ),
        ],
      ),
    );
  }
}

/// A [CurveEditor] driven directly by a property [value] (decoding it to a
/// [ParticleCurve]), matching the `(label, value, onChanged)` shape the
/// inspector uses for the other particle kinds.
class CurveField extends StatelessWidget {
  const CurveField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final PropertyValue? value;
  final void Function(Object?) onChanged;

  @override
  Widget build(BuildContext context) => CurveEditor(
    label: label,
    curve: decodeParticleCurve(value),
    onChanged: onChanged,
  );
}

class _KeyframeRow extends StatelessWidget {
  const _KeyframeRow({
    required this.t,
    required this.v,
    required this.onChanged,
    required this.onRemove,
  });

  final double t;
  final double v;
  final void Function(double t, double v) onChanged;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 12, top: 1, bottom: 1),
      child: Row(
        children: [
          Expanded(
            child: _InlineNumber(
              label: 't',
              value: t,
              onChanged: (nt) => onChanged(nt, v),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _InlineNumber(
              label: 'v',
              value: v,
              onChanged: (nv) => onChanged(t, nv),
            ),
          ),
          _RemoveButton(onPressed: onRemove),
        ],
      ),
    );
  }
}

// --- Gradient ---

/// Edits a [ColorGradient] as a color-stop table with a live preview bar. Emits
/// a `{stops: [{t, color: {r, g, b, a}}, ...]}` map on every change.
class GradientEditor extends StatelessWidget {
  const GradientEditor({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final PropertyValue? value;
  final void Function(Object?) onChanged;

  void _emit(List<ColorStop> stops) =>
      onChanged(_gradientToJson(ColorGradient(stops)));

  @override
  Widget build(BuildContext context) {
    final gradient = decodeColorGradient(value);
    final stops = gradient.stops.toList();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(
                width: _labelWidth,
                child: Text(label, style: _labelStyle),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: SizedBox(
                  height: 18,
                  child: CustomPaint(painter: _GradientPainter(gradient)),
                ),
              ),
              _AddButton(
                tooltip: 'Add stop',
                onPressed: () =>
                    _emit([...stops, ColorStop(1.0, Vector4(1, 1, 1, 1))]),
              ),
            ],
          ),
          for (var i = 0; i < stops.length; i++)
            _StopRow(
              stop: stops[i],
              onChanged: (s) {
                final next = stops.toList();
                next[i] = s;
                _emit(next);
              },
              onRemove: stops.length > 1
                  ? () => _emit([...stops]..removeAt(i))
                  : null,
            ),
        ],
      ),
    );
  }
}

class _StopRow extends StatelessWidget {
  const _StopRow({
    required this.stop,
    required this.onChanged,
    required this.onRemove,
  });

  final ColorStop stop;
  final void Function(ColorStop) onChanged;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final c = stop.color;
    void emit({double? t, double? r, double? g, double? b, double? a}) {
      onChanged(
        ColorStop(t ?? stop.t, Vector4(r ?? c.x, g ?? c.y, b ?? c.z, a ?? c.w)),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(left: 12, top: 1, bottom: 1),
      child: Row(
        children: [
          SizedBox(
            width: 52,
            child: _InlineNumber(
              label: 't',
              value: stop.t,
              onChanged: (v) => emit(t: v),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(child: _Axis('R', c.x, (v) => emit(r: v))),
          Expanded(child: _Axis('G', c.y, (v) => emit(g: v))),
          Expanded(child: _Axis('B', c.z, (v) => emit(b: v))),
          Expanded(child: _Axis('A', c.w, (v) => emit(a: v))),
          _RemoveButton(onPressed: onRemove),
        ],
      ),
    );
  }
}

// --- Shared bits ---

Map<String, Object> _curveToJson(ParticleCurve curve) => {
  'keys': [
    for (final k in curve.keyframes) {'t': k.t, 'v': k.value},
  ],
};

Map<String, Object> _gradientToJson(ColorGradient gradient) => {
  'stops': [
    for (final s in gradient.stops)
      {
        't': s.t,
        'color': {
          'r': s.color.x,
          'g': s.color.y,
          'b': s.color.z,
          'a': s.color.w,
        },
      },
  ],
};

class _ModeDropdown extends StatelessWidget {
  const _ModeDropdown({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String value;
  final List<String> options;
  final void Function(String) onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 24,
      child: DropdownButton<String>(
        value: value,
        isExpanded: true,
        isDense: true,
        style: _labelStyle.copyWith(color: Theme.of(context).hintColor),
        items: [
          for (final o in options)
            DropdownMenuItem(
              value: o,
              child: Text(o, style: _labelStyle),
            ),
        ],
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }
}

class _InlineNumber extends StatefulWidget {
  const _InlineNumber({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final double value;
  final void Function(double) onChanged;

  @override
  State<_InlineNumber> createState() => _InlineNumberState();
}

class _InlineNumberState extends State<_InlineNumber> {
  late final TextEditingController _ctrl;
  late final FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value.toStringAsFixed(3));
    _focus = FocusNode()..addListener(_onFocus);
  }

  void _onFocus() {
    if (!_focus.hasFocus) _commit();
  }

  void _commit() {
    if (_ctrl.text == widget.value.toStringAsFixed(3)) return;
    final v = double.tryParse(_ctrl.text);
    if (v != null) widget.onChanged(v);
  }

  @override
  void didUpdateWidget(_InlineNumber old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value && !_focus.hasFocus) {
      _ctrl.text = widget.value.toStringAsFixed(3);
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 12, top: 1, bottom: 1),
      child: Row(
        children: [
          Text(
            widget.label,
            style: const TextStyle(fontSize: 9, color: Colors.grey),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: SizedBox(
              height: 22,
              child: TextField(
                controller: _ctrl,
                focusNode: _focus,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                style: const TextStyle(fontSize: 10),
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _commit(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Axis extends StatelessWidget {
  const _Axis(this.label, this.value, this.onChanged);
  final String label;
  final double value;
  final void Function(double) onChanged;

  @override
  Widget build(BuildContext context) =>
      _InlineNumber(label: label, value: value, onChanged: onChanged);
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.tooltip, required this.onPressed});
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.add, size: 14),
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
      padding: EdgeInsets.zero,
      onPressed: onPressed,
    );
  }
}

class _RemoveButton extends StatelessWidget {
  const _RemoveButton({required this.onPressed});
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.close, size: 13),
      tooltip: 'Remove',
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
      padding: EdgeInsets.zero,
      onPressed: onPressed,
    );
  }
}

class _CurvePainter extends CustomPainter {
  _CurvePainter(this.curve);
  final ParticleCurve curve;

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = Colors.black26;
    canvas.drawRect(Offset.zero & size, bg);

    // Sample the curve and map its observed range into the box.
    const samples = 48;
    final values = [
      for (var i = 0; i < samples; i++) curve.sample(i / (samples - 1)),
    ];
    var lo = values.reduce((a, b) => a < b ? a : b);
    var hi = values.reduce((a, b) => a > b ? a : b);
    if (hi - lo < 1e-6) {
      lo -= 0.5;
      hi += 0.5;
    }
    final path = Path();
    for (var i = 0; i < samples; i++) {
      final x = size.width * i / (samples - 1);
      final norm = (values[i] - lo) / (hi - lo);
      final y = size.height * (1 - norm);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.lightBlueAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_CurvePainter old) => !identical(old.curve, curve);
}

class _GradientPainter extends CustomPainter {
  _GradientPainter(this.gradient);
  final ColorGradient gradient;

  @override
  void paint(Canvas canvas, Size size) {
    // A checker so alpha reads, then the gradient composited over it.
    const cell = 6.0;
    for (var y = 0.0; y < size.height; y += cell) {
      for (var x = 0.0; x < size.width; x += cell) {
        final dark = (((x / cell).floor() + (y / cell).floor()) % 2) == 0;
        canvas.drawRect(
          Rect.fromLTWH(x, y, cell, cell),
          Paint()..color = dark ? Colors.grey.shade700 : Colors.grey.shade500,
        );
      }
    }
    const samples = 64;
    final out = Vector4.zero();
    for (var i = 0; i < samples; i++) {
      gradient.sample(i / (samples - 1), out);
      final x = size.width * i / (samples - 1);
      canvas.drawRect(
        Rect.fromLTWH(x, 0, size.width / samples + 1, size.height),
        Paint()
          ..color = Color.fromARGB(
            (out.w.clamp(0.0, 1.0) * 255).round(),
            (out.x.clamp(0.0, 1.0) * 255).round(),
            (out.y.clamp(0.0, 1.0) * 255).round(),
            (out.z.clamp(0.0, 1.0) * 255).round(),
          ),
      );
    }
  }

  @override
  bool shouldRepaint(_GradientPainter old) =>
      !identical(old.gradient, gradient);
}
