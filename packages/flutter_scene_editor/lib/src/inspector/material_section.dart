/// Inspector editor for a mesh's material resource. A single "Type" control
/// sets or resets the material, a live preview and origin badge show what it is
/// and where it comes from, and each texture slot is a unified resource card
/// with its own preview, origin, and clear action. Materials are resources, not
/// components, so this reads the material referenced by the selected node's mesh
/// and commits edits through the command layer.
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
// ignore: implementation_imports
import 'package:scene/scene.dart';

import '../shell/editor_theme.dart';
import '../shell/panel_chrome.dart';
import '../controller/editor_controller.dart';
import '../io/scene_io.dart';
import 'live_fields.dart';
import 'material_preview.dart';
import 'property_editors.dart';
import 'resource_origin.dart';
import 'resource_slot_card.dart';

// Material texture-property slots offered per material type. The key is the
// material property the realizer reads (a ResourceRefValue to a texture).
const _pbrTextureSlots = [
  ('Base color', 'baseColorTexture'),
  ('Metallic-roughness', 'metallicRoughnessTexture'),
  ('Normal', 'normalTexture'),
  ('Emissive', 'emissiveTexture'),
];
const _unlitTextureSlots = [('Base color', 'baseColorTexture')];

List<(String, String)> _textureSlotsFor(String type) => switch (type) {
  'physicallyBased' => _pbrTextureSlots,
  'unlit' => _unlitTextureSlots,
  _ => const [],
};

String _typeLabel(String type) => switch (type) {
  'physicallyBased' => 'Physically based',
  'unlit' => 'Unlit',
  'fmat' => 'Shader (.fmat)',
  _ => type,
};

String _fileName(String key) => key.replaceAll('\\', '/').split('/').last;

// `strength` is a nonnegative multiplier with a soft slider range; typing or
// scrubbing past the slider max is allowed (HDR emission wants values like
// 1000, only the slider track is bounded).
enum _Kind { factor, strength, color, boolean, choice }

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
  _Field('emissiveStrength', 'Emissive strength', _Kind.strength),
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

// Sentinel dropdown value: reset the material to a plain default.
const _noneValue = '__none';

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
    final source = controller.document.resources[materialId];
    final composed = source ?? controller.displayDocument.resources[materialId];
    if (composed is! MaterialResource) return const SizedBox.shrink();
    if (source == null) {
      // Owned by an instanced prefab (or an imported model inside one), so
      // there is no source resource to edit; show what it is instead of
      // nothing. TODO(material-extract): offer extract-to-document per the
      // asset provenance design.
      return Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Material', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 4),
            Text(
              composed.name.isEmpty
                  ? _typeLabel(composed.type)
                  : '${composed.name} (${_typeLabel(composed.type)})',
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 2),
            Text(
              'Owned by the instanced prefab; assign a scene material to '
              'replace it.',
              style: TextStyle(fontSize: 11, color: editorMutedTextColor),
            ),
          ],
        ),
      );
    }
    final resource = source as MaterialResource;
    final type = resource.type;
    final isFmat = type == 'fmat';
    final assetKey = resource.asset?.key;
    final sourcePath = assetKey == null
        ? null
        : controller.resolveAssetPath(assetKey);
    final sourceMissing =
        isFmat &&
        (assetKey == null ||
            sourcePath == null ||
            !File(sourcePath).existsSync());
    final metadata = assetKey == null
        ? null
        : controller.fmatLibrary.metadataForKey(assetKey);
    final compileError = !isFmat
        ? null
        : assetKey == null
        ? 'This shader material has no source.'
        : controller.fmatLibrary.errorForKey(assetKey);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: Text(
            'Material',
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: LabeledControlRow(
            label: 'Type',
            control: _typeDropdown(context, type),
          ),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: ResourceSlotCard(
            title: isFmat
                ? (assetKey == null ? 'No source' : _fileName(assetKey))
                : (resource.name.isEmpty ? _typeLabel(type) : resource.name),
            // An unnamed parametric material already titles itself with the
            // type, so the kind line only repeats it for named ones.
            kind: !isFmat && resource.name.isEmpty ? '' : _typeLabel(type),
            locality: materialLocality(resource),
            path: assetKey,
            reference: assetKey,
            previewIcon: Icons.blur_on,
            preview: MaterialPreview(controller: controller, nodeId: nodeId),
            missing: sourceMissing,
            missingLabel: 'Shader source is missing on disk',
            onReplace: isFmat ? () => _replaceFmatSource(context) : null,
            removeTooltip: 'Reset to a default material',
            aspectRatio: 1.9,
          ),
        ),
        if (isFmat && !sourceMissing && compileError != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
            child: Text(
              compileError,
              style: const TextStyle(fontSize: 11, color: editorErrorColor),
            ),
          ),
        if (isFmat && compileError == null && metadata == null)
          const Padding(
            padding: EdgeInsets.fromLTRB(8, 0, 8, 6),
            child: Text(
              'Compiling…',
              style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
            ),
          ),
        if (isFmat)
          ..._fmatFields(metadata, resource.properties)
        else
          ..._parametricFields(context, resource),
        ..._textureSection(context, resource, metadata),
      ],
    );
  }

  Widget _typeDropdown(BuildContext context, String type) {
    const known = ['physicallyBased', 'unlit', 'fmat'];
    return EditorDropdown<String>(
      value: known.contains(type) ? type : 'physicallyBased',
      items: const [
        DropdownMenuItem(
          value: 'physicallyBased',
          child: Text('Physically based'),
        ),
        DropdownMenuItem(value: 'unlit', child: Text('Unlit')),
        DropdownMenuItem(value: 'fmat', child: Text('Shader (.fmat)…')),
        DropdownMenuItem(
          value: _noneValue,
          child: Text('None (default material)'),
        ),
      ],
      onChanged: (value) => _onTypeChanged(context, type, value),
    );
  }

  Future<void> _onTypeChanged(
    BuildContext context,
    String current,
    String? value,
  ) async {
    if (value == null || value == current) return;
    if (value == 'fmat') {
      await _replaceFmatSource(context);
      return;
    }
    // "None" resets to a plain default; a parametric choice switches type.
    await controller.run('setMaterialType', {
      'materialId': materialId.toToken(),
      'type': value == _noneValue ? 'physicallyBased' : value,
    });
  }

  Future<void> _replaceFmatSource(BuildContext context) async {
    final path = await pickFmatPath();
    if (path == null) return;
    await controller.run('setMaterialType', {
      'materialId': materialId.toToken(),
      'type': 'fmat',
      'asset': referenceFmatAsset(controller.baseDirectory, path),
    });
  }

  List<Widget> _parametricFields(
    BuildContext context,
    MaterialResource resource,
  ) {
    final fields = _fieldsFor(resource.type);
    if (fields.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: InspectorDescriptionText(
            'This material type has no editable properties here.',
            style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
          ),
        ),
      ];
    }
    return [
      for (final field in fields)
        _fieldEditor(context, field, resource.properties[field.key]),
    ];
  }

  // fmat parameter fields generated from the compiled sidecar schema.
  List<Widget> _fmatFields(
    Map<String, Object?>? metadata,
    Map<String, PropertyValue> properties,
  ) {
    final parameters = (metadata?['parameters'] as List?) ?? const [];
    return [
      for (final raw in parameters)
        _fmatFieldEditor((raw as Map).cast<String, Object?>(), properties),
    ];
  }

  // Texture slots for the material (parametric slots, or fmat samplers).
  List<Widget> _textureSection(
    BuildContext context,
    MaterialResource resource,
    Map<String, Object?>? metadata,
  ) {
    final List<(String, String)> slots;
    if (resource.type == 'fmat') {
      final samplers = (metadata?['samplers'] as List?) ?? const [];
      slots = [
        for (final raw in samplers)
          if ((raw as Map)['name'] case final String name) (name, name),
      ];
    } else {
      slots = _textureSlotsFor(resource.type);
    }
    if (slots.isEmpty) return const [];
    return [
      const Divider(),
      const Padding(
        padding: EdgeInsets.fromLTRB(8, 0, 8, 4),
        child: Text('Textures', style: TextStyle(fontSize: 12)),
      ),
      for (final (label, slot) in slots)
        _textureSlot(context, label, slot, resource.properties[slot]),
    ];
  }

  Widget _textureSlot(
    BuildContext context,
    String label,
    String slot,
    PropertyValue? value,
  ) {
    final ref = value is ResourceRefValue ? value : null;
    final texture = ref == null ? null : controller.document.resources[ref.id];
    if (texture is! TextureResource) {
      return _addTextureRow(context, label, slot);
    }
    final key = texture.asset?.key;
    final path = key == null ? null : controller.resolveAssetPath(key);
    final missing =
        texture.asset != null && (path == null || !File(path).existsSync());
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: ResourceSlotCard(
        title: key == null ? '$label texture' : _fileName(key),
        kind: '$label · ${_textureKind(texture)}',
        locality: textureLocality(texture),
        path: key,
        reference: key ?? ref!.id.toToken(),
        preview: missing ? null : _textureThumbnail(texture, path),
        missing: missing,
        missingLabel: 'Image is missing on disk',
        onReplace: () => _pickTexture(context, slot),
        onRemove: () => controller.run('clearMaterialProperty', {
          'materialId': materialId.toToken(),
          'key': slot,
        }),
        removeTooltip: 'Remove texture',
        aspectRatio: 2.8,
      ),
    );
  }

  Widget _addTextureRow(BuildContext context, String label, String slot) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Row(
        children: [
          Icon(Icons.image_outlined, size: 14, color: scheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 12))),
          FButton(
            variant: .outline,
            size: .xs,
            mainAxisSize: .min,
            onPress: () => _pickTexture(context, slot),
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickTexture(BuildContext context, String slot) async {
    final path = await pickImagePath(
      initialDirectory: controller.baseDirectory,
    );
    if (path != null) {
      await importMaterialTexture(controller, materialId, slot, path);
    }
  }

  String _textureKind(TextureResource texture) {
    final key = texture.asset?.key;
    if (key != null) {
      final lower = key.toLowerCase();
      if (lower.endsWith('.ktx2')) return 'KTX2 texture';
      if (lower.endsWith('.png')) return 'PNG image';
      if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
        return 'JPEG image';
      }
      if (lower.endsWith('.webp')) return 'WebP image';
      return 'Image';
    }
    final format = controller.document.payload(texture.payload!)?.format;
    return 'Embedded ${format ?? 'image'}';
  }

  // A small preview for a texture, or null to fall back to the slot icon.
  Widget? _textureThumbnail(TextureResource texture, String? path) {
    const decodable = ['.png', '.jpg', '.jpeg', '.webp'];
    if (texture.asset != null && path != null) {
      final lower = path.toLowerCase();
      if (decodable.any(lower.endsWith)) {
        return Image.file(
          File(path),
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        );
      }
      return null;
    }
    final payloadId = texture.payload;
    if (payloadId != null) {
      final payload = controller.document.payload(payloadId);
      final bytes = payload?.bytes;
      final format = payload?.format;
      if (bytes != null &&
          const ['png', 'jpg', 'jpeg', 'webp'].contains(format)) {
        return Image.memory(
          bytes,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        );
      }
    }
    return null;
  }

  // One sidecar-declared parameter as an inspector field. Values shown are
  // the document override when present, else the sidecar default.
  Widget _fmatFieldEditor(
    Map<String, Object?> param,
    Map<String, PropertyValue> properties,
  ) {
    final name = param['name'] as String;
    final type = param['type'] as String?;
    final hint = (param['hint'] as Map?)?.cast<String, Object?>();
    final defaultValue = param['default'];
    final value = properties[name];
    switch (type) {
      case 'float' || 'int':
        final isInt = type == 'int';
        final ranged = hint?['kind'] == 'range';
        final min = ranged ? (hint!['min'] as num).toDouble() : 0.0;
        final max = ranged ? (hint!['max'] as num).toDouble() : 1.0;
        final current = switch (value) {
          DoubleValue(:final value) => value,
          IntValue(:final value) => value.toDouble(),
          _ => defaultValue is num ? defaultValue.toDouble() : 0.0,
        };
        // The slider track is bounded by the range hint (or 0-1 when
        // unranged), but the numeric field accepts any typed or scrubbed
        // value; a hint bounds the ergonomic range, not the parameter.
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: SliderNumberField(
            label: name,
            value: current,
            min: min,
            max: max,
            fractionDigits: isInt ? 0 : 3,
            onPreview: (v) => _preview(name, isInt ? v.round() : v),
            onCommit: (v) => _set(name, isInt ? v.round() : v),
          ),
        );
      case 'vec4' when hint?['kind'] == 'source_color':
        final fallback = defaultValue is List && defaultValue.length == 4
            ? [for (final c in defaultValue) (c as num).toDouble()]
            : const [1.0, 1.0, 1.0, 1.0];
        final c = value is ColorValue
            ? value
            : ColorValue(fallback[0], fallback[1], fallback[2], fallback[3]);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: ColorEditor(
            label: name,
            r: c.r,
            g: c.g,
            b: c.b,
            a: c.a,
            onPreview: (r, g, b, a) =>
                _preview(name, {'r': r, 'g': g, 'b': b, 'a': a}),
            onCommit: (r, g, b, a) =>
                _set(name, {'r': r, 'g': g, 'b': b, 'a': a}),
          ),
        );
      default:
        // TODO(fmat-inspector-vectors): field editors for vec2/vec3/plain
        // vec4/mat4 parameters; until then they are set in the .fmat default.
        return ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          title: Text('$name ($type)', style: const TextStyle(fontSize: 13)),
          subtitle: const Text(
            'Not editable here yet.',
            style: TextStyle(fontSize: 11, color: editorMutedTextColor),
          ),
        );
    }
  }

  Widget _fieldEditor(
    BuildContext context,
    _Field field,
    PropertyValue? value,
  ) {
    // An unset property is absent from the (sparse) material resource, so fall
    // back to the value the realized material actually uses, never a guessed
    // constant. Keeps every field showing the correct default.
    final effective = controller.effectiveMaterialValue(nodeId, field.key);
    switch (field.kind) {
      case _Kind.factor:
        final current = switch (value) {
          DoubleValue(:final value) => value,
          IntValue(:final value) => value.toDouble(),
          _ => effective is num ? effective.toDouble() : 0.0,
        };
        return LiveSlider(
          label: field.label,
          value: current.clamp(0.0, 1.0),
          onPreview: (v) => _preview(field.key, v),
          onCommit: (v) => _set(field.key, v),
        );
      case _Kind.strength:
        final current = switch (value) {
          DoubleValue(:final value) => value,
          IntValue(:final value) => value.toDouble(),
          _ => effective is num ? effective.toDouble() : 1.0,
        };
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: SliderNumberField(
            label: field.label,
            value: current,
            max: 10,
            onPreview: (v) => _preview(field.key, math.max(v, 0.0)),
            onCommit: (v) => _set(field.key, math.max(v, 0.0)),
          ),
        );
      case _Kind.boolean:
        final current = value is BoolValue && value.value;
        return InspectorSwitch(
          label: field.label,
          value: current,
          onChanged: (v) => _set(field.key, v),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        );
      case _Kind.choice:
        final current = value is StringValue
            ? value.value
            : field.options!.first;
        return LabeledControlRow(
          label: field.label,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          control: EditorDropdown<String>(
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
        final fallback = effective is Map
            ? [
                (effective['r'] as num).toDouble(),
                (effective['g'] as num).toDouble(),
                (effective['b'] as num).toDouble(),
                (effective['a'] as num).toDouble(),
              ]
            : _defaultColor(field.key);
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
