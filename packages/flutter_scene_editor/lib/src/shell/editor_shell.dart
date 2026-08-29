import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_scene/scene.dart' show Scene;
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
import 'package:forui/forui.dart';

import '../controller/editor_controller.dart';
import '../io/glb_import_options.dart';
import '../io/scene_io.dart';
import '../panels/asset_browser_panel.dart';
import '../panels/console_panel.dart';
import '../panels/history_panel.dart';
import '../panels/inspector_panel.dart';
import '../panels/outliner_panel.dart';
import '../panels/render_graph_panel.dart';
import '../inspector/scene_settings_dialog.dart';
import '../render_graph/render_graph_inspector.dart';
import '../project/app_session.dart';
import '../project/project_runner.dart';
import '../viewport/component_gizmos.dart';
import '../viewport/viewport_camera_handle.dart';
import '../panels/animation_panel.dart';
import '../panels/flow_panel.dart';
import '../launcher/scene_templates.dart';
import '../panels/vfx_panel.dart';
import '../viewport/viewport_panel.dart';
import 'command_palette.dart';
import 'dock_layout.dart';
import 'docking_shell.dart';
import 'editor_theme.dart';
import 'editor_dialog.dart';

/// The panels [EditorShell] registers with its [DockingShell], id to the
/// title shown on tabs and in the View menu.
const Map<String, String> _panelTitles = {
  'viewport': 'Viewport',
  'animation': 'Animation',
  'effects': 'Effects',
  'flow': 'Flow',
  'outliner': 'Outliner',
  'inspector': 'Inspector',
  'assets': 'Assets',
  'history': 'History',
  'console': 'Console',
  'render_graph': 'Render Graph',
};

List<String> get _panelIds => _panelTitles.keys.toList();

/// Extra viewports are created at runtime with ids like `viewport2` and are
/// admitted through layout persistence as dynamic panels.
final RegExp _extraViewportPattern = RegExp(r'^viewport\d+$');

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
    this.recentScenePaths = const [],
    this.onRemoveRecentScene,
    this.onClearRecentScenes,
    this.namedLayouts = const {},
    this.onSaveNamedLayout,
    this.onDeleteNamedLayout,
    this.onShowSettings,
    this.projectName,
    this.projectRootDirectory,
    this.onOpenProject,
    this.onNewProject,
    this.onCloseProject,
    this.recentProjectPaths = const [],
    this.onOpenRecentProject,
    this.onEditBuildConfigs,
    this.trailing = const [],
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

  /// Host widgets appended to the menu bar's right side (toolchain and build
  /// controls).
  final List<Widget> trailing;

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

  /// Most recently opened or saved scenes, newest first.
  final List<String> recentScenePaths;

  final ValueChanged<String>? onRemoveRecentScene;
  final VoidCallback? onClearRecentScenes;

  /// User-named dock layout snapshots.
  final Map<String, String> namedLayouts;

  final void Function(String name, String layout)? onSaveNamedLayout;
  final ValueChanged<String>? onDeleteNamedLayout;

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

  late DockLayout _dockLayout =
      DockLayout.tryParse(
        widget.dockLayoutJson,
        knownPanels: _panelIds,
        isDynamic: _extraViewportPattern.hasMatch,
      ) ??
      defaultEditorDockLayout();

  EditorController get _ctrl => widget.controller;

  String? get _sceneDialogDirectory => _currentPath == null
      ? _ctrl.baseDirectory
      : File(_currentPath!).parent.path;

  /// Runtime-created viewports present anywhere in the layout, in stable
  /// (numeric) order.
  List<String> get _extraViewportIds => {
    ..._dockLayout.panelIds(),
    ..._dockLayout.floating,
    ..._dockLayout.hidden,
  }.where(_extraViewportPattern.hasMatch).toList()..sort();

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

  void _applyDockLayout(String? source) {
    final replacement = source == null
        ? defaultEditorDockLayout()
        : DockLayout.tryParse(
                source,
                knownPanels: _panelIds,
                isDynamic: _extraViewportPattern.hasMatch,
              ) ??
              defaultEditorDockLayout();
    setState(() => _dockLayout = replacement);
    widget.onDockLayoutChanged?.call(replacement.toJsonString());
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

  Future<void> _saveCurrentLayoutAs() async {
    final controller = TextEditingController();
    final name = await showEditorFDialog<String>(
      context: context,
      builder: (context, style, animation) => FDialog(
        animation: animation,
        builder: (context, style) => Padding(
          padding: const EdgeInsets.all(18),
          child: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Save Layout', style: editorDialogTitleText),
                const SizedBox(height: 14),
                FTextField(
                  control: FTextFieldControl.managed(controller: controller),
                  autofocus: true,
                  hint: 'Layout name',
                  onSubmit: (_) {
                    final value = controller.text.trim();
                    if (value.isNotEmpty) Navigator.pop(context, value);
                  },
                ),
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
                      onPress: () {
                        final value = controller.text.trim();
                        if (value.isNotEmpty) Navigator.pop(context, value);
                      },
                      child: const Text('Save'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    controller.dispose();
    if (name == null || !mounted) return;
    final existing = widget.namedLayouts.keys.cast<String?>().firstWhere(
      (candidate) => candidate!.toLowerCase() == name.toLowerCase(),
      orElse: () => null,
    );
    if (existing != null) {
      final overwrite = await _confirmLayoutOverwrite(existing);
      if (!overwrite || !mounted) return;
    }
    widget.onSaveNamedLayout?.call(name, _dockLayout.toJsonString());
  }

  Future<bool> _confirmLayoutOverwrite(String name) async {
    return await showEditorFDialog<bool>(
          context: context,
          builder: (context, style, animation) => FDialog(
            animation: animation,
            builder: (context, style) => Padding(
              padding: const EdgeInsets.all(18),
              child: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Overwrite Layout?',
                      style: editorDialogTitleText,
                    ),
                    const SizedBox(height: 10),
                    Text('Replace the saved layout “$name”?'),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        FButton(
                          variant: .outline,
                          size: .xs,
                          mainAxisSize: .min,
                          onPress: () => Navigator.pop(context, false),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 8),
                        FButton(
                          size: .xs,
                          mainAxisSize: .min,
                          onPress: () => Navigator.pop(context, true),
                          child: const Text('Overwrite'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ) ??
        false;
  }

  Future<void> _manageLayouts() async {
    await showEditorFDialog<void>(
      context: context,
      builder: (context, style, animation) => FDialog(
        animation: animation,
        constraints: const BoxConstraints(minWidth: 520, maxWidth: 560),
        builder: (context, style) => Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Manage Layouts', style: editorDialogTitleText),
              const SizedBox(height: 12),
              if (widget.namedLayouts.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text('No named layouts have been saved.'),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 360),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final entry in widget.namedLayouts.entries)
                        _LayoutManagerRow(
                          name: entry.key,
                          onApply: () {
                            Navigator.pop(context);
                            _applyDockLayout(entry.value);
                          },
                          onOverwrite: () async {
                            final overwrite = await _confirmLayoutOverwrite(
                              entry.key,
                            );
                            if (overwrite) {
                              widget.onSaveNamedLayout?.call(
                                entry.key,
                                _dockLayout.toJsonString(),
                              );
                            }
                          },
                          onDelete: () {
                            widget.onDeleteNamedLayout?.call(entry.key);
                            Navigator.pop(context);
                          },
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: FButton(
                  variant: .outline,
                  size: .xs,
                  mainAxisSize: .min,
                  onPress: () => Navigator.pop(context),
                  child: const Text('Done'),
                ),
              ),
            ],
          ),
        ),
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
                  recentScenePaths: widget.recentScenePaths,
                  onOpenRecentScene: _openPath,
                  onRemoveRecentScene: widget.onRemoveRecentScene,
                  onClearRecentScenes: widget.onClearRecentScenes,
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
                  onAddPrimitive: _addPrimitiveByCommand,
                  onAddEmpty: () => unawaited(_addEmptyNode()),
                  onAddObject: (type) {
                    final entry = componentObjects.firstWhere(
                      (candidate) => candidate.type == type,
                    );
                    unawaited(_addComponentObject(entry.type, entry.label));
                  },
                  onAddPrefab: _addPrefabInstance,
                  onNewComponentScript: widget.projectRootDirectory == null
                      ? null
                      : _newComponentScript,
                  onNewNativeComponentScript:
                      widget.projectRootDirectory == null
                      ? null
                      : () => unawaited(_newNativeComponentScript()),
                  onPaletteOpen: () => setState(() => _paletteOpen = true),
                  isPanelVisible: _dockLayout.isVisible,
                  onTogglePanel: _togglePanel,
                  onNewViewport: _newViewport,
                  onShowToolchain: _showToolchain,
                  onShowSettings: widget.onShowSettings,
                  onShowSceneSettings: _showSceneSettings,
                  projectName: widget.projectName,
                  onOpenProject: widget.onOpenProject,
                  onNewProject: widget.onNewProject,
                  onCloseProject: widget.onCloseProject,
                  recentProjectPaths: widget.recentProjectPaths,
                  onOpenRecentProject: widget.onOpenRecentProject,
                  onEditBuildConfigs: widget.onEditBuildConfigs,
                  trailing: widget.trailing,
                  namedLayouts: widget.namedLayouts,
                  onApplyLayout: _applyDockLayout,
                  onSaveCurrentLayout: _saveCurrentLayoutAs,
                  onManageLayouts: _manageLayouts,
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
                              gizmoPreferences: widget.gizmoPreferences,
                            ),
                          ),
                          DockPanel(
                            id: 'animation',
                            title: 'Animation',
                            child: AnimationPanel(controller: _ctrl),
                          ),
                          DockPanel(
                            id: 'effects',
                            title: 'Effects',
                            child: VfxPanel(controller: _ctrl),
                          ),
                          DockPanel(
                            id: 'flow',
                            title: 'Flow',
                            child: FlowPanel(controller: _ctrl),
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
                              projectRoot: widget.projectRootDirectory,
                              onOpenScene: _openPath,
                            ),
                          ),
                          DockPanel(
                            id: 'history',
                            title: 'History',
                            child: HistoryPanel(controller: _ctrl),
                          ),
                          DockPanel(
                            id: 'render_graph',
                            title: 'Render Graph',
                            child: RenderGraphPanel(
                              controller: _ctrl,
                              inspector: _renderGraphInspector,
                            ),
                          ),
                          if (widget.projectRunner != null)
                            DockPanel(
                              id: 'console',
                              title: 'Console',
                              child: ConsolePanel(
                                runner: widget.projectRunner!,
                                session: widget.appSession,
                              ),
                            ),
                          for (final id in _extraViewportIds)
                            DockPanel(
                              id: id,
                              title: 'Viewport ${id.substring(8)}',
                              closable: true,
                              child: ViewportPanel(
                                controller: _ctrl,
                                gizmoPreferences: widget.gizmoPreferences,
                              ),
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

  void _showSceneSettings() =>
      unawaited(showSceneSettings(context, controller: _ctrl));

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
    // No Terrain entry: a plane becomes terrain the moment it is sculpted,
    // so a second object that is only a plane with hills already on it is one
    // concept too many.
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
    (group: 'Effects', label: 'Particle Emitter', type: 'particleEmitter'),
    (group: 'Effects', label: 'Trail', type: 'trail'),
    (group: 'Audio', label: 'Audio Source', type: 'audioSource'),
    (group: 'Audio', label: 'Audio Listener', type: 'audioListener'),
    (group: 'Environment', label: 'Water', type: 'water'),
    (group: 'Environment', label: 'Lightning', type: 'lightning'),
    (group: 'Scripting', label: 'Flow Graph', type: 'flow'),
    (group: 'Volume', label: 'Environment Volume', type: 'environmentVolume'),
    (group: 'Volume', label: 'Irradiance Volume', type: 'irradianceVolume'),
    (group: 'Volume', label: 'Reflection Probe', type: 'reflectionProbe'),
  ];

  /// The [componentObjects] in one group, in declaration order.
  static Iterable<({String group, String label, String type})> objectsIn(
    String group,
  ) => componentObjects.where((entry) => entry.group == group);

  /// Creates an empty node, the parent everything else gets grouped under.
  Future<void> _addEmptyNode() async {
    final before = Set.of(_ctrl.document.nodes.keys);
    await _ctrl.run('createNode', {'name': 'Node'});
    _ctrl.selection.selectOnly(
      _ctrl.document.nodes.keys.firstWhere((id) => !before.contains(id)),
    );
  }

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

    // Select the new node.
    _ctrl.selection.selectOnly(nodeId);
  }
}

// ---------------------------------------------------------------------------
// Menu bar.
// ---------------------------------------------------------------------------

class _LayoutManagerRow extends StatelessWidget {
  const _LayoutManagerRow({
    required this.name,
    required this.onApply,
    required this.onOverwrite,
    required this.onDelete,
  });

  final String name;
  final VoidCallback onApply;
  final VoidCallback onOverwrite;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextButton(
              onPressed: onApply,
              style: TextButton.styleFrom(alignment: Alignment.centerLeft),
              child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
          FButton(
            variant: .ghost,
            size: .xs,
            mainAxisSize: .min,
            onPress: onOverwrite,
            child: const Text('Overwrite'),
          ),
          FButton.icon(
            variant: .ghost,
            size: .xs,
            onPress: onDelete,
            child: const Icon(Icons.close, size: 14),
          ),
        ],
      ),
    );
  }
}

class _EditorMenuBar extends StatelessWidget {
  const _EditorMenuBar({
    required this.controller,
    required this.currentPath,
    required this.onNew,
    required this.onOpen,
    required this.recentScenePaths,
    required this.onOpenRecentScene,
    required this.onRemoveRecentScene,
    required this.onClearRecentScenes,
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
    required this.onAddPrimitive,
    required this.onAddEmpty,
    required this.onAddObject,
    required this.onAddPrefab,
    required this.onNewComponentScript,
    required this.onNewNativeComponentScript,
    required this.onPaletteOpen,
    required this.isPanelVisible,
    required this.onTogglePanel,
    required this.onNewViewport,
    required this.onShowToolchain,
    this.onShowSettings,
    required this.onShowSceneSettings,
    this.projectName,
    this.onOpenProject,
    this.onNewProject,
    this.onCloseProject,
    this.recentProjectPaths = const [],
    this.onOpenRecentProject,
    this.onEditBuildConfigs,
    this.trailing = const [],
    required this.namedLayouts,
    required this.onApplyLayout,
    required this.onSaveCurrentLayout,
    required this.onManageLayouts,
    required this.leadingInset,
    this.onDragStart,
  });

  final EditorController controller;
  final String? currentPath;
  final VoidCallback onNew;
  final VoidCallback onOpen;
  final List<String> recentScenePaths;
  final ValueChanged<String> onOpenRecentScene;
  final ValueChanged<String>? onRemoveRecentScene;
  final VoidCallback? onClearRecentScenes;
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

  /// Runs the named `create…Geometry` command and builds a node around it.
  final ValueChanged<String> onAddPrimitive;

  /// Creates an empty node, the parent other objects get grouped under.
  final VoidCallback onAddEmpty;

  /// Creates a node carrying the named component type.
  final ValueChanged<String> onAddObject;
  final VoidCallback onAddPrefab;

  /// Writes a new component script into the open project. Null with no
  /// project open, which disables the menu item rather than hiding it.
  final VoidCallback? onNewComponentScript;

  /// Scaffolds a C++ component and the Dart component that owns it. Null
  /// with no project open, for the same reason.
  final VoidCallback? onNewNativeComponentScript;
  final VoidCallback onPaletteOpen;
  final bool Function(String panelId) isPanelVisible;
  final ValueChanged<String> onTogglePanel;
  final VoidCallback onNewViewport;
  final VoidCallback onShowToolchain;
  final VoidCallback? onShowSettings;

  /// Opens the scene's own settings (its lighting, background and rendering).
  final VoidCallback onShowSceneSettings;
  final String? projectName;
  final VoidCallback? onOpenProject;
  final VoidCallback? onNewProject;
  final VoidCallback? onCloseProject;
  final List<String> recentProjectPaths;
  final ValueChanged<String>? onOpenRecentProject;
  final VoidCallback? onEditBuildConfigs;
  final List<Widget> trailing;
  final Map<String, String> namedLayouts;
  final ValueChanged<String?> onApplyLayout;
  final VoidCallback onSaveCurrentLayout;
  final VoidCallback onManageLayouts;
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
      child: EditorToolbar(
        height: 28,
        horizontalPadding: 0,
        children: [
          SizedBox(width: leadingInset),
          Image.asset(
            'packages/flutter_scene_editor/assets/flutter_scene_logo.png',
            width: 18,
            height: 18,
            cacheWidth: 36,
          ),
          const SizedBox(width: 6),
          Text(_title(), style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(width: 16),
          _Menu(
            label: 'File',
            items: [
              // Project-first: the project group leads, scenes open inside
              // its context.
              if (onOpenProject != null) ...[
                _MenuItem(label: 'Open Project…', onTap: onOpenProject),
                _MenuItem(label: 'New Project…', onTap: onNewProject),
                _MenuItem(
                  label: 'Open Recent Project',
                  children: recentProjectPaths.isEmpty
                      ? const [_MenuItem(label: 'No Recent Projects')]
                      : [
                          for (final path in recentProjectPaths)
                            _MenuItem(
                              label: path.split(Platform.pathSeparator).last,
                              detail: File(path).parent.path,
                              onTap: () => onOpenRecentProject?.call(path),
                            ),
                        ],
                ),
                if (projectName != null) ...[
                  _MenuItem(
                    label: 'Edit Build Configurations…',
                    onTap: onEditBuildConfigs,
                  ),
                  _MenuItem(label: 'Close Project', onTap: onCloseProject),
                ],
                const _MenuItem.divider(),
              ],
              _MenuItem(label: 'New Scene', onTap: onNew),
              _MenuItem(label: 'Open Scene…', onTap: onOpen),
              _MenuItem(
                label: 'Open Recent Scene',
                children: recentScenePaths.isEmpty
                    ? const [_MenuItem(label: 'No Recent Scenes')]
                    : [
                        for (final path in recentScenePaths)
                          _MenuItem(
                            label: path.split(Platform.pathSeparator).last,
                            detail: File(path).existsSync()
                                ? File(path).parent.path
                                : 'Missing  ${File(path).parent.path}',
                            onTap: () => onOpenRecentScene(path),
                            onRemove: onRemoveRecentScene == null
                                ? null
                                : () => onRemoveRecentScene!(path),
                          ),
                        const _MenuItem.divider(),
                        _MenuItem(
                          label: 'Clear Recent Scenes',
                          onTap: onClearRecentScenes,
                        ),
                      ],
              ),
              _MenuItem(label: 'Import glTF…', onTap: onImportGlb),
              _MenuItem(
                label: 'Re-import glTF…',
                onTap: canReimport ? onReimportGlb : null,
              ),
              _MenuItem(label: 'Save', onTap: onSave),
              _MenuItem(label: 'Save As…', onTap: onSaveAs),
              const _MenuItem.divider(),
              // The scene's own settings, distinct from the editor's below.
              _MenuItem(label: 'Scene Settings…', onTap: onShowSceneSettings),
              if (onShowSettings != null) ...[
                const _MenuItem.divider(),
                _MenuItem(label: 'Settings…', onTap: onShowSettings),
              ],
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
              _MenuItem(label: 'Empty Node', onTap: onAddEmpty),
              _MenuItem(
                label: '3D Object',
                children: [
                  for (final primitive in _EditorShellState.primitiveCommands)
                    _MenuItem(
                      label: primitive.label,
                      onTap: () => onAddPrimitive(primitive.command),
                    ),
                  for (final group in const [
                    'Camera',
                    'Light',
                    'Environment',
                    'Effects',
                    'Audio',
                    'Volume',
                    'Scripting',
                  ])
                    if (_EditorShellState.objectsIn(group).length == 1)
                      _MenuItem(
                        label: _EditorShellState.objectsIn(group).single.label,
                        onTap: () => onAddObject(
                          _EditorShellState.objectsIn(group).single.type,
                        ),
                      )
                    else
                      _MenuItem(
                        label: group,
                        children: [
                          for (final entry in _EditorShellState.objectsIn(
                            group,
                          ))
                            _MenuItem(
                              label: entry.label,
                              onTap: () => onAddObject(entry.type),
                            ),
                        ],
                      ),
                ],
              ),
              _MenuItem(label: 'Prefab Instance…', onTap: onAddPrefab),
              _MenuItem(
                label: 'Component Script…',
                onTap: onNewComponentScript,
              ),
              _MenuItem(
                label: 'Native Component…',
                onTap: onNewNativeComponentScript,
              ),
            ],
          ),
          // Built when the menu opens so the checkmarks reflect hides made
          // from tab context menus (which don't rebuild this bar).
          _Menu(
            label: 'View',
            itemsBuilder: () => [
              _MenuItem(label: 'New Viewport', onTap: onNewViewport),
              _MenuItem(
                label: 'Layouts',
                children: [
                  _MenuItem(
                    label: 'Reset to Default Layout',
                    onTap: () => onApplyLayout(null),
                  ),
                  for (final entry in namedLayouts.entries)
                    _MenuItem(
                      label: entry.key,
                      onTap: () => onApplyLayout(entry.value),
                    ),
                  const _MenuItem.divider(),
                  _MenuItem(
                    label: 'Save Current Layout As…',
                    onTap: onSaveCurrentLayout,
                  ),
                  _MenuItem(label: 'Manage Layouts…', onTap: onManageLayouts),
                ],
              ),
              for (final entry in _panelTitles.entries)
                _MenuItem(
                  label: entry.value,
                  checked: isPanelVisible(entry.key),
                  onTap: () => onTogglePanel(entry.key),
                ),
              _MenuItem(label: 'Shader Toolchain…', onTap: onShowToolchain),
            ],
          ),
          _MenuButton(label: 'Commands', onTap: onPaletteOpen),
          const Spacer(),
          ...trailing,
          const SizedBox(width: 6),
        ],
      ),
    );
  }

  String _title() {
    final scene = currentPath?.split(Platform.pathSeparator).last;
    final project = projectName;
    if (project != null && scene != null) return '$project · $scene';
    if (project != null) return 'Scene Editor  ($project)';
    if (scene != null) return 'Scene Editor  ($scene)';
    return 'Scene Editor';
  }
}

class _MenuItem {
  const _MenuItem({
    required this.label,
    this.detail,
    this.onTap,
    this.onRemove,
    this.checked,
    this.children,
  }) : divider = false;

  const _MenuItem.divider()
    : label = '',
      detail = null,
      onTap = null,
      onRemove = null,
      checked = null,
      children = null,
      divider = true;

  final String label;
  final String? detail;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;

  /// Non-null renders a leading checkmark slot (checked or empty).
  final bool? checked;
  final List<_MenuItem>? children;
  final bool divider;
}

class _Menu extends StatefulWidget {
  const _Menu({required this.label, this.items, this.itemsBuilder})
    : assert((items == null) != (itemsBuilder == null));

  final String label;
  final List<_MenuItem>? items;

  /// Deferred alternative to [items], invoked when the menu opens, for
  /// entries whose state can change without this bar rebuilding.
  final List<_MenuItem> Function()? itemsBuilder;

  @override
  State<_Menu> createState() => _MenuState();
}

class _MenuState extends State<_Menu> {
  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      menuChildren: _buildMenuItems(widget.items ?? widget.itemsBuilder!()),
      builder: (context, controller, child) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (controller.isOpen) {
            controller.close();
            return;
          }
          // Refresh deferred menu state before the overlay is built.
          setState(() {});
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) controller.open();
          });
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(widget.label, style: const TextStyle(fontSize: 11)),
        ),
      ),
    );
  }

  List<Widget> _buildMenuItems(List<_MenuItem> source) => [
    for (final item in source)
      if (item.divider)
        const Divider(height: 8)
      else if (item.children != null)
        SubmenuButton(
          menuChildren: _buildMenuItems(item.children!),
          child: Text(item.label),
        )
      else
        MenuItemButton(
          onPressed: item.onTap,
          leadingIcon: item.checked == null
              ? null
              : editorMenuCheckmark(item.checked!),
          child: item.detail == null && item.onRemove == null
              ? Text(item.label)
              : SizedBox(
                  width: 360,
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (item.detail != null)
                              Text(
                                item.detail!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: editorMenuItemDetailText,
                              ),
                          ],
                        ),
                      ),
                      if (item.onRemove != null)
                        IconButton(
                          tooltip: 'Remove from recent scenes',
                          onPressed: item.onRemove,
                          icon: const Icon(Icons.close, size: 14),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                ),
        ),
  ];
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
