// ignore: implementation_imports
import 'package:flutter_scene/src/fscene/id.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/fscene/specs.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/fscene/property_value.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/fscene/realize/component_schema.dart';
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math.dart' show Quaternion, Vector3;

import '../controller/editor_controller.dart';
import '../inspector/euler.dart';
import '../inspector/material_section.dart';
import '../inspector/property_editors.dart';
import '../io/scene_io.dart';

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
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final primary = controller.selection.primary;
        final node = primary != null ? controller.displayNode(primary) : null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PanelHeader(label: 'Inspector'),
            Expanded(
              child: node == null
                  ? const Center(
                      child: Text(
                        'Nothing selected',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    )
                  : _NodeInspector(node: node, controller: controller),
            ),
          ],
        );
      },
    );
  }
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
    // Adding and removing whole components is only wired for plain scene nodes;
    // prefab content edits property values in place (structural component edits
    // on prefab content are a TODO(prefab-member-components)).
    final isPrefabContent = isMember || isInstance;

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
          _SectionHeader(label: 'Node'),
          // Name field.
          _StringRow(
            label: 'Name',
            value: node.name,
            onSubmit: (v) => controller.setNodeNameRouted(node.id, v),
          ),
          // Visibility toggle.
          _BoolRow(
            label: 'Visible',
            value: node.visible,
            onChanged: (v) => controller.setNodeVisibleRouted(node.id, v),
          ),
          const SizedBox(height: 8),
          _SectionHeader(label: 'Transform'),
          _TransformEditor(node: node, controller: controller),
          // Components.
          for (final component in node.components) ...[
            const SizedBox(height: 8),
            _ComponentSection(
              node: node,
              component: component,
              controller: controller,
              canRemove: !isPrefabContent,
            ),
            // A mesh's material is a resource; edit it inline below the mesh.
            if (component.type == 'mesh' &&
                component.properties['material'] is ResourceRefValue)
              MaterialSection(
                controller: controller,
                materialId:
                    (component.properties['material'] as ResourceRefValue).id,
              ),
          ],
          if (!isPrefabContent) ...[
            const SizedBox(height: 8),
            _AddComponentBar(node: node, controller: controller),
          ],
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Vec3Field(
          label: 'Translation',
          x: t?.x ?? 0,
          y: t?.y ?? 0,
          z: t?.z ?? 0,
          onSubmit: (v) =>
              controller.setNodeTransformRouted(node.id, translation: v),
        ),
        Vec3Field(
          label: 'Scale',
          x: s?.x ?? 1,
          y: s?.y ?? 1,
          z: s?.z ?? 1,
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
              onSubmit: (v) {
                final q = eulerXyzDegreesToQuaternion(
                  Vector3(
                    (v['x']! as num).toDouble(),
                    (v['y']! as num).toDouble(),
                    (v['z']! as num).toDouble(),
                  ),
                );
                controller.setNodeTransformRouted(
                  node.id,
                  rotation: {'x': q.x, 'y': q.y, 'z': q.z, 'w': q.w},
                );
              },
            );
          },
        ),
      ],
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

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          label: 'Component: ${component.type}',
          trailing: canRemove
              ? _IconAction(
                  icon: Icons.close,
                  tooltip: 'Remove component',
                  onPressed: () => controller.run('removeComponent', {
                    'nodeId': node.id.toToken(),
                    'componentType': component.type,
                  }),
                )
              : null,
        ),
        _ComponentEditor(
          node: node,
          component: component,
          controller: controller,
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
          style: TextStyle(fontSize: 11, color: Colors.grey),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final def in schema)
          _SchemaPropertyRow(
            def: def,
            value: component.properties[def.name] ?? def.defaultValue,
            controller: controller,
            onChanged: (v) => _set(def.name, v),
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
    required this.def,
    required this.value,
    required this.controller,
    required this.onChanged,
  });

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

  @override
  Widget build(BuildContext context) {
    final label = def.name;
    switch (def.kind) {
      case ComponentPropertyKind.boolean:
        return _BoolRow(
          label: label,
          value: value is BoolValue ? (value as BoolValue).value : false,
          onChanged: onChanged,
        );
      case ComponentPropertyKind.integer:
        return _IntRow(
          label: label,
          value: value is IntValue ? (value as IntValue).value : 0,
          onSubmit: onChanged,
        );
      case ComponentPropertyKind.number:
        return _DoubleRow(label: label, value: _double(0), onSubmit: onChanged);
      case ComponentPropertyKind.string:
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
      case ComponentPropertyKind.vec3:
        final v = value is Vec3Value ? (value as Vec3Value).value : null;
        return Vec3Field(
          label: label,
          x: v?.x ?? 0,
          y: v?.y ?? 0,
          z: v?.z ?? 0,
          onSubmit: onChanged,
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
      case ComponentPropertyKind.vec2:
      case ComponentPropertyKind.vec4:
      case ComponentPropertyKind.quaternion:
      case ComponentPropertyKind.list:
      case ComponentPropertyKind.map:
        // TODO(component-property-editors): vec2/vec4/quaternion/list/map.
        return _ReadOnlyRow(label: label, text: '(${def.kind.name})');
    }
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
    return Align(
      alignment: Alignment.centerLeft,
      child: PopupMenuButton<String>(
        enabled: available.isNotEmpty,
        tooltip: 'Add a component',
        onSelected: (type) => controller.run('addComponent', {
          'nodeId': node.id.toToken(),
          'componentType': type,
        }),
        itemBuilder: (_) => [
          for (final type in available)
            PopupMenuItem<String>(
              value: type,
              height: 28,
              child: Text(type, style: const TextStyle(fontSize: 12)),
            ),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.add,
                size: 14,
                color: available.isEmpty
                    ? Colors.grey
                    : Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 4),
              Text(
                'Add Component',
                style: TextStyle(
                  fontSize: 11,
                  color: available.isEmpty
                      ? Colors.grey
                      : Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
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
            child: Text(
              isMember
                  ? 'Prefab content from $source. Edits are saved as overrides.'
                  : 'Prefab instance of $source.',
              style: TextStyle(fontSize: 10, color: scheme.onTertiaryContainer),
            ),
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
        _SectionHeader(label: 'Prefab'),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text(
            '${instance.source.key}  ($overrides override'
            '${overrides == 1 ? '' : 's'})',
            style: const TextStyle(fontSize: 10, color: Colors.grey),
            overflow: TextOverflow.ellipsis,
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, this.trailing});
  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.4),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// A compact icon button for section headers.
class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.onPressed,
    this.tooltip,
  });
  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 18,
      height: 18,
      child: IconButton(
        padding: EdgeInsets.zero,
        iconSize: 14,
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
              style: const TextStyle(fontSize: 11, color: Colors.grey),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
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
            child: DropdownButton<String>(
              value: current,
              isDense: true,
              isExpanded: true,
              style: const TextStyle(fontSize: 11),
              items: [
                for (final option in options)
                  DropdownMenuItem(value: option, child: Text(option)),
              ],
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
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
      default:
        return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final matching = [
      for (final r in controller.document.resources.values)
        if (_matches(r)) r.id,
    ];
    // Keep the current value selectable even if it is some other kind.
    final ids = {if (value != null) value!, ...matching}.toList();
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
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  )
                : DropdownButton<LocalId>(
                    value: ids.contains(value) ? value : null,
                    isDense: true,
                    isExpanded: true,
                    hint: const Text('Pick…', style: TextStyle(fontSize: 11)),
                    style: const TextStyle(fontSize: 11),
                    items: [
                      for (final id in ids)
                        DropdownMenuItem(
                          value: id,
                          child: Text(
                            id.toToken(),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (id) {
                      if (id != null) onChanged({'\$resource': id.toToken()});
                    },
                  ),
          ),
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
    final nodes = controller.document.nodes.values.toList();
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
            child: DropdownButton<LocalId>(
              value: nodes.any((n) => n.id == value) ? value : null,
              isDense: true,
              isExpanded: true,
              hint: const Text('Pick…', style: TextStyle(fontSize: 11)),
              style: const TextStyle(fontSize: 11),
              items: [
                for (final n in nodes)
                  DropdownMenuItem(
                    value: n.id,
                    child: Text(
                      n.name.isEmpty ? n.id.toToken() : n.name,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (id) {
                if (id != null) onChanged({'\$node': id.toToken()});
              },
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
    if (v != null) widget.onSubmit(v);
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
            child: SizedBox(
              height: 24,
              child: TextField(
                controller: _ctrl,
                focusNode: _focus,
                style: const TextStyle(fontSize: 11),
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
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
          SizedBox(
            height: 20,
            child: Switch(
              value: value,
              onChanged: onChanged,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
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
            child: SizedBox(
              height: 24,
              child: TextField(
                controller: _ctrl,
                focusNode: _focus,
                keyboardType: const TextInputType.numberWithOptions(
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
                onSubmitted: (_) => _commit(),
              ),
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
    if (v != null) widget.onSubmit(v);
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
            child: SizedBox(
              height: 24,
              child: TextField(
                controller: _ctrl,
                focusNode: _focus,
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
                onSubmitted: (_) => _commit(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
