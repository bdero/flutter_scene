/// Selection and viewport commands.
///
/// These change transient state rather than the document, so they return an
/// empty transaction and never reach the undo history. They exist as commands
/// so a script, an agent, and the UI all drive the editor through one
/// registry.
library;

import 'package:scene/scene.dart';

import 'change.dart';
import 'command.dart';
import 'params.dart';
import 'selection.dart';
import 'view_host.dart';

Transaction _nothing(String name) => Transaction(name: name, records: const []);

Selection _requireSelection(CommandContext ctx) =>
    ctx.selection ??
    (throw const CommandException('This session has no selection'));

ViewHost _requireView(CommandContext ctx) =>
    ctx.view ?? (throw const CommandException('This session has no viewport'));

/// Replaces, adds to, removes from, or toggles the selection.
final selectNodes = CommandEntry(
  name: 'selectNodes',
  doc:
      'Select nodes. "mode" replaces the selection by default, or adds to, '
      'removes from, or toggles it. The last id given becomes primary.',
  category: 'Selection',
  kind: CommandKind.selection,
  paramSchema: const [
    ParamSpec(name: 'nodeIds', type: ParamType.nodeRefList, label: 'Nodes'),
    ParamSpec(
      name: 'mode',
      type: ParamType.string,
      label: 'Mode',
      description: 'replace (default), add, remove, or toggle.',
      required: false,
      defaultValue: 'replace',
    ),
  ],
  applicable: (ctx, params) => ctx.selection != null,
  execute: (ctx, params) {
    final selection = _requireSelection(ctx);
    final ids = requireNodeIdList(params, 'nodeIds');
    final mode = optionalString(params, 'mode', orElse: 'replace')!;
    for (final id in ids) {
      if (ctx.document.nodes[id] == null) {
        throw CommandException('No node ${id.toToken()}');
      }
    }
    switch (mode) {
      case 'replace':
        selection.set(ids);
      case 'add':
        ids.forEach(selection.add);
      case 'remove':
        ids.forEach(selection.remove);
      case 'toggle':
        ids.forEach(selection.toggle);
      default:
        throw CommandException(
          'Unknown selection mode "$mode"; use replace, add, remove, or '
          'toggle',
        );
    }
    return _nothing('Select');
  },
);

/// Clears the selection.
final clearSelection = CommandEntry(
  name: 'clearSelection',
  doc: 'Clear the selection.',
  category: 'Selection',
  kind: CommandKind.selection,
  paramSchema: const [],
  applicable: (ctx, params) => ctx.selection != null,
  execute: (ctx, params) {
    _requireSelection(ctx).clear();
    return _nothing('Clear selection');
  },
);

/// Moves the viewport camera. Omitted fields keep their current value.
final setViewportCamera = CommandEntry(
  name: 'setViewportCamera',
  doc:
      'Move the viewport camera. Every field is optional and keeps its '
      'current value when omitted.',
  category: 'View',
  kind: CommandKind.view,
  paramSchema: const [
    ParamSpec(
      name: 'azimuth',
      type: ParamType.number,
      label: 'Azimuth',
      description: 'Orbit angle around the target, in radians.',
      required: false,
    ),
    ParamSpec(
      name: 'elevation',
      type: ParamType.number,
      label: 'Elevation',
      description: 'Orbit angle above the target, in radians.',
      required: false,
    ),
    ParamSpec(
      name: 'radius',
      type: ParamType.number,
      label: 'Distance',
      required: false,
    ),
    ParamSpec(
      name: 'target',
      type: ParamType.vec3,
      label: 'Target',
      required: false,
    ),
    ParamSpec(
      name: 'orthographic',
      type: ParamType.boolean,
      label: 'Orthographic',
      required: false,
    ),
  ],
  applicable: (ctx, params) => ctx.view != null,
  execute: (ctx, params) {
    final view = _requireView(ctx);
    final current = view.camera;
    view.setCamera(
      EditorCameraSpec(
        azimuth: optionalDouble(params, 'azimuth') ?? current.azimuth,
        elevation: optionalDouble(params, 'elevation') ?? current.elevation,
        radius: optionalDouble(params, 'radius') ?? current.radius,
        target: optionalVec3(params, 'target') ?? current.target,
        orthographic:
            optionalBool(params, 'orthographic') ?? current.orthographic,
      ),
    );
    return _nothing('Move camera');
  },
);

/// Frames nodes in the viewport.
final frameNodes = CommandEntry(
  name: 'frameNodes',
  doc: 'Move the viewport camera to frame the given nodes.',
  category: 'View',
  kind: CommandKind.view,
  paramSchema: const [
    ParamSpec(name: 'nodeIds', type: ParamType.nodeRefList, label: 'Nodes'),
  ],
  applicable: (ctx, params) => ctx.view != null,
  execute: (ctx, params) {
    final view = _requireView(ctx);
    final ids = requireNodeIdList(params, 'nodeIds');
    if (!view.frame(ids)) {
      throw const CommandException('Nothing to frame; no renderable bounds');
    }
    return _nothing('Frame');
  },
);

/// The selection and viewport commands.
final List<CommandEntry> viewCommands = [
  selectNodes,
  clearSelection,
  setViewportCamera,
  frameNodes,
];
