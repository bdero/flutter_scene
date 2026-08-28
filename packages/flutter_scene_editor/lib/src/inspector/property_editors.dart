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
        padding: const EdgeInsets.symmetric(vertical: 2),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(
              widget.label,
              style: const TextStyle(fontSize: 11),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: FTextField(
              control: FTextFieldControl.managed(controller: _ctrl),
              size: FTextFieldSizeVariant.sm,
              onSubmit: widget.onSubmit,
            ),
          ),
        ],
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
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: const TextStyle(fontSize: 11),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
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
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(
              widget.label,
              style: const TextStyle(fontSize: 11),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
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
  });

  final String label;
  final double x;
  final double y;
  final double z;

  /// Called with {x, y, z} map when any field is submitted.
  final void Function(Map<String, Object> v) onSubmit;

  /// Updates the realized value without recording history.
  final void Function(Map<String, Object> v)? onPreview;
  final double scrubStep;
  final double snapStep;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: const TextStyle(fontSize: 11),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _AxisField(
              label: 'X',
              color: editorAxisColors[0],
              value: x,
              scrubStep: scrubStep,
              snapStep: snapStep,
              onPreview: (v) => onPreview?.call({'x': v, 'y': y, 'z': z}),
              onSubmit: (v) => onSubmit({'x': v, 'y': y, 'z': z}),
            ),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: _AxisField(
              label: 'Y',
              color: editorAxisColors[1],
              value: y,
              scrubStep: scrubStep,
              snapStep: snapStep,
              onPreview: (v) => onPreview?.call({'x': x, 'y': v, 'z': z}),
              onSubmit: (v) => onSubmit({'x': x, 'y': v, 'z': z}),
            ),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: _AxisField(
              label: 'Z',
              color: editorAxisColors[2],
              value: z,
              scrubStep: scrubStep,
              snapStep: snapStep,
              onPreview: (v) => onPreview?.call({'x': x, 'y': y, 'z': v}),
              onSubmit: (v) => onSubmit({'x': x, 'y': y, 'z': v}),
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
  });
  final String label;
  final Color color;
  final double value;
  final double scrubStep;
  final double snapStep;
  final ValueChanged<double>? onPreview;
  final void Function(double) onSubmit;

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
    this.height = 34,
    this.fractionDigits = 3,
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
  }

  void _onTextFocusChanged() {
    if (_editing && !_textFocus.hasFocus) _finishTextEditing(commit: true);
  }

  void _beginTextEditing() {
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
    final borderAlpha = active ? 0.9 : (_hovered ? 0.55 : 0.24);
    final fillAlpha = _dragging ? 0.11 : (_hovered ? 0.055 : 0.025);
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
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 90),
            height: widget.height,
            decoration: BoxDecoration(
              color: widget.color.withValues(alpha: fillAlpha),
              border: Border.all(
                color: widget.color.withValues(alpha: borderAlpha),
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            child: _editing
                ? FTextField(
                    control: FTextFieldControl.managed(controller: _text),
                    focusNode: _textFocus,
                    size: FTextFieldSizeVariant.sm,
                    textAlign: TextAlign.right,
                    selectAllOnFocus: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    mouseCursor: SystemMouseCursors.text,
                    prefixBuilder: widget.label.isEmpty
                        ? null
                        : (_, _, _) => Padding(
                            padding: const EdgeInsets.only(left: 6, right: 3),
                            child: Text(
                              widget.label,
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: widget.color,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                    onSubmit: (_) => _finishTextEditing(commit: true),
                  )
                : Semantics(
                    label: widget.label.isEmpty
                        ? 'Numeric value'
                        : '${widget.label} value',
                    value: _format(_displayValue),
                    button: true,
                    hint: 'Click to type or drag horizontally to adjust',
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 7),
                      child: Row(
                        children: [
                          if (widget.label.isNotEmpty) ...[
                            Text(
                              widget.label,
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: widget.color,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 4),
                          ],
                          Expanded(
                            child: Text(
                              _format(_displayValue),
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                color: context.theme.colors.foreground,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
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
    final label = Text(
      widget.label,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 11),
    );
    final slider = InspectorSlider(
      value: value.clamp(widget.min, widget.max),
      min: widget.min,
      max: widget.max,
      onChanged: _update,
      onChangeEnd: _commit,
    );
    final field = SizedBox(
      width: 76,
      child: ScrubbableNumberField(
        label: '',
        color: context.theme.colors.primary,
        value: value,
        scrubStep: step,
        snapStep: widget.snapStep ?? step,
        fractionDigits: widget.fractionDigits,
        height: 34,
        enableInfiniteDrag: widget.enableInfiniteDrag,
        onPreview: _update,
        onCommit: _commit,
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: LayoutBuilder(
        builder: (context, constraints) => constraints.maxWidth >= 260
            ? Row(
                children: [
                  SizedBox(width: 102, child: label),
                  Expanded(child: slider),
                  const SizedBox(width: 6),
                  field,
                ],
              )
            : Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: label),
                      const SizedBox(width: 6),
                      field,
                    ],
                  ),
                  slider,
                ],
              ),
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

/// A labeled control row that stays valid at any panel width. Dockable
/// panels can get arbitrarily narrow, where a [ListTile] with a wide
/// trailing control fails its layout assertion; here the control wraps to
/// its own line instead, scaling down as a last resort.
class LabeledControlRow extends StatelessWidget {
  const LabeledControlRow({
    super.key,
    required this.label,
    required this.control,
    this.padding = const EdgeInsets.symmetric(vertical: 2),
  });

  final String label;
  final Widget control;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        children: [
          Text(label, style: const TextStyle(fontSize: 13)),
          FittedBox(fit: BoxFit.scaleDown, child: control),
        ],
      ),
    );
  }
}
