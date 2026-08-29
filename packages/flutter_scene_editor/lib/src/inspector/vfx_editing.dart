/// Putting an effect in the scene, and swapping the one that is already there.
///
/// A plume of smoke is a shape, a spawner, five distributions and four
/// modules, which is why nobody builds one to put dust under a footstep. Both
/// gestures here go through the command layer -- the effect is built in
/// memory, serialized through its own codec, and the properties set on a
/// component -- so an effect dropped from the menu is one undo step and is
/// identical to the same effect authored by hand.
library;

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart'
    show VfxCategory, VfxPreset, vfxPresetsIn;
import 'package:scene/scene.dart' show LocalId;

import '../controller/editor_controller.dart';
import '../shell/editor_dialog.dart';
import '../shell/editor_theme.dart';

/// The document component an effect is.
const String vfxComponentType = 'particleEmitter';

/// Builds [preset] and returns its properties, ready to set on a component.
Map<String, Object?>? _propertiesOf(EditorController ctrl, VfxPreset preset) =>
    ctrl.capturePropertiesOf(preset.build());

/// Adds [preset] to the scene as a new node carrying an emitter.
///
/// Returns the node it created, already selected, so a caller can frame it.
Future<LocalId> addVfxPreset(
  EditorController ctrl,
  VfxPreset preset, {
  LocalId? parent,
}) async {
  final properties = _propertiesOf(ctrl, preset);
  final before = Set.of(ctrl.document.nodes.keys);
  await ctrl.run('createNode', {
    'name': preset.name,
    if (parent != null) 'parentId': parent.toToken(),
  });
  final nodeId = ctrl.document.nodes.keys.firstWhere(
    (id) => !before.contains(id),
  );
  await ctrl.run('addComponent', {
    'nodeId': nodeId.toToken(),
    'componentType': vfxComponentType,
  });
  if (properties != null && properties.isNotEmpty) {
    await ctrl.run('setComponentProperties', {
      'nodeId': nodeId.toToken(),
      'componentType': vfxComponentType,
      'properties': properties,
    });
  }
  ctrl.selection.selectOnly(nodeId);
  return nodeId;
}

/// Makes the emitter already on [nodeId] be [preset] instead.
///
/// Every field of the preset is written, including the ones it leaves at
/// their defaults: a merge would leave the outgoing effect's tuning behind,
/// so switching smoke to rain would give you rain that still drifted upward.
Future<void> applyVfxPresetTo(
  EditorController ctrl,
  LocalId nodeId,
  VfxPreset preset,
) async {
  final captured = _propertiesOf(ctrl, preset);
  if (captured == null) return;
  final properties = <String, Object?>{
    for (final def in ctrl.componentSchema(vfxComponentType))
      if (def.defaultValue != null && !captured.containsKey(def.name))
        def.name: def.defaultValue,
    ...captured,
  };
  await ctrl.run('setComponentProperties', {
    'nodeId': nodeId.toToken(),
    'componentType': vfxComponentType,
    'properties': properties,
  });
}

/// The effect browser: every shipped effect, searchable, with what each one
/// is for.
///
/// The Add menu lists the same effects by name, which is the fast path once
/// you know which one you want. This is the other half: the descriptions are
/// how you find out that the thing you want under a footstep is called Dust
/// Puff.
Future<VfxPreset?> showVfxBrowser(
  BuildContext context, {
  required String title,
  required String action,
}) => showEditorDialog<VfxPreset>(
  context,
  builder: (context) => _VfxBrowserDialog(title: title, action: action),
);

class _VfxBrowserDialog extends StatefulWidget {
  const _VfxBrowserDialog({required this.title, required this.action});

  final String title;

  /// What the button on each card says: "Add" or "Use".
  final String action;

  @override
  State<_VfxBrowserDialog> createState() => _VfxBrowserDialogState();
}

class _VfxBrowserDialogState extends State<_VfxBrowserDialog> {
  final TextEditingController _search = TextEditingController();
  String _query = '';
  VfxPreset? _focused;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(VfxPreset preset) {
    if (_query.isEmpty) return true;
    final needle = _query.toLowerCase();
    return preset.name.toLowerCase().contains(needle) ||
        preset.description.toLowerCase().contains(needle) ||
        preset.category.label.toLowerCase().contains(needle);
  }

  @override
  Widget build(BuildContext context) {
    final groups = [
      for (final category in VfxCategory.values)
        (category, vfxPresetsIn(category).where(_matches).toList()),
    ].where((group) => group.$2.isNotEmpty).toList();

    return AlertDialog(
      title: Text(widget.title, style: editorDialogTitleText),
      contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      content: SizedBox(
        width: 520,
        height: 480,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              autofocus: true,
              style: editorBodyText,
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'Search effects',
                prefixIcon: Icon(Icons.search, size: 16),
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => setState(() => _query = value.trim()),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: groups.isEmpty
                  ? Center(
                      child: Text(
                        'No effect matches.',
                        style: editorDetailText,
                      ),
                    )
                  : ListView(
                      primary: false,
                      children: [
                        for (final (category, presets) in groups) ...[
                          EditorSectionHeader(label: category.label),
                          for (final preset in presets)
                            _PresetCard(
                              preset: preset,
                              action: widget.action,
                              focused: _focused?.id == preset.id,
                              onFocus: () => setState(() => _focused = preset),
                              onChoose: () => Navigator.of(context).pop(preset),
                            ),
                          const SizedBox(height: 6),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _focused == null
              ? null
              : () => Navigator.of(context).pop(_focused),
          child: Text(widget.action),
        ),
      ],
    );
  }
}

class _PresetCard extends StatelessWidget {
  const _PresetCard({
    required this.preset,
    required this.action,
    required this.focused,
    required this.onFocus,
    required this.onChoose,
  });

  final VfxPreset preset;
  final String action;
  final bool focused;
  final VoidCallback onFocus;
  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onFocus,
    onDoubleTap: onChoose,
    borderRadius: BorderRadius.circular(4),
    child: Container(
      margin: const EdgeInsets.only(bottom: 5),
      padding: const EdgeInsets.fromLTRB(10, 8, 8, 9),
      decoration: BoxDecoration(
        color: editorPanelColor,
        border: Border.all(
          color: focused ? editorAccentColor : editorLineColor,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(preset.name, style: editorSubheadText),
                const SizedBox(height: 3),
                Text(preset.description, style: editorDetailText),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            onPressed: onChoose,
            child: Text(action, style: const TextStyle(fontSize: 11)),
          ),
        ],
      ),
    ),
  );
}
