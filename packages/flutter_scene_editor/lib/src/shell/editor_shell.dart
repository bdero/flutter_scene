import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controller/editor_controller.dart';
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
  });

  final EditorController controller;

  /// Called when the user opens a new file or clears the scene; the parent
  /// should rebuild with the new controller.
  final void Function(EditorController newController) onControllerReplaced;

  @override
  State<EditorShell> createState() => _EditorShellState();
}

class _EditorShellState extends State<EditorShell> {
  bool _paletteOpen = false;
  String? _currentPath;

  EditorController get _ctrl => widget.controller;

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
                  onSave: _save,
                  onSaveAs: _saveAs,
                  onUndo: _ctrl.undo,
                  onRedo: _ctrl.redo,
                  onAddCube: _addCube,
                  onAddSphere: _addSphere,
                  onPaletteOpen: () => setState(() => _paletteOpen = true),
                ),
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      DockingShell(
                        viewportPane: ViewportPanel(controller: _ctrl),
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
    final primary = _ctrl.selection.primary;
    if (primary == null) return;
    await _ctrl.run('deleteNode', {'nodeId': primary.toToken()});
  }

  // Adds a cube: creates geometry, material, node, and attaches a mesh
  // component in four commands, reading back new resource ids after each.
  Future<void> _addCube() async {
    await _addPrimitive('createCuboidGeometry');
  }

  Future<void> _addSphere() async {
    await _addPrimitive('createSphereGeometry');
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
    required this.onSave,
    required this.onSaveAs,
    required this.onUndo,
    required this.onRedo,
    required this.onAddCube,
    required this.onAddSphere,
    required this.onPaletteOpen,
  });

  final EditorController controller;
  final String? currentPath;
  final VoidCallback onNew;
  final VoidCallback onOpen;
  final VoidCallback onSave;
  final VoidCallback onSaveAs;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onAddCube;
  final VoidCallback onAddSphere;
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
                ? 'flutter_scene Editor  (${currentPath!.split(Platform.pathSeparator).last})'
                : 'flutter_scene Editor',
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const SizedBox(width: 16),
          _Menu(
            label: 'File',
            items: [
              _MenuItem(label: 'New', onTap: onNew),
              _MenuItem(label: 'Open…', onTap: onOpen),
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
            ],
          ),
          _Menu(
            label: 'Add',
            items: [
              _MenuItem(label: 'Cube', onTap: onAddCube),
              _MenuItem(label: 'Sphere', onTap: onAddSphere),
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
