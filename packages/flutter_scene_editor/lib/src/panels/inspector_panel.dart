// ignore: implementation_imports
import 'package:flutter_scene/src/fscene/id.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/fscene/scene_document.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/fscene/specs.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/fscene/property_value.dart';
import 'package:flutter/material.dart';

import '../controller/editor_controller.dart';
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
        final node = primary != null ? controller.document.node(primary) : null;
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionHeader(label: 'Node'),
          // Name field.
          _StringRow(
            label: 'Name',
            value: node.name,
            onSubmit: (v) => controller.run('setNodeName', {
              'nodeId': node.id.toToken(),
              'name': v,
            }),
          ),
          // Visibility toggle.
          _BoolRow(
            label: 'Visible',
            value: node.visible,
            onChanged: (v) => controller.run('setNodeVisible', {
              'nodeId': node.id.toToken(),
              'visible': v,
            }),
          ),
          const SizedBox(height: 8),
          _SectionHeader(label: 'Transform'),
          _TransformEditor(node: node, controller: controller),
          // Components.
          for (final component in node.components) ...[
            const SizedBox(height: 8),
            _SectionHeader(label: 'Component: ${component.type}'),
            _ComponentEditor(
              node: node,
              component: component,
              controller: controller,
            ),
          ],
          // Prefab instance section shown when the node has an instance.
          if (node.instance != null) ...[
            const SizedBox(height: 8),
            _PrefabInstanceSection(
              instanceNodeId: node.id,
              instance: node.instance!,
              controller: controller,
            ),
          ],
        ],
      ),
    );
  }
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
          onSubmit: (v) => controller.run('setNodeTransform', {
            'nodeId': node.id.toToken(),
            'translation': v,
          }),
        ),
        Vec3Field(
          label: 'Scale',
          x: s?.x ?? 1,
          y: s?.y ?? 1,
          z: s?.z ?? 1,
          onSubmit: (v) => controller.run('setNodeTransform', {
            'nodeId': node.id.toToken(),
            'scale': v,
          }),
        ),
        // TODO(rotation-editor): add a rotation editor (Euler angles or
        // quaternion fields) when a Vec4Field is available.
        if (r != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              'Rotation: (${r.x.toStringAsFixed(2)}, ${r.y.toStringAsFixed(2)}, ${r.z.toStringAsFixed(2)}, ${r.w.toStringAsFixed(2)})',
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ),
      ],
    );
  }
}

class _ComponentEditor extends StatelessWidget {
  const _ComponentEditor({
    required this.node,
    required this.component,
    required this.controller,
  });

  final NodeSpec node;
  final ComponentSpec component;
  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    if (component.properties.isEmpty) {
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
        for (final entry in component.properties.entries)
          _PropertyValueRow(
            label: entry.key,
            value: entry.value,
            onChanged: (newValue) {
              controller.run('setComponentProperties', {
                'nodeId': node.id.toToken(),
                'componentType': component.type,
                'properties': {entry.key: newValue},
              });
            },
          ),
      ],
    );
  }
}

/// Displays one typed [PropertyValue] as an editable field.
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
      _ => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text(
          '$label: (${value.runtimeType})',
          style: const TextStyle(fontSize: 11, color: Colors.grey),
        ),
      ),
    };
  }
}

// ---- prefab instance section ------------------------------------------------

/// One row of overridable-property data for a prefab node.
///
/// [effectiveValue] is the override value when one exists, otherwise the
/// prefab's own value. [isOverridden] marks whether an override is in effect.
typedef _OverrideProp = ({
  String nodeLabel,
  LocalId prefabNodeId,
  String path,
  PropertyValue effectiveValue,
  bool isOverridden,
});

/// Collects the overridable properties for every node in [prefabDoc], merged
/// with any active [overrides] on the instance.
List<_OverrideProp> _collectProps(
  SceneDocument prefabDoc,
  List<PropertyOverride> overrides,
) {
  // Build a quick lookup of active overrides: (target.token, path) -> value.
  final activeMap = <String, PropertyValue>{
    for (final o in overrides) '${o.target.toToken()}|${o.path}': o.value,
  };

  final props = <_OverrideProp>[];

  for (final prefabNode in prefabDoc.nodes.values) {
    final nodeLabel = prefabNode.name.isNotEmpty
        ? prefabNode.name
        : prefabNode.id.toToken();
    final tid = prefabNode.id.toToken();

    void addProp(String path, PropertyValue baseValue) {
      final key = '$tid|$path';
      final override = activeMap[key];
      props.add((
        nodeLabel: nodeLabel,
        prefabNodeId: prefabNode.id,
        path: path,
        effectiveValue: override ?? baseValue,
        isOverridden: override != null,
      ));
    }

    // name (StringValue)
    addProp('name', StringValue(prefabNode.name));

    // layers (IntValue)
    addProp('layers', IntValue(prefabNode.layers));

    // transform.trs.t / .r / .s
    final trs = prefabNode.transform is TrsTransform
        ? prefabNode.transform as TrsTransform
        : null;
    if (trs != null) {
      addProp('transform.trs.t', Vec3Value(trs.translation));
      addProp('transform.trs.r', QuaternionValue(trs.rotation));
      addProp('transform.trs.s', Vec3Value(trs.scale));
    }

    // components.<type>.<prop>
    for (final comp in prefabNode.components) {
      for (final entry in comp.properties.entries) {
        addProp('components.${comp.type}.${entry.key}', entry.value);
      }
    }
  }
  return props;
}

/// The prefab instance inspector section.
///
/// When the selected node is a prefab instance ([node.instance] != null), this
/// shows the source path, a flat list of overridable properties (each with an
/// override indicator and per-property Revert), and Apply/Revert All buttons.
///
/// Properties are loaded from the prefab document via [FutureBuilder] the
/// first time and cached on the controller thereafter.
class _PrefabInstanceSection extends StatelessWidget {
  const _PrefabInstanceSection({
    required this.instanceNodeId,
    required this.instance,
    required this.controller,
  });

  final LocalId instanceNodeId;
  final PrefabInstanceSpec instance;
  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(label: 'Prefab Instance'),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text(
            instance.source.key,
            style: const TextStyle(fontSize: 10, color: Colors.grey),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        // Action buttons.
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 4),
          child: Row(
            children: [
              Expanded(
                child: _SmallButton(
                  label: 'Apply to source',
                  tooltip:
                      'Bakes overrides into the source .fscene, then clears '
                      'them on this instance. All instances of the prefab will '
                      'reflect the change.',
                  onPressed: () => _applyToSource(context),
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
        // Property rows loaded from the prefab document.
        FutureBuilder<SceneDocument>(
          future: controller.loadPrefabDocument(instance.source),
          builder: (context, snap) {
            if (snap.hasError) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  'Could not load prefab: ${snap.error}',
                  style: const TextStyle(fontSize: 10, color: Colors.red),
                ),
              );
            }
            if (!snap.hasData) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  'Loading...',
                  style: TextStyle(fontSize: 10, color: Colors.grey),
                ),
              );
            }
            final prefabDoc = snap.data!;
            final props = _collectProps(prefabDoc, instance.overrides);
            if (props.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  '(no overridable properties)',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final prop in props)
                  _OverrideRow(
                    prop: prop,
                    instanceNodeId: instanceNodeId,
                    controller: controller,
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Future<void> _applyToSource(BuildContext context) async {
    final dir = controller.baseDirectory;
    final key = instance.source.key;
    if (!key.startsWith('/') && dir == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Cannot apply: the scene has no base directory (save it first).',
            ),
          ),
        );
      }
      return;
    }
    final path = key.startsWith('/') ? key : '$dir/$key';
    try {
      await applyOverridesToSource(
        sourcePath: path,
        overrides: instance.overrides,
      );
      // Clear the cached document so the next load re-reads the updated file.
      controller.clearPrefabCache(instance.source.key);
      await controller.run('clearPrefabOverrides', {
        'nodeId': instanceNodeId.toToken(),
      });
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Applied overrides to $key')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Apply failed: $e')));
      }
    }
  }
}

/// One overridable-property row: label, value editor, override dot, and Revert.
class _OverrideRow extends StatelessWidget {
  const _OverrideRow({
    required this.prop,
    required this.instanceNodeId,
    required this.controller,
  });

  final _OverrideProp prop;
  final LocalId instanceNodeId;
  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final valueWidget = _valueEditor(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          // Override indicator dot.
          SizedBox(
            width: 8,
            child: prop.isOverridden
                ? Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: accent,
                      shape: BoxShape.circle,
                    ),
                  )
                : null,
          ),
          Expanded(child: valueWidget),
          // Per-property revert button (shown when overridden).
          if (prop.isOverridden)
            SizedBox(
              width: 40,
              height: 20,
              child: TextButton(
                onPressed: () => controller.run('removePrefabOverride', {
                  'nodeId': instanceNodeId.toToken(),
                  'target': prop.prefabNodeId.toToken(),
                  'path': prop.path,
                }),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'Revert',
                  style: TextStyle(fontSize: 9, color: accent),
                ),
              ),
            )
          else
            const SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _valueEditor(BuildContext context) {
    final label = '${prop.nodeLabel}.${_shortPath(prop.path)}';
    final v = prop.effectiveValue;
    return switch (v) {
      StringValue sv => _StringRow(
        label: label,
        value: sv.value,
        onSubmit: (nv) => _setOverride({'s': nv}),
      ),
      IntValue iv => _IntRow(
        label: label,
        value: iv.value,
        onSubmit: (nv) => _setOverride(nv),
      ),
      Vec3Value vv => Vec3Field(
        label: label,
        x: vv.value.x,
        y: vv.value.y,
        z: vv.value.z,
        onSubmit: (nv) => _setOverride(nv),
      ),
      QuaternionValue qv => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text(
          '$label: (${qv.value.x.toStringAsFixed(2)}, '
          '${qv.value.y.toStringAsFixed(2)}, '
          '${qv.value.z.toStringAsFixed(2)}, '
          '${qv.value.w.toStringAsFixed(2)})',
          style: const TextStyle(fontSize: 10, color: Colors.grey),
        ),
      ),
      DoubleValue dv => _DoubleRow(
        label: label,
        value: dv.value,
        onSubmit: (nv) => _setOverride(nv),
      ),
      _ => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text(
          '$label: (${v.runtimeType})',
          style: const TextStyle(fontSize: 10, color: Colors.grey),
        ),
      ),
    };
  }

  void _setOverride(Object value) {
    controller.run('setPrefabOverride', {
      'nodeId': instanceNodeId.toToken(),
      'target': prop.prefabNodeId.toToken(),
      'path': prop.path,
      'value': value,
    });
  }

  /// Abbreviates a property path for the label column.
  String _shortPath(String path) {
    // transform.trs.t -> t, components.mesh.material -> mesh.material, etc.
    final parts = path.split('.');
    if (parts.first == 'transform' && parts.length == 3) return parts.last;
    if (parts.first == 'components' && parts.length == 3) {
      return '${parts[1]}.${parts[2]}';
    }
    return parts.last;
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
  const _SectionHeader({required this.label});
  final String label;

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
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
        ),
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
    if (!_focus.hasFocus) widget.onSubmit(_ctrl.text);
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
                onSubmitted: widget.onSubmit,
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
