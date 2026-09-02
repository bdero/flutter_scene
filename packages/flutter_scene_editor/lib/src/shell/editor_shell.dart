import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_scene_codegen/flutter_scene_codegen.dart'
    show
        componentClassName,
        componentClassNameError,
        componentFileName,
        componentScriptSource,
        hookWithNativeComponents,
        nativeComponentBinding,
        nativeComponentHookCall,
        nativeComponentSource;
import 'package:flutter_scene/scene.dart'
    show Node, Scene, VfxCategory, vfxPresetsIn, writeGlb;
import 'package:forui/forui.dart';
import 'package:scene/scene.dart' show visualScriptComponentType;

import '../controller/editor_controller.dart';
import '../io/glb_import_options.dart';
import '../io/scene_io.dart';
import '../panels/asset_browser_panel.dart';
import '../panels/console_panel.dart';
import '../panels/history_panel.dart';
import '../panels/game_view_panel.dart';
import '../panels/inspector_panel.dart';
import '../panels/outliner_panel.dart';
import '../panels/render_graph_panel.dart';
import '../inspector/scene_settings_dialog.dart';
import '../inspector/vfx_editing.dart';
import '../render_graph/render_graph_inspector.dart';
import '../project/app_session.dart';
import '../project/project_runner.dart';
import '../viewport/component_gizmos.dart';
import '../viewport/viewport_camera_handle.dart';
import '../panels/animation_panel.dart';
import '../panels/visual_scripter_panel.dart';
import '../launcher/scene_templates.dart';
import '../viewport/transform_gizmo.dart';
import '../viewport/viewport_panel.dart';
import '../viewport/viewport_tools.dart';
import 'command_palette.dart';
import 'editor_menu.dart';
import 'editor_regions.dart';
import 'editor_status_bar.dart';
import 'editor_theme.dart';
import 'editor_top_strip.dart';
import 'panel_chrome.dart';
import 'tool_rail.dart';
import 'editor_dialog.dart';

/// A tool that takes the window rather than a corner of it.
///
/// Editing a blueprint, or reading a captured frame, is a mode you enter and
/// leave; a panel competing for room with a scene it is not about is worse at
/// both jobs.
enum EditorScreen {
  visualScripter('Visual Scripter'),
  renderGraph('Render Graph'),
  history('History');

  const EditorScreen(this.title);

  final String title;
}

/// Picks the gizmo's handle (W/E/R).
class ToolIntent extends Intent {
  const ToolIntent(this.mode);

  final GizmoMode mode;
}

/// Flips the gizmo between world and object space (X).
class ToggleSpaceIntent extends Intent {
  const ToggleSpaceIntent();
}

/// Leaves a full-screen editor (Esc).
class CloseScreenIntent extends Intent {
  const CloseScreenIntent();
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
    this.workspaceJson,
    this.onWorkspaceChanged,
    this.windowControlsInset = 8,
    this.onWindowDragStart,
    this.currentPath,
    this.onDocumentPathChanged,
    this.recentScenePaths = const [],
    this.onRemoveRecentScene,
    this.onClearRecentScenes,
    this.onShowSettings,
    this.projectName,
    this.projectRootDirectory,
    this.onOpenProject,
    this.onNewProject,
    this.onCloseProject,
    this.recentProjectPaths = const [],
    this.onOpenRecentProject,
    this.onEditBuildConfigs,
    this.stripLeading = const [],
    this.stripTrailing = const [],
    this.projectRunner,
    this.appSession,
    this.onDocumentSaved,
    this.gizmoPreferences,
  });

  final EditorController controller;

  /// Opens the host's settings window (Flutter installations, ...); null
  /// hides the menu item.
  final VoidCallback? onShowSettings;

  /// The open project's display name, or null with no project open.
  final String? projectName;

  /// The open project's resolved root directory; scopes the asset browser to
  /// the whole project instead of the open scene's directory.
  final String? projectRootDirectory;

  /// Project lifecycle actions; null hides the corresponding menu items.
  final VoidCallback? onOpenProject;
  final VoidCallback? onNewProject;
  final VoidCallback? onCloseProject;
  final List<String> recentProjectPaths;
  final ValueChanged<String>? onOpenRecentProject;

  /// Opens the open project's build configuration editor; null when no
  /// project is open.
  final VoidCallback? onEditBuildConfigs;

  /// The top strip's left cluster, after the project menu: what is being
  /// built, and for what.
  final List<Widget> stripLeading;

  /// The top strip's right cluster, after the viewport's own controls: the
  /// transport, and what a running session turns it into.
  final List<Widget> stripTrailing;

  /// The host's task subprocess owner; non-null adds the Console panel.
  final ProjectRunner? projectRunner;

  /// The host's Play session, shown in the Console panel's controls.
  final AppSession? appSession;

  /// Called after the document is written to disk (Save and Save As), with
  /// the saved path. Hosts hook save-triggered behavior here (for example
  /// hot-restarting the running session).
  final ValueChanged<String>? onDocumentSaved;

  /// Called when the user opens a new file or clears the scene; the parent
  /// should rebuild with the new controller.
  final void Function(EditorController newController) onControllerReplaced;

  /// Optional key on the viewport's [RepaintBoundary], so a host can capture
  /// the rendered viewport (the MCP `screenshot_viewport` perception tool).
  final GlobalKey? viewportRepaintBoundaryKey;

  /// Optional remote control attached to the primary viewport's camera (the
  /// MCP camera tools).
  final ViewportCameraHandle? viewportCameraHandle;

  /// Shared component-gizmo visibility preferences, forwarded to every
  /// viewport; the host persists them with the editor settings. Null gives
  /// each viewport an unpersisted default.
  final GizmoPreferences? gizmoPreferences;

  /// Region sizes and collapse state previously emitted through
  /// [onWorkspaceChanged]. Anything unreadable -- including a dock layout
  /// saved before the regions landed -- starts from the defaults.
  final String? workspaceJson;

  /// Reports the workspace whenever a region settles at a new size or is
  /// collapsed, so the host can persist it. Not called per drag frame.
  final ValueChanged<String>? onWorkspaceChanged;

  /// Space before the top strip's first item. Hosts that hide the native
  /// title bar set this to clear the window controls drawn over the content.
  final double windowControlsInset;

  /// Called when a drag starts on the top strip's empty middle. Hosts that
  /// hide the native title bar use it to move the window.
  final VoidCallback? onWindowDragStart;

  /// The document's file path (shown in the top strip, reused by Save), kept
  /// by the host. Null for an unsaved scene.
  final String? currentPath;

  /// Reports the document path changing from inside the shell (the project
  /// menu's New/Open/Save As), so the host's record stays true.
  final ValueChanged<String?>? onDocumentPathChanged;

  /// Most recently opened or saved scenes, newest first.
  final List<String> recentScenePaths;

  final ValueChanged<String>? onRemoveRecentScene;
  final VoidCallback? onClearRecentScenes;

  @override
  State<EditorShell> createState() => _EditorShellState();
}

class _EditorShellState extends State<EditorShell> with WidgetsBindingObserver {
  bool _paletteOpen = false;
  // Shared by the Render Graph panel across controller replacements; the
  // panel rebinds its scene each build.
  final RenderGraphInspector _renderGraphInspector = RenderGraphInspector();
  late String? _currentPath = widget.currentPath;
  final FileDialogHistory _dialogHistory = FileDialogHistory();
  // Whether a "source changed on disk" banner is currently shown, so a window
  // refocus does not stack duplicate banners.
  bool _changeBannerShown = false;

  /// Region sizes and collapse state. Per user, never in the project file.
  late final EditorWorkspace _workspace =
      EditorWorkspace.tryParse(widget.workspaceJson) ?? EditorWorkspace();

  /// Which handle the gizmo shows, and in what frame. Held here rather than in
  /// the viewport so the rail and every scene view agree on it.
  final ViewportToolState _tools = ViewportToolState();

  ViewportMode _mode = ViewportMode.scene;
  EditorScreen? _screen;

  /// Whether the viewport is alone, and what to put back when it is not.
  bool _viewportFocused = false;
  (bool, bool, bool) _restoreRegions = (true, true, true);

  EditorController get _ctrl => widget.controller;

  String? get _sceneDialogDirectory => _currentPath == null
      ? _ctrl.baseDirectory
      : File(_currentPath!).parent.path;

  // Shows what the .fmat compiler resolved to (which impellerc, where the
  // framework shaders came from, the packaged Flutter revision), or why it
  // could not resolve. The library resolves lazily, so before any fmat has
  // loaded there is nothing to report yet.
  void _showToolchain() {
    final library = _ctrl.fmatLibrary;
    final toolchain = library.toolchain;
    final message =
        toolchain?.describe() ??
        library.toolchainError ??
        'Not resolved yet; the toolchain resolves on the first .fmat load.';
    showEditorDialog<void>(
      context,
      builder: (context) => AlertDialog(
        title: const Text('Shader toolchain', style: editorDialogTitleText),
        content: SelectableText(
          message,
          style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  /// Writes a new annotated component into the project and opens it.
  ///
  /// The host already watches `lib/` and regenerates codecs on save, so the
  /// file appearing is the whole gesture: the type shows up in Add Component
  /// with a generated inspector without anything else being run.
  Future<void> _newComponentScript() async {
    final root = widget.projectRootDirectory;
    if (root == null) return;

    final typed = await _promptForComponentName();
    if (typed == null || !mounted) return;

    final className = componentClassName(typed);
    final directory = Directory('$root/lib/components');
    final file = File('${directory.path}/${componentFileName(className)}');

    if (file.existsSync()) {
      _report('${file.path.substring(root.length + 1)} already exists.');
      // Opening it is more useful than refusing outright: the name they typed
      // is almost certainly the component they meant to go back to.
      _ctrl.sourceFileOpener?.call(file.path);
      return;
    }

    try {
      directory.createSync(recursive: true);
      file.writeAsStringSync(componentScriptSource(className));
    } on FileSystemException catch (e) {
      _report('Could not write the script, ${e.message}');
      return;
    }

    _report('Created ${file.path.substring(root.length + 1)}');
    _ctrl.sourceFileOpener?.call(file.path);
  }

  /// Writes a native component: the C++ that does the work, the Dart
  /// component that owns it, and the build-hook line that compiles them.
  ///
  /// All three at once, because any one alone is broken. The C++ without the
  /// hook never compiles; the Dart without the C++ throws at the symbol
  /// lookup; the hook without either does nothing.
  Future<void> _newNativeComponentScript() async {
    final root = widget.projectRootDirectory;
    if (root == null) return;

    final typed = await _promptForComponentName(native: true);
    if (typed == null || !mounted) return;

    final className = componentClassName(typed);
    final fileName = componentFileName(className);
    final dartFile = File('$root/lib/components/$fileName');
    final nativeFile = File(
      '$root/native/${fileName.replaceAll('.dart', '.cpp')}',
    );

    if (dartFile.existsSync() || nativeFile.existsSync()) {
      _report('$className already exists.');
      _ctrl.sourceFileOpener?.call(
        dartFile.existsSync() ? dartFile.path : nativeFile.path,
      );
      return;
    }

    try {
      Directory('$root/lib/components').createSync(recursive: true);
      Directory('$root/native').createSync(recursive: true);
      nativeFile.writeAsStringSync(nativeComponentSource(className));
      dartFile.writeAsStringSync(nativeComponentBinding(className));
    } on FileSystemException catch (e) {
      _report('Could not write the component, ${e.message}');
      return;
    }

    _wireNativeBuildHook(root);
    _report('Created $className. Rebuild to compile its native half.');
    // The C++ first: it is the half being written, and the Dart wrapper is
    // mostly already correct.
    _ctrl.sourceFileOpener?.call(nativeFile.path);
  }

  /// Adds the native build step to the project's hook, or says what to add
  /// when the hook is not the shape it expects.
  void _wireNativeBuildHook(String root) {
    final hook = File('$root/hook/build.dart');
    if (!hook.existsSync()) {
      _report('No hook/build.dart; add $nativeComponentHookCall to one.');
      return;
    }
    final updated = hookWithNativeComponents(hook.readAsStringSync());
    // Null means it is already wired, or the hook is hand-written enough that
    // guessing where the line goes would be worse than asking.
    if (updated == null) return;
    try {
      hook.writeAsStringSync(updated);
    } on FileSystemException {
      _report('Add this to hook/build.dart: $nativeComponentHookCall');
    }
  }

  void _report(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Asks for a component name, re-prompting while the name would not compile.
  Future<String?> _promptForComponentName({bool native = false}) async {
    final controller = TextEditingController();
    String? error;
    return showEditorFDialog<String>(
      context: context,
      builder: (context, style, animation) => StatefulBuilder(
        builder: (context, setLocal) {
          void submit() {
            final value = controller.text.trim();
            final problem = componentClassNameError(value);
            if (problem != null) {
              setLocal(() => error = problem);
              return;
            }
            Navigator.pop(context, value);
          }

          return FDialog(
            animation: animation,
            builder: (context, style) => Padding(
              padding: const EdgeInsets.all(18),
              child: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      native ? 'New Native Component' : 'New Component Script',
                      style: editorDialogTitleText,
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Written to lib/components and picked up on save.',
                      style: TextStyle(
                        fontSize: 12,
                        color: editorMutedTextColor,
                      ),
                    ),
                    const SizedBox(height: 14),
                    FTextField(
                      control: FTextFieldControl.managed(
                        controller: controller,
                      ),
                      autofocus: true,
                      hint: 'Component name (Spinner, HealthBar)',
                      onSubmit: (_) => submit(),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        error!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFFE08276),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        FButton(
                          variant: .outline,
                          size: .xs,
                          mainAxisSize: .min,
                          onPress: () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 8),
                        FButton(
                          size: .xs,
                          mainAxisSize: .min,
                          onPress: submit,
                          child: const Text('Create'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _ctrl.lastError.addListener(_showError);
    // The Render Graph panel and viewport debug modes need the engine's
    // capture hooks; opting in editor-wide keeps shipping apps unaffected.
    Scene.debugAllowRenderGraphCapture = true;
    WidgetsBinding.instance.addObserver(this);
    // The rail draws the tool state and the regions draw the workspace, so
    // both have to reach the shell's build.
    _tools.addListener(_onSharedStateChanged);
    _workspace.addListener(_onSharedStateChanged);
  }

  void _onSharedStateChanged() {
    if (mounted) setState(() {});
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
    _tools
      ..removeListener(_onSharedStateChanged)
      ..dispose();
    _workspace.removeListener(_onSharedStateChanged);
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
    final text = 'Command failed, $message';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: SelectableText(text),
        backgroundColor: Theme.of(context).colorScheme.error,
        // Errors stick around long enough to read and copy; Copy puts the
        // full text on the clipboard in one click.
        duration: const Duration(seconds: 10),
        showCloseIcon: true,
        action: SnackBarAction(
          label: 'Copy',
          onPressed: () => Clipboard.setData(ClipboardData(text: text)),
        ),
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
        // The tools the rail's tooltips promise.
        SingleActivator(LogicalKeyboardKey.keyW): ToolIntent(
          GizmoMode.translate,
        ),
        SingleActivator(LogicalKeyboardKey.keyE): ToolIntent(GizmoMode.rotate),
        SingleActivator(LogicalKeyboardKey.keyR): ToolIntent(GizmoMode.scale),
        SingleActivator(LogicalKeyboardKey.keyX): ToggleSpaceIntent(),
        SingleActivator(LogicalKeyboardKey.escape): CloseScreenIntent(),
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
          ToolIntent: _GuardedAction<ToolIntent>(
            () => !_isEditingText(),
            (intent) => _tools.mode = intent.mode,
          ),
          ToggleSpaceIntent: _GuardedAction<ToggleSpaceIntent>(
            () => !_isEditingText(),
            (_) => _tools.toggleSpace(),
          ),
          CloseScreenIntent: _GuardedAction<CloseScreenIntent>(
            () => !_isEditingText() && _screen != null,
            (_) => _closeScreen(),
          ),
          SaveIntent: CallbackAction<SaveIntent>(onInvoke: (_) => _save()),
          CommandPaletteIntent: CallbackAction<CommandPaletteIntent>(
            onInvoke: (_) => setState(() => _paletteOpen = true),
          ),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            body: Stack(
              fit: StackFit.expand,
              children: [
                if (_screen != null)
                  _buildScreen(_screen!)
                else
                  _buildRegions(),
                if (_paletteOpen)
                  CommandPaletteOverlay(
                    controller: _ctrl,
                    onDismiss: () => setState(() => _paletteOpen = false),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // The window.
  // -------------------------------------------------------------------------

  /// The four regions, the rail, and the line along the bottom.
  Widget _buildRegions() {
    // The window's top-left corner is the rail and the hierarchy's header
    // now. Where the host draws its own window controls over the content,
    // they land there, so that space is given up rather than drawn under.
    final inset = widget.windowControlsInset;
    return EditorRegions(
      workspace: _workspace,
      onWorkspaceChanged: _persistWorkspace,
      windowControlsInset: inset,
      rail: EditorToolRail(
        leading: inset > 0 ? const SizedBox.shrink() : _logo(),
        tools: EditorToolRail.transformTools(_tools),
        utility: _utilityRailItems(),
      ),
      hierarchy: EditorRegion(
        header: EditorPanelHeader(
          label: 'Hierarchy',
          leadingInset: (inset - editorRailWidth).clamp(0, double.infinity),
          actions: [
            EditorMenu(
              icon: Icons.add,
              tooltip: 'Add to the scene',
              trailingChevron: false,
              itemsBuilder: _addMenuItems,
            ),
            EditorPanelIconButton(
              icon: Icons.copy_all_outlined,
              tooltip: _ctrl.selection.isEmpty
                  ? 'Select something to duplicate it'
                  : 'Duplicate',
              onPressed: _ctrl.selection.isEmpty
                  ? null
                  : _ctrl.duplicateSelection,
            ),
            EditorPanelIconButton(
              icon: Icons.delete_outline,
              tooltip: _ctrl.selection.isEmpty
                  ? 'Select something to delete it'
                  : 'Delete',
              onPressed: _ctrl.selection.isEmpty ? null : _deleteSelected,
            ),
          ],
          onCollapse: () => _toggleRegion(_workspace.toggleHierarchy),
          collapseTooltip: 'Hide the hierarchy',
        ),
        body: OutlinerPanel(controller: _ctrl),
      ),
      topStrip: EditorTopStrip(
        title: _stripTitle(),
        projectMenuItems: _projectMenuItems,
        panelsMenuItems: _panelsMenuItems,
        mode: _mode,
        onModeChanged: (mode) => setState(() => _mode = mode),
        onSceneSettings: _showSceneSettings,
        onToggleFocus: _toggleViewportFocus,
        focused: _viewportFocused,
        leading: widget.stripLeading,
        trailing: widget.stripTrailing,
        onDragStart: widget.onWindowDragStart,
      ),
      viewport: switch (_mode) {
        ViewportMode.scene => ViewportPanel(
          controller: _ctrl,
          tools: _tools,
          repaintBoundaryKey: widget.viewportRepaintBoundaryKey,
          cameraHandle: widget.viewportCameraHandle,
          gizmoPreferences: widget.gizmoPreferences,
        ),
        ViewportMode.game => GameViewPanel(controller: _ctrl),
      },
      shelf: EditorRegion(
        header: EditorPanelHeader(
          label: _workspace.shelfMode.label,
          leading: _ShelfModes(
            mode: _workspace.shelfMode,
            onChanged: (mode) {
              setState(() => _workspace.showShelf(mode));
              _persistWorkspace();
            },
          ),
          onCollapse: () => _toggleRegion(_workspace.toggleShelf),
          collapsed: !_workspace.shelfOpen,
          collapseTooltip: _workspace.shelfOpen
              ? 'Hide the shelf'
              : 'Show the shelf',
        ),
        body: switch (_workspace.shelfMode) {
          ShelfMode.project => AssetBrowserPanel(
            controller: _ctrl,
            onImportModel: _importModelFromBrowser,
            projectRoot: widget.projectRootDirectory,
            onOpenScene: _openPath,
          ),
          ShelfMode.console =>
            widget.projectRunner == null
                ? const _ShelfEmpty(
                    'The console shows a build or a run. Open a project to get one.',
                  )
                : ConsolePanel(
                    runner: widget.projectRunner!,
                    session: widget.appSession,
                  ),
          ShelfMode.animation => AnimationPanel(controller: _ctrl),
        },
      ),
      inspector: EditorRegion(
        header: EditorPanelHeader(
          label: 'Inspector',
          onCollapse: () => _toggleRegion(_workspace.toggleInspector),
          collapseTooltip: 'Hide the inspector',
        ),
        body: InspectorPanel(controller: _ctrl),
      ),
      statusBar: EditorStatusBar(
        runner: widget.projectRunner,
        onOpenConsole: _openConsole,
      ),
    );
  }

  /// A screen: the rail and the thing you entered, and no scene behind it.
  ///
  /// Editing a blueprint or reading a frame's render graph is a mode you enter
  /// and leave -- you are working on the Door, not on the level with a Door in
  /// it -- so it takes the window rather than competing for a corner of it.
  Widget _buildScreen(EditorScreen screen) {
    return Row(
      children: [
        EditorToolRail(
          leading: _logo(),
          tools: const [],
          utility: _utilityRailItems(),
        ),
        Expanded(
          child: Column(
            children: [
              EditorPanelHeader(
                label: screen.title,
                actions: [
                  EditorPanelIconButton(
                    icon: Icons.close,
                    tooltip: 'Back to the scene  (Esc)',
                    onPressed: _closeScreen,
                  ),
                ],
              ),
              Expanded(
                child: EditorPanelBody(
                  child: switch (screen) {
                    EditorScreen.visualScripter => VisualScripterPanel(
                      controller: _ctrl,
                    ),
                    EditorScreen.renderGraph => RenderGraphPanel(
                      controller: _ctrl,
                      inspector: _renderGraphInspector,
                    ),
                    EditorScreen.history => HistoryPanel(controller: _ctrl),
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _logo() => Image.asset(
    'packages/flutter_scene_editor/assets/flutter_scene_logo.png',
    width: 18,
    height: 18,
    cacheWidth: 36,
  );

  List<EditorRailItem> _utilityRailItems() => [
    EditorRailItem(
      icon: Icons.search,
      tooltip: 'Commands',
      shortcut: 'Cmd+P',
      onPressed: () => setState(() => _paletteOpen = true),
    ),
    EditorRailItem(
      icon: Icons.memory_outlined,
      tooltip: 'Shader toolchain',
      onPressed: _showToolchain,
    ),
    EditorRailItem(
      icon: Icons.settings_outlined,
      tooltip: widget.onShowSettings == null
          ? 'Settings live in the host application'
          : 'Settings',
      onPressed: widget.onShowSettings,
    ),
  ];

  String _stripTitle() {
    final scene = _currentPath?.split(Platform.pathSeparator).last;
    final project = widget.projectName;
    if (project != null && scene != null) return '$project · $scene';
    return project ?? scene ?? 'Scene Editor';
  }

  void _toggleRegion(VoidCallback toggle) {
    setState(toggle);
    _persistWorkspace();
  }

  /// Collapses everything but the viewport, and puts it all back.
  ///
  /// What was open before is restored rather than everything being opened,
  /// because a toggle that gives you back a different window than it took is a
  /// toggle people press once.
  void _toggleViewportFocus() {
    setState(() {
      if (_viewportFocused) {
        _workspace
          ..hierarchyOpen = _restoreRegions.$1
          ..inspectorOpen = _restoreRegions.$2
          ..shelfOpen = _restoreRegions.$3;
        _viewportFocused = false;
      } else {
        _restoreRegions = (
          _workspace.hierarchyOpen,
          _workspace.inspectorOpen,
          _workspace.shelfOpen,
        );
        _workspace
          ..hierarchyOpen = false
          ..inspectorOpen = false
          ..shelfOpen = false;
        _viewportFocused = true;
      }
    });
    _persistWorkspace();
  }

  void _openScreen(EditorScreen screen) => setState(() => _screen = screen);

  void _closeScreen() => setState(() => _screen = null);

  void _persistWorkspace() =>
      widget.onWorkspaceChanged?.call(_workspace.toJsonString());

  /// Brings the Console up, which is what the status bar is a shortcut to.
  ///
  /// The shelf may be collapsed, or showing something else; either way this is
  /// one gesture. A status line you cannot click through to is a status line
  /// that tells you something happened and nothing about what.
  void _openConsole() {
    setState(() => _workspace.showShelf(ShelfMode.console));
    _persistWorkspace();
  }

  // -------------------------------------------------------------------------
  // The menus, at the places they act on.
  // -------------------------------------------------------------------------

  /// The project menu at the left of the top strip: what File used to be.
  List<EditorMenuItem> _projectMenuItems() {
    final selected = _ctrl.selection.ids;
    final canReimport =
        selected.length == 1 &&
        _ctrl.document.nodes[selected.first]?.instance != null;
    return [
      if (widget.onOpenProject != null) ...[
        EditorMenuItem(label: 'Open Project…', onTap: widget.onOpenProject),
        EditorMenuItem(label: 'New Project…', onTap: widget.onNewProject),
        EditorMenuItem(
          label: 'Open Recent Project',
          children: widget.recentProjectPaths.isEmpty
              ? const [EditorMenuItem(label: 'No Recent Projects')]
              : [
                  for (final path in widget.recentProjectPaths)
                    EditorMenuItem(
                      label: path.split(Platform.pathSeparator).last,
                      detail: File(path).parent.path,
                      onTap: () => widget.onOpenRecentProject?.call(path),
                    ),
                ],
        ),
        if (widget.projectName != null) ...[
          EditorMenuItem(
            label: 'Build Configurations…',
            onTap: widget.onEditBuildConfigs,
          ),
          EditorMenuItem(label: 'Close Project', onTap: widget.onCloseProject),
        ],
        const EditorMenuItem.divider(),
      ],
      EditorMenuItem(label: 'New Scene', onTap: _newScene),
      EditorMenuItem(label: 'Open Scene…', onTap: _open),
      EditorMenuItem(
        label: 'Open Recent Scene',
        children: widget.recentScenePaths.isEmpty
            ? const [EditorMenuItem(label: 'No Recent Scenes')]
            : [
                for (final path in widget.recentScenePaths)
                  EditorMenuItem(
                    label: path.split(Platform.pathSeparator).last,
                    detail: File(path).existsSync()
                        ? File(path).parent.path
                        : 'Missing  ${File(path).parent.path}',
                    onTap: () => _openPath(path),
                    removeTooltip: 'Remove from recent scenes',
                    onRemove: widget.onRemoveRecentScene == null
                        ? null
                        : () => widget.onRemoveRecentScene!(path),
                  ),
                const EditorMenuItem.divider(),
                EditorMenuItem(
                  label: 'Clear Recent Scenes',
                  onTap: widget.onClearRecentScenes,
                ),
              ],
      ),
      EditorMenuItem(label: 'Import glTF…', onTap: _importGlb),
      EditorMenuItem(
        label: 'Re-import glTF…',
        onTap: canReimport ? _reimportGlb : null,
      ),
      EditorMenuItem(label: 'Save', onTap: _save),
      EditorMenuItem(label: 'Save As…', onTap: _saveAs),
      EditorMenuItem(
        label: 'Export glTF…',
        onTap: _ctrl.realizedRoot == null ? null : _exportGlb,
      ),
      EditorMenuItem(
        label: 'Export Selection as glTF…',
        onTap: _ctrl.selection.ids.length == 1 ? _exportSelectionGlb : null,
      ),
      const EditorMenuItem.divider(),
      EditorMenuItem(label: 'Scene Settings…', onTap: _showSceneSettings),
      if (widget.onShowSettings != null)
        EditorMenuItem(label: 'Settings…', onTap: widget.onShowSettings),
    ];
  }

  /// The panels menu: the regions, the shelf's modes, and the screens.
  List<EditorMenuItem> _panelsMenuItems() => [
    EditorMenuItem(
      label: 'Hierarchy',
      checked: _workspace.hierarchyOpen,
      onTap: () => _toggleRegion(_workspace.toggleHierarchy),
    ),
    EditorMenuItem(
      label: 'Inspector',
      checked: _workspace.inspectorOpen,
      onTap: () => _toggleRegion(_workspace.toggleInspector),
    ),
    EditorMenuItem(
      label: 'Shelf',
      checked: _workspace.shelfOpen,
      onTap: () => _toggleRegion(_workspace.toggleShelf),
    ),
    const EditorMenuItem.divider(),
    for (final mode in ShelfMode.values)
      EditorMenuItem(
        label: mode.label,
        checked: _workspace.shelfOpen && _workspace.shelfMode == mode,
        onTap: () {
          setState(() => _workspace.showShelf(mode));
          _persistWorkspace();
        },
      ),
    const EditorMenuItem.divider(),
    for (final screen in EditorScreen.values)
      EditorMenuItem(label: screen.title, onTap: () => _openScreen(screen)),
    const EditorMenuItem.divider(),
    EditorMenuItem(label: 'Shader Toolchain…', onTap: _showToolchain),
  ];

  /// The add menu, on the hierarchy's header: what Add used to be.
  List<EditorMenuItem> _addMenuItems() => [
    EditorMenuItem(
      label: 'Empty Node',
      onTap: () => unawaited(_addEmptyNode()),
    ),
    EditorMenuItem(
      label: '3D Object',
      children: [
        for (final primitive in _EditorShellState.primitiveCommands)
          EditorMenuItem(
            label: primitive.label,
            onTap: () => _addPrimitiveByCommand(primitive.command),
          ),
        for (final group in const [
          'Camera',
          'Light',
          'Environment',
          'Effects',
          'Audio',
          'UI',
          'Volume',
          'Scripting',
        ])
          if (_EditorShellState.objectsIn(group).length == 1)
            EditorMenuItem(
              label: _EditorShellState.objectsIn(group).single.label,
              onTap: () =>
                  _addObject(_EditorShellState.objectsIn(group).single.type),
            )
          else
            EditorMenuItem(
              label: group,
              children: [
                for (final entry in _EditorShellState.objectsIn(group))
                  EditorMenuItem(
                    label: entry.label,
                    onTap: () => _addObject(entry.type),
                  ),
              ],
            ),
      ],
    ),
    EditorMenuItem(
      label: 'VFX',
      children: [
        EditorMenuItem(label: 'Browse Effects…', onTap: _browseVfx),
        const EditorMenuItem.divider(),
        for (final category in VfxCategory.values)
          EditorMenuItem(
            label: category.label,
            children: [
              for (final preset in vfxPresetsIn(category))
                EditorMenuItem(
                  label: preset.name,
                  detail: preset.description,
                  onTap: () => unawaited(addVfxPreset(_ctrl, preset)),
                ),
            ],
          ),
        const EditorMenuItem.divider(),
        EditorMenuItem(
          label: 'Empty Emitter',
          onTap: () => _addObject('particleEmitter'),
        ),
      ],
    ),
    EditorMenuItem(label: 'Prefab Instance…', onTap: _addPrefabInstance),
    EditorMenuItem(
      label: 'Component Script…',
      onTap: widget.projectRootDirectory == null ? null : _newComponentScript,
    ),
    EditorMenuItem(
      label: 'Native Component…',
      onTap: widget.projectRootDirectory == null
          ? null
          : () => unawaited(_newNativeComponentScript()),
    ),
  ];

  void _addObject(String type) {
    final entry = componentObjects.firstWhere(
      (candidate) => candidate.type == type,
    );
    unawaited(_addComponentObject(entry.type, entry.label));
  }

  // -------------------------------------------------------------------------
  // Actions.
  // -------------------------------------------------------------------------

  void _setPath(String? path) {
    _currentPath = path;
    widget.onDocumentPathChanged?.call(path);
  }

  /// Surfaces an export problem on the one channel the editor already has.
  void _reportExport(String message) => _ctrl.lastError.value = message;

  /// Writes the open scene out as a binary glTF.
  ///
  /// The document's own nodes, not the scene's: the editor's grid and gizmo
  /// helpers live in the same scene graph and are nobody's model.
  Future<void> _exportGlb() async {
    final root = _ctrl.realizedRoot;
    if (root == null) return;
    await _exportNode(
      root,
      suggested: _currentPath == null
          ? 'scene'
          : _currentPath!.split(Platform.pathSeparator).last.split('.').first,
    );
  }

  /// Writes the single selected node and its descendants.
  Future<void> _exportSelectionGlb() async {
    final id = _ctrl.selection.ids.single;
    final node = _ctrl.liveNode(id);
    if (node == null) {
      _reportExport(
        'That node is not realized yet, so it cannot be '
        'exported. Let the scene finish loading and try again.',
      );
      return;
    }
    await _exportNode(node, suggested: node.name.isEmpty ? 'node' : node.name);
  }

  Future<void> _exportNode(Node node, {required String suggested}) async {
    final path = await pickGlbSavePath(
      suggestedName: suggested,
      initialDirectory: _sceneDialogDirectory,
    );
    if (path == null) return;
    final warnings = <String>[];
    try {
      final bytes = writeGlb(node, onWarning: warnings.add);
      await File(path).writeAsBytes(bytes);
    } on Object catch (error) {
      _reportExport('Could not write $path: $error');
      return;
    }
    // Whatever could not be written is said out loud rather than discovered
    // when the file is opened somewhere else.
    for (final warning in warnings) {
      _reportExport(warning);
    }
  }

  void _showSceneSettings() =>
      unawaited(showSceneSettings(context, controller: _ctrl));

  /// Opens the effect catalogue, and adds what it returns.
  Future<void> _browseVfx() async {
    final preset = await showVfxBrowser(
      context,
      title: 'Add Effect',
      action: 'Add',
    );
    if (preset == null || !mounted) return;
    await addVfxPreset(_ctrl, preset);
  }

  Future<void> _newScene() async {
    // Asked rather than assumed: an empty scene is a sky and nothing else,
    // and starting there means building the same floor and the same key
    // light before any of the work that is actually this scene's.
    final template = await pickSceneTemplate(context);
    if (template == null || !mounted) return;
    final ctrl = await EditorController.empty(document: template.build());
    widget.onControllerReplaced(ctrl);
    setState(() {
      _setPath(null);
      _paletteOpen = false;
    });
  }

  Future<void> _open() async {
    final path = await pickOpenPath(initialDirectory: _sceneDialogDirectory);
    if (path == null) return;
    await _openPath(path);
  }

  Future<void> _openPath(String path) async {
    try {
      final ctrl = await openFscene(path);
      widget.onControllerReplaced(ctrl);
      setState(() {
        _setPath(path);
        _paletteOpen = false;
      });
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not open: $e')));
      }
    }
  }

  Future<void> _importGlb() async {
    final path = await pickModelPath(initialDirectory: _sceneDialogDirectory);
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
    final saved = await _writeTo(path);
    if (saved) _setPath(path);
  }

  Future<void> _saveAs() async {
    final suggested = _currentPath == null
        ? 'scene.fscene'
        : _currentPath!.split(Platform.pathSeparator).last;
    final path = await pickSavePath(
      suggestedName: suggested,
      initialDirectory: _sceneDialogDirectory,
    );
    if (path == null) return;
    final saved = await _writeTo(path);
    if (saved && mounted) setState(() => _setPath(path));
  }

  Future<bool> _writeTo(String path) async {
    try {
      await saveFscene(_ctrl, path);
      // A new scene had no base directory; after saving it lives next to the
      // file, so relative references and the asset browser resolve from there.
      _ctrl.setBaseDirectory(File(path).parent.path);
      widget.onDocumentSaved?.call(path);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved to $path'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
      return true;
    } on IOException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Save failed: $e')));
      }
      return false;
    }
  }

  Future<void> _deleteSelected() async {
    await _ctrl.deleteSelection();
  }

  // Adds a blank node, selected and revealed in the outliner.
  Future<void> _addEmptyNode() async {
    final beforeNodes = Set.of(_ctrl.document.nodes.keys);
    await _ctrl.run('createNode', {'name': 'Node'});
    final nodeId = _ctrl.document.nodes.keys.firstWhere(
      (id) => !beforeNodes.contains(id),
    );
    _ctrl.selection.selectOnly(nodeId);
    _ctrl.revealInOutliner(nodeId);
  }

  // Adds a cube: creates geometry, material, node, and attaches a mesh
  // component in four commands, reading back new resource ids after each.
  // The primitives the engine can build, in the order they appear in the
  // menu: the ones a level is blocked out with first.
  static const primitiveCommands = <({String label, String command})>[
    (label: 'Cube', command: 'createCuboidGeometry'),
    (label: 'Sphere', command: 'createSphereGeometry'),
    (label: 'Plane', command: 'createPlaneGeometry'),
    (label: 'Cylinder', command: 'createCylinderGeometry'),
    (label: 'Capsule', command: 'createCapsuleGeometry'),
    (label: 'Wedge', command: 'createWedgeGeometry'),
    (label: 'Disc', command: 'createDiscGeometry'),
    (label: 'Torus', command: 'createTorusGeometry'),
    (label: 'Icosphere', command: 'createIcosphereGeometry'),
    // Terrain is its own object, the way it is everywhere else. A plane can
    // still become one by being sculpted, but that route only works if you
    // already know it exists -- which is why nobody found the terrain tools.
    (label: 'Terrain', command: 'createTerrainGeometry'),
  ];

  // Adds a sub-scene as a prefab instance node. The source is stored relative
  // to the open scene's directory when possible (portable), absolute otherwise.
  Future<void> _addPrefabInstance() async {
    final path = await pickOpenPath(
      initialDirectory: _dialogHistory.prefabInitialDirectory(
        _sceneDialogDirectory,
      ),
    );
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
      _dialogHistory.rememberPrefab(path);
      final instanceId = tx.records.first.targetId;
      _ctrl.selection.selectOnly(instanceId);
      _ctrl.revealInOutliner(instanceId);
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

  void _addPrimitiveByCommand(String command) {
    final primitive = primitiveCommands.firstWhere(
      (entry) => entry.command == command,
    );
    unawaited(_addPrimitive(primitive.command, primitive.label));
  }

  /// Scene objects that are a node plus one component, grouped the way the
  /// Add menu shows them. A primitive needs geometry and a material built
  /// first; these do not, so they share one two-command path.
  static const componentObjects = <({String group, String label, String type})>[
    (group: 'Camera', label: 'Camera', type: 'camera'),
    (group: 'Light', label: 'Directional Light', type: 'directionalLight'),
    (group: 'Light', label: 'Point Light', type: 'pointLight'),
    (group: 'Light', label: 'Spot Light', type: 'spotLight'),
    (group: 'Light', label: 'Area Light', type: 'rectAreaLight'),
    (group: 'Effects', label: 'Trail', type: 'trail'),
    (group: 'Audio', label: 'Audio Source', type: 'audioSource'),
    (group: 'Audio', label: 'Audio Listener', type: 'audioListener'),
    (group: 'Environment', label: 'Water', type: 'water'),
    (group: 'Environment', label: 'Lightning', type: 'lightning'),
    (
      group: 'Scripting',
      label: 'Visual Script',
      type: visualScriptComponentType,
    ),
    // A canvas is the root of a UI layout: everything under it positions
    // itself against its rectangle. Adding a rect on its own is done from
    // Add Component, since it only means something beneath a canvas.
    (group: 'UI', label: 'Canvas', type: 'canvas'),
    (group: 'Volume', label: 'Environment Volume', type: 'environmentVolume'),
    (group: 'Volume', label: 'Irradiance Volume', type: 'irradianceVolume'),
    (group: 'Volume', label: 'Reflection Probe', type: 'reflectionProbe'),
  ];

  /// The [componentObjects] in one group, in declaration order.
  static Iterable<({String group, String label, String type})> objectsIn(
    String group,
  ) => componentObjects.where((entry) => entry.group == group);

  /// Creates an empty node, the parent everything else gets grouped under.

  /// Creates a node carrying one component, named for what it is.
  Future<void> _addComponentObject(String componentType, String label) async {
    final before = Set.of(_ctrl.document.nodes.keys);
    await _ctrl.run('createNode', {'name': label});
    final nodeId = _ctrl.document.nodes.keys.firstWhere(
      (id) => !before.contains(id),
    );
    await _ctrl.run('addComponent', {
      'nodeId': nodeId.toToken(),
      'componentType': componentType,
    });
    _ctrl.selection.selectOnly(nodeId);
  }

  Future<void> _addPrimitive(String geoCommand, String nodeName) async {
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
    await _ctrl.run('createNode', {'name': nodeName});
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

    // Select the new node and bring its outliner row into view.
    _ctrl.selection.selectOnly(nodeId);
    _ctrl.revealInOutliner(nodeId);
  }
}

/// The shelf's mode picker: three modes, one visible at a time.
///
/// Not a tab strip. A tab strip says these are three panels docked in one
/// place and could be docked elsewhere; this says the shelf is one place with
/// three things it can be showing.
class _ShelfModes extends StatelessWidget {
  const _ShelfModes({required this.mode, required this.onChanged});

  final ShelfMode mode;
  final ValueChanged<ShelfMode> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final option in ShelfMode.values)
        EditorPanelIconButton(
          icon: option.icon,
          tooltip: option.label,
          selected: option == mode,
          onPressed: () => onChanged(option),
        ),
    ],
  );
}

/// What a shelf mode shows when there is nothing behind it yet.
class _ShelfEmpty extends StatelessWidget {
  const _ShelfEmpty(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: editorDetailText,
      ),
    ),
  );
}
