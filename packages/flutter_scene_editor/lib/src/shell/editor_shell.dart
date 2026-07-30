import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controller/editor_controller.dart';
import '../io/glb_import_options.dart';
import '../io/scene_io.dart';
import '../panels/asset_browser_panel.dart';
import '../panels/history_panel.dart';
import '../panels/inspector_panel.dart';
import '../panels/outliner_panel.dart';
import '../viewport/viewport_camera_handle.dart';
import '../viewport/viewport_panel.dart';
import 'command_palette.dart';
import 'dock_layout.dart';
import 'docking_shell.dart';

/// The panels [EditorShell] registers with its [DockingShell], id to the
/// title shown on tabs and in the View menu.
const Map<String, String> _panelTitles = {
  'viewport': 'Viewport',
  'outliner': 'Outliner',
  'inspector': 'Inspector',
  'assets': 'Assets',
  'history': 'History',
};

List<String> get _panelIds => _panelTitles.keys.toList();

/// Extra viewports are created at runtime with ids like `viewport2` and are
/// admitted through layout persistence as dynamic panels.
final RegExp _extraViewportPattern = RegExp(r'^viewport\d+$');

/// The out-of-box arrangement, viewport left, outliner over inspector right,
/// tabbed assets/history strip along the bottom.
DockLayout _defaultDockLayout() {
  return DockLayout(
    DockSplit(
      Axis.vertical,
      [
        DockSplit(
          Axis.horizontal,
          [
            DockTabs(['viewport']),
            DockSplit(
              Axis.vertical,
              [
                DockTabs(['outliner']),
                DockTabs(['inspector']),
              ],
              [0.5, 0.5],
            ),
          ],
          [0.72, 0.28],
        ),
        DockTabs(['assets', 'history']),
      ],
      [0.74, 0.26],
    ),
  );
}

/// Intent for undo (Cmd+Z).
class UndoIntent extends Intent {
  const UndoIntent();
}

/// Intent for redo (Cmd+Shift+Z).
class RedoIntent extends Intent {
  const RedoIntent();
}

/// Intent for deleting the primary selected node (Delete).
class DeleteNodeIntent extends Intent {
  const DeleteNodeIntent();
}

/// Intent for saving the scene (Cmd+S).
class SaveIntent extends Intent {
  const SaveIntent();
}

/// Intent for opening the command palette (Cmd+P or Cmd+Shift+P).
class CommandPaletteIntent extends Intent {
  const CommandPaletteIntent();
}

/// Intent for copying the selection (Cmd+C).
class CopyIntent extends Intent {
  const CopyIntent();
}

/// Intent for pasting the clipboard (Cmd+V).
class PasteIntent extends Intent {
  const PasteIntent();
}

/// Intent for duplicating the selection (Cmd+D).
class DuplicateIntent extends Intent {
  const DuplicateIntent();
}

/// An action that disables itself when [enabled] returns false, so the bound
/// key falls through to the focused widget (for example a text field) instead
/// of being consumed.
class _GuardedAction<T extends Intent> extends Action<T> {
  _GuardedAction(this.enabled, this.onInvokeCallback);

  final bool Function() enabled;
  final Object? Function(T intent) onInvokeCallback;

  @override
  bool isEnabled(T intent) => enabled();

  @override
  bool consumesKey(T intent) => enabled();

  @override
  Object? invoke(T intent) => onInvokeCallback(intent);
}

/// The top-level editor widget.
///
/// Accepts an [EditorController] and builds the full 4-panel shell with
/// menu bar, keyboard shortcuts, and a command palette overlay. Opening a new
/// file or creating an empty scene replaces the controller in the parent state
/// (via [onControllerReplaced]).
class EditorShell extends StatefulWidget {
  const EditorShell({
    super.key,
    required this.controller,
    required this.onControllerReplaced,
    this.viewportRepaintBoundaryKey,
    this.viewportCameraHandle,
    this.dockLayoutJson,
    this.onDockLayoutChanged,
    this.menuBarLeadingInset = 8,
    this.onMenuBarDragStart,
    this.currentPath,
    this.onDocumentPathChanged,
  });

  final EditorController controller;

  /// Called when the user opens a new file or clears the scene; the parent
  /// should rebuild with the new controller.
  final void Function(EditorController newController) onControllerReplaced;

  /// Optional key on the viewport's [RepaintBoundary], so a host can capture
  /// the rendered viewport (the MCP `screenshot_viewport` perception tool).
  final GlobalKey? viewportRepaintBoundaryKey;

  /// Optional remote control attached to the primary viewport's camera (the
  /// MCP camera tools).
  final ViewportCameraHandle? viewportCameraHandle;

  /// A dock layout previously emitted through [onDockLayoutChanged]. Invalid
  /// or missing layouts fall back to the default arrangement.
  final String? dockLayoutJson;

  /// Reports the serialized dock layout whenever panels are rearranged, so
  /// the host can persist it.
  final ValueChanged<String>? onDockLayoutChanged;

  /// Space before the menu bar's first item. Hosts that hide the native
  /// title bar set this to clear the window controls drawn over the content.
  final double menuBarLeadingInset;

  /// Called when a drag starts on the menu bar's empty area. Hosts that hide
  /// the native title bar use it to move the window.
  final VoidCallback? onMenuBarDragStart;

  /// The document's file path (shown in the menu bar, reused by Save), kept
  /// by the host. Null for an unsaved scene.
  final String? currentPath;

  /// Reports the document path changing from inside the shell (File menu
  /// New/Open/Save As), so the host's record stays true.
  final ValueChanged<String?>? onDocumentPathChanged;

  @override
  State<EditorShell> createState() => _EditorShellState();
}

class _EditorShellState extends State<EditorShell> with WidgetsBindingObserver {
  bool _paletteOpen = false;
  late String? _currentPath = widget.currentPath;
  // Whether a "source changed on disk" banner is currently shown, so a window
  // refocus does not stack duplicate banners.
  bool _changeBannerShown = false;

  late final DockLayout _dockLayout =
      DockLayout.tryParse(
        widget.dockLayoutJson,
        knownPanels: _panelIds,
        isDynamic: _extraViewportPattern.hasMatch,
      ) ??
      _defaultDockLayout();

  EditorController get _ctrl => widget.controller;

  /// Runtime-created viewports present anywhere in the layout, in stable
  /// (numeric) order.
  List<String> get _extraViewportIds => {
    ..._dockLayout.panelIds(),
    ..._dockLayout.floating,
    ..._dockLayout.hidden,
  }.where(_extraViewportPattern.hasMatch).toList()..sort();

  void _newViewport() {
    final existing = _extraViewportIds.toSet();
    var n = 2;
    while (existing.contains('viewport$n')) {
      n++;
    }
    final id = 'viewport$n';
    setState(() {
      // Split the group holding a docked viewport; when every viewport is
      // floating or hidden, fall back to the last group.
      DockTabs? anchor;
      for (final candidate in ['viewport', ...existing]) {
        anchor = _dockLayout.groupOf(candidate);
        if (anchor != null) break;
      }
      if (anchor != null) {
        _dockLayout.dock(id, anchor, DockZone.right);
      } else {
        _dockLayout.showPanel(id);
      }
    });
    widget.onDockLayoutChanged?.call(_dockLayout.toJsonString());
  }

  void _togglePanel(String id) {
    setState(() {
      if (_dockLayout.isVisible(id)) {
        _dockLayout.hidePanel(id);
      } else {
        _dockLayout.showPanel(id);
      }
    });
    widget.onDockLayoutChanged?.call(_dockLayout.toJsonString());
  }

  @override
  void initState() {
    super.initState();
    _ctrl.lastError.addListener(_showError);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-focusing the editor is a natural moment to notice a source model that
    // changed in another app.
    if (state == AppLifecycleState.resumed) _checkSourceChanges();
  }

  @override
  void didUpdateWidget(EditorShell old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.lastError.removeListener(_showError);
      _ctrl.lastError.addListener(_showError);
    }
    // The host is the path's source of truth (it can save/open externally,
    // over MCP for example).
    if (old.currentPath != widget.currentPath) {
      _currentPath = widget.currentPath;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ctrl.lastError.removeListener(_showError);
    super.dispose();
  }

  // Re-imports the linked glTF the single selected instance references, letting
  // the user adjust the recorded import settings first.
  Future<void> _reimportGlb() async {
    final ids = _ctrl.selection.ids;
    if (ids.length != 1) return;
    final record = linkedImportRecordFor(_ctrl, ids.first);
    if (record == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The selection is not a linked glTF.')),
      );
      return;
    }
    final options = await showGlbImportOptions(
      context,
      initial: record.toOptions(),
      showLinkToggle: false,
      title: 'Re-import glTF',
    );
    if (options == null || !mounted) return;
    try {
      await reimportLinkedModel(_ctrl, ids.first, options);
    } on IOException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Re-import failed: $e')));
      }
    }
  }

  // Checks linked imports for a source model that changed on disk and offers a
  // re-import.
  void _checkSourceChanges() {
    if (_changeBannerShown || !mounted) return;
    final changes = changedLinkedSources(_ctrl);
    if (changes.isEmpty) return;
    _changeBannerShown = true;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showMaterialBanner(
      MaterialBanner(
        content: Text(
          changes.length == 1
              ? 'A linked model changed on disk.'
              : '${changes.length} linked models changed on disk.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              messenger.hideCurrentMaterialBanner();
              _changeBannerShown = false;
              _reimportChanged(changes);
            },
            child: const Text('Re-import'),
          ),
          TextButton(
            onPressed: () {
              messenger.hideCurrentMaterialBanner();
              _changeBannerShown = false;
            },
            child: const Text('Dismiss'),
          ),
        ],
      ),
    );
  }

  Future<void> _reimportChanged(List<LinkedSourceChange> changes) async {
    for (final change in changes) {
      final record = linkedImportRecordFor(_ctrl, change.instanceId);
      if (record == null) continue;
      try {
        await reimportLinkedModel(_ctrl, change.instanceId, record.toOptions());
      } on IOException {
        // Skip a model that cannot be read; the others still refresh.
      }
    }
  }

  void _showError() {
    final message = _ctrl.lastError.value;
    if (message == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Command failed, $message'),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
    _ctrl.lastError.value = null;
  }

  /// Whether a text field currently has focus, so the global shortcuts can
  /// step aside and let it handle the key.
  bool _isEditingText() {
    final context = FocusManager.instance.primaryFocus?.context;
    return context != null &&
        context.findAncestorStateOfType<EditableTextState>() != null;
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.keyZ, meta: true): UndoIntent(),
        SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true):
            RedoIntent(),
        SingleActivator(LogicalKeyboardKey.delete): DeleteNodeIntent(),
        SingleActivator(LogicalKeyboardKey.backspace): DeleteNodeIntent(),
        SingleActivator(LogicalKeyboardKey.keyS, meta: true): SaveIntent(),
        SingleActivator(LogicalKeyboardKey.keyP, meta: true):
            CommandPaletteIntent(),
        SingleActivator(LogicalKeyboardKey.keyC, meta: true): CopyIntent(),
        SingleActivator(LogicalKeyboardKey.keyV, meta: true): PasteIntent(),
        SingleActivator(LogicalKeyboardKey.keyD, meta: true): DuplicateIntent(),
      },
      child: Actions(
        actions: {
          // Undo, redo, and delete disable themselves while a text field is
          // focused, so the key passes through to the field (Backspace edits
          // text, Cmd+Z undoes typing) instead of being swallowed.
          UndoIntent: _GuardedAction<UndoIntent>(
            () => !_isEditingText(),
            (_) => _ctrl.undo(),
          ),
          RedoIntent: _GuardedAction<RedoIntent>(
            () => !_isEditingText(),
            (_) => _ctrl.redo(),
          ),
          DeleteNodeIntent: _GuardedAction<DeleteNodeIntent>(
            () => !_isEditingText(),
            (_) => _deleteSelected(),
          ),
          // Copy/paste/duplicate also step aside while a text field is focused
          // so the keys edit text instead of the scene.
          CopyIntent: _GuardedAction<CopyIntent>(
            () => !_isEditingText(),
            (_) => _ctrl.copySelection(),
          ),
          PasteIntent: _GuardedAction<PasteIntent>(
            () => !_isEditingText(),
            (_) => _ctrl.paste(),
          ),
          DuplicateIntent: _GuardedAction<DuplicateIntent>(
            () => !_isEditingText(),
            (_) => _ctrl.duplicateSelection(),
          ),
          SaveIntent: CallbackAction<SaveIntent>(onInvoke: (_) => _save()),
          CommandPaletteIntent: CallbackAction<CommandPaletteIntent>(
            onInvoke: (_) => setState(() => _paletteOpen = true),
          ),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            body: Column(
              children: [
                _EditorMenuBar(
                  controller: _ctrl,
                  currentPath: _currentPath,
                  onNew: _newScene,
                  onOpen: _open,
                  onImportGlb: _importGlb,
                  onReimportGlb: _reimportGlb,
                  onSave: _save,
                  onSaveAs: _saveAs,
                  onUndo: _ctrl.undo,
                  onRedo: _ctrl.redo,
                  onDuplicate: _ctrl.duplicateSelection,
                  onCopy: _ctrl.copySelection,
                  onPaste: _ctrl.paste,
                  onDelete: _deleteSelected,
                  onAddCube: _addCube,
                  onAddSphere: _addSphere,
                  onAddPrefab: _addPrefabInstance,
                  onPaletteOpen: () => setState(() => _paletteOpen = true),
                  isPanelVisible: _dockLayout.isVisible,
                  onTogglePanel: _togglePanel,
                  onNewViewport: _newViewport,
                  leadingInset: widget.menuBarLeadingInset,
                  onDragStart: widget.onMenuBarDragStart,
                ),
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      DockingShell(
                        layout: _dockLayout,
                        onLayoutChanged: (layout) => widget.onDockLayoutChanged
                            ?.call(layout.toJsonString()),
                        panels: [
                          DockPanel(
                            id: 'viewport',
                            title: 'Viewport',
                            child: ViewportPanel(
                              controller: _ctrl,
                              repaintBoundaryKey:
                                  widget.viewportRepaintBoundaryKey,
                              cameraHandle: widget.viewportCameraHandle,
                            ),
                          ),
                          DockPanel(
                            id: 'outliner',
                            title: 'Outliner',
                            child: OutlinerPanel(controller: _ctrl),
                            actions: IconButton(
                              icon: const Icon(Icons.add, size: 16),
                              tooltip: 'Create node',
                              onPressed: () =>
                                  _ctrl.run('createNode', {'name': 'Node'}),
                            ),
                          ),
                          DockPanel(
                            id: 'inspector',
                            title: 'Inspector',
                            child: InspectorPanel(controller: _ctrl),
                          ),
                          DockPanel(
                            id: 'assets',
                            title: 'Assets',
                            child: AssetBrowserPanel(
                              controller: _ctrl,
                              onImportModel: _importModelFromBrowser,
                            ),
                          ),
                          DockPanel(
                            id: 'history',
                            title: 'History',
                            child: HistoryPanel(controller: _ctrl),
                          ),
                          for (final id in _extraViewportIds)
                            DockPanel(
                              id: id,
                              title: 'Viewport ${id.substring(8)}',
                              closable: true,
                              child: ViewportPanel(controller: _ctrl),
                            ),
                        ],
                      ),
                      if (_paletteOpen)
                        CommandPaletteOverlay(
                          controller: _ctrl,
                          onDismiss: () => setState(() => _paletteOpen = false),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Actions.
  // -------------------------------------------------------------------------

  void _setPath(String? path) {
    _currentPath = path;
    widget.onDocumentPathChanged?.call(path);
  }

  Future<void> _newScene() async {
    final ctrl = await EditorController.empty();
    widget.onControllerReplaced(ctrl);
    setState(() {
      _setPath(null);
      _paletteOpen = false;
    });
  }

  Future<void> _open() async {
    final path = await pickOpenPath();
    if (path == null) return;
    try {
      final ctrl = await openFscene(path);
      widget.onControllerReplaced(ctrl);
      setState(() {
        _setPath(path);
        _paletteOpen = false;
      });
    } on IOException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not open: $e')));
      }
    }
  }

  Future<void> _importGlb() async {
    final path = await pickModelPath();
    if (path == null || !mounted) return;
    await _importModelFromBrowser(path);
  }

  // Imports a glTF model at a known [path] (from the asset browser), showing the
  // same import-options dialog as the File menu's Import glTF.
  Future<void> _importModelFromBrowser(String path) async {
    if (!mounted) return;
    final options = await showGlbImportOptions(context);
    if (options == null || !mounted) return;
    // Graft under the selected node when exactly one is selected, else add to
    // the scene roots.
    final parentId = _ctrl.selection.ids.length == 1
        ? _ctrl.selection.ids.first
        : null;
    if (options.linkToSource && _ctrl.baseDirectory == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Save the scene before importing a linked asset, or turn off '
            '"Link to source".',
          ),
        ),
      );
      return;
    }
    try {
      if (options.linkToSource) {
        // Linked: write the model under imported/ and reference it as a prefab
        // instance, so it can be re-imported and edits survive as overrides.
        await importLinkedModel(_ctrl, path, options, parentId: parentId);
      } else {
        // Embedded: graft the model into the scene as one undoable edit.
        final document = await importModelDocument(
          path,
          compressTextures: options.compressTextures,
        );
        await _ctrl.importSceneIntoScene(
          document,
          parentId: parentId,
          scale: options.scale,
          upAxis: options.upAxis,
        );
      }
      setState(() => _paletteOpen = false);
    } on IOException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not import: $e')));
      }
    } on FormatException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not import: ${e.message}')),
        );
      }
    }
  }

  Future<void> _save() async {
    final path = _currentPath;
    if (path == null) {
      await _saveAs();
      return;
    }
    await _writeTo(path);
  }

  Future<void> _saveAs() async {
    final suggested = _currentPath == null
        ? 'scene.fscene'
        : _currentPath!.split(Platform.pathSeparator).last;
    final path = await pickSavePath(suggestedName: suggested);
    if (path == null) return;
    await _writeTo(path);
    if (mounted) setState(() => _setPath(path));
  }

  Future<void> _writeTo(String path) async {
    try {
      await saveFscene(_ctrl, path);
      // A new scene had no base directory; after saving it lives next to the
      // file, so relative references and the asset browser resolve from there.
      _ctrl.setBaseDirectory(File(path).parent.path);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved to $path'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } on IOException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Save failed: $e')));
      }
    }
  }

  Future<void> _deleteSelected() async {
    await _ctrl.deleteSelection();
  }

  // Adds a cube: creates geometry, material, node, and attaches a mesh
  // component in four commands, reading back new resource ids after each.
  Future<void> _addCube() async {
    await _addPrimitive('createCuboidGeometry');
  }

  Future<void> _addSphere() async {
    await _addPrimitive('createSphereGeometry');
  }

  // Adds a sub-scene as a prefab instance node. The source is stored relative
  // to the open scene's directory when possible (portable), absolute otherwise.
  Future<void> _addPrefabInstance() async {
    final path = await pickOpenPath();
    if (path == null) return;
    final base = _ctrl.baseDirectory;
    final source = (base != null && path.startsWith('$base/'))
        ? path.substring(base.length + 1)
        : path;
    final name = source
        .split(Platform.pathSeparator)
        .last
        .replaceAll('.fscene', '');
    try {
      final tx = await _ctrl.run('instantiatePrefab', {
        'prefabAsset': source,
        'name': name,
      });
      _ctrl.selection.selectOnly(tx.records.first.targetId);
    } catch (e) {
      // Realizing the instance failed (for example the prefab could not be
      // loaded). Roll the instance back so the scene stays consistent.
      if (_ctrl.history.canUndo) await _ctrl.undo();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not add prefab: $e')));
      }
    }
  }

  Future<void> _addPrimitive(String geoCommand) async {
    // Step 1: count resources before geometry creation.
    final beforeGeo = Set.of(_ctrl.document.resources.keys);
    await _ctrl.run(geoCommand);
    final geoId = _ctrl.document.resources.keys.firstWhere(
      (id) => !beforeGeo.contains(id),
    );

    // Step 2: create a physically-based material. Start half metallic and half
    // rough, a neutral look-dev default that reads better than the engine's
    // fully-rough non-metal.
    final beforeMat = Set.of(_ctrl.document.resources.keys);
    await _ctrl.run('createMaterial', {
      'type': 'physicallyBased',
      'properties': {'metallic': 0.5, 'roughness': 0.5},
    });
    final matId = _ctrl.document.resources.keys.firstWhere(
      (id) => !beforeMat.contains(id),
    );

    // Step 3: create a scene node.
    final beforeNodes = Set.of(_ctrl.document.nodes.keys);
    await _ctrl.run('createNode', {
      'name': geoCommand == 'createCuboidGeometry' ? 'Cube' : 'Sphere',
    });
    final nodeId = _ctrl.document.nodes.keys.firstWhere(
      (id) => !beforeNodes.contains(id),
    );

    // Step 4: attach a mesh component referencing both resources.
    await _ctrl.run('addComponent', {
      'nodeId': nodeId.toToken(),
      'componentType': 'mesh',
      'properties': {
        'geometry': {'\$resource': geoId.toToken()},
        'material': {'\$resource': matId.toToken()},
      },
    });

    // Select the new node.
    _ctrl.selection.selectOnly(nodeId);
  }
}

// ---------------------------------------------------------------------------
// Menu bar.
// ---------------------------------------------------------------------------

class _EditorMenuBar extends StatelessWidget {
  const _EditorMenuBar({
    required this.controller,
    required this.currentPath,
    required this.onNew,
    required this.onOpen,
    required this.onImportGlb,
    required this.onReimportGlb,
    required this.onSave,
    required this.onSaveAs,
    required this.onUndo,
    required this.onRedo,
    required this.onDuplicate,
    required this.onCopy,
    required this.onPaste,
    required this.onDelete,
    required this.onAddCube,
    required this.onAddSphere,
    required this.onAddPrefab,
    required this.onPaletteOpen,
    required this.isPanelVisible,
    required this.onTogglePanel,
    required this.onNewViewport,
    required this.leadingInset,
    this.onDragStart,
  });

  final EditorController controller;
  final String? currentPath;
  final VoidCallback onNew;
  final VoidCallback onOpen;
  final VoidCallback onImportGlb;
  final VoidCallback onReimportGlb;
  final VoidCallback onSave;
  final VoidCallback onSaveAs;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onDuplicate;
  final VoidCallback onCopy;
  final VoidCallback onPaste;
  final VoidCallback onDelete;
  final VoidCallback onAddCube;
  final VoidCallback onAddSphere;
  final VoidCallback onAddPrefab;
  final VoidCallback onPaletteOpen;
  final bool Function(String panelId) isPanelVisible;
  final ValueChanged<String> onTogglePanel;
  final VoidCallback onNewViewport;
  final double leadingInset;
  final VoidCallback? onDragStart;

  @override
  Widget build(BuildContext context) {
    // Re-import is offered when a single prefab instance is selected (a linked
    // glTF import). The handler confirms it is actually linked.
    final selected = controller.selection.ids;
    final canReimport =
        selected.length == 1 &&
        controller.document.nodes[selected.first]?.instance != null;
    // The pan handler makes the bar's empty space a window-drag region when
    // the host hides the native title bar; the buttons keep their own taps.
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: onDragStart == null ? null : (_) => onDragStart!(),
      child: Container(
        height: 28,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Row(
          children: [
            SizedBox(width: leadingInset),
            Text(
              currentPath != null
                  ? 'Scene Editor  (${currentPath!.split(Platform.pathSeparator).last})'
                  : 'Scene Editor',
              style: Theme.of(context).textTheme.labelSmall,
            ),
            const SizedBox(width: 16),
            _Menu(
              label: 'File',
              items: [
                _MenuItem(label: 'New', onTap: onNew),
                _MenuItem(label: 'Open…', onTap: onOpen),
                _MenuItem(label: 'Import glTF…', onTap: onImportGlb),
                _MenuItem(
                  label: 'Re-import glTF…',
                  onTap: canReimport ? onReimportGlb : null,
                ),
                _MenuItem(label: 'Save', onTap: onSave),
                _MenuItem(label: 'Save As…', onTap: onSaveAs),
              ],
            ),
            _Menu(
              label: 'Edit',
              items: [
                _MenuItem(
                  label: 'Undo',
                  onTap: controller.history.canUndo ? onUndo : null,
                ),
                _MenuItem(
                  label: 'Redo',
                  onTap: controller.history.canRedo ? onRedo : null,
                ),
                _MenuItem(
                  label: 'Duplicate',
                  onTap: controller.selection.isNotEmpty ? onDuplicate : null,
                ),
                _MenuItem(
                  label: 'Copy',
                  onTap: controller.selection.isNotEmpty ? onCopy : null,
                ),
                _MenuItem(
                  label: 'Paste',
                  onTap: controller.canPaste ? onPaste : null,
                ),
                _MenuItem(
                  label: 'Delete',
                  onTap: controller.selection.isNotEmpty ? onDelete : null,
                ),
              ],
            ),
            _Menu(
              label: 'Add',
              items: [
                _MenuItem(label: 'Cube', onTap: onAddCube),
                _MenuItem(label: 'Sphere', onTap: onAddSphere),
                _MenuItem(label: 'Prefab Instance…', onTap: onAddPrefab),
              ],
            ),
            // Built when the menu opens so the checkmarks reflect hides made
            // from tab context menus (which don't rebuild this bar).
            _Menu(
              label: 'View',
              itemsBuilder: () => [
                _MenuItem(label: 'New Viewport', onTap: onNewViewport),
                for (final entry in _panelTitles.entries)
                  _MenuItem(
                    label: entry.value,
                    checked: isPanelVisible(entry.key),
                    onTap: () => onTogglePanel(entry.key),
                  ),
              ],
            ),
            _MenuButton(label: 'Commands', onTap: onPaletteOpen),
          ],
        ),
      ),
    );
  }
}

class _MenuItem {
  const _MenuItem({required this.label, this.onTap, this.checked});
  final String label;
  final VoidCallback? onTap;

  /// Non-null renders a leading checkmark slot (checked or empty).
  final bool? checked;
}

class _Menu extends StatelessWidget {
  const _Menu({required this.label, this.items, this.itemsBuilder})
    : assert((items == null) != (itemsBuilder == null));

  final String label;
  final List<_MenuItem>? items;

  /// Deferred alternative to [items], invoked when the menu opens, for
  /// entries whose state can change without this bar rebuilding.
  final List<_MenuItem> Function()? itemsBuilder;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<VoidCallback?>(
      tooltip: '',
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(label, style: const TextStyle(fontSize: 11)),
      ),
      itemBuilder: (_) => [
        for (final item in items ?? itemsBuilder!())
          PopupMenuItem<VoidCallback?>(
            value: item.onTap,
            enabled: item.onTap != null,
            height: 28,
            child: Row(
              children: [
                if (item.checked != null)
                  SizedBox(
                    width: 20,
                    child: item.checked!
                        ? const Icon(Icons.check, size: 14)
                        : null,
                  ),
                Text(item.label, style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
      ],
      onSelected: (cb) => cb?.call(),
    );
  }
}

class _MenuButton extends StatelessWidget {
  const _MenuButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(0, 28),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: const TextStyle(fontSize: 11),
      ),
      child: Text(label),
    );
  }
}
