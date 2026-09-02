import 'dart:async' show unawaited;
import 'package:collection/collection.dart' show DeepCollectionEquality;
import 'dart:math' as math;

import 'package:scene/scene.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/fscene/realize/component_schema.dart';
import 'package:flutter/material.dart' hide Matrix4, Step;
import 'package:flutter_scene/scene.dart'
    show Component, PointLightComponent, SpotLightComponent;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:forui/forui.dart';
import 'package:vector_math/vector_math.dart' show Matrix4, Quaternion, Vector3;

import '../controller/editor_controller.dart';
import '../viewport/component_gizmos.dart' show componentGlyph;
import '../inspector/euler.dart';
import '../inspector/live_fields.dart';
import '../blueprints/blueprint_editor_screen.dart';
import '../inspector/material_section.dart';
import '../inspector/nav_mesh_editor.dart';
import '../inspector/particle_emitter_controls.dart';
import '../inspector/particle_value_editors.dart';
import '../inspector/property_editors.dart';
import '../inspector/reference_picker.dart';
import '../inspector/resource_origin.dart';
import '../inspector/terrain_section.dart';
import '../inspector/vfx_editing.dart';
import '../inspector/water_conversion.dart';
import '../inspector/stage_section.dart';
import '../io/scene_io.dart';
import '../shell/editor_theme.dart';
import '../shell/panel_chrome.dart';

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
          final selection = controller.selection;
          final primary = selection.primary;
          // Primary first, then the rest of the selection in order.
          final nodes = [
            if (primary != null)
              if (controller.displayNode(primary) case final node?) node,
            for (final id in selection.ids)
              if (id != primary)
                if (controller.displayNode(id) case final node?) node,
          ];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: nodes.isEmpty
                    ? StageSection(controller: controller)
                    : _NodeInspector(nodes: nodes, controller: controller),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Whether two property values encode identically (canonical JSON form).
bool _sameValue(PropertyValue? a, PropertyValue? b) {
  Object? encode(PropertyValue? value) =>
      value == null ? null : encodePropertyValue(value, (id) => id.toToken());
  return const DeepCollectionEquality().equals(encode(a), encode(b));
}

class _NodeInspector extends StatelessWidget {
  const _NodeInspector({required this.nodes, required this.controller});

  /// The selected nodes, primary first. Fields shared by every node render
  /// through the same widgets a single selection uses; differing values show
  /// dashes and an edit applies to the whole selection.
  final List<NodeSpec> nodes;
  final EditorController controller;

  NodeSpec get node => nodes.first;
  bool get single => nodes.length == 1;

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

    // A component type renders when every selected node carries it.
    var sharedTypes = {for (final c in node.components) c.type};
    for (final other in nodes.skip(1)) {
      sharedTypes = sharedTypes.intersection({
        for (final c in other.components) c.type,
      });
    }
    final uniformName = nodes.every((n) => n.name == node.name);
    final uniformVisible = nodes.every((n) => n.visible == node.visible);
    final uniformShadowCasting = nodes.every(
      (n) => n.shadowCastingMode == node.shadowCastingMode,
    );
    // Whether every node's material ref matches, so the shared material can
    // be edited inline for the whole selection.
    bool uniformRef(String type, String key) {
      final refs = [
        for (final n in nodes)
          n.components
              .where((c) => c.type == type)
              .firstOrNull
              ?.properties[key],
      ];
      final first = refs.first;
      if (first is! ResourceRefValue) return false;
      return refs.every((r) => r is ResourceRefValue && r.id == first.id);
    }

    return SingleChildScrollView(
      // Room under the last control, so the end of a component's properties
      // is not the bottom edge of the window.
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (single && instanceId != null)
            _PrefabBanner(
              isMember: isMember,
              source: _instanceSource(instanceId),
            ),
          EditorSectionHeader(
            label: single ? 'Node' : 'Node (${nodes.length} selected)',
          ),
          // Name field.
          _StringRow(
            label: 'Name',
            value: node.name,
            mixed: !uniformName,
            onSubmit: (v) {
              for (final n in nodes) {
                controller.setNodeNameRouted(n.id, v);
              }
            },
          ),
          // Visibility toggle.
          _BoolRow(
            label: 'Visible',
            value: node.visible,
            mixed: !uniformVisible,
            onChanged: (v) {
              for (final n in nodes) {
                controller.setNodeVisibleRouted(n.id, v);
              }
            },
          ),
          // How the node's meshes cast; only meaningful for mesh-bearing
          // nodes, so it follows the mesh into the selection.
          if (sharedTypes.contains('mesh'))
            EnumRow(
              label: 'Shadows',
              value: uniformShadowCasting ? node.shadowCastingMode : null,
              options: const ['on', 'off', 'doubleSided', 'shadowsOnly'],
              labels: const {
                'on': 'Cast',
                'off': 'Do not cast',
                'doubleSided': 'Cast double-sided',
                'shadowsOnly': 'Shadows only',
              },
              onChanged: (v) {
                for (final n in nodes) {
                  controller.setNodeShadowCastingRouted(n.id, v);
                }
              },
            ),
          const SizedBox(height: 8),
          EditorSectionHeader(label: 'Transform'),
          _TransformEditor(nodes: nodes, controller: controller),
          // Components (the ones the whole selection shares).
          for (final component in node.components)
            if (sharedTypes.contains(component.type)) ...[
              const SizedBox(height: 8),
              _ComponentSection(
                nodes: nodes,
                type: component.type,
                controller: controller,
                canRemove: nodes.every((n) {
                  final source = controller.document.nodes[n.id]?.components;
                  return source != null
                      ? source.any((c) => c.type == component.type)
                      : controller
                            .memberAddedComponentTypes(n.id)
                            .contains(component.type);
                }),
              ),
              // A mesh's material is a resource; edit it inline below the
              // mesh when the whole selection shares the same material.
              if (component.type == 'mesh' &&
                  component.properties['material'] is ResourceRefValue &&
                  (single || uniformRef('mesh', 'material')))
                MaterialSection(
                  controller: controller,
                  nodeId: node.id,
                  materialId:
                      (component.properties['material'] as ResourceRefValue).id,
                ),
              // The terrain tools, where a terrain is selected. This is where
              // they are found: the scene view's corner button is a shortcut
              // for people who already know they exist. One terrain at a time,
              // since the tools act on a specific height field.
              if (single && component.type == 'mesh')
                if (terrainSpecOf(controller, node.id) case final terrain?) ...[
                  const SizedBox(height: 8),
                  TerrainSection(
                    controller: controller,
                    nodeId: node.id,
                    spec: terrain,
                  ),
                ],
              // A graph is drawn on a screen, not in a docked tab, so the
              // component that holds one says where to go and opens it.
              if (single && component.type == 'visualScript')
                _EditGraphRow(controller: controller, node: node),
              // A flat surface can become an area of water where it stands,
              // which is what a lake is: not an object you place, a piece of
              // ground you say is wet.
              if (single &&
                  component.type == 'mesh' &&
                  canBecomeWater(controller, node.id))
                _MakeWaterRow(controller: controller, nodeId: node.id),
              // A volume's environment is a resource; edit its look inline.
              if (single &&
                  component.type == 'environmentVolume' &&
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
          _AddComponentBar(nodes: nodes, controller: controller),
          // Prefab actions (apply/revert) for the enclosing instance.
          if (single && instanceId != null) ...[
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
  const _TransformEditor({required this.nodes, required this.controller});

  /// The nodes edited together, primary first. Per-axis values the selection
  /// disagrees on render as dashes; a commit writes only the entered axes
  /// (each node keeps its own values elsewhere).
  final List<NodeSpec> nodes;
  final EditorController controller;

  NodeSpec get node => nodes.first;
  bool get single => nodes.length == 1;

  static TrsTransform _trsOf(NodeSpec node) {
    final transform = node.transform;
    if (transform is TrsTransform) return transform;
    final t = Vector3.zero();
    final r = Quaternion.identity();
    final s = Vector3.zero();
    transform.toMatrix4().decompose(t, r, s);
    return TrsTransform(translation: t, rotation: r, scale: s);
  }

  bool _axisUniform(List<Vector3> values, int axis) {
    final first = values.first[axis];
    return values.every((v) => (v[axis] - first).abs() < 1e-9);
  }

  // Applies the submitted axes over each node's own vector, then hands every
  // node's full TRS to one batched undo step.
  void _commitEach(
    Map<String, Object> v,
    TrsTransform Function(TrsTransform current, Vector3 merged) next,
    List<Vector3> currents,
  ) {
    final batch = <LocalId, TrsTransform>{};
    for (var i = 0; i < nodes.length; i++) {
      final merged = Vector3.copy(currents[i]);
      if (v['x'] case final num x) merged.x = x.toDouble();
      if (v['y'] case final num y) merged.y = y.toDouble();
      if (v['z'] case final num z) merged.z = z.toDouble();
      batch[nodes[i].id] = next(_trsOf(nodes[i]), merged);
    }
    unawaited(controller.setNodeTransformsBatch(batch));
  }

  @override
  Widget build(BuildContext context) {
    final trsList = [for (final n in nodes) _trsOf(n)];
    final trs = node.transform is TrsTransform
        ? node.transform as TrsTransform
        : null;
    final t = trs?.translation ?? trsList.first.translation;
    final s = trs?.scale ?? trsList.first.scale;
    final translations = [for (final e in trsList) e.translation];
    final scales = [for (final e in trsList) e.scale];
    final eulers = [
      for (final e in trsList) quaternionToEulerXyzDegrees(e.rotation),
    ];
    final live = controller.liveNode(node.id);
    final worldOrigin = single ? live?.globalTransform.getTranslation() : null;
    final geometryCenter = single ? live?.combinedWorldBounds?.center : null;

    void previewEach(
      Map<String, Object> v,
      Matrix4 Function(TrsTransform current, Vector3 merged) compose,
      List<Vector3> currents,
    ) {
      for (var i = 0; i < nodes.length; i++) {
        final merged = Vector3.copy(currents[i]);
        if (v['x'] case final num x) merged.x = x.toDouble();
        if (v['y'] case final num y) merged.y = y.toDouble();
        if (v['z'] case final num z) merged.z = z.toDouble();
        controller.previewLocalTransform(
          nodes[i].id,
          compose(trsList[i], merged),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Vec3Field(
          label: 'Translation',
          x: t.x,
          y: t.y,
          z: t.z,
          mixedX: !_axisUniform(translations, 0),
          mixedY: !_axisUniform(translations, 1),
          mixedZ: !_axisUniform(translations, 2),
          scrubStep: 0.01,
          snapStep: 1,
          onPreview: (v) => previewEach(
            v,
            (current, merged) =>
                Matrix4.compose(merged, current.rotation, current.scale),
            translations,
          ),
          onSubmit: (v) {
            if (single) {
              controller.setNodeTransformRouted(node.id, translation: v);
              return;
            }
            _commitEach(
              v,
              (current, merged) => TrsTransform(
                translation: merged,
                rotation: current.rotation,
                scale: current.scale,
              ),
              translations,
            );
          },
        ),
        Vec3Field(
          label: 'Scale',
          x: s.x,
          y: s.y,
          z: s.z,
          mixedX: !_axisUniform(scales, 0),
          mixedY: !_axisUniform(scales, 1),
          mixedZ: !_axisUniform(scales, 2),
          scrubStep: 0.01,
          snapStep: 0.1,
          onPreview: (v) => previewEach(
            v,
            (current, merged) =>
                Matrix4.compose(current.translation, current.rotation, merged),
            scales,
          ),
          onSubmit: (v) {
            if (single) {
              controller.setNodeTransformRouted(node.id, scale: v);
              return;
            }
            _commitEach(
              v,
              (current, merged) => TrsTransform(
                translation: current.translation,
                rotation: current.rotation,
                scale: merged,
              ),
              scales,
            );
          },
        ),
        // Rotation as XYZ Euler degrees.
        Vec3Field(
          label: 'Rotation',
          x: eulers.first.x,
          y: eulers.first.y,
          z: eulers.first.z,
          mixedX: !_axisUniform(eulers, 0),
          mixedY: !_axisUniform(eulers, 1),
          mixedZ: !_axisUniform(eulers, 2),
          scrubStep: 0.1,
          snapStep: 1,
          onPreview: (v) => previewEach(
            v,
            (current, merged) => Matrix4.compose(
              current.translation,
              eulerXyzDegreesToQuaternion(merged),
              current.scale,
            ),
            eulers,
          ),
          onSubmit: (v) {
            if (single) {
              final merged = Vector3.copy(eulers.first);
              if (v['x'] case final num x) merged.x = x.toDouble();
              if (v['y'] case final num y) merged.y = y.toDouble();
              if (v['z'] case final num z) merged.z = z.toDouble();
              final q = eulerXyzDegreesToQuaternion(merged);
              controller.setNodeTransformRouted(
                node.id,
                rotation: {'x': q.x, 'y': q.y, 'z': q.z, 'w': q.w},
              );
              return;
            }
            _commitEach(
              v,
              (current, merged) => TrsTransform(
                translation: current.translation,
                rotation: eulerXyzDegreesToQuaternion(merged),
                scale: current.scale,
              ),
              eulers,
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
      padding: const EdgeInsets.symmetric(vertical: editorRowGap),
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
/// Warns that a light's authored shadow is not being drawn because the shared
/// shadow atlas ran out of slots for its light type. Shown on the light's own
/// component, where the Casts shadow toggle that appears inert lives.
class _ShadowBudgetNotice extends StatelessWidget {
  const _ShadowBudgetNotice();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 4, 4, 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.warning_amber_rounded, size: 13, color: _warningColor),
        const SizedBox(width: 5),
        const Expanded(
          child: Text(
            'Casts shadow is on, but the shadow atlas has no slot left for '
            'this light type, so no shadow is drawn. Turn it off on lights '
            'that do not need one.',
            style: TextStyle(fontSize: 11, color: _warningColor),
          ),
        ),
      ],
    ),
  );
}

const Color _warningColor = Color(0xFFE6B84D);

class _ComponentSection extends StatelessWidget {
  const _ComponentSection({
    required this.nodes,
    required this.type,
    required this.controller,
    required this.canRemove,
  });

  /// The nodes edited together, primary first; each carries a [type]
  /// component.
  final List<NodeSpec> nodes;
  final String type;
  final EditorController controller;
  final bool canRemove;

  NodeSpec get node => nodes.first;

  Future<void> _removeAll() async {
    for (final n in nodes) {
      await controller.removeComponentRouted(n.id, type);
    }
  }

  // The header's right-click menu: source-file actions (enabled when the
  // component came from project source extraction) and removal (mirroring
  // the header's close button).
  Future<void> _showContextMenu(BuildContext context, Offset position) async {
    final sourcePath = controller.componentSourcePaths[type];
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
        await _removeAll();
    }
  }

  /// How many of the edited nodes are lights asking for a shadow the shared
  /// atlas had no slot for. Drives the notice above the component's fields,
  /// where the Casts shadow toggle that appears to do nothing lives.
  int _droppedShadowCount() {
    if (type != 'pointLight' && type != 'spotLight') return 0;
    var dropped = 0;
    for (final node in nodes) {
      final live = controller.liveNode(node.id);
      if (live == null) continue;
      for (final component in live.getComponents<Component>()) {
        final casts = switch (component) {
          SpotLightComponent(:final light) => light.castsShadow,
          PointLightComponent(:final light) => light.castsShadow,
          _ => false,
        };
        if (!casts) continue;
        if (!controller.scene.isShadowCasterGranted(component)) dropped++;
      }
    }
    return dropped;
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
          child: EditorSectionHeader(
            label: humanizeIdentifier(type),
            trailing: canRemove
                ? _IconAction(
                    icon: Icons.close,
                    tooltip: 'Remove component',
                    onPressed: _removeAll,
                  )
                : null,
          ),
        ),
        if (_droppedShadowCount() > 0) const _ShadowBudgetNotice(),
        // Two component types are not a property bag and need their own
        // controls above the schema-driven ones. Single selection only: a
        // bake and a playback clock act on one thing.
        if (nodes.length == 1) ...[
          // A nav surface is bake settings plus a bake: the four agent
          // numbers only mean anything drawn together, and nothing in a
          // schema-driven list runs a bake.
          if (type == 'navMeshSurface')
            NavMeshEditor(controller: controller, nodeId: nodes.first.id),
          // An emitter's authored fields are a property bag, but its clock is
          // not: play, pause and restart reach the running simulation, and
          // restart is how a one-shot is fired at all.
          if (type == vfxComponentType)
            ParticleEmitterControls(
              controller: controller,
              nodeId: nodes.first.id,
            ),
        ],
        _ComponentEditor(nodes: nodes, type: type, controller: controller),
      ],
    );
  }
}

/// Renders a component's editable properties from its declared schema, falling
/// back to whatever is in the property bag for keys the schema does not cover.
/// A field shows the bag's value when present, otherwise the schema default.
class _ComponentEditor extends StatelessWidget {
  const _ComponentEditor({
    required this.nodes,
    required this.type,
    required this.controller,
  });

  /// The nodes edited together, primary first; each carries a [type]
  /// component. A property whose values differ renders through the same
  /// widget with a dash, and a commit applies to every node.
  final List<NodeSpec> nodes;
  final String type;
  final EditorController controller;

  NodeSpec get node => nodes.first;
  bool get single => nodes.length == 1;

  ComponentSpec? _componentOn(NodeSpec node) =>
      node.components.where((c) => c.type == type).firstOrNull;

  void _set(String name, Object? value) {
    if (value == null) return;
    if (single) {
      controller.setComponentPropertyRouted(node.id, type, name, value);
      return;
    }
    unawaited(
      controller.setComponentPropertiesOnNodes(
        [for (final n in nodes) n.id],
        type,
        {name: value},
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final component = _componentOn(node)!;
    final schema = controller.componentSchema(type);
    final schemaNames = {for (final d in schema) d.name};
    // Keys present on the component but not described by the schema, so nothing
    // a node carries is ever hidden. For a multi-selection only keys every
    // node carries render.
    final extras = [
      for (final entry in component.properties.entries)
        if (!schemaNames.contains(entry.key) &&
            nodes.every(
              (n) => _componentOn(n)!.properties.containsKey(entry.key),
            ))
          entry,
    ];

    if (schema.isEmpty && extras.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: editorRowGap),
        child: Text(
          '(no editable properties)',
          style: TextStyle(fontSize: 11, color: Colors.grey),
        ),
      );
    }

    PropertyValue? valueOn(NodeSpec n, String name, PropertyValue? fallback) =>
        _componentOn(n)!.properties[name] ?? fallback;

    bool mixedFor(String name, PropertyValue? fallback) {
      final first = valueOn(node, name, fallback);
      return nodes
          .skip(1)
          .any((n) => !_sameValue(valueOn(n, name, fallback), first));
    }

    Widget row(ComponentPropertyDef def) => _SchemaPropertyRow(
      componentType: type,
      def: def,
      value: component.properties[def.name] ?? def.defaultValue,
      mixed: mixedFor(def.name, def.defaultValue),
      controller: controller,
      onChanged: (v) => _set(def.name, v),
      onPreview: (value) {
        for (final n in nodes) {
          controller.previewComponentProperty(n.id, type, def.name, value);
        }
      },
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
            identity: '${node.id.toToken()}/$type',
            children: [
              for (final entry in groups.entries)
                InspectorAccordionItem(
                  title: humanizeIdentifier(entry.key),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [for (final def in entry.value) row(def)],
                  ),
                ),
            ],
          ),
        for (final entry in extras)
          if (mixedFor(entry.key, null))
            _ReadOnlyRow(
              label: humanizeIdentifier(entry.key),
              text: 'Mixed values',
            )
          else
            _PropertyValueRow(
              label: humanizeIdentifier(entry.key),
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
    this.onPreview,
    this.mixed = false,
  });

  final String componentType;
  final ComponentPropertyDef def;
  final PropertyValue? value;
  final EditorController controller;
  final void Function(Object?) onChanged;

  /// Streams in-drag values onto the live component (no transaction), so the
  /// scene follows the drag; null leaves the drag preview inert.
  final void Function(PropertyValue value)? onPreview;

  /// A multi-selection whose values differ for this property. Simple kinds
  /// render their normal editor with a dash; structured kinds read as
  /// "Mixed values" until the selection agrees.
  final bool mixed;

  static const _mixedEditableKinds = {
    ComponentPropertyKind.boolean,
    ComponentPropertyKind.integer,
    ComponentPropertyKind.number,
    ComponentPropertyKind.string,
    ComponentPropertyKind.assetRef,
    ComponentPropertyKind.vec3,
  };

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

  Widget _buildEditor(BuildContext context) {
    // The schema's name is an identifier; the row shows it as words.
    final label = humanizeIdentifier(def.name);
    if (mixed && !_mixedEditableKinds.contains(def.kind)) {
      return _ReadOnlyRow(label: label, text: 'Mixed values');
    }
    switch (def.kind) {
      case ComponentPropertyKind.boolean:
        return _BoolRow(
          label: label,
          value: value is BoolValue ? (value as BoolValue).value : false,
          mixed: mixed,
          onChanged: onChanged,
        );
      case ComponentPropertyKind.integer:
        final powerOfTwo = def.constraint<PowerOfTwo>();
        final current = value is IntValue ? (value as IntValue).value : 0;
        if (powerOfTwo != null) {
          final powers = _powersOfTwo(powerOfTwo);
          return EnumRow(
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
            mixed: mixed,
            onPreview: (value) => onPreview?.call(IntValue(value.round())),
            onCommit: (value) => onChanged(value.round()),
          );
        }
        return _IntRow(
          label: label,
          value: current,
          mixed: mixed,
          onSubmit: onChanged,
        );
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
            mixed: mixed,
            onPreview: (value) => onPreview?.call(DoubleValue(value / scale)),
            onCommit: (value) => onChanged(value / scale),
          );
        }
        return _DoubleRow(
          label: '$label$suffix',
          value: current,
          mixed: mixed,
          onSubmit: (raw) => onChanged(raw / scale),
        );
      case ComponentPropertyKind.string:
      case ComponentPropertyKind.assetRef:
        if (def.options != null) {
          return EnumRow(
            label: label,
            value: mixed
                ? null
                : value is StringValue
                ? (value as StringValue).value
                : null,
            options: def.options!,
            onChanged: onChanged,
          );
        }
        return _StringRow(
          label: label,
          value: value is StringValue ? (value as StringValue).value : '',
          mixed: mixed,
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
            mixed: mixed,
            onPreview: (r, g, b, _) =>
                onPreview?.call(Vec3Value(Vector3(r, g, b))),
            onCommit: (r, g, b, _) => onChanged({'x': r, 'y': g, 'z': b}),
          );
        }
        return Vec3Field(
          label: label,
          x: v?.x ?? 0,
          y: v?.y ?? 0,
          z: v?.z ?? 0,
          mixedX: mixed,
          mixedY: mixed,
          mixedZ: mixed,
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
      case ComponentPropertyKind.matrix4:
      case ComponentPropertyKind.list:
      case ComponentPropertyKind.map:
        // TODO(component-property-editors): matrix4, structured list, and
        // open-map editors (lists land with the components that need them).
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
            padding: const EdgeInsets.symmetric(vertical: editorRowGap),
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
          EnumRow(
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
  const _AddComponentBar({required this.nodes, required this.controller});

  /// The nodes a chosen component adds onto (every selected node).
  final List<NodeSpec> nodes;
  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    // Offer only types absent from every selected node.
    final present = {
      for (final n in nodes)
        for (final c in n.components) c.type,
    };
    final available = [
      for (final type in controller.componentTypes())
        if (!present.contains(type)) type,
    ];
    return MenuAnchor(
      menuChildren: [
        for (final type in available)
          MenuItemButton(
            onPressed: () {
              for (final n in nodes) {
                controller.addComponentRouted(n.id, type);
              }
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(type),
                // Foreign types (known by schema, realized as data in the
                // editor) show where the schema came from.
                if (controller.foreignTypeProvenance[type]
                    case final provenance?) ...[
                  const SizedBox(width: 6),
                  Text(
                    provenance == 'live' ? 'project' : provenance,
                    style: editorMicroText,
                  ),
                ],
              ],
            ),
          ),
      ],
      builder: (context, menu, _) => EditorActionButton(
        label: 'Add Component',
        icon: Icons.add,
        tooltip: available.isEmpty
            ? 'This node already carries every component type'
            : 'Add a component to the selection',
        onPressed: available.isEmpty
            ? null
            : () => menu.isOpen ? menu.close() : menu.open(),
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
          padding: const EdgeInsets.symmetric(vertical: editorRowGap),
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
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
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
      padding: const EdgeInsets.symmetric(vertical: editorRowGap),
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
@visibleForTesting
class EnumRow extends StatelessWidget {
  const EnumRow({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.labels,
  });
  final String label;
  final String? value;
  final List<String> options;
  final void Function(String) onChanged;

  /// Display text per option, for values whose identifier reads poorly in a
  /// menu. Options missing here show their raw value.
  final Map<String, String>? labels;

  @override
  Widget build(BuildContext context) {
    final current = options.contains(value) ? value : null;
    return LabeledControlRow(
      label: label,
      control: SizedBox(
        width: double.infinity,
        child: FSelect<String>(
          // Keyed by display label, valued by the option itself (FSelect
          // takes Map<String, T>); with no labels the two coincide, which
          // is why the plain form reads as option: option.
          items: {
            for (final option in options) (labels?[option] ?? option): option,
          },
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
      padding: const EdgeInsets.symmetric(vertical: editorRowGap),
      child: Row(
        children: [
          SizedBox(
            width: editorPropertyLabelWidth,
            child: Text(
              label,
              style: editorRowLabelText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: editorRowGutter),
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
      padding: const EdgeInsets.symmetric(vertical: editorRowGap),
      child: Row(
        children: [
          SizedBox(
            width: editorPropertyLabelWidth,
            child: Text(
              label,
              style: editorRowLabelText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: editorRowGutter),
          Expanded(
            child: ids.isEmpty
                ? Text(
                    '(no ${resourceKind ?? 'resource'} resources)',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  )
                : ReferencePicker(
                    entries: [
                      for (final id in ids) (id: id, label: _label(id)),
                    ],
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
    final nodes = controller.document.nodes.values.toList();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: editorRowGap),
      child: Row(
        children: [
          SizedBox(
            width: editorPropertyLabelWidth,
            child: Text(
              label,
              style: editorRowLabelText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: editorRowGutter),
          Expanded(
            child: ReferencePicker(
              entries: [
                for (final node in nodes)
                  (
                    id: node.id,
                    label: node.name.isEmpty ? node.id.toToken() : node.name,
                  ),
              ],
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
          Text(
            widget.label,
            style: const TextStyle(fontSize: 9, color: Colors.grey),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: EditorTextField(
              controller: _ctrl,
              focusNode: _focus,
              // The row's own focus listener commits.
              commitOnFocusLoss: false,
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
    this.mixed = false,
  });
  final String label;
  final String value;
  final void Function(String) onSubmit;

  /// Dash placeholder for a multi-selection whose values disagree; a commit
  /// applies the entered text to every node.
  final bool mixed;

  @override
  State<_StringRow> createState() => _StringRowState();
}

class _StringRowState extends State<_StringRow> {
  late TextEditingController _ctrl;
  late final FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.mixed ? '' : widget.value);
    _focus = FocusNode()..addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (!_focus.hasFocus) _commit();
  }

  void _commit() {
    // Skip a no-op edit when the text is unchanged (or still the mixed dash).
    if (widget.mixed) {
      if (_ctrl.text.isNotEmpty) widget.onSubmit(_ctrl.text);
      return;
    }
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
    return LabeledControlRow(
      label: widget.label,
      control: EditorTextField(
        controller: _ctrl,
        focusNode: _focus,
        hint: widget.mixed ? '\u2014' : null,
        // The focus listener this row already owns does the committing.
        commitOnFocusLoss: false,
        onSubmit: (_) => _commit(),
      ),
    );
  }
}

class _BoolRow extends StatelessWidget {
  const _BoolRow({
    required this.label,
    required this.value,
    required this.onChanged,
    this.mixed = false,
  });
  final String label;
  final bool value;
  final void Function(bool) onChanged;

  /// A multi-selection whose values disagree; a dash marks the state and the
  /// next toggle applies one value to every node.
  final bool mixed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: editorRowGap),
      child: Row(
        children: [
          SizedBox(
            width: editorPropertyLabelWidth,
            child: Text(
              label,
              style: editorRowLabelText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: editorRowGutter),
          if (mixed) ...[
            const Text(
              '\u2014',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
            const SizedBox(width: 4),
          ],
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
    this.mixed = false,
  });
  final String label;
  final int value;
  final void Function(int) onSubmit;

  /// Dash placeholder for a multi-selection whose values disagree.
  final bool mixed;

  @override
  State<_IntRow> createState() => _IntRowState();
}

class _IntRowState extends State<_IntRow> {
  late TextEditingController _ctrl;
  late final FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
      text: widget.mixed ? '' : widget.value.toString(),
    );
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
      padding: const EdgeInsets.symmetric(vertical: editorRowGap),
      child: Row(
        children: [
          SizedBox(
            width: editorPropertyLabelWidth,
            child: Text(
              widget.label,
              style: editorRowLabelText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: editorRowGutter),
          Expanded(
            child: EditorTextField(
              controller: _ctrl,
              focusNode: _focus,
              // The row's own focus listener commits.
              commitOnFocusLoss: false,
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
    this.mixed = false,
  });
  final String label;
  final double value;
  final void Function(double) onSubmit;

  /// Dash placeholder for a multi-selection whose values disagree.
  final bool mixed;

  @override
  State<_DoubleRow> createState() => _DoubleRowState();
}

class _DoubleRowState extends State<_DoubleRow> {
  late TextEditingController _ctrl;
  late final FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
      text: widget.mixed ? '' : widget.value.toStringAsFixed(3),
    );
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
      padding: const EdgeInsets.symmetric(vertical: editorRowGap),
      child: Row(
        children: [
          SizedBox(
            width: editorPropertyLabelWidth,
            child: Text(
              widget.label,
              style: editorRowLabelText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: editorRowGutter),
          Expanded(
            child: EditorTextField(
              controller: _ctrl,
              focusNode: _focus,
              // The row's own focus listener commits.
              commitOnFocusLoss: false,
              onSubmit: (_) => _commit(),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown on the mesh rather than in the Add menu, because the thing being
/// made water is this surface: it keeps the node's name, its transform, and
/// the footprint it already had.
class _MakeWaterRow extends StatelessWidget {
  const _MakeWaterRow({required this.controller, required this.nodeId});

  final EditorController controller;
  final LocalId nodeId;

  @override
  Widget build(BuildContext context) {
    final footprint = surfaceFootprint(controller, nodeId);
    if (footprint == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Make this surface water, '
              '${footprint.width.toStringAsFixed(0)} by '
              '${footprint.depth.toStringAsFixed(0)} units where it stands.',
              style: editorDetailText,
            ),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            icon: const Icon(Icons.water, size: 14),
            label: const Text('Make water', style: TextStyle(fontSize: 11)),
            onPressed: () => makeSurfaceWater(controller, nodeId),
          ),
        ],
      ),
    );
  }
}

/// The way into a node's graph, on the component that holds it.
class _EditGraphRow extends StatelessWidget {
  const _EditGraphRow({required this.controller, required this.node});

  final EditorController controller;
  final NodeSpec node;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        icon: const Icon(Icons.schema_outlined, size: 14),
        label: const Text('Edit Graph', style: TextStyle(fontSize: 11)),
        onPressed: () => unawaited(
          openNodeScriptEditor(
            context: context,
            controller: controller,
            nodeName: node.name.isEmpty ? 'Node' : node.name,
          ),
        ),
      ),
    ),
  );
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
/// positions as a project grows. After them come the project's own Scripts --
/// the ones you most often want and the only ones you can edit -- then
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
/// category -- so "phys" finds every physics component, not only the one
/// spelled that way.
bool matchesComponentQuery(String type, ComponentTypeInfo info, String query) {
  if (query.isEmpty) return true;
  final needle = query.toLowerCase();
  return type.toLowerCase().contains(needle) ||
      addComponentCategory(info).toLowerCase().contains(needle);
}

/// The component picker: a search field over every type this node does not
/// already carry, grouped by category.
