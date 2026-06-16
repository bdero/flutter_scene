import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controller/editor_controller.dart';
import '../io/glb_import_options.dart';
import '../io/scene_io.dart';
import '../panels/history_panel.dart';
import '../panels/inspector_panel.dart';
import '../panels/outliner_panel.dart';
import '../viewport/viewport_panel.dart';
import 'command_palette.dart';
import 'docking_shell.dart';

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
  });

  final EditorController controller;

  /// Called when the user opens a new file or clears the scene; the parent
  /// should rebuild with the new controller.
  final void Function(EditorController newController) onControllerReplaced;

  /// Optional key on the viewport's [RepaintBoundary], so a host can capture
  /// the rendered viewport (the MCP `screenshot_viewport` perception tool).
  final GlobalKey? viewportRepaintBoundaryKey;

  @override
  State<EditorShell> createState() => _EditorShellState();
}

class _EditorShellState extends State<EditorShell> {
  bool _paletteOpen = false;
  String? _currentPath;

  EditorController get _ctrl => widget.controller;

  @override
  void initState() {
    super.initState();
    _ctrl.lastError.addListener(_showError);
  }

  @override
  void didUpdateWidget(EditorShell old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.lastError.removeListener(_showError);
      _ctrl.lastError.addListener(_showError);
    }
  }

  @override
  void dispose() {
    _ctrl.lastError.removeListener(_showError);
    super.dispose();
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
                ),
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      DockingShell(
                        viewportPane: ViewportPanel(
                          controller: _ctrl,
                          repaintBoundaryKey: widget.viewportRepaintBoundaryKey,
                        ),
                        outlinerPane: OutlinerPanel(controller: _ctrl),
                        inspectorPane: InspectorPanel(controller: _ctrl),
                        historyPane: HistoryPanel(controller: _ctrl),
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

  Future<void> _newScene() async {
    final ctrl = await EditorController.empty();
    widget.onControllerReplaced(ctrl);
    setState(() {
      _currentPath = null;
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
        _currentPath = path;
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
    final options = await showGlbImportOptions(context);
    if (options == null) return;
    try {
      // Graft under the selected node when exactly one is selected, else add
      // to the scene roots. Lands as one undoable edit.
      final parentId = _ctrl.selection.ids.length == 1
          ? _ctrl.selection.ids.first
          : null;
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
    if (mounted) setState(() => _currentPath = path);
  }

  Future<void> _writeTo(String path) async {
    try {
      await saveFscene(_ctrl, path);
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

    // Step 2: create a physically-based material.
    final beforeMat = Set.of(_ctrl.document.resources.keys);
    await _ctrl.run('createMaterial', {'type': 'physicallyBased'});
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
  });

  final EditorController controller;
  final String? currentPath;
  final VoidCallback onNew;
  final VoidCallback onOpen;
  final VoidCallback onImportGlb;
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

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          const SizedBox(width: 8),
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
          _MenuButton(label: 'Commands', onTap: onPaletteOpen),
        ],
      ),
    );
  }
}

class _MenuItem {
  const _MenuItem({required this.label, this.onTap});
  final String label;
  final VoidCallback? onTap;
}

class _Menu extends StatelessWidget {
  const _Menu({required this.label, required this.items});
  final String label;
  final List<_MenuItem> items;

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
        for (final item in items)
          PopupMenuItem<VoidCallback?>(
            value: item.onTap,
            enabled: item.onTap != null,
            height: 28,
            child: Text(item.label, style: const TextStyle(fontSize: 12)),
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
