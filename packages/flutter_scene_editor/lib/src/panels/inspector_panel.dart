// ignore: implementation_imports
import 'package:flutter_scene/src/fscene/specs.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/fscene/property_value.dart';
import 'package:flutter/material.dart';

import '../controller/editor_controller.dart';
import '../inspector/property_editors.dart';

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

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(_StringRow old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) _ctrl.text = widget.value;
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

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value.toString());
  }

  @override
  void didUpdateWidget(_IntRow old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) _ctrl.text = widget.value.toString();
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
                onSubmitted: (text) {
                  final v = int.tryParse(text);
                  if (v != null) widget.onSubmit(v);
                },
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

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value.toStringAsFixed(3));
  }

  @override
  void didUpdateWidget(_DoubleRow old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      _ctrl.text = widget.value.toStringAsFixed(3);
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
                onSubmitted: (text) {
                  final v = double.tryParse(text);
                  if (v != null) widget.onSubmit(v);
                },
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
