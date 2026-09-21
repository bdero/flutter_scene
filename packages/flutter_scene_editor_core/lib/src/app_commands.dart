/// Commands for everything around the document: opening and saving, the
/// project, the running app, and the editor's own tools and panels.
///
/// These act on the session's [EditorHost], so they are inapplicable in a
/// headless session. Application commands are asynchronous and never reach
/// the undo history; tool and panel commands change view state.
///
/// TODO(session-scoped-commands): the registry lives on a session, so the
/// three commands that would create one (`newDocument`, `openDocument`,
/// `openProject`) cannot be reached before a document is open. The editor's
/// start screen and the MCP tools of the same name cover that case today.
library;

import 'change.dart';
import 'command.dart';
import 'editor_host.dart';
import 'params.dart';

Transaction _nothing(String name) => Transaction(name: name, records: const []);

EditorHost _host(CommandContext ctx) =>
    ctx.host ??
    (throw const CommandException('This session has no editor to drive'));

bool Function(CommandContext, Map<String, Object?>) _supports(String command) =>
    (ctx, params) => ctx.host?.supports(command) ?? false;

CommandEntry _application({
  required String name,
  required String doc,
  required String category,
  required Future<void> Function(EditorHost host, Map<String, Object?> params)
  perform,
  List<ParamSpec> paramSchema = const [],
}) => CommandEntry.application(
  name: name,
  doc: doc,
  category: category,
  paramSchema: paramSchema,
  applicable: _supports(name),
  perform: (ctx, params) => perform(_host(ctx), params),
);

const _pathParam = ParamSpec(
  name: 'path',
  type: ParamType.string,
  label: 'Path',
);

/// Replaces the open document with an empty one.
final newDocument = _application(
  name: 'newDocument',
  doc: 'Close the open document and start an empty one.',
  category: 'Document',
  perform: (host, params) => host.newDocument(),
);

/// Opens a `.fscene`.
final openDocument = _application(
  name: 'openDocument',
  doc: 'Open the `.fscene` document at a path.',
  category: 'Document',
  paramSchema: const [_pathParam],
  perform: (host, params) => host.openDocument(requireString(params, 'path')),
);

/// Saves the open document.
final saveDocument = _application(
  name: 'saveDocument',
  doc: 'Save the open document, to a path when one is given.',
  category: 'Document',
  paramSchema: const [
    ParamSpec(
      name: 'path',
      type: ParamType.string,
      label: 'Path',
      required: false,
    ),
  ],
  perform: (host, params) =>
      host.saveDocument(path: optionalString(params, 'path')),
);

/// Opens a project.
final openProject = _application(
  name: 'openProject',
  doc: 'Open the project at a path (an `.fproject`, or its directory).',
  category: 'Project',
  paramSchema: const [_pathParam],
  perform: (host, params) => host.openProject(requireString(params, 'path')),
);

/// Closes the open project.
final closeProject = _application(
  name: 'closeProject',
  doc: 'Close the open project.',
  category: 'Project',
  perform: (host, params) => host.closeProject(),
);

/// Selects the build configuration.
final selectBuildConfiguration = _application(
  name: 'selectBuildConfiguration',
  doc: 'Select the build configuration the toolbar runs.',
  category: 'Project',
  paramSchema: const [
    ParamSpec(name: 'id', type: ParamType.string, label: 'Configuration'),
  ],
  perform: (host, params) =>
      host.selectBuildConfiguration(requireString(params, 'id')),
);

/// Selects the target device.
final selectDevice = _application(
  name: 'selectDevice',
  doc: 'Select the device the project runs on.',
  category: 'Project',
  paramSchema: const [
    ParamSpec(name: 'id', type: ParamType.string, label: 'Device'),
  ],
  perform: (host, params) => host.selectDevice(requireString(params, 'id')),
);

/// Builds the project.
final buildProject = _application(
  name: 'buildProject',
  doc: 'Build the project with the selected configuration.',
  category: 'Run',
  perform: (host, params) => host.buildProject(),
);

/// Runs the project.
final runProject = _application(
  name: 'runProject',
  doc: 'Run the project on the selected device.',
  category: 'Run',
  perform: (host, params) => host.runProject(),
);

/// Stops the running project.
final stopProject = _application(
  name: 'stopProject',
  doc: 'Stop the running project.',
  category: 'Run',
  perform: (host, params) => host.stopProject(),
);

/// Hot reloads the running project.
final hotReload = _application(
  name: 'hotReload',
  doc: 'Hot reload the running project.',
  category: 'Run',
  perform: (host, params) => host.hotReload(),
);

/// Hot restarts the running project.
final hotRestart = _application(
  name: 'hotRestart',
  doc: 'Hot restart the running project.',
  category: 'Run',
  perform: (host, params) => host.hotRestart(),
);

/// Reloads the running project's scene.
final reloadScene = _application(
  name: 'reloadScene',
  doc: "Reload the running project's scene from the open document.",
  category: 'Run',
  perform: (host, params) => host.reloadScene(),
);

/// Imports a model into the document.
final importModel = _application(
  name: 'importModel',
  doc: 'Import a model file (`.glb`, `.gltf`) into the open document.',
  category: 'Import',
  paramSchema: const [
    _pathParam,
    ParamSpec(
      name: 'parentId',
      type: ParamType.nodeRef,
      label: 'Parent',
      required: false,
    ),
    ParamSpec(
      name: 'scale',
      type: ParamType.number,
      label: 'Scale',
      required: false,
      defaultValue: 1.0,
    ),
  ],
  perform: (host, params) => host.importModel(
    requireString(params, 'path'),
    parentId: optionalString(params, 'parentId'),
    scale: optionalDouble(params, 'scale') ?? 1.0,
  ),
);

/// Imports an environment image.
final importEnvironment = _application(
  name: 'importEnvironment',
  doc: 'Import an environment image and make it the stage environment.',
  category: 'Import',
  paramSchema: const [_pathParam],
  perform: (host, params) =>
      host.importEnvironment(requireString(params, 'path')),
);

/// Switches the active viewport tool.
final setToolMode = CommandEntry(
  name: 'setToolMode',
  doc: 'Switch the active viewport tool (translate, rotate, scale).',
  category: 'View',
  kind: CommandKind.ui,
  paramSchema: const [
    ParamSpec(name: 'mode', type: ParamType.string, label: 'Tool'),
  ],
  applicable: _supports('setToolMode'),
  execute: (ctx, params) {
    final host = _host(ctx);
    final mode = requireString(params, 'mode');
    if (!host.toolModes.contains(mode)) {
      throw CommandException(
        'Unknown tool "$mode"; use one of ${host.toolModes.join(', ')}',
      );
    }
    host.setToolMode(mode);
    return _nothing('Switch tool');
  },
);

/// Shows a panel, docking it when it is not in the layout.
final showPanel = CommandEntry(
  name: 'showPanel',
  doc: 'Show an editor panel, docking it when it is not in the layout.',
  category: 'View',
  kind: CommandKind.ui,
  paramSchema: const [
    ParamSpec(name: 'panel', type: ParamType.string, label: 'Panel'),
  ],
  applicable: _supports('showPanel'),
  execute: (ctx, params) {
    final host = _host(ctx);
    final id = requireString(params, 'panel');
    if (!host.panels.contains(id)) {
      throw CommandException(
        'Unknown panel "$id"; use one of ${host.panels.join(', ')}',
      );
    }
    host.showPanel(id);
    return _nothing('Show panel');
  },
);

/// Focuses a panel.
final focusPanel = CommandEntry(
  name: 'focusPanel',
  doc: 'Focus an editor panel, showing it first when it is hidden.',
  category: 'View',
  kind: CommandKind.ui,
  paramSchema: const [
    ParamSpec(name: 'panel', type: ParamType.string, label: 'Panel'),
  ],
  applicable: _supports('focusPanel'),
  execute: (ctx, params) {
    final host = _host(ctx);
    final id = requireString(params, 'panel');
    if (!host.panels.contains(id)) {
      throw CommandException(
        'Unknown panel "$id"; use one of ${host.panels.join(', ')}',
      );
    }
    host.focusPanel(id);
    return _nothing('Focus panel');
  },
);

/// Switches the viewport debug mode.
final setViewportDebugMode = CommandEntry(
  name: 'setViewportDebugMode',
  doc: 'Switch the viewport debug visualization.',
  category: 'View',
  kind: CommandKind.ui,
  paramSchema: const [
    ParamSpec(name: 'mode', type: ParamType.string, label: 'Mode'),
  ],
  applicable: _supports('setViewportDebugMode'),
  execute: (ctx, params) {
    final host = _host(ctx);
    final mode = requireString(params, 'mode');
    if (!host.viewportDebugModes.contains(mode)) {
      throw CommandException(
        'Unknown debug mode "$mode"; use one of '
        '${host.viewportDebugModes.join(', ')}',
      );
    }
    host.setViewportDebugMode(mode);
    return _nothing('Set debug view');
  },
);

/// Everything an editor host drives.
final List<CommandEntry> applicationCommands = [
  newDocument,
  openDocument,
  saveDocument,
  openProject,
  closeProject,
  selectBuildConfiguration,
  selectDevice,
  buildProject,
  runProject,
  stopProject,
  hotReload,
  hotRestart,
  reloadScene,
  importModel,
  importEnvironment,
  setToolMode,
  showPanel,
  focusPanel,
  setViewportDebugMode,
];
