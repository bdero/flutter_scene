import 'dart:math' as math;

import 'package:scene/scene.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/fscene/realize/component_schema.dart';
import 'package:flutter/material.dart' hide Matrix4, Step;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:forui/forui.dart';
import 'package:vector_math/vector_math.dart' show Matrix4, Quaternion, Vector3;

import '../controller/editor_controller.dart';
import '../inspector/euler.dart';
import '../viewport/component_gizmos.dart' show componentGlyph;
import '../inspector/live_fields.dart';
import '../inspector/material_section.dart';
import '../inspector/nav_mesh_editor.dart';
import '../inspector/particle_emitter_controls.dart';
import '../inspector/vfx_editing.dart';
import '../inspector/particle_value_editors.dart';
import '../inspector/property_editors.dart';
import '../inspector/reference_picker.dart';
import '../inspector/resource_origin.dart';
import '../inspector/stage_section.dart';
import '../io/scene_io.dart';
import '../shell/editor_dialog.dart';
import '../shell/editor_theme.dart';

/// Property inspector for the primary selected node.
///
/// Shows editable name, visibility, transform (TRS), and per-component
/// property sections. Each field commit runs the appropriate command through
/// [EditorController.run], so every edit is undoable.
class InspectorPanel extends StatelessWidget {
  const InspectorPanel({super.key, required this.controller});

  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    return InspectorTextScope(
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final primary = controller.selection.primary;
          final node = primary != null ? controller.displayNode(primary) : null;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: node == null
                    ? const _NothingSelected()
                    : _NodeInspector(node: node, controller: controller),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// What the inspector says when nothing is selected.
///
/// It used to say it with the scene's settings, which made those the thing
/// you found by accident and the selected node the thing you went looking
/// for. They have their own place now, and this says where.
class _NothingSelected extends StatelessWidget {
  const _NothingSelected();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.ads_click_outlined,
            size: 22,
            color: editorMutedTextColor,
          ),
          const SizedBox(height: 8),
          const Text(
            'Select a node to edit it.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: editorMutedTextColor),
          ),
          const SizedBox(height: 4),
          Text(
            'The scene\'s own lighting, background and rendering are under '
            'File \u203a Scene Settings.',
            textAlign: TextAlign.center,
            style: editorDetailText,
          ),
        ],
      ),
    ),
  );
}

class _NodeInspector extends StatelessWidget {
  const _NodeInspector({required this.node, required this.controller});

  final NodeSpec node;
  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    // A node inside a prefab (its edits become overrides on the instance), and
    // the instance it belongs to (also set when the instance node itself is
    // selected, whose merged components come from the prefab).
    final isMember = controller.isPrefabMember(node.id);
    final isInstance = controller.document.nodes[node.id]?.instance != null;
    final instanceId = isMember
        ? controller.memberOrigin(node.id)!.instanceId
        : (isInstance ? node.id : null);
    // A component is removable when the document authored it here: on the
    // source node's own list (plain nodes and components added onto a prefab
    // instance), or in the enclosing instance's member-component delta (a
    // component added to this prefab member). Prefab-authored components
    // stay locked; suppressing those needs the removedComponentTypes
    // machinery (TODO(prefab-member-components)).
    final sourceComponents = controller.document.nodes[node.id]?.components;
    final memberAddedTypes = controller.memberAddedComponentTypes(node.id);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (instanceId != null)
            _PrefabBanner(
              isMember: isMember,
              source: _instanceSource(instanceId),
            ),
          EditorCollapsibleSection(
            key: const ValueKey('section:node'),
            label: 'Node',
            icon: Icons.category_outlined,
            // The node's own visibility, in the same place a component's
            // enabled flag sits, so the header means one thing throughout.
            enabled: node.visible,
            onEnabledChanged: (value) =>
                controller.setNodeVisibleRouted(node.id, value),
            child: _StringRow(
              label: 'Name',
              value: node.name,
              onSubmit: (v) => controller.setNodeNameRouted(node.id, v),
            ),
          ),
          const SizedBox(height: 8),
          EditorCollapsibleSection(
            key: const ValueKey('section:transform'),
            label: 'Transform',
            icon: Icons.open_with,
            child: _TransformEditor(node: node, controller: controller),
          ),
          // Components.
          for (final component in node.components) ...[
            const SizedBox(height: 8),
            _ComponentSection(
              node: node,
              component: component,
              controller: controller,
              canRemove: sourceComponents != null
                  ? sourceComponents.any((c) => c.type == component.type)
                  : memberAddedTypes.contains(component.type),
            ),
            // A mesh's material is a resource; edit it inline below the mesh.
            if (component.type == 'mesh' &&
                component.properties['material'] is ResourceRefValue)
              MaterialSection(
                controller: controller,
                nodeId: node.id,
                materialId:
                    (component.properties['material'] as ResourceRefValue).id,
              ),
            // A volume's environment is a resource; edit its look inline.
            if (component.type == 'environmentVolume' &&
                component.properties['environment'] is ResourceRefValue)
              _VolumeEnvironmentEditor(
                controller: controller,
                nodeId: node.id,
                environmentId:
                    (component.properties['environment'] as ResourceRefValue)
                        .id,
              ),
          ],
          // Components add onto any editable node: a source-document node
          // carries them directly (a prefab instance included), and a prefab
          // member records them on the enclosing instance's delta.
          const SizedBox(height: 8),
          _AddComponentBar(node: node, controller: controller),
          // Prefab actions (apply/revert) for the enclosing instance.
          if (instanceId != null) ...[
            const SizedBox(height: 8),
            _PrefabActions(
              instanceNodeId: instanceId,
              attachTarget: node.id,
              controller: controller,
            ),
          ],
        ],
      ),
    );
  }

  String _instanceSource(LocalId instanceId) =>
      controller.document.nodes[instanceId]?.instance?.source.key ?? '';
}

class _TransformEditor extends StatelessWidget {
  const _TransformEditor({required this.node, required this.controller});

  final NodeSpec node;
  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    final trs = node.transform is TrsTransform
        ? node.transform as TrsTransform
        : null;
    final t = trs?.translation;
    final r = trs?.rotation;
    final s = trs?.scale;
    final translation = t ?? Vector3.zero();
    final rotation = r ?? Quaternion.identity();
    final scale = s ?? Vector3.all(1);
    final live = controller.liveNode(node.id);
    final worldOrigin = live?.globalTransform.getTranslation();
    final geometryCenter = live?.combinedWorldBounds?.center;

    Vector3 vector(Map<String, Object> value) => Vector3(
      (value['x']! as num).toDouble(),
      (value['y']! as num).toDouble(),
      (value['z']! as num).toDouble(),
    );

    void preview(Vector3 t, Quaternion r, Vector3 s) {
      controller.previewLocalTransform(node.id, Matrix4.compose(t, r, s));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Vec3Field(
          label: 'Translation',
          x: t?.x ?? 0,
          y: t?.y ?? 0,
          z: t?.z ?? 0,
          scrubStep: 0.01,
          snapStep: 1,
          onPreview: (v) => preview(vector(v), rotation, scale),
          onSubmit: (v) =>
              controller.setNodeTransformRouted(node.id, translation: v),
        ),
        Vec3Field(
          label: 'Scale',
          x: s?.x ?? 1,
          y: s?.y ?? 1,
          z: s?.z ?? 1,
          scrubStep: 0.01,
          snapStep: 0.1,
          onPreview: (v) => preview(translation, rotation, vector(v)),
          onSubmit: (v) => controller.setNodeTransformRouted(node.id, scale: v),
        ),
        // Rotation as XYZ Euler degrees.
        Builder(
          builder: (context) {
            final euler = quaternionToEulerXyzDegrees(
              r ?? Quaternion.identity(),
            );
            return Vec3Field(
              label: 'Rotation',
              x: euler.x,
              y: euler.y,
              z: euler.z,
              scrubStep: 0.1,
              snapStep: 1,
              onPreview: (v) => preview(
                translation,
                eulerXyzDegreesToQuaternion(vector(v)),
                scale,
              ),
              onSubmit: (v) {
                final q = eulerXyzDegreesToQuaternion(vector(v));
                controller.setNodeTransformRouted(
                  node.id,
                  rotation: {'x': q.x, 'y': q.y, 'z': q.z, 'w': q.w},
                );
              },
            );
          },
        ),
        if (worldOrigin != null)
          _ReadOnlyVec3Row(label: 'World origin', value: worldOrigin),
        if (geometryCenter != null)
          _ReadOnlyVec3Row(label: 'Geometry center', value: geometryCenter),
      ],
    );
  }
}

class _ReadOnlyVec3Row extends StatelessWidget {
  const _ReadOnlyVec3Row({required this.label, required this.value});

  final String label;
  final Vector3 value;

  @override
  Widget build(BuildContext context) {
    String number(double value) => value.toStringAsFixed(3);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 11,
              ),
            ),
          ),
          Expanded(
            child: Text(
              '${number(value.x)}, ${number(value.y)}, ${number(value.z)}',
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
                fontSize: 11,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

/// A component's section header (type name + remove button) and its editor.
class _ComponentSection extends StatelessWidget {
  const _ComponentSection({
    required this.node,
    required this.component,
    required this.controller,
    required this.canRemove,
  });

  final NodeSpec node;
  final ComponentSpec component;
  final EditorController controller;
  final bool canRemove;

  // The header's right-click menu: source-file actions (enabled when the
  // component came from project source extraction) and removal (mirroring
  // the header's close button).
  Future<void> _showContextMenu(BuildContext context, Offset position) async {
    final sourcePath = controller.componentSourcePaths[component.type];
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    const itemStyle = TextStyle(fontSize: 12);
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          value: 'copy',
          enabled: sourcePath != null,
          height: 34,
          child: const Text('Copy source path', style: itemStyle),
        ),
        PopupMenuItem(
          value: 'open',
          enabled: sourcePath != null,
          height: 34,
          child: const Text('Open source in editor', style: itemStyle),
        ),
        PopupMenuItem(
          value: 'remove',
          enabled: canRemove,
          height: 34,
          child: const Text('Remove component', style: itemStyle),
        ),
      ],
    );
    switch (action) {
      case 'copy':
        await Clipboard.setData(ClipboardData(text: sourcePath!));
      case 'open':
        await controller.sourceFileOpener?.call(sourcePath!);
      case 'remove':
        await controller.removeComponentRouted(node.id, component.type);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onSecondaryTapUp: (details) =>
              _showContextMenu(context, details.globalPosition),
          child: EditorCollapsibleSection(
            // Keyed by type so folding one component does not fold whichever
            // component happens to take its place after a reorder.
            key: ValueKey('component:${component.type}'),
            label: component.type,
            icon: componentPickerGlyph((
              category: controller.componentSchemaFor(component.type)?.category,
              icon: controller.componentSchemaFor(component.type)?.icon,
              provenance: controller.foreignTypeProvenance[component.type],
            )),
            enabled: switch (component.properties['enabled']) {
              BoolValue(value: final value) => value,
              // Absent means the default, which is on.
              _ => true,
            },
            onEnabledChanged: (value) => controller.setComponentPropertyRouted(
              node.id,
              component.type,
              'enabled',
              value,
            ),
            trailing: canRemove
                ? _IconAction(
                    icon: Icons.close,
                    tooltip: 'Remove component',
                    onPressed: () => controller.removeComponentRouted(
                      node.id,
                      component.type,
                    ),
                  )
                : null,
            child: switch (component.type) {
              // A nav surface is bake settings plus a bake, not a property
              // bag: the four agent numbers only mean anything drawn
              // together, and nothing in a schema-driven list runs a bake.
              'navMeshSurface' => NavMeshEditor(
                controller: controller,
                nodeId: node.id,
              ),
              // An emitter's authored fields are a property bag, but its
              // clock is not: play, pause and restart reach the running
              // simulation, and restart is how a one-shot is fired at all.
              vfxComponentType => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ParticleEmitterControls(
                    controller: controller,
                    nodeId: node.id,
                  ),
                  _ComponentEditor(
                    node: node,
                    component: component,
                    controller: controller,
                  ),
                ],
              ),
              _ => _ComponentEditor(
                node: node,
                component: component,
                controller: controller,
              ),
            },
          ),
        ),
      ],
    );
  }
}

/// Renders a component's editable properties from its declared schema, falling
/// back to whatever is in the property bag for keys the schema does not cover.
/// A field shows the bag's value when present, otherwise the schema default.
class _ComponentEditor extends StatelessWidget {
  const _ComponentEditor({
    required this.node,
    required this.component,
    required this.controller,
  });

  final NodeSpec node;
  final ComponentSpec component;
  final EditorController controller;

  void _set(String name, Object? value) {
    if (value == null) return;
    controller.setComponentPropertyRouted(node.id, component.type, name, value);
  }

  @override
  Widget build(BuildContext context) {
    final schema = controller.componentSchema(component.type);
    final schemaNames = {for (final d in schema) d.name};
    // Keys present on the component but not described by the schema, so nothing
    // a node carries is ever hidden.
    final extras = [
      for (final entry in component.properties.entries)
        if (!schemaNames.contains(entry.key)) entry,
    ];

    if (schema.isEmpty && extras.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 2),
        child: Text(
          '(no editable properties)',
          style: TextStyle(fontSize: 11, color: editorMutedTextColor),
        ),
      );
    }

    Widget row(ComponentPropertyDef def) => _SchemaPropertyRow(
      componentType: component.type,
      def: def,
      value: component.properties[def.name] ?? def.defaultValue,
      controller: controller,
      onChanged: (v) => _set(def.name, v),
    );

    // Ungrouped properties render flat; each declared group folds into an
    // accordion section, in first-appearance order.
    final ungrouped = [
      for (final def in schema)
        if (def.group == null) def,
    ];
    final groups = <String, List<ComponentPropertyDef>>{};
    for (final def in schema) {
      final group = def.group;
      if (group != null) groups.putIfAbsent(group, () => []).add(def);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final def in ungrouped) row(def),
        if (groups.isNotEmpty)
          InspectorAccordion(
            identity: '${node.id.toToken()}/${component.type}',
            children: [
              for (final entry in groups.entries)
                InspectorAccordionItem(
                  title: Text(entry.key),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [for (final def in entry.value) row(def)],
                  ),
                ),
            ],
          ),
        for (final entry in extras)
          _PropertyValueRow(
            label: entry.key,
            value: entry.value,
            onChanged: (v) => _set(entry.key, v),
          ),
      ],
    );
  }
}

/// Renders one declared property by its [ComponentPropertyKind], using
/// [value] (the current value or the schema default, possibly null).
class _SchemaPropertyRow extends StatelessWidget {
  const _SchemaPropertyRow({
    required this.componentType,
    required this.def,
    required this.value,
    required this.controller,
    required this.onChanged,
  });

  final String componentType;
  final ComponentPropertyDef def;
  final PropertyValue? value;
  final EditorController controller;
  final void Function(Object?) onChanged;

  double _double(double fallback) {
    final v = value;
    if (v is DoubleValue) return v.value;
    if (v is IntValue) return v.value.toDouble();
    return fallback;
  }

  // A slider renders when the schema declares a soft range (or a fully
  // bounded hard range); otherwise a plain scrub field, clamped by the
  // command layer against the hard bounds.
  ({double min, double max, double step, int digits})? _sliderRange(
    double current,
  ) {
    final soft = def.constraint<SoftRange>();
    final min = soft?.min ?? def.hardMin;
    final max = soft?.max ?? def.hardMax;
    if (min == null || max == null) return null;
    final span = max - min;
    final step =
        def.constraint<Step>()?.step ?? (span <= 2 ? 0.01 : span / 200);
    final digits = step >= 1
        ? 0
        : step >= 0.1
        ? 2
        : step >= 0.01
        ? 3
        : 4;
    return (min: min, max: max, step: step, digits: digits);
  }

  bool get _degrees => def.constraint<AngleRadians>() != null;

  List<int> _powersOfTwo(PowerOfTwo constraint) {
    final powers = <int>[];
    for (var value = 1; value <= (constraint.max ?? 1 << 14); value <<= 1) {
      if (value >= constraint.min) powers.add(value);
    }
    return powers;
  }

  /// A one-line summary of a value nobody may edit here. Deliberately short:
  /// a payload token or a byte count says the thing is present, and the
  /// whole point is that its contents are not a person's business.
  String _summary() => switch (value) {
    null => '(not set)',
    StringValue(:final value) => value.isEmpty ? '(none)' : value,
    BoolValue(:final value) => '$value',
    IntValue(:final value) => '$value',
    DoubleValue(:final value) => '$value',
    _ => '(set)',
  };

  Widget _buildEditor(BuildContext context) {
    final label = def.name;
    if (def.constraint<ReadOnly>() != null) {
      return _ReadOnlyRow(label: label, text: _summary());
    }
    switch (def.kind) {
      case ComponentPropertyKind.boolean:
        return _BoolRow(
          label: label,
          value: value is BoolValue ? (value as BoolValue).value : false,
          onChanged: onChanged,
        );
      case ComponentPropertyKind.integer:
        final powerOfTwo = def.constraint<PowerOfTwo>();
        final current = value is IntValue ? (value as IntValue).value : 0;
        if (powerOfTwo != null) {
          final powers = _powersOfTwo(powerOfTwo);
          return _EnumRow(
            label: label,
            value: '$current',
            options: [for (final power in powers) '$power'],
            onChanged: (name) => onChanged(int.tryParse(name) ?? current),
          );
        }
        final range = _sliderRange(current.toDouble());
        if (range != null) {
          return SliderNumberField(
            label: label,
            value: current.toDouble(),
            min: range.min,
            max: range.max,
            scrubStep: math.max(1, range.step),
            snapStep: math.max(1, range.step),
            fractionDigits: 0,
            onPreview: (_) {},
            onCommit: (value) => onChanged(value.round()),
          );
        }
        return _IntRow(label: label, value: current, onSubmit: onChanged);
      case ComponentPropertyKind.number:
        final scale = _degrees ? 180 / math.pi : 1.0;
        final current = _double(0) * scale;
        final suffix = _degrees ? ' (degrees)' : '';
        final range = _sliderRange(current);
        if (range != null) {
          return SliderNumberField(
            label: '$label$suffix',
            value: current,
            min: range.min * scale,
            max: range.max * scale,
            scrubStep: _degrees ? 1.0 : range.step,
            snapStep: _degrees ? 1.0 : range.step,
            fractionDigits: _degrees ? 1 : range.digits,
            onPreview: (_) {},
            onCommit: (value) => onChanged(value / scale),
          );
        }
        return _DoubleRow(
          label: '$label$suffix',
          value: current,
          onSubmit: (raw) => onChanged(raw / scale),
        );
      case ComponentPropertyKind.string:
      case ComponentPropertyKind.assetRef:
        if (def.options != null) {
          return _EnumRow(
            label: label,
            value: value is StringValue ? (value as StringValue).value : null,
            options: def.options!,
            onChanged: onChanged,
          );
        }
        return _StringRow(
          label: label,
          value: value is StringValue ? (value as StringValue).value : '',
          onSubmit: onChanged,
        );
      case ComponentPropertyKind.vec2:
        final v = value is Vec2Value ? (value as Vec2Value).value : null;
        return _Vec2Row(
          label: label,
          x: v?.x ?? 0,
          y: v?.y ?? 0,
          onSubmit: onChanged,
        );
      case ComponentPropertyKind.vec3:
        final v = value is Vec3Value ? (value as Vec3Value).value : null;
        if (def.constraint<RgbColor>() != null) {
          return ColorEditor(
            channelBuilder: sliderColorChannel,
            label: label,
            r: v?.x ?? 1,
            g: v?.y ?? 1,
            b: v?.z ?? 1,
            a: 1,
            showAlpha: false,
            onPreview: (_, _, _, _) {},
            onCommit: (r, g, b, _) => onChanged({'x': r, 'y': g, 'z': b}),
          );
        }
        return Vec3Field(
          label: label,
          x: v?.x ?? 0,
          y: v?.y ?? 0,
          z: v?.z ?? 0,
          onSubmit: onChanged,
        );
      case ComponentPropertyKind.vec4:
        final v = value is Vec4Value ? (value as Vec4Value).value : null;
        return _Vec4Row(
          label: label,
          x: v?.x ?? 0,
          y: v?.y ?? 0,
          z: v?.z ?? 0,
          w: v?.w ?? 0,
          onSubmit: onChanged,
        );
      case ComponentPropertyKind.quaternion:
        final q = value is QuaternionValue
            ? (value as QuaternionValue).value
            : Quaternion.identity();
        final euler = quaternionToEulerXyzDegrees(q);
        return Vec3Field(
          label: '$label (euler degrees)',
          x: euler.x,
          y: euler.y,
          z: euler.z,
          onSubmit: (v) {
            final rotated = eulerXyzDegreesToQuaternion(
              Vector3(
                (v['x'] as num?)?.toDouble() ?? euler.x,
                (v['y'] as num?)?.toDouble() ?? euler.y,
                (v['z'] as num?)?.toDouble() ?? euler.z,
              ),
            );
            onChanged({
              r'$quat': {
                'x': rotated.x,
                'y': rotated.y,
                'z': rotated.z,
                'w': rotated.w,
              },
            });
          },
        );
      case ComponentPropertyKind.color:
        return _ColorRow(
          label: label,
          value: value is ColorValue ? value as ColorValue : null,
          onChanged: onChanged,
        );
      case ComponentPropertyKind.resourceRef:
        return _ResourceRefRow(
          label: label,
          resourceKind: def.resourceKind,
          value: value is ResourceRefValue
              ? (value as ResourceRefValue).id
              : null,
          controller: controller,
          onChanged: onChanged,
        );
      case ComponentPropertyKind.nodeRef:
        return _NodeRefRow(
          label: label,
          value: value is NodeRefValue ? (value as NodeRefValue).id : null,
          controller: controller,
          onChanged: onChanged,
        );
      case ComponentPropertyKind.distribution:
        return DistributionField(
          label: label,
          value: value,
          onChanged: onChanged,
        );
      case ComponentPropertyKind.curve:
        return CurveField(label: label, value: value, onChanged: onChanged);
      case ComponentPropertyKind.gradient:
        return GradientEditor(label: label, value: value, onChanged: onChanged);
      case ComponentPropertyKind.object:
        return _ObjectRow(
          label: label,
          def: def,
          value: value is MapValue ? value as MapValue : null,
          controller: controller,
          onChanged: onChanged,
        );
      case ComponentPropertyKind.union:
        return _UnionRow(
          label: label,
          def: def,
          value: value is MapValue ? value as MapValue : null,
          controller: controller,
          onChanged: onChanged,
        );
      case ComponentPropertyKind.list:
        // A list with no item descriptor says nothing about what it holds, so
        // there is no editor to offer for it.
        if (def.itemDef == null) {
          return _ReadOnlyRow(label: label, text: '(list)');
        }
        return _ListRow(
          label: label,
          def: def,
          value: value is ListValue ? value as ListValue : null,
          controller: controller,
          onChanged: onChanged,
        );
      case ComponentPropertyKind.matrix4:
      case ComponentPropertyKind.map:
        // TODO(component-property-editors): matrix4 and open-map editors.
        return _ReadOnlyRow(label: label, text: '(${def.kind.name})');
    }
  }

  @override
  Widget build(BuildContext context) {
    final editor = _buildEditor(context);
    final doc = def.doc;
    if (doc == null || doc.isEmpty) return editor;
    return Tooltip(
      message: doc,
      waitDuration: const Duration(milliseconds: 600),
      child: editor,
    );
  }
}

/// Loosens a typed [PropertyValue] back into the raw JSON shape the command
/// layer coerces, so structured editors can resubmit whole objects with one
/// field changed.
Object? _rawFromValue(PropertyValue? value) => switch (value) {
  null => null,
  BoolValue(:final value) => value,
  IntValue(:final value) => value,
  DoubleValue(:final value) => value,
  StringValue(:final value) => value,
  Vec2Value(:final value) => {'x': value.x, 'y': value.y},
  Vec3Value(:final value) => {'x': value.x, 'y': value.y, 'z': value.z},
  Vec4Value(:final value) => {
    'x': value.x,
    'y': value.y,
    'z': value.z,
    'w': value.w,
  },
  QuaternionValue(:final value) => {
    r'$quat': {'x': value.x, 'y': value.y, 'z': value.z, 'w': value.w},
  },
  Matrix4Value(:final value) => [for (final v in value.storage) v],
  ColorValue() => {'r': value.r, 'g': value.g, 'b': value.b, 'a': value.a},
  ResourceRefValue(:final id) => {r'$resource': id.toToken()},
  NodeRefValue(:final id) => {r'$node': id.toToken()},
  ListValue(:final values) => [for (final v in values) _rawFromValue(v)],
  MapValue(:final values) => {
    for (final entry in values.entries) entry.key: _rawFromValue(entry.value),
  },
};

/// Nested-object editor: renders the declared fields and resubmits the whole
/// object on any field change.
/// Edits a list of structured entries: LOD levels, animator states, the
/// waypoints of a camera path.
///
/// Entries fold, because a list of five objects with six fields each is
/// unreadable open. Each carries its index, since order is meaningful in
/// every list the schema declares — a LOD's levels run coarse to fine, a
/// blend's stops run along their parameter.
class _ListRow extends StatefulWidget {
  const _ListRow({
    required this.label,
    required this.def,
    required this.value,
    required this.controller,
    required this.onChanged,
  });

  final String label;
  final ComponentPropertyDef def;
  final ListValue? value;
  final EditorController controller;
  final void Function(Object?) onChanged;

  @override
  State<_ListRow> createState() => _ListRowState();
}

class _ListRowState extends State<_ListRow> {
  int? _open;

  ComponentPropertyDef get _itemDef => widget.def.itemDef!;

  List<PropertyValue> get _entries =>
      widget.value?.values ?? const <PropertyValue>[];

  /// The smallest number of entries the schema will accept, so removal can
  /// stop rather than producing something that fails to load.
  int get _minimum => widget.def.constraint<MinCount>()?.count ?? 0;

  void _submit(List<PropertyValue> entries) =>
      widget.onChanged([for (final entry in entries) _rawFromValue(entry)]);

  void _add() {
    final entries = [..._entries];
    // A new entry starts from the item's declared defaults rather than empty,
    // so it is valid the moment it exists.
    entries.add(
      _itemDef.kind == ComponentPropertyKind.object
          ? MapValue({
              for (final field in _itemDef.objectFields ?? const [])
                if (field.defaultValue case final value?) field.name: value,
            })
          : _itemDef.defaultValue ?? const BoolValue(false),
    );
    setState(() => _open = entries.length - 1);
    _submit(entries);
  }

  void _removeAt(int index) {
    final entries = [..._entries]..removeAt(index);
    setState(() => _open = null);
    _submit(entries);
  }

  void _move(int index, int by) {
    final target = index + by;
    if (target < 0 || target >= _entries.length) return;
    final entries = [..._entries];
    final moved = entries.removeAt(index);
    entries.insert(target, moved);
    setState(() => _open = target);
    _submit(entries);
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${widget.label}  (${entries.length})',
                  style: editorDetailText,
                ),
              ),
              _IconAction(
                icon: Icons.add,
                tooltip: 'Add ${widget.label}',
                onPressed: _add,
              ),
            ],
          ),
          if (entries.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Text('Empty', style: editorDetailText),
            ),
          for (var i = 0; i < entries.length; i++)
            _ListEntry(
              index: i,
              open: _open == i,
              canRemove: entries.length > _minimum,
              onToggle: () => setState(() => _open = _open == i ? null : i),
              onRemove: () => _removeAt(i),
              onMoveUp: i == 0 ? null : () => _move(i, -1),
              onMoveDown: i == entries.length - 1 ? null : () => _move(i, 1),
              child: _SchemaPropertyRow(
                componentType: '',
                def: _itemDef,
                value: entries[i],
                controller: widget.controller,
                // Entries go back out as raw values, so an edited one is
                // spliced into the raw list rather than converted back into a
                // PropertyValue first.
                onChanged: (raw) {
                  final next = [
                    for (final entry in _entries) _rawFromValue(entry),
                  ];
                  next[i] = raw;
                  widget.onChanged(next);
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// One entry of a [_ListRow]: a numbered header with reorder and remove, and
/// the entry's own editor beneath when open.
class _ListEntry extends StatelessWidget {
  const _ListEntry({
    required this.index,
    required this.open,
    required this.canRemove,
    required this.onToggle,
    required this.onRemove,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.child,
  });

  final int index;
  final bool open;
  final bool canRemove;
  final VoidCallback onToggle;
  final VoidCallback onRemove;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Icon(
                  open ? Icons.arrow_drop_down : Icons.arrow_right,
                  size: editorIconSizeLarge,
                  color: editorMutedTextColor,
                ),
                Expanded(child: Text('$index', style: editorDetailText)),
                _IconAction(
                  icon: Icons.arrow_upward,
                  tooltip: 'Move up',
                  onPressed: onMoveUp,
                ),
                _IconAction(
                  icon: Icons.arrow_downward,
                  tooltip: 'Move down',
                  onPressed: onMoveDown,
                ),
                _IconAction(
                  icon: Icons.close,
                  tooltip: canRemove ? 'Remove' : 'The list needs this entry',
                  onPressed: canRemove ? onRemove : null,
                ),
              ],
            ),
          ),
        ),
        if (open)
          Padding(
            padding: const EdgeInsets.only(left: 10, bottom: 4),
            child: child,
          ),
      ],
    );
  }
}

class _ObjectRow extends StatelessWidget {
  const _ObjectRow({
    required this.label,
    required this.def,
    required this.value,
    required this.controller,
    required this.onChanged,
  });

  final String label;
  final ComponentPropertyDef def;
  final MapValue? value;
  final EditorController controller;
  final void Function(Object?) onChanged;

  @override
  Widget build(BuildContext context) {
    final fields = def.objectFields ?? const <ComponentPropertyDef>[];
    final current = value?.values ?? const <String, PropertyValue>{};
    void submitField(String name, Object? raw) {
      final merged = <String, Object?>{
        for (final entry in current.entries)
          entry.key: _rawFromValue(entry.value),
      };
      merged[name] = raw;
      onChanged(merged);
    }

    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(label, style: const TextStyle(fontSize: 11)),
          ),
          for (final field in fields)
            _SchemaPropertyRow(
              componentType: '',
              def: field,
              value: current[field.name] ?? field.defaultValue,
              controller: controller,
              onChanged: (raw) => submitField(field.name, raw),
            ),
        ],
      ),
    );
  }
}

/// Tagged-union editor: a variant dropdown plus the selected variant's
/// fields, resubmitting the whole union value on any change.
class _UnionRow extends StatelessWidget {
  const _UnionRow({
    required this.label,
    required this.def,
    required this.value,
    required this.controller,
    required this.onChanged,
  });

  final String label;
  final ComponentPropertyDef def;
  final MapValue? value;
  final EditorController controller;
  final void Function(Object?) onChanged;

  @override
  Widget build(BuildContext context) {
    final variants = def.unionVariants ?? const {};
    final current = value?.values ?? const <String, PropertyValue>{};
    final tagValue = current[def.unionTag];
    final tag = tagValue is StringValue && variants.containsKey(tagValue.value)
        ? tagValue.value
        : (variants.isEmpty ? null : variants.keys.first);
    final fields = tag == null
        ? const <ComponentPropertyDef>[]
        : variants[tag]!;

    void submitField(String name, Object? raw) {
      final merged = <String, Object?>{
        def.unionTag: tag,
        for (final entry in current.entries)
          if (entry.key != def.unionTag) entry.key: _rawFromValue(entry.value),
      };
      merged[name] = raw;
      onChanged(merged);
    }

    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _EnumRow(
            label: label,
            value: tag,
            options: variants.keys.toList(),
            // Switching variants starts from that variant's defaults.
            onChanged: (nextTag) => onChanged({def.unionTag: nextTag}),
          ),
          for (final field in fields)
            _SchemaPropertyRow(
              componentType: '',
              def: field,
              value: current[field.name] ?? field.defaultValue,
              controller: controller,
              onChanged: (raw) => submitField(field.name, raw),
            ),
        ],
      ),
    );
  }
}

/// Two scrub fields submitting `{x, y}`.
class _Vec2Row extends StatelessWidget {
  const _Vec2Row({
    required this.label,
    required this.x,
    required this.y,
    required this.onSubmit,
  });

  final String label;
  final double x;
  final double y;
  final void Function(Object?) onSubmit;

  @override
  Widget build(BuildContext context) => LabeledControlRow(
    label: label,
    control: Row(
      children: [
        Expanded(
          child: ScrubbableNumberField(
            label: 'X',
            color: editorAxisColors[0],
            value: x,
            scrubStep: 0.01,
            snapStep: 1,
            onCommit: (v) => onSubmit({'x': v, 'y': y}),
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: ScrubbableNumberField(
            label: 'Y',
            color: editorAxisColors[1],
            value: y,
            scrubStep: 0.01,
            snapStep: 1,
            onCommit: (v) => onSubmit({'x': x, 'y': v}),
          ),
        ),
      ],
    ),
  );
}

/// Four scrub fields submitting `{x, y, z, w}`.
class _Vec4Row extends StatelessWidget {
  const _Vec4Row({
    required this.label,
    required this.x,
    required this.y,
    required this.z,
    required this.w,
    required this.onSubmit,
  });

  final String label;
  final double x;
  final double y;
  final double z;
  final double w;
  final void Function(Object?) onSubmit;

  @override
  Widget build(BuildContext context) {
    Map<String, Object> withComponent(String key, double v) => {
      'x': key == 'x' ? v : x,
      'y': key == 'y' ? v : y,
      'z': key == 'z' ? v : z,
      'w': key == 'w' ? v : w,
    };
    return LabeledControlRow(
      label: label,
      control: Row(
        children: [
          for (final (key, current) in [('x', x), ('y', y), ('z', z), ('w', w)])
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 4),
                child: ScrubbableNumberField(
                  label: key.toUpperCase(),
                  color:
                      editorAxisColors[key == 'x'
                          ? 0
                          : key == 'y'
                          ? 1
                          : 2],
                  value: current,
                  scrubStep: 0.01,
                  snapStep: 1,
                  onCommit: (v) => onSubmit(withComponent(key, v)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Displays one typed [PropertyValue] as an editable field, inferring the widget
/// from the value type (used for schema-less keys present on the component).
class _PropertyValueRow extends StatelessWidget {
  const _PropertyValueRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final PropertyValue value;
  final void Function(Object?) onChanged;

  @override
  Widget build(BuildContext context) {
    return switch (value) {
      BoolValue v => _BoolRow(
        label: label,
        value: v.value,
        onChanged: onChanged,
      ),
      IntValue v => _IntRow(label: label, value: v.value, onSubmit: onChanged),
      DoubleValue v => _DoubleRow(
        label: label,
        value: v.value,
        onSubmit: onChanged,
      ),
      StringValue v => _StringRow(
        label: label,
        value: v.value,
        onSubmit: onChanged,
      ),
      Vec3Value v => Vec3Field(
        label: label,
        x: v.value.x,
        y: v.value.y,
        z: v.value.z,
        onSubmit: onChanged,
      ),
      _ => _ReadOnlyRow(label: label, text: '(${value.runtimeType})'),
    };
  }
}

/// A row that lets the user add a component of any type not already on the node.
class _AddComponentBar extends StatelessWidget {
  const _AddComponentBar({required this.node, required this.controller});

  final NodeSpec node;
  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    final present = {for (final c in node.components) c.type};
    final available = [
      for (final type in controller.componentTypes())
        if (!present.contains(type)) type,
    ];
    final enabled = available.isNotEmpty;
    final tint = enabled
        ? Theme.of(context).colorScheme.primary
        : editorMutedTextColor;
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton(
        onPressed: enabled
            ? () async {
                final type = await showAddComponentPicker(
                  context,
                  controller: controller,
                  available: available,
                );
                if (type != null) {
                  controller.addComponentRouted(node.id, type);
                }
              }
            : null,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add, size: 14, color: tint),
            const SizedBox(width: 4),
            Text('Add Component', style: TextStyle(fontSize: 11, color: tint)),
          ],
        ),
      ),
    );
  }
}

/// What the picker knows about one component type: the category and icon its
/// schema declares (if any) and where the editor learned about it.
typedef ComponentTypeInfo = ({
  String? category,
  String? icon,
  String? provenance,
});

/// The glyph shown beside [type] in the picker.
///
/// A schema's own icon wins; otherwise the row falls back to its category's
/// glyph, so every row carries something. A component that declares nothing
/// and sits in no category still reads as a component rather than as a gap.
IconData componentPickerGlyph(ComponentTypeInfo info) =>
    componentGlyph(info.icon) ??
    switch (addComponentCategory(info)) {
      'Mesh' => Icons.view_in_ar_outlined,
      'Effects' => Icons.auto_awesome_outlined,
      'Rendering' => Icons.lightbulb_outline,
      'Cameras' => Icons.videocam_outlined,
      'Physics' => Icons.animation_outlined,
      'Audio' => Icons.volume_up_outlined,
      'Animation' => Icons.movie_filter_outlined,
      'Navigation' => Icons.route_outlined,
      'UI' => Icons.widgets_outlined,
      'Scripts' => Icons.code,
      'Packages' => Icons.inventory_2_outlined,
      _ => Icons.settings_input_component_outlined,
    };

/// Where a type sits in the picker: its declared category, "Scripts" for a
/// project's own components, "Packages" for a dependency's, and "Other" for
/// anything that declares nothing.
///
/// Project components are grouped by where they came from rather than by what
/// they do, because that is what you are looking for when you have just
/// written one.
String addComponentCategory(ComponentTypeInfo info) {
  final declared = info.category;
  if (declared != null && declared.isNotEmpty) return declared;
  return switch (info.provenance) {
    'live' || 'cache' => 'Scripts',
    null => 'Other',
    _ => 'Packages',
  };
}

/// Groups [types] by [addComponentCategory], each group sorted by name.
///
/// The built-in groups come first and alphabetically, so they keep their
/// positions as a project grows. After them come the project's own Scripts —
/// the ones you most often want and the only ones you can edit — then
/// Packages, then Other as the genuine catch-all.
List<MapEntry<String, List<String>>> groupComponentTypes(
  Map<String, ComponentTypeInfo> types,
) {
  final groups = <String, List<String>>{};
  for (final entry in types.entries) {
    groups
        .putIfAbsent(addComponentCategory(entry.value), () => [])
        .add(entry.key);
  }
  const last = ['Scripts', 'Packages', 'Other'];
  int rank(String name) {
    final index = last.indexOf(name);
    return index < 0 ? 0 : index + 1;
  }

  final names = groups.keys.toList()
    ..sort((a, b) {
      final byRank = rank(a).compareTo(rank(b));
      return byRank != 0 ? byRank : a.compareTo(b);
    });
  return [for (final name in names) MapEntry(name, groups[name]!..sort())];
}

/// Whether [type] matches [query], case-insensitively, on its name or its
/// category — so "phys" finds every physics component, not only the one
/// spelled that way.
bool matchesComponentQuery(String type, ComponentTypeInfo info, String query) {
  if (query.isEmpty) return true;
  final needle = query.toLowerCase();
  return type.toLowerCase().contains(needle) ||
      addComponentCategory(info).toLowerCase().contains(needle);
}

/// The component picker: a search field over every type this node does not
/// already carry, grouped by category.
Future<String?> showAddComponentPicker(
  BuildContext context, {
  required EditorController controller,
  required List<String> available,
}) {
  ComponentTypeInfo infoOf(String type) {
    final schema = controller.componentSchemaFor(type);
    return (
      category: schema?.category,
      icon: schema?.icon,
      provenance: controller.foreignTypeProvenance[type],
    );
  }

  final search = TextEditingController();
  return showEditorFDialog<String>(
    context: context,
    builder: (context, style, animation) => StatefulBuilder(
      builder: (context, setLocal) {
        final query = search.text.trim();
        final matching = <String, ComponentTypeInfo>{
          for (final type in available)
            if (matchesComponentQuery(type, infoOf(type), query))
              type: infoOf(type),
        };
        final groups = groupComponentTypes(matching);
        return FDialog(
          animation: animation,
          builder: (context, style) => Padding(
            padding: const EdgeInsets.all(14),
            child: SizedBox(
              width: 380,
              height: 460,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Add Component', style: editorDialogTitleText),
                  const SizedBox(height: 10),
                  FTextField(
                    control: FTextFieldControl.managed(
                      controller: search,
                      onChange: (_) => setLocal(() {}),
                    ),
                    autofocus: true,
                    hint: 'Search',
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: matching.isEmpty
                        ? const Center(
                            child: Text(
                              'No component matches.',
                              style: TextStyle(
                                fontSize: 11,
                                color: editorMutedTextColor,
                              ),
                            ),
                          )
                        : ListView(
                            primary: false,
                            children: [
                              for (final group in groups) ...[
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    2,
                                    10,
                                    2,
                                    4,
                                  ),
                                  child: Text(
                                    group.key.toUpperCase(),
                                    style: const TextStyle(
                                      fontSize: 9,
                                      letterSpacing: 1.1,
                                      color: editorMutedTextColor,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                for (final type in group.value)
                                  _ComponentPickerRow(
                                    type: type,
                                    info: infoOf(type),
                                    onTap: () => Navigator.pop(context, type),
                                  ),
                              ],
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

class _ComponentPickerRow extends StatelessWidget {
  const _ComponentPickerRow({
    required this.type,
    required this.info,
    required this.onTap,
  });

  final String type;
  final ComponentTypeInfo info;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final provenance = info.provenance;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
        child: Row(
          children: [
            Icon(
              componentPickerGlyph(info),
              size: 14,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(type, style: const TextStyle(fontSize: 12))),
            // Types the editor knows by schema but did not compile show where
            // that schema came from.
            if (provenance != null)
              Text(
                provenance == 'live' ? 'project' : provenance,
                style: const TextStyle(
                  fontSize: 9,
                  color: editorMutedTextColor,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---- prefab in-context editing ----------------------------------------------

/// A banner shown above the inspector when the selected node is prefab content,
/// explaining that edits become overrides on the instance.
class _PrefabBanner extends StatelessWidget {
  const _PrefabBanner({required this.isMember, required this.source});

  final bool isMember;
  final String source;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Icon(Icons.link, size: 12, color: scheme.tertiary),
          const SizedBox(width: 6),
          Expanded(
            child: InspectorDescriptionText(
              isMember
                  ? 'Prefab content from $source. Edits are saved as overrides.'
                  : 'Prefab instance of $source.',
              style: TextStyle(fontSize: 10, color: scheme.onTertiaryContainer),
            ),
          ),
          const SizedBox(width: 4),
          OriginBadge(
            locality: ResourceLocality.external,
            path: source,
            dense: true,
          ),
        ],
      ),
    );
  }
}

/// Apply/revert actions for the enclosing prefab instance: bake the instance's
/// delta into the prefab source, or drop all overrides.
class _PrefabActions extends StatelessWidget {
  const _PrefabActions({
    required this.instanceNodeId,
    required this.attachTarget,
    required this.controller,
  });

  final LocalId instanceNodeId;

  /// The node a new attached node parents under (the selected member, or the
  /// instance node to attach at its root).
  final LocalId attachTarget;
  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    final instance = controller.document.nodes[instanceNodeId]?.instance;
    if (instance == null) return const SizedBox.shrink();
    final overrides = instance.overrides.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EditorSectionHeader(label: 'Prefab'),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              OriginBadge(
                locality: ResourceLocality.external,
                path: instance.source.key,
                dense: true,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${instance.source.key}  ($overrides override'
                  '${overrides == 1 ? '' : 's'})',
                  style: const TextStyle(
                    fontSize: 10,
                    color: editorMutedTextColor,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 2),
          child: _SmallButton(
            label: 'Attach node here',
            tooltip:
                'Adds a node attached under this node. It is a normal scene '
                'node you can move, add components to, and delete.',
            onPressed: () => controller.attachNodeUnder(attachTarget),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 2, bottom: 4),
          child: Row(
            children: [
              Expanded(
                child: _SmallButton(
                  label: 'Apply to prefab',
                  tooltip:
                      'Bakes this instance\'s overrides into the prefab '
                      '.fscene, then clears them. Every instance reflects it.',
                  onPressed: () => _applyToSource(context, instance.source.key),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _SmallButton(
                  label: 'Revert all',
                  tooltip: 'Drops all overrides on this instance.',
                  onPressed: () => controller.run('clearPrefabOverrides', {
                    'nodeId': instanceNodeId.toToken(),
                  }),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _applyToSource(BuildContext context, String key) async {
    final messenger = ScaffoldMessenger.of(context);
    final instance = controller.document.nodes[instanceNodeId]?.instance;
    if (instance == null) return;
    final dir = controller.baseDirectory;
    if (!key.startsWith('/') && dir == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Cannot apply: the scene has no base directory (save it first).',
          ),
        ),
      );
      return;
    }
    final path = key.startsWith('/') ? key : '$dir/$key';
    try {
      await applyInstanceToSource(
        sourcePath: path,
        host: controller.document,
        instance: instance,
      );
      controller.clearPrefabCache(key);
      await controller.run('clearPrefabOverrides', {
        'nodeId': instanceNodeId.toToken(),
      });
      messenger.showSnackBar(SnackBar(content: Text('Applied to $key')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Apply failed: $e')));
    }
  }
}

/// A compact action button for the prefab section.
class _SmallButton extends StatelessWidget {
  const _SmallButton({
    required this.label,
    required this.onPressed,
    this.tooltip,
  });
  final String label;
  final VoidCallback onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final btn = OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: const TextStyle(fontSize: 10),
      ),
      child: Text(label),
    );
    if (tooltip != null) return Tooltip(message: tooltip!, child: btn);
    return btn;
  }
}

// ---- helpers ----------------------------------------------------------------

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.onPressed,
    this.tooltip,
  });
  final IconData icon;

  /// Null disables the button. IconButton greys itself, which is the right
  /// signal for an action that exists but cannot apply right now — moving the
  /// first entry of a list up, say.
  final VoidCallback? onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 18,
      height: 18,
      child: IconButton(
        padding: EdgeInsets.zero,
        iconSize: editorIconSize,
        tooltip: tooltip,
        icon: Icon(icon),
        onPressed: onPressed,
      ),
    );
  }
}

/// A label and a read-only value, for property kinds without an editor yet.
class _ReadOnlyRow extends StatelessWidget {
  const _ReadOnlyRow({required this.label, required this.text});
  final String label;
  final String text;

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
              style: const TextStyle(fontSize: 11, color: editorMutedTextColor),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 11, color: editorMutedTextColor),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// A dropdown for a string property with a fixed set of [options].
class _EnumRow extends StatelessWidget {
  const _EnumRow({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });
  final String label;
  final String? value;
  final List<String> options;
  final void Function(String) onChanged;

  @override
  Widget build(BuildContext context) {
    final current = options.contains(value) ? value : null;
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
            child: FSelect<String>(
              items: {for (final option in options) option: option},
              control: FSelectControl.lifted(
                value: current,
                onChange: (v) {
                  if (v != null) onChanged(v);
                },
              ),
              size: FTextFieldSizeVariant.sm,
              // expands would trip the framework's expands-with-maxLines
              // text-field assertion (the select's field keeps maxLines 1).
            ),
          ),
        ],
      ),
    );
  }
}

/// Four compact RGBA fields for a [ColorValue] property.
class _ColorRow extends StatelessWidget {
  const _ColorRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final ColorValue? value;
  final void Function(Map<String, Object>) onChanged;

  @override
  Widget build(BuildContext context) {
    final r = value?.r ?? 0;
    final g = value?.g ?? 0;
    final b = value?.b ?? 0;
    final a = value?.a ?? 1;
    void emit({double? nr, double? ng, double? nb, double? na}) =>
        onChanged({'r': nr ?? r, 'g': ng ?? g, 'b': nb ?? b, 'a': na ?? a});
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
            child: _MiniNumber(
              label: 'R',
              value: r,
              onSubmit: (v) => emit(nr: v),
            ),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: _MiniNumber(
              label: 'G',
              value: g,
              onSubmit: (v) => emit(ng: v),
            ),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: _MiniNumber(
              label: 'B',
              value: b,
              onSubmit: (v) => emit(nb: v),
            ),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: _MiniNumber(
              label: 'A',
              value: a,
              onSubmit: (v) => emit(na: v),
            ),
          ),
        ],
      ),
    );
  }
}

/// A dropdown over the document's resources of a given [resourceKind].
class _ResourceRefRow extends StatelessWidget {
  const _ResourceRefRow({
    required this.label,
    required this.resourceKind,
    required this.value,
    required this.controller,
    required this.onChanged,
  });
  final String label;
  final String? resourceKind;
  final LocalId? value;
  final EditorController controller;
  final void Function(Map<String, Object>) onChanged;

  bool _matches(ResourceSpec r) {
    switch (resourceKind) {
      case 'geometry':
        return r is GeometryResource;
      case 'material':
        return r is MaterialResource;
      case 'texture':
        return r is TextureResource || r is RenderTextureResource;
      case 'environment':
        return r is EnvironmentResource;
      default:
        return true;
    }
  }

  // A friendly label for the dropdown: named resources show their name and
  // file-backed textures their basename, with the id token as the last
  // resort. The display document also covers prefab-owned resources.
  String _label(LocalId id) {
    final r =
        controller.displayDocument.resource(id) ??
        controller.document.resource(id);
    final name = switch (r) {
      MaterialResource(:final name) => name,
      EnvironmentResource(:final name) => name,
      TextureResource(:final asset?) => asset.key.split('/').last,
      _ => '',
    };
    return name.isEmpty ? id.toToken() : name;
  }

  Future<void> _createEnvironment() async {
    final tx = await controller.run('createEnvironmentResource', {});
    if (tx.records.isEmpty) return;
    onChanged({'\$resource': tx.records.first.targetId.toToken()});
  }

  Future<void> _importTexture() async {
    final path = await pickImagePath(
      initialDirectory: controller.baseDirectory,
    );
    if (path == null) return;
    final id = await importTextureResource(controller, path);
    if (id != null) onChanged({'\$resource': id.toToken()});
  }

  @override
  Widget build(BuildContext context) {
    final matching = [
      for (final r in controller.document.resources.values)
        if (_matches(r)) r.id,
    ];
    // Keep the current value selectable even if it is some other kind.
    final ids = {if (value != null) value!, ...matching}.toList();
    final canCreate = resourceKind == 'environment';
    final selected = value == null
        ? null
        : controller.document.resource(value!);
    final origin = selected == null ? null : resourceOriginOf(selected);
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
            child: ids.isEmpty
                ? Text(
                    '(no ${resourceKind ?? 'resource'} resources)',
                    style: const TextStyle(
                      fontSize: 11,
                      color: editorMutedTextColor,
                    ),
                  )
                : ReferencePicker(
                    entries: () => [
                      for (final id in ids) (id: id, label: _label(id)),
                    ],
                    isEmpty: ids.isEmpty,
                    valueLabel: value == null ? null : _label(value!),
                    value: value,
                    emptyLabel: '(no ${resourceKind ?? 'resource'} resources)',
                    onChanged: (id) => onChanged({'\$resource': id.toToken()}),
                  ),
          ),
          if (origin != null) ...[
            const SizedBox(width: 4),
            OriginBadge(locality: origin.$1, path: origin.$2, dense: true),
          ],
          if (canCreate)
            IconButton(
              icon: const Icon(Icons.add, size: 16),
              tooltip: 'New environment',
              visualDensity: VisualDensity.compact,
              onPressed: _createEnvironment,
            ),
          if (resourceKind == 'texture')
            IconButton(
              icon: const Icon(Icons.image, size: 16),
              tooltip: 'Import texture',
              visualDensity: VisualDensity.compact,
              onPressed: _importTexture,
            ),
        ],
      ),
    );
  }
}

/// Edits the look of the environment resource an environment-volume component
/// references, reusing the stage's environment and sky controls.
class _VolumeEnvironmentEditor extends StatelessWidget {
  const _VolumeEnvironmentEditor({
    required this.controller,
    required this.nodeId,
    required this.environmentId,
  });

  final EditorController controller;
  final LocalId nodeId;
  final LocalId environmentId;

  @override
  Widget build(BuildContext context) {
    final res = controller.document.resource(environmentId);
    if (res is! EnvironmentResource) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 8, top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            res.name.isEmpty ? 'Environment' : 'Environment: ${res.name}',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          EnvironmentControls(
            controller: controller,
            environment: res,
            volumeNodeId: nodeId,
            allowEnvironmentImport: true,
          ),
          const Divider(),
          SkySection(
            controller: controller,
            environment: res,
            volumeNodeId: nodeId,
          ),
          const Divider(),
          const Text(
            'Color management',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          ColorManagementControls(
            controller: controller,
            environment: res,
            volumeNodeId: nodeId,
          ),
          EnvironmentEffectsControls(controller: controller, environment: res),
        ],
      ),
    );
  }
}

/// A dropdown over the document's nodes for a node-reference property.
class _NodeRefRow extends StatelessWidget {
  const _NodeRefRow({
    required this.label,
    required this.value,
    required this.controller,
    required this.onChanged,
  });
  final String label;
  final LocalId? value;
  final EditorController controller;
  final void Function(Map<String, Object>) onChanged;

  @override
  Widget build(BuildContext context) {
    final nodes = controller.document.nodes;
    final current = value == null ? null : nodes[value];
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
            child: ReferencePicker(
              // Built when the picker opens; a scene's node list is long and
              // nothing shows it until someone asks.
              entries: () => [
                for (final node in nodes.values)
                  (
                    id: node.id,
                    label: node.name.isEmpty ? node.id.toToken() : node.name,
                  ),
              ],
              isEmpty: nodes.isEmpty,
              valueLabel: current == null
                  ? null
                  : (current.name.isEmpty
                        ? current.id.toToken()
                        : current.name),
              value: value,
              emptyLabel: '(no nodes)',
              onChanged: (id) => onChanged({'\$node': id.toToken()}),
            ),
          ),
        ],
      ),
    );
  }
}

/// A tiny labelled number field used by [_ColorRow].
class _MiniNumber extends StatefulWidget {
  const _MiniNumber({
    required this.label,
    required this.value,
    required this.onSubmit,
  });
  final String label;
  final double value;
  final void Function(double) onSubmit;

  @override
  State<_MiniNumber> createState() => _MiniNumberState();
}

class _MiniNumberState extends State<_MiniNumber> {
  late final TextEditingController _ctrl;
  late final FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value.toStringAsFixed(2));
    _focus = FocusNode()..addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (!_focus.hasFocus) _commit();
  }

  void _commit() {
    if (_ctrl.text == widget.value.toStringAsFixed(2)) return;
    final v = double.tryParse(_ctrl.text);
    if (v != null && v.isFinite) widget.onSubmit(v);
  }

  @override
  void didUpdateWidget(_MiniNumber old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value && !_focus.hasFocus) {
      _ctrl.text = widget.value.toStringAsFixed(2);
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
      height: 32,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.label, style: editorMicroText),
          const SizedBox(width: 2),
          Expanded(
            child: FTextField(
              control: FTextFieldControl.managed(controller: _ctrl),
              focusNode: _focus,
              size: FTextFieldSizeVariant.sm,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              onSubmit: (_) => _commit(),
            ),
          ),
        ],
      ),
    );
  }
}

class _StringRow extends StatefulWidget {
  const _StringRow({
    required this.label,
    required this.value,
    required this.onSubmit,
  });
  final String label;
  final String value;
  final void Function(String) onSubmit;

  @override
  State<_StringRow> createState() => _StringRowState();
}

class _StringRowState extends State<_StringRow> {
  late TextEditingController _ctrl;
  late final FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value);
    _focus = FocusNode()..addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (!_focus.hasFocus) _commit();
  }

  void _commit() {
    // Skip a no-op edit when the text is unchanged.
    if (_ctrl.text != widget.value) widget.onSubmit(_ctrl.text);
  }

  @override
  void didUpdateWidget(_StringRow old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value && !_focus.hasFocus) {
      _ctrl.text = widget.value;
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
              focusNode: _focus,
              size: FTextFieldSizeVariant.sm,
              onSubmit: (_) => _commit(),
            ),
          ),
        ],
      ),
    );
  }
}

class _BoolRow extends StatelessWidget {
  const _BoolRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final bool value;
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
          InspectorToggleSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _IntRow extends StatefulWidget {
  const _IntRow({
    required this.label,
    required this.value,
    required this.onSubmit,
  });
  final String label;
  final int value;
  final void Function(int) onSubmit;

  @override
  State<_IntRow> createState() => _IntRowState();
}

class _IntRowState extends State<_IntRow> {
  late TextEditingController _ctrl;
  late final FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value.toString());
    _focus = FocusNode()..addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (!_focus.hasFocus) _commit();
  }

  void _commit() {
    // Skip a no-op edit when the text matches the current value.
    if (_ctrl.text == widget.value.toString()) return;
    final v = int.tryParse(_ctrl.text);
    if (v != null) widget.onSubmit(v);
  }

  @override
  void didUpdateWidget(_IntRow old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value && !_focus.hasFocus) {
      _ctrl.text = widget.value.toString();
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
              focusNode: _focus,
              size: FTextFieldSizeVariant.sm,
              keyboardType: const TextInputType.numberWithOptions(signed: true),
              onSubmit: (_) => _commit(),
            ),
          ),
        ],
      ),
    );
  }
}

class _DoubleRow extends StatefulWidget {
  const _DoubleRow({
    required this.label,
    required this.value,
    required this.onSubmit,
  });
  final String label;
  final double value;
  final void Function(double) onSubmit;

  @override
  State<_DoubleRow> createState() => _DoubleRowState();
}

class _DoubleRowState extends State<_DoubleRow> {
  late TextEditingController _ctrl;
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
    // Skip when the text still matches the current value's canonical rendering.
    if (_ctrl.text == widget.value.toStringAsFixed(3)) return;
    final v = double.tryParse(_ctrl.text);
    if (v != null && v.isFinite) widget.onSubmit(v);
  }

  @override
  void didUpdateWidget(_DoubleRow old) {
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
              focusNode: _focus,
              size: FTextFieldSizeVariant.sm,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              onSubmit: (_) => _commit(),
            ),
          ),
        ],
      ),
    );
  }
}
