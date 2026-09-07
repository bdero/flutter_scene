import 'dart:async';

// ignore: implementation_imports
import 'package:scene/scene.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_scene_editor_core/flutter_scene_editor_core.dart';
import 'package:forui/forui.dart';
import 'package:native_mouse_cursor/native_mouse_cursor.dart';

import 'live_fields.dart';
import '../shell/editor_theme.dart';
import '../shell/panel_chrome.dart';

/// A single editable field driven by a [UiFieldDescriptor].
///
/// Switching on [UiFieldDescriptor.type] to render the right input widget.
/// On commit the caller-supplied [onChanged] receives the typed value
/// (String/bool/int/double/Map) matching the type.
class PropertyField extends StatelessWidget {
  const PropertyField({
    super.key,
    required this.descriptor,
    required this.currentValue,
    required this.onChanged,
  });

  final UiFieldDescriptor descriptor;

  /// The current raw value from the document (a [PropertyValue] or null).
  final PropertyValue? currentValue;

  /// Called with the new typed value ready to pass to a command.
  final void Function(Object? value) onChanged;

  // The seed when the document has no explicit value: the field's declared
  // default (from the component schema), never a guessed zero/empty, so an
  // unset field shows the value the engine actually uses.
  double get _numberDefault =>
      (descriptor.defaultValue as num?)?.toDouble() ?? 0.0;

  @override
  Widget build(BuildContext context) {
    return switch (descriptor.type) {
      ParamType.string => _StringField(
        label: descriptor.label,
        initial: currentValue is StringValue
            ? (currentValue as StringValue).value
            : (descriptor.defaultValue as String? ?? ''),
        onSubmit: onChanged,
      ),
      ParamType.boolean => _BoolField(
        label: descriptor.label,
        initial: currentValue is BoolValue
            ? (currentValue as BoolValue).value
            : (descriptor.defaultValue as bool? ?? false),
        onChanged: onChanged,
      ),
      ParamType.integer => _NumberField(
        label: descriptor.label,
        initial: currentValue is IntValue
            ? (currentValue as IntValue).value.toDouble()
            : _numberDefault,
        isInt: true,
        onSubmit: onChanged,
      ),
      ParamType.number => _NumberField(
        label: descriptor.label,
        initial: currentValue is DoubleValue
            ? (currentValue as DoubleValue).value
            : _numberDefault,
        isInt: false,
        onSubmit: onChanged,
      ),
      _ => Padding(
        padding: const EdgeInsets.symmetric(vertical: editorRowGap),
        child: Row(
          children: [
            SizedBox(
              width: 90,
              child: Text(
                descriptor.label,
                style: const TextStyle(
                  fontSize: 11,
                  color: editorMutedTextColor,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '(${descriptor.type.name})',
              style: const TextStyle(fontSize: 11, color: editorMutedTextColor),
            ),
          ],
        ),
      ),
    };
  }
}

class _StringField extends StatefulWidget {
  const _StringField({
    required this.label,
    required this.initial,
    required this.onSubmit,
  });
  final String label;
  final String initial;
  final void Function(String) onSubmit;

  @override
  State<_StringField> createState() => _StringFieldState();
}

class _StringFieldState extends State<_StringField> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initial);
  }

  @override
  void didUpdateWidget(_StringField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initial != widget.initial && !_ctrl.text.contains('\n')) {
      _ctrl.text = widget.initial;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LabeledControlRow(
      label: widget.label,
      control: EditorTextField(
        controller: _ctrl,
        onSubmit: widget.onSubmit,
        commitOnFocusLoss: false,
      ),
    );
  }
}

class _BoolField extends StatelessWidget {
  const _BoolField({
    required this.label,
    required this.initial,
    required this.onChanged,
  });
  final String label;
  final bool initial;
  final void Function(bool) onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: editorRowGap),
      child: Row(
        children: [
          SizedBox(
            width: editorPropertyLabelWidth,
            child: Text(
              label,
              style: editorRowLabelText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: editorRowGutter),
          InspectorToggleSwitch(value: initial, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _NumberField extends StatefulWidget {
  const _NumberField({
    required this.label,
    required this.initial,
    required this.isInt,
    required this.onSubmit,
  });
  final String label;
  final double initial;
  final bool isInt;
  final void Function(Object) onSubmit;

  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
      text: widget.isInt
          ? widget.initial.toInt().toString()
          : widget.initial.toStringAsFixed(3),
    );
  }

  @override
  void didUpdateWidget(_NumberField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initial != widget.initial) {
      _ctrl.text = widget.isInt
          ? widget.initial.toInt().toString()
          : widget.initial.toStringAsFixed(3);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit(String text) {
    if (widget.isInt) {
      final v = int.tryParse(text);
      if (v != null) widget.onSubmit(v);
    } else {
      // tryParse accepts "NaN"/"Infinity"/overflow; a non-finite value would
      // poison the document (canonical JSON refuses to encode it on save).
      final v = double.tryParse(text);
      if (v != null && v.isFinite) widget.onSubmit(v);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: editorRowGap),
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
          Expanded(
            child: FTextField(
              control: FTextFieldControl.managed(controller: _ctrl),
              size: FTextFieldSizeVariant.sm,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              onSubmit: _submit,
            ),
          ),
        ],
      ),
    );
  }
}

/// A compact XYZ vector editor (3 number fields inline).
class Vec3Field extends StatelessWidget {
  const Vec3Field({
    super.key,
    required this.label,
    required this.x,
    required this.y,
    required this.z,
    required this.onSubmit,
    this.onPreview,
    this.scrubStep = 0.01,
    this.snapStep = 1,
    this.mixedX = false,
    this.mixedY = false,
    this.mixedZ = false,
  });

  final String label;
  final double x;
  final double y;
  final double z;

  /// Called with an axis map when any field is submitted. Every axis is
  /// present unless it is marked mixed and was not the edited one, so a
  /// multi-selection commit can keep each node's own value there.
  final void Function(Map<String, Object> v) onSubmit;

  /// Updates the realized value without recording history.
  final void Function(Map<String, Object> v)? onPreview;
  final double scrubStep;
  final double snapStep;

  /// Per-axis mixed markers for a multi-selection (dash until edited).
  final bool mixedX;
  final bool mixedY;
  final bool mixedZ;

  Map<String, Object> _axisMap(int edited, double v) => {
    if (edited == 0) 'x': v else if (!mixedX) 'x': x,
    if (edited == 1) 'y': v else if (!mixedY) 'y': y,
    if (edited == 2) 'z': v else if (!mixedZ) 'z': z,
  };

  @override
  Widget build(BuildContext context) {
    return LabeledControlRow(
      label: label,
      control: Row(
        children: [
          Expanded(
            child: _AxisField(
              label: 'X',
              color: editorAxisColors[0],
              value: x,
              mixed: mixedX,
              scrubStep: scrubStep,
              snapStep: snapStep,
              onPreview: (v) => onPreview?.call(_axisMap(0, v)),
              onSubmit: (v) => onSubmit(_axisMap(0, v)),
            ),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: _AxisField(
              label: 'Y',
              color: editorAxisColors[1],
              value: y,
              mixed: mixedY,
              scrubStep: scrubStep,
              snapStep: snapStep,
              onPreview: (v) => onPreview?.call(_axisMap(1, v)),
              onSubmit: (v) => onSubmit(_axisMap(1, v)),
            ),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: _AxisField(
              label: 'Z',
              color: editorAxisColors[2],
              value: z,
              mixed: mixedZ,
              scrubStep: scrubStep,
              snapStep: snapStep,
              onPreview: (v) => onPreview?.call(_axisMap(2, v)),
              onSubmit: (v) => onSubmit(_axisMap(2, v)),
            ),
          ),
        ],
      ),
    );
  }
}

class _AxisField extends StatefulWidget {
  const _AxisField({
    required this.label,
    required this.color,
    required this.value,
    required this.scrubStep,
    required this.snapStep,
    required this.onPreview,
    required this.onSubmit,
    this.mixed = false,
  });
  final String label;
  final Color color;
  final double value;
  final double scrubStep;
  final double snapStep;
  final ValueChanged<double>? onPreview;
  final void Function(double) onSubmit;
  final bool mixed;

  @override
  State<_AxisField> createState() => _AxisFieldState();
}

class _AxisFieldState extends State<_AxisField> {
  @override
  Widget build(BuildContext context) {
    return ScrubbableNumberField(
      label: widget.label,
      color: widget.color,
      value: widget.value,
      mixed: widget.mixed,
      scrubStep: widget.scrubStep,
      snapStep: widget.snapStep,
      onPreview: widget.onPreview,
      onCommit: widget.onSubmit,
    );
  }
}

/// A number field that scrubs horizontally or edits as text after a click.
class ScrubbableNumberField extends StatefulWidget {
  const ScrubbableNumberField({
    super.key,
    required this.label,
    required this.color,
    required this.value,
    required this.scrubStep,
    required this.snapStep,
    this.onPreview,
    required this.onCommit,
    this.height = editorFieldHeight,
    this.fractionDigits = 3,
    this.mixed = false,
    this.enableInfiniteDrag = true,
  });

  final String label;
  final Color color;
  final double value;
  final double scrubStep;
  final double snapStep;
  final ValueChanged<double>? onPreview;
  final ValueChanged<double> onCommit;
  final double height;
  final int fractionDigits;

  /// Renders a dash instead of [value] until the field is edited, for a
  /// multi-selection whose nodes disagree; [value] still seeds the edit.
  final bool mixed;

  /// Disables native pointer wrapping in widget tests.
  @visibleForTesting
  final bool enableInfiniteDrag;

  @override
  State<ScrubbableNumberField> createState() => _ScrubbableNumberFieldState();
}

class _ScrubbableNumberFieldState extends State<ScrubbableNumberField> {
  static const _dragThreshold = 4.0;

  final _text = TextEditingController();
  final _textFocus = FocusNode();
  final _interactionFocus = FocusNode();
  final _infiniteDrag = InfiniteDragController(
    axis: InfiniteDragAxis.horizontal,
    edgeMargin: 24,
  );

  bool _hovered = false;
  bool _editing = false;
  bool _touched = false;
  bool _pending = false;
  bool _dragging = false;
  int? _pointer;
  Offset _origin = Offset.zero;
  double _displayValue = 0;
  double _startValue = 0;
  double _rawValue = 0;
  double _editStartValue = 0;
  int _dragSerial = 0;
  Future<void> _updates = Future.value();

  String _format(double value) {
    final canonical = value.abs() < 0.0005 ? 0.0 : value;
    return canonical.toStringAsFixed(widget.fractionDigits);
  }

  @override
  void initState() {
    super.initState();
    _displayValue = widget.value;
    _text.text = _format(widget.value);
    _textFocus.addListener(_onTextFocusChanged);
  }

  @override
  void didUpdateWidget(ScrubbableNumberField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && !_editing && !_dragging) {
      _displayValue = widget.value;
      _text.text = _format(widget.value);
    }
    if (oldWidget.mixed != widget.mixed) _touched = false;
  }

  bool get _showDash => widget.mixed && !_touched && !_editing && !_dragging;

  void _onTextFocusChanged() {
    if (_editing && !_textFocus.hasFocus) _finishTextEditing(commit: true);
  }

  void _beginTextEditing() {
    _touched = true;
    _editStartValue = _displayValue;
    _text.text = _format(_displayValue);
    setState(() => _editing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_editing) return;
      _textFocus.requestFocus();
      _text.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _text.text.length,
      );
    });
  }

  void _finishTextEditing({required bool commit}) {
    if (!_editing) return;
    // Reject "NaN"/"Infinity"/overflow, which tryParse accepts; a non-finite
    // value would poison the document (canonical JSON refuses it on save).
    final parsed = double.tryParse(_text.text);
    final valid = parsed != null && parsed.isFinite;
    final next = commit && valid ? parsed : _editStartValue;
    final changed = next != _editStartValue;
    setState(() {
      _editing = false;
      _displayValue = next;
      _text.text = _format(next);
    });
    if (commit && valid && changed) widget.onCommit(next);
  }

  void _onPointerDown(PointerDownEvent event) {
    if (_editing) return;
    if (_dragging && event.buttons & kSecondaryMouseButton != 0) {
      _cancelDrag();
      return;
    }
    if (event.buttons & kPrimaryMouseButton == 0) return;
    _interactionFocus.requestFocus();
    _touched = true;
    _pointer = event.pointer;
    _origin = event.position;
    _startValue = widget.value;
    _displayValue = widget.value;
    _rawValue = widget.value;
    _pending = true;
    _dragging = false;
    _dragSerial++;
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_pointer != event.pointer) return;
    if (_pending) {
      final displacement = event.position - _origin;
      if (displacement.distance < _dragThreshold) return;
      _pending = false;
      _dragging = true;
      final serial = _dragSerial;
      if (widget.enableInfiniteDrag) {
        unawaited(
          _infiniteDrag.start(
            event.position,
            viewportSize: MediaQuery.sizeOf(context),
            onLockedDelta: (delta) {
              if (mounted && serial == _dragSerial) _applyDelta(delta.dx);
            },
          ),
        );
      }
      _applyDelta(displacement.dx);
      return;
    }
    if (!_dragging) return;
    if (!widget.enableInfiniteDrag) {
      _applyDelta(event.delta.dx);
      return;
    }
    final serial = _dragSerial;
    final viewportSize = MediaQuery.sizeOf(context);
    _updates = _updates.then((_) async {
      final dx = await _infiniteDrag.update(
        globalPosition: event.position,
        delta: event.delta,
        viewportSize: viewportSize,
      );
      if (mounted && serial == _dragSerial) _applyDelta(dx);
    });
  }

  void _applyDelta(double dx) {
    if (dx == 0) return;
    final keyboard = HardwareKeyboard.instance;
    final precision = keyboard.isShiftPressed ? 0.1 : 1.0;
    _rawValue += dx * widget.scrubStep * precision;
    var next = _rawValue;
    if ((keyboard.isControlPressed || keyboard.isMetaPressed) &&
        widget.snapStep > 0) {
      next = (next / widget.snapStep).round() * widget.snapStep;
    }
    setState(() {
      _displayValue = next;
      _text.text = _format(next);
    });
    widget.onPreview?.call(next);
  }

  void _onPointerUp(PointerUpEvent event) {
    if (_pointer != event.pointer) return;
    _pointer = null;
    if (_pending) {
      _pending = false;
      _beginTextEditing();
      return;
    }
    if (!_dragging) return;
    _dragging = false;
    final serial = _dragSerial;
    unawaited(_finishDrag(serial));
  }

  Future<void> _finishDrag(int serial) async {
    await _updates;
    await _infiniteDrag.end();
    if (!mounted || serial != _dragSerial) return;
    if (_displayValue != _startValue) widget.onCommit(_displayValue);
    setState(() {});
  }

  void _cancelDrag() {
    if (!_pending && !_dragging) return;
    _dragSerial++;
    _pointer = null;
    _pending = false;
    _dragging = false;
    _displayValue = _startValue;
    _rawValue = _startValue;
    _text.text = _format(_startValue);
    widget.onPreview?.call(_startValue);
    unawaited(_infiniteDrag.cancel());
    setState(() {});
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape) {
      return KeyEventResult.ignored;
    }
    if (_editing) {
      _finishTextEditing(commit: false);
      _interactionFocus.requestFocus();
      return KeyEventResult.handled;
    }
    if (_pending || _dragging) {
      _cancelDrag();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _infiniteDrag.dispose();
    _textFocus
      ..removeListener(_onTextFocusChanged)
      ..dispose();
    _interactionFocus.dispose();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = _dragging || _editing;
    final unit = widget.label;
    return Focus(
      focusNode: _interactionFocus,
      onKeyEvent: _onKey,
      child: MouseRegion(
        cursor: _editing
            ? SystemMouseCursors.text
            : SystemMouseCursors.resizeLeftRight,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerUp,
          onPointerCancel: (_) => _cancelDrag(),
          child: EditorFieldSurface(
            height: widget.height,
            hovered: _hovered,
            active: active,
            accent: widget.color,
            child: Row(
              children: [
                Expanded(
                  child: _editing
                      // A bare field inside the shared surface rather than a
                      // styled one of its own, so entering a value does not
                      // change the shape of the row it is in.
                      ? TextField(
                          controller: _text,
                          focusNode: _textFocus,
                          decoration: const InputDecoration.collapsed(
                            hintText: '',
                          ),
                          style: const TextStyle(
                            color: editorValueColor,
                            fontFeatures: [FontFeature.tabularFigures()],
                            fontSize: 11,
                          ),
                          cursorColor: editorValueColor,
                          cursorWidth: 1,
                          autocorrect: false,
                          enableSuggestions: false,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          mouseCursor: SystemMouseCursors.text,
                          onSubmitted: (_) => _finishTextEditing(commit: true),
                        )
                      : Semantics(
                          label: unit.isEmpty ? 'Numeric value' : '$unit value',
                          value: _showDash ? 'mixed' : _format(_displayValue),
                          button: true,
                          hint: 'Click to type or drag horizontally to adjust',
                          child: Text(
                            _showDash ? '\u2014' : _format(_displayValue),
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              // Amber, so a number you can drag never reads
                              // like a number being reported to you. Every
                              // transform row has both within a few pixels.
                              color: editorValueColor,
                              fontFeatures: [FontFeature.tabularFigures()],
                              fontSize: 11,
                            ),
                          ),
                        ),
                ),
                // The axis or unit, at the trailing edge: it names the field
                // rather than labelling it, so it sits out of the way of the
                // value and keeps the axis colour the gizmo uses.
                if (unit.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  Text(
                    unit,
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      color: widget.color,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A compact slider paired with a scrub-to-adjust and type-to-edit field.
class SliderNumberField extends StatefulWidget {
  const SliderNumberField({
    super.key,
    required this.label,
    required this.value,
    this.min = 0,
    this.max = 1,
    this.scrubStep,
    this.snapStep,
    this.fractionDigits = 3,
    required this.onPreview,
    required this.onCommit,
    this.mixed = false,
    this.enableInfiniteDrag = true,
  }) : assert(max > min);

  final String label;
  final double value;
  final double min;
  final double max;
  final double? scrubStep;
  final double? snapStep;
  final int fractionDigits;
  final ValueChanged<double> onPreview;
  final ValueChanged<double> onCommit;

  /// Dash display for a multi-selection whose nodes disagree.
  final bool mixed;

  @visibleForTesting
  final bool enableInfiniteDrag;

  @override
  State<SliderNumberField> createState() => _SliderNumberFieldState();
}

class _SliderNumberFieldState extends State<SliderNumberField> {
  double? _preview;

  @override
  void didUpdateWidget(SliderNumberField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) _preview = null;
  }

  void _update(double value) {
    setState(() => _preview = value);
    widget.onPreview(value);
  }

  void _commit(double value) {
    setState(() => _preview = value);
    widget.onCommit(value);
  }

  @override
  Widget build(BuildContext context) {
    final value = _preview ?? widget.value;
    final step = widget.scrubStep ?? (widget.max - widget.min) / 300;
    // The number leads and the slider follows it, which is the order the
    // value is read in: a slider says roughly where you are in a range, and
    // the number says what you are actually going to ship.
    final field = SizedBox(
      width: 64,
      child: ScrubbableNumberField(
        label: '',
        color: editorAccentColor,
        value: value,
        mixed: widget.mixed && _preview == null,
        scrubStep: step,
        snapStep: widget.snapStep ?? step,
        fractionDigits: widget.fractionDigits,
        enableInfiniteDrag: widget.enableInfiniteDrag,
        onPreview: _update,
        onCommit: _commit,
      ),
    );
    return LabeledControlRow(
      label: widget.label,
      control: Row(
        children: [
          field,
          const SizedBox(width: 6),
          Expanded(
            child: InspectorSlider(
              value: value.clamp(widget.min, widget.max),
              min: widget.min,
              max: widget.max,
              onChanged: _update,
              onChangeEnd: _commit,
            ),
          ),
        ],
      ),
    );
  }
}

/// Builds a slider/scrub field for one channel in a [ColorEditor].
Widget sliderColorChannel({
  required String label,
  required double value,
  required double min,
  required double max,
  required ValueChanged<double> onPreview,
  required ValueChanged<double> onCommit,
}) => SliderNumberField(
  label: label,
  value: value,
  min: min,
  max: max,
  scrubStep: max >= 100 ? 1 : (max - min) / 300,
  snapStep: max >= 100 ? 1 : 0.01,
  fractionDigits: max >= 100 ? 0 : 3,
  onPreview: onPreview,
  onCommit: onCommit,
);

/// One labelled property: the label in the shared column, the control in the
/// rest of the width.
///
/// This is the row the whole inspector is made of, so its measurements are
/// the panel's: [editorPropertyLabelWidth] of label, [editorRowGutter] of gap,
/// and whatever is left for the control. Labels take no colon -- two columns
/// already say which is the name and which is the value.
///
/// A control that sizes itself sits at the left of the value column; one that
/// wants the width (a field, a dropdown) takes it. Both are fine here, which
/// they were not when this measured the control against unbounded width.
class LabeledControlRow extends StatelessWidget {
  const LabeledControlRow({
    super.key,
    required this.label,
    required this.control,
    this.padding = const EdgeInsets.symmetric(vertical: editorRowGap),
    this.tooltip,
  });

  final String label;
  final Widget control;
  final EdgeInsetsGeometry padding;

  /// What the label means, where the name alone does not carry it.
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    Widget name = Text(
      label,
      style: editorRowLabelText,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    // Always hoverable, because the column is a fixed width and a long
    // property name ellipsizes in it. A name you cannot read is a property
    // you cannot use.
    name = Tooltip(
      message: tooltip ?? label,
      waitDuration: const Duration(milliseconds: 500),
      child: name,
    );
    return Padding(
      padding: padding,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: editorPropertyRowHeight),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(width: editorPropertyLabelWidth, child: name),
            const SizedBox(width: editorRowGutter),
            Expanded(
              child: Align(alignment: Alignment.centerLeft, child: control),
            ),
          ],
        ),
      ),
    );
  }
}
