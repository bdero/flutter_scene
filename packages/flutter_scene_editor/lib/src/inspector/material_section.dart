/// Inspector editor for a mesh's material resource (base color, PBR factors,
/// alpha mode, ...). Materials are resources, not components, so this reads the
/// material referenced by the selected node's mesh component and commits edits
/// through the `setMaterialProperties` command.
library;

import 'package:flutter/material.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/fscene/id.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/fscene/property_value.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/fscene/specs.dart';

import '../controller/editor_controller.dart';

enum _Kind { factor, color, boolean, choice }

class _Field {
  const _Field(this.key, this.label, this.kind, {this.options});
  final String key;
  final String label;
  final _Kind kind;
  final List<String>? options;
}

const _physicallyBased = [
  _Field('baseColor', 'Base color', _Kind.color),
  _Field('metallic', 'Metallic', _Kind.factor),
  _Field('roughness', 'Roughness', _Kind.factor),
  _Field('emissive', 'Emissive', _Kind.color),
  _Field(
    'alphaMode',
    'Alpha mode',
    _Kind.choice,
    options: ['opaque', 'mask', 'blend'],
  ),
  _Field('alphaCutoff', 'Alpha cutoff', _Kind.factor),
  _Field('doubleSided', 'Double sided', _Kind.boolean),
];

const _unlit = [
  _Field('baseColor', 'Base color', _Kind.color),
  _Field('doubleSided', 'Double sided', _Kind.boolean),
];

List<_Field> _fieldsFor(String type) => switch (type) {
  'physicallyBased' => _physicallyBased,
  'unlit' => _unlit,
  _ => const [],
};

/// Renders editors for the material [materialId] (a [MaterialResource]),
/// committing each change through [controller].
class MaterialSection extends StatelessWidget {
  const MaterialSection({
    super.key,
    required this.controller,
    required this.materialId,
  });

  final EditorController controller;
  final LocalId materialId;

  void _set(String key, Object rawValue) {
    controller.run('setMaterialProperties', {
      'materialId': materialId.toToken(),
      'properties': {key: rawValue},
    });
  }

  @override
  Widget build(BuildContext context) {
    final resource = controller.document.resources[materialId];
    if (resource is! MaterialResource) return const SizedBox.shrink();
    final fields = _fieldsFor(resource.type);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: Text(
            'Material: ${resource.type}',
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ),
        if (fields.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Text(
              'This material type has no editable properties here.',
              style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
            ),
          )
        else
          for (final field in fields)
            _fieldEditor(context, field, resource.properties[field.key]),
      ],
    );
  }

  Widget _fieldEditor(
    BuildContext context,
    _Field field,
    PropertyValue? value,
  ) {
    switch (field.kind) {
      case _Kind.factor:
        final current = value is DoubleValue
            ? value.value
            : (value is IntValue ? value.value.toDouble() : 0.0);
        return _FactorSlider(
          label: field.label,
          value: current.clamp(0.0, 1.0),
          onChanged: (v) => _set(field.key, v),
        );
      case _Kind.boolean:
        final current = value is BoolValue && value.value;
        return SwitchListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          title: Text(field.label, style: const TextStyle(fontSize: 13)),
          value: current,
          onChanged: (v) => _set(field.key, v),
        );
      case _Kind.choice:
        final current = value is StringValue
            ? value.value
            : field.options!.first;
        return ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          title: Text(field.label, style: const TextStyle(fontSize: 13)),
          trailing: DropdownButton<String>(
            value: field.options!.contains(current)
                ? current
                : field.options!.first,
            items: [
              for (final option in field.options!)
                DropdownMenuItem(value: option, child: Text(option)),
            ],
            onChanged: (v) => v == null ? null : _set(field.key, v),
          ),
        );
      case _Kind.color:
        final c = value is ColorValue ? value : const ColorValue(1, 1, 1, 1);
        return _ColorRow(
          label: field.label,
          color: c,
          onChanged: (r, g, b, a) =>
              _set(field.key, {'r': r, 'g': g, 'b': b, 'a': a}),
        );
    }
  }
}

// A 0..1 factor slider that commits once per drag (one undo step).
class _FactorSlider extends StatefulWidget {
  const _FactorSlider({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  State<_FactorSlider> createState() => _FactorSliderState();
}

class _FactorSliderState extends State<_FactorSlider> {
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final value = _dragging ?? widget.value;
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      title: Text(widget.label, style: const TextStyle(fontSize: 13)),
      subtitle: Slider(
        value: value,
        onChanged: (v) => setState(() => _dragging = v),
        onChangeEnd: (v) {
          setState(() => _dragging = null);
          widget.onChanged(v);
        },
      ),
      trailing: Text(value.toStringAsFixed(2)),
    );
  }
}

// A linear-RGBA color row: a swatch that opens a slider dialog.
class _ColorRow extends StatelessWidget {
  const _ColorRow({
    required this.label,
    required this.color,
    required this.onChanged,
  });
  final String label;
  final ColorValue color;
  final void Function(double r, double g, double b, double a) onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      title: Text(label, style: const TextStyle(fontSize: 13)),
      trailing: InkWell(
        onTap: () async {
          final result = await showDialog<List<double>>(
            context: context,
            builder: (_) => _ColorDialog(label: label, color: color),
          );
          if (result != null) {
            onChanged(result[0], result[1], result[2], result[3]);
          }
        },
        child: Container(
          width: 28,
          height: 18,
          decoration: BoxDecoration(
            color: _swatch(color),
            border: Border.all(color: Theme.of(context).dividerColor),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      ),
    );
  }
}

int _channel(double v) => (v.clamp(0.0, 1.0) * 255).round();

// An approximate sRGB swatch for a linear color (preview only).
Color _swatch(ColorValue c) =>
    Color.fromARGB(_channel(c.a), _channel(c.r), _channel(c.g), _channel(c.b));

class _ColorDialog extends StatefulWidget {
  const _ColorDialog({required this.label, required this.color});
  final String label;
  final ColorValue color;

  @override
  State<_ColorDialog> createState() => _ColorDialogState();
}

class _ColorDialogState extends State<_ColorDialog> {
  late double _r = widget.color.r;
  late double _g = widget.color.g;
  late double _b = widget.color.b;
  late double _a = widget.color.a;

  Widget _channel(String name, double value, ValueChanged<double> onChanged) {
    return Row(
      children: [
        SizedBox(width: 16, child: Text(name)),
        Expanded(
          child: Slider(
            value: value.clamp(0.0, 1.0),
            onChanged: (v) => setState(() => onChanged(v)),
          ),
        ),
        SizedBox(width: 36, child: Text(value.toStringAsFixed(2))),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.label),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 28,
            decoration: BoxDecoration(
              color: _swatch(ColorValue(_r, _g, _b, _a)),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
          ),
          const SizedBox(height: 8),
          _channel('R', _r, (v) => _r = v),
          _channel('G', _g, (v) => _g = v),
          _channel('B', _b, (v) => _b = v),
          _channel('A', _a, (v) => _a = v),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop([_r, _g, _b, _a]),
          child: const Text('Apply'),
        ),
      ],
    );
  }
}
