/// Inspector editor for a mesh's material resource (base color, PBR factors,
/// alpha mode, ...). Materials are resources, not components, so this reads the
/// material referenced by the selected node's mesh component and commits edits
/// through the `setMaterialProperties` command. Sliders and colors preview live
/// on the node's realized mesh while dragging and commit one undo step on
/// release.
library;

import 'package:flutter/material.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/fscene/id.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/fscene/property_value.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/fscene/specs.dart';

import '../controller/editor_controller.dart';
import 'live_fields.dart';

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

// The default a color field shows when the material has no value yet. Emissive
// defaults to black (no emission); other colors to white.
List<double> _defaultColor(String key) =>
    key == 'emissive' ? const [0, 0, 0, 1] : const [1, 1, 1, 1];

/// Renders editors for the material [materialId] (a [MaterialResource]) used by
/// node [nodeId], committing changes through [controller] and previewing slider
/// and color drags live on [nodeId]'s realized mesh.
class MaterialSection extends StatelessWidget {
  const MaterialSection({
    super.key,
    required this.controller,
    required this.nodeId,
    required this.materialId,
  });

  final EditorController controller;
  final LocalId nodeId;
  final LocalId materialId;

  void _set(String key, Object value) {
    controller.run('setMaterialProperties', {
      'materialId': materialId.toToken(),
      'properties': {key: value},
    });
  }

  void _preview(String key, Object value) =>
      controller.previewMaterialProperty(nodeId, key, value);

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
        final current = switch (value) {
          DoubleValue(:final value) => value,
          IntValue(:final value) => value.toDouble(),
          _ => 0.0,
        };
        return LiveSlider(
          label: field.label,
          value: current.clamp(0.0, 1.0),
          onPreview: (v) => _preview(field.key, v),
          onCommit: (v) => _set(field.key, v),
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
        final fallback = _defaultColor(field.key);
        final c = value is ColorValue
            ? value
            : ColorValue(fallback[0], fallback[1], fallback[2], fallback[3]);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: ColorEditor(
            label: field.label,
            r: c.r,
            g: c.g,
            b: c.b,
            a: c.a,
            onPreview: (r, g, b, a) =>
                _preview(field.key, {'r': r, 'g': g, 'b': b, 'a': a}),
            onCommit: (r, g, b, a) =>
                _set(field.key, {'r': r, 'g': g, 'b': b, 'a': a}),
          ),
        );
    }
  }
}
