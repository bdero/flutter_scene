// ignore: implementation_imports
import 'package:flutter_scene/src/fscene/property_value.dart';
import 'package:flutter/material.dart';
import 'package:flutter_scene_editor_core/flutter_scene_editor_core.dart';

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
                style: const TextStyle(fontSize: 11, color: Colors.grey),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '(${descriptor.type.name})',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
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
            child: SizedBox(
              height: 24,
              child: TextField(
                controller: _ctrl,
                style: const TextStyle(fontSize: 11),
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  border: OutlineInputBorder(),
                ),
                onSubmitted: widget.onSubmit,
              ),
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
          SizedBox(
            height: 20,
            child: Switch(
              value: initial,
              onChanged: onChanged,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
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
      final v = double.tryParse(text);
      if (v != null) widget.onSubmit(v);
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
            child: SizedBox(
              height: 24,
              child: TextField(
                controller: _ctrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                style: const TextStyle(fontSize: 11),
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  border: OutlineInputBorder(),
                ),
                onSubmitted: _submit,
              ),
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
  });

  final String label;
  final double x;
  final double y;
  final double z;

  /// Called with {x, y, z} map when any field is submitted.
  final void Function(Map<String, Object> v) onSubmit;

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
              value: x,
              onSubmit: (v) => onSubmit({'x': v, 'y': y, 'z': z}),
            ),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: _AxisField(
              label: 'Y',
              value: y,
              onSubmit: (v) => onSubmit({'x': x, 'y': v, 'z': z}),
            ),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: _AxisField(
              label: 'Z',
              value: z,
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
    required this.value,
    required this.onSubmit,
  });
  final String label;
  final double value;
  final void Function(double) onSubmit;

  @override
  State<_AxisField> createState() => _AxisFieldState();
}

class _AxisFieldState extends State<_AxisField> {
  late final TextEditingController _ctrl;
  late final FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value.toStringAsFixed(3));
    _focus = FocusNode()..addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (!_focus.hasFocus) _commit();
  }

  void _commit() {
    // Skip when the text still matches the current value's canonical rendering,
    // so leaving a field untouched does not record a no-op edit.
    if (_ctrl.text == widget.value.toStringAsFixed(3)) return;
    final v = double.tryParse(_ctrl.text);
    if (v != null) widget.onSubmit(v);
  }

  @override
  void didUpdateWidget(_AxisField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && !_focus.hasFocus) {
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
    return SizedBox(
      height: 22,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.label,
            style: const TextStyle(fontSize: 9, color: Colors.grey),
          ),
          const SizedBox(width: 2),
          Expanded(
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
        ],
      ),
    );
  }
}
