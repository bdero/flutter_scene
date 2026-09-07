/// Asset browser: a project-wide, browsable index of the open scene's files
/// (models, images, HDRs, sub-scenes) plus the document's embedded resources.
///
/// Files are dragged or clicked into the scene; the embedded section shows what
/// each pooled resource is used by and lets the author remove unused ones (an
/// explicit, undoable action, never a silent cleanup on save). The full
/// embed/externalize-to-a-shared-file flows are designed in
/// notes/architecture/asset_browser_and_resource_model_design.md and land in a
/// later phase; this is the read-and-drag-in first version.
library;

import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:forui/forui.dart';

import '../project/fproject.dart' show pathIsWithin;
import '../shell/editor_menu.dart';
import '../shell/editor_theme.dart';
import '../shell/panel_chrome.dart';
import '../assets/asset_index.dart';
import 'package:scene/visual_script.dart';

import '../blueprints/blueprint_editor_screen.dart';
import '../blueprints/blueprint_file.dart';
import '../blueprints/blueprint_parents.dart';
import '../blueprints/pick_parent_class_dialog.dart';
import '../controller/editor_controller.dart';
import '../assets/environment_thumbnail.dart';
import '../inspector/resource_origin.dart';
import '../io/file_browser.dart';
import '../io/scene_io.dart';
import 'package:flutter_scene_editor_core/flutter_scene_editor_core.dart';
import 'package:scene/scene.dart' show LocalId, writeFscene;

/// The asset browser panel.
class AssetBrowserPanel extends StatefulWidget {
  const AssetBrowserPanel({
    super.key,
    required this.controller,
    required this.onImportModel,
    this.projectRoot,
    this.onOpenScene,
  });

  final EditorController controller;

  /// Imports a raw glTF model file (`.glb`/`.gltf`); the shell shows the import
  /// options dialog. `.fscene`/`.fsceneb` are instantiated directly as prefabs.
  final Future<void> Function(String path) onImportModel;

  /// The open project's root. Set, the browser scans it (every scene and
  /// resource in the project, regardless of which scene is open); unset, it
  /// falls back to the open scene's directory.
  final String? projectRoot;

  /// Opens an `.fscene` file in the editor (the scene rows' open action);
  /// tapping a scene row still instantiates it as a prefab.
  final ValueChanged<String>? onOpenScene;

  @override
  State<AssetBrowserPanel> createState() => _AssetBrowserPanelState();
}

class _AssetBrowserPanelState extends State<AssetBrowserPanel> {
  List<FileAsset> _files = const [];
  final Set<String> _expandedDirectories = {};

  /// The folder whose contents the right pane is showing, relative to the
  /// scan root; empty is the root itself.
  ///
  /// This is what a new asset, a dropped file and an extracted prefab land
  /// in. Without it every one of those had to guess, and they all guessed
  /// "the project root".
  String _folder = '';

  /// Whether the right pane is showing the open scene's own pooled resources
  /// rather than a folder. They are assets of the document, not of the disk,
  /// so they get a place in the tree rather than a section stapled under it.
  bool _sceneResources = false;

  /// The kind the contents pane is limited to, or null for everything.
  FileAssetKind? _kind;

  /// Whether files from outside the application are hovering over the panel.
  bool _osDragOver = false;

  /// Watches the project for assets that change outside the editor.
  StreamSubscription<FileSystemEvent>? _watch;
  Timer? _watchDebounce;

  _AssetViewMode _viewMode = _AssetViewMode.thumbnails;
  bool _scanning = false;
  final TextEditingController _filter = TextEditingController();
  String _query = '';
  String? _scannedDir;

  EditorController get _ctrl => widget.controller;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onDocChanged);
    _ctrl.history.addListener(_onHistoryChanged);
    _rescan();
  }

  @override
  void didUpdateWidget(AssetBrowserPanel old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onDocChanged);
      old.controller.history.removeListener(_onHistoryChanged);
      _ctrl.addListener(_onDocChanged);
      _ctrl.history.addListener(_onHistoryChanged);
      _rescan();
    } else if (old.projectRoot != widget.projectRoot) {
      _rescan();
    }
  }

  /// Rescans when something changes on disk.
  ///
  /// An asset is usually edited in the tool that made it, and a browser that
  /// only notices on an explicit refresh is a browser showing yesterday's
  /// project. Debounced, because a save from another application arrives as a
  /// burst of events, and filtered, because a build directory changing is not
  /// news.
  void _watchProject(String? directory) {
    _watch?.cancel();
    _watch = null;
    if (directory == null) return;
    final root = Directory(directory);
    if (!root.existsSync()) return;
    try {
      _watch = root.watch(recursive: true).listen((event) {
        if (_isNoise(event.path)) return;
        _watchDebounce?.cancel();
        _watchDebounce = Timer(
          const Duration(milliseconds: 400),
          () => unawaited(_rescan()),
        );
      }, onError: (_) {});
    } on FileSystemException {
      // Watching is a convenience; a filesystem that will not report changes
      // still browses and still rescans on demand.
    }
  }

  static bool _isNoise(String path) {
    final normalized = path.replaceAll('\\', '/');
    for (final segment in normalized.split('/')) {
      if (segment.startsWith('.')) return true;
      if (segment == 'build' || segment == 'node_modules') return true;
    }
    return false;
  }

  @override
  void dispose() {
    _watch?.cancel();
    _watchDebounce?.cancel();
    _ctrl.removeListener(_onDocChanged);
    _ctrl.history.removeListener(_onHistoryChanged);
    _filter.dispose();
    super.dispose();
  }

  // A project open scans the project root (every scene and resource in the
  // project); otherwise the open scene's directory.
  String? get _scanRoot => widget.projectRoot ?? _ctrl.baseDirectory;

  /// The selected folder as an absolute directory, or null with no scan root.
  String? get _currentDirectory {
    final root = _scanRoot;
    if (root == null) return null;
    if (_folder.isEmpty) return root;
    return '$root${Platform.pathSeparator}'
        '${_folder.replaceAll('/', Platform.pathSeparator)}';
  }

  /// The files directly inside [_folder] (not its subfolders), after the kind
  /// filter. Searching widens this to the whole project, because a search that
  /// only looks in the folder you happen to be standing in is a search that
  /// finds nothing.
  List<FileAsset> _contents(String query) {
    final kind = _kind;
    final matches = <FileAsset>[];
    for (final asset in _files) {
      if (kind != null && asset.kind != kind) continue;
      final keep = query.isEmpty
          ? _folderOf(asset) == _folder
          : asset.relativePath.toLowerCase().contains(query);
      if (keep) matches.add(asset);
    }
    matches.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return matches;
  }

  static String _folderOf(FileAsset asset) {
    final parts = asset.relativePath.split(RegExp(r'[/\\]'));
    if (parts.length < 2) return '';
    return parts.take(parts.length - 1).join('/');
  }

  void _selectFolder(String path) => setState(() {
    _folder = path;
    _sceneResources = false;
    _expandedDirectories.add(path);
  });

  void _onDocChanged() {
    if (_scanRoot != _scannedDir) {
      _rescan();
    }
  }

  void _onHistoryChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _rescan() async {
    final dir = _scanRoot;
    _scannedDir = dir;
    if (dir == null) {
      setState(() => _files = const []);
      return;
    }
    setState(() => _scanning = true);
    _watchProject(dir);
    final files = await scanProjectAssets(dir);
    if (!mounted) return;
    setState(() {
      _files = files;
      _expandedDirectories.addAll(_directoryPaths(files));
      _scanning = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    bool matches(FileAsset asset) =>
        q.isEmpty || asset.relativePath.toLowerCase().contains(q);

    final visibleFiles = _files.where(matches).toList();
    final embedded = embeddedResources(
      _ctrl.document,
    ).where((r) => q.isEmpty || r.label.toLowerCase().contains(q)).toList();

    return DropTarget(
      // Files dragged in from the desktop. They land in the folder the left
      // pane has selected, which is the whole reason that selection exists.
      onDragEntered: (_) => setState(() => _osDragOver = true),
      onDragExited: (_) => setState(() => _osDragOver = false),
      onDragDone: (detail) {
        setState(() => _osDragOver = false);
        unawaited(_importDropped([for (final file in detail.files) file.path]));
      },
      child: DragTarget<LocalId>(
        onWillAcceptWithDetails: (details) => _scanRoot != null,
        onAcceptWithDetails: (details) => unawaited(_makePrefab(details.data)),
        builder: (context, candidate, rejected) => GestureDetector(
          // Right-clicking the panel's empty space is where people go to make a
          // new asset, in every tool that has a project browser.
          behavior: HitTestBehavior.translucent,
          onSecondaryTapUp: (d) => unawaited(_showCreateMenu(d.globalPosition)),
          child: Container(
            foregroundDecoration: candidate.isEmpty && !_osDragOver
                ? null
                : BoxDecoration(
                    border: Border.all(color: editorAccentColor, width: 2),
                    color: editorAccentColor.withValues(alpha: 0.07),
                  ),
            child: _buildBrowser(context, visibleFiles, embedded, q),
          ),
        ),
      ),
    );
  }

  /// Copies files dropped from outside the application into the selected
  /// folder.
  ///
  /// A copy, not a link: an asset that lives outside the project is an asset
  /// that is missing on the next machine. A file already inside the project is
  /// left where it is and simply revealed, because dragging something onto
  /// itself should not produce a second copy of it.
  Future<void> _importDropped(List<String> paths) async {
    final root = _scanRoot;
    final target = _currentDirectory;
    if (root == null || target == null) {
      _report('Open a project (or save the scene) before importing assets.');
      return;
    }
    var copied = 0;
    var skipped = 0;
    final rejected = <String>[];
    for (final path in paths) {
      final source = File(path);
      if (!source.existsSync()) continue;
      if (assetKindOf(path) == null) {
        rejected.add(path.split(Platform.pathSeparator).last);
        continue;
      }
      if (pathIsWithin(root, path)) {
        skipped++;
        continue;
      }
      try {
        await source.copy(
          _freeCopyPath(target, path.split(Platform.pathSeparator).last),
        );
        copied++;
      } on Object catch (error) {
        _report('Could not import ${source.path}: $error');
        return;
      }
    }
    await _rescan();
    if (!mounted) return;
    final where = _folder.isEmpty ? 'the project root' : _folder;
    final parts = [
      if (copied > 0)
        'Imported $copied file${copied == 1 ? '' : 's'} into $where',
      if (skipped > 0) '$skipped already in the project',
      if (rejected.isNotEmpty)
        'not an asset the editor reads: ${rejected.join(', ')}',
    ];
    if (parts.isNotEmpty) _report(parts.join('. '));
  }

  /// [name] inside [directory], numbered if something is already there.
  static String _freeCopyPath(String directory, String name) {
    final dot = name.lastIndexOf('.');
    final stem = dot <= 0 ? name : name.substring(0, dot);
    final extension = dot <= 0 ? '' : name.substring(dot);
    var candidate = '$directory${Platform.pathSeparator}$name';
    var counter = 2;
    while (File(candidate).existsSync()) {
      candidate =
          '$directory${Platform.pathSeparator}$stem-${counter++}$extension';
    }
    return candidate;
  }

  /// The right-click-on-nothing menu: what you can make here.
  Future<void> _showCreateMenu(Offset position) async {
    final root = _scanRoot;
    if (root == null) {
      _report('Open a project first: a blueprint is a file in one.');
      return;
    }
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    const itemStyle = TextStyle(fontSize: 12);
    final kind = await showMenu<BlueprintKind>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        const PopupMenuItem<BlueprintKind>(
          enabled: false,
          height: 26,
          child: Text('Create', style: editorMicroText),
        ),
        for (final kind in BlueprintKind.values)
          PopupMenuItem(
            value: kind,
            height: 34,
            child: Text(kind.label, style: itemStyle),
          ),
      ],
    );
    if (kind == null || !mounted) return;
    await _createBlueprint(kind, root);
  }

  /// Makes a blueprint of [kind] under [root] and opens it.
  ///
  /// A class is asked what it extends before it exists, because the answer
  /// decides what its graphs may assume -- which events they receive, what
  /// `self` is. Changing it later is reparenting, and reparenting can
  /// invalidate every node in the graph. The kinds that produce no instances,
  /// an interface and a macro library, are not asked: there is nothing for a
  /// parent to mean.
  Future<void> _createBlueprint(BlueprintKind kind, String root) async {
    var parent = defaultBlueprintParent;
    if (kind == BlueprintKind.blueprintClass ||
        kind == BlueprintKind.widgetBlueprint) {
      final picked = await pickParentClass(
        context: context,
        all: allBlueprintParents(
          _ctrl.componentTypes(),
          schemaFor: _ctrl.componentSchemaFor,
        ),
      );
      // Dismissing the picker cancels the whole thing: a class with no parent
      // is not something that can exist, so there is nothing to half-make.
      if (picked == null) return;
      parent = picked;
    }

    final path = freeBlueprintPath(
      _currentDirectory ?? root,
      defaultBlueprintName(kind),
    );
    final file = BlueprintFile(path);
    try {
      await file.write(
        newBlueprint(name: file.name, kind: kind, parentClass: parent),
      );
    } on Object catch (error) {
      _report('Could not write the blueprint: $error');
      return;
    }
    await _rescan();
    if (!mounted) return;
    await openBlueprintEditor(context: context, controller: _ctrl, file: file);
  }

  Widget _buildBrowser(
    BuildContext context,
    List<FileAsset> visibleFiles,
    List<EmbeddedResource> embedded,
    String q,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _toolbar(context),
        if (_scanRoot == null)
          const Expanded(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Open a project (or save the scene) to browse assets.',
                  style: TextStyle(fontSize: 12, color: editorMutedTextColor),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          )
        else
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 180,
                  child: _folderPane(context, embedded.length),
                ),
                const EditorRegionDivider(axis: Axis.vertical),
                Expanded(child: _contentsPane(context, embedded, q)),
              ],
            ),
          ),
      ],
    );
  }

  /// The left pane: where things are.
  ///
  /// Folders only. Files live on the right, because a tree that holds both is
  /// a tree you scroll past folders to read.
  Widget _folderPane(BuildContext context, int embeddedCount) {
    final root = _buildAssetTree(_files);
    final rootName = _scanRoot == null
        ? '/'
        : _scanRoot!.split(Platform.pathSeparator).last;
    return Container(
      color: editorSurfaceColor,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 4),
        children: [
          _DirectoryRow(
            name: rootName,
            depth: 0,
            expanded: true,
            selected: _folder.isEmpty && !_sceneResources,
            hasChildren: root.sortedDirectories.isNotEmpty,
            onSelect: () => _selectFolder(''),
            onToggle: () {},
          ),
          for (final directory in root.sortedDirectories)
            ..._folderBranch(context, directory, depth: 1),
          if (embeddedCount > 0) ...[
            const Divider(height: 9, color: editorLineColor),
            _DirectoryRow(
              name: 'Scene resources  ($embeddedCount)',
              depth: 0,
              expanded: false,
              selected: _sceneResources,
              hasChildren: false,
              icon: Icons.inventory_2_outlined,
              onSelect: () => setState(() => _sceneResources = true),
              onToggle: () {},
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _folderBranch(
    BuildContext context,
    _AssetDirectory directory, {
    required int depth,
  }) {
    final expanded = _expandedDirectories.contains(directory.path);
    return [
      _DirectoryRow(
        name: directory.name,
        depth: depth,
        expanded: expanded,
        selected: !_sceneResources && _folder == directory.path,
        hasChildren: directory.sortedDirectories.isNotEmpty,
        onSelect: () => _selectFolder(directory.path),
        onToggle: () => setState(() {
          if (!_expandedDirectories.remove(directory.path)) {
            _expandedDirectories.add(directory.path);
          }
        }),
      ),
      if (expanded)
        for (final child in directory.sortedDirectories)
          ..._folderBranch(context, child, depth: depth + 1),
    ];
  }

  /// The right pane: what is here.
  Widget _contentsPane(
    BuildContext context,
    List<EmbeddedResource> embedded,
    String q,
  ) {
    if (_sceneResources) {
      return Container(
        color: editorSurfaceColor,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          children: [_embeddedSection(context, embedded)],
        ),
      );
    }
    final items = _contents(q);
    if (items.isEmpty) {
      return Container(
        color: editorSurfaceColor,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              q.isEmpty
                  ? 'Nothing in this folder yet. Right-click to make something, '
                        'or drag a node here to save it as a prefab.'
                  : 'No asset matches "$q".',
              style: const TextStyle(fontSize: 12, color: editorMutedTextColor),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    return Container(
      color: editorSurfaceColor,
      child: _viewMode == _AssetViewMode.thumbnails
          ? SingleChildScrollView(
              padding: const EdgeInsets.all(8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final asset in items)
                    _FileThumbnailTile(
                      asset: asset,
                      onAct: _actOn,
                      onContextMenu: _showFileMenu,
                    ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: items.length,
              itemBuilder: (context, index) => _FileListRow(
                asset: items[index],
                depth: 0,
                onAct: _actOn,
                onOpenScene: _openSceneAction(items[index]),
                onContextMenu: _showFileMenu,
              ),
            ),
    );
  }

  Widget _toolbar(BuildContext context) {
    return EditorToolbar(
      leading: [
        const SizedBox(width: 2),
        // Where you are, so an action that writes "here" says where here is.
        Icon(
          _sceneResources ? Icons.inventory_2_outlined : Icons.folder_outlined,
          size: 14,
          color: editorMutedTextColor,
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 150,
          child: Text(
            _sceneResources
                ? 'Scene resources'
                : _folder.isEmpty
                ? 'Project root'
                : _folder,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
        ),
        const SizedBox(width: 8),
        EditorMenu(
          label: _kind == null ? 'All' : _kindLabel(_kind!),
          tooltip: 'Show one kind of asset',
          items: [
            EditorMenuItem(
              label: 'All',
              checked: _kind == null,
              onTap: () => setState(() => _kind = null),
            ),
            for (final kind in FileAssetKind.values)
              EditorMenuItem(
                label: _kindLabel(kind),
                checked: _kind == kind,
                onTap: () => setState(() => _kind = kind),
              ),
          ],
        ),
        const SizedBox(width: 4),
        // A fixed width, not Expanded: this strip scrolls, so it is laid out
        // against unbounded width and a flex child is an error there. See
        // [EditorToolbarScroller].
        SizedBox(
          width: 170,
          child: FTextField(
            control: FTextFieldControl.managed(
              controller: _filter,
              onChange: (value) => setState(() => _query = value.text),
            ),
            size: .sm,
            hint: 'Search assets',
            prefixBuilder: (_, _, _) => const Padding(
              padding: EdgeInsets.only(left: 8, right: 4),
              child: Icon(Icons.search, size: 14),
            ),
          ),
        ),
        const SizedBox(width: 4),
        _viewButton(
          context,
          mode: _AssetViewMode.thumbnails,
          icon: Icons.grid_view_outlined,
          tooltip: 'Thumbnails',
        ),
        _viewButton(
          context,
          mode: _AssetViewMode.list,
          icon: Icons.view_list_outlined,
          tooltip: 'List',
        ),
        IconButton(
          tooltip: 'Rescan',
          visualDensity: VisualDensity.compact,
          icon: _scanning
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh, size: 16),
          onPressed: _scanning ? null : _rescan,
        ),
      ],
    );
  }

  static String _kindLabel(FileAssetKind kind) => switch (kind) {
    FileAssetKind.model => 'Models',
    FileAssetKind.scene => 'Scenes',
    FileAssetKind.environmentImage => 'Environments',
    FileAssetKind.image => 'Images',
    FileAssetKind.material => 'Materials',
    FileAssetKind.blueprint => 'Blueprints',
  };

  Widget _viewButton(
    BuildContext context, {
    required _AssetViewMode mode,
    required IconData icon,
    required String tooltip,
  }) {
    final selected = _viewMode == mode;
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: () => setState(() => _viewMode = mode),
        borderRadius: BorderRadius.circular(3),
        child: Container(
          width: 26,
          height: 24,
          decoration: BoxDecoration(
            color: selected
                ? scheme.primary.withValues(alpha: 0.16)
                : Colors.transparent,
            border: Border.all(
              color: selected ? scheme.primary : Colors.transparent,
            ),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Icon(
            icon,
            size: 16,
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  // Text formats the source-editor action opens.
  static const _textExtensions = {
    '.fmat',
    '.fscene',
    '.fproject',
    '.json',
    '.glsl',
    '.frag',
    '.vert',
    '.dart',
    '.cube',
    '.md',
    '.txt',
    '.yaml',
  };

  static bool _isTextAsset(FileAsset asset) {
    final name = asset.name.toLowerCase();
    return _textExtensions.any(name.endsWith);
  }

  // The per-file right-click menu: clipboard path, the platform file
  // browser's reveal verb, and the source editor for text formats.
  Future<void> _showFileMenu(FileAsset asset, Offset position) async {
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
        const PopupMenuItem(
          value: 'copy',
          height: 34,
          child: Text('Copy path', style: itemStyle),
        ),
        PopupMenuItem(
          value: 'reveal',
          height: 34,
          child: Text(revealInFileBrowserLabel, style: itemStyle),
        ),
        if (_isTextAsset(asset))
          const PopupMenuItem(
            value: 'open',
            height: 34,
            child: Text('Open source in editor', style: itemStyle),
          ),
      ],
    );
    switch (action) {
      case 'copy':
        await Clipboard.setData(ClipboardData(text: asset.path));
      case 'reveal':
        await revealInFileBrowser(asset.path);
      case 'open':
        await _ctrl.sourceFileOpener?.call(asset.path);
    }
  }

  Widget _embeddedSection(BuildContext context, List<EmbeddedResource> items) {
    if (items.isEmpty) return const SizedBox.shrink();
    final unused = items.where((r) => r.isUnused).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _header(context, 'In this scene  (${items.length})'),
            ),
            if (unused.isNotEmpty)
              TextButton.icon(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.delete_sweep_outlined, size: 16),
                label: Text(
                  'Remove ${unused.length} unused',
                  style: const TextStyle(fontSize: 12),
                ),
                onPressed: () => _removeUnused(unused),
              ),
          ],
        ),
        for (final r in items) _embeddedTile(context, r),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _embeddedTile(BuildContext context, EmbeddedResource r) {
    final used = r.usedBy;
    final subtitle = used.isEmpty
        ? 'Unused'
        : 'Used by ${used.length}: ${used.take(3).join(', ')}'
              '${used.length > 3 ? '…' : ''}';
    final spec = _ctrl.document.resource(r.id);
    final (locality, path) = spec == null
        ? (ResourceLocality.builtIn, null)
        : resourceOriginOf(spec);
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      visualDensity: VisualDensity.compact,
      leading: Icon(_embeddedIcon(r.kind), size: 16),
      title: Row(
        children: [
          Flexible(
            child: Text(
              r.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ),
          const SizedBox(width: 6),
          OriginBadge(locality: locality, path: path, dense: true),
        ],
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 11,
          color: r.isUnused ? editorWarningColor : editorMutedTextColor,
        ),
      ),
      trailing: r.isUnused
          ? IconButton(
              tooltip: 'Remove unused resource',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close, size: 16),
              onPressed: () => _removeUnused([r]),
            )
          : null,
    );
  }

  Widget _header(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(top: 6, bottom: 4),
    child: Text(
      text,
      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
    ),
  );

  // The open-in-editor action for `.fscene` rows (null hides the affordance).
  VoidCallback? _openSceneAction(FileAsset asset) {
    final onOpenScene = widget.onOpenScene;
    if (onOpenScene == null) return null;
    if (asset.kind != FileAssetKind.scene) return null;
    if (!asset.name.toLowerCase().endsWith('.fscene')) return null;
    return () => onOpenScene(asset.path);
  }

  // Acts on a file tile, picking the natural default for its kind.
  Future<void> _actOn(FileAsset asset) async {
    switch (asset.kind) {
      case FileAssetKind.model:
        if (asset.name.toLowerCase().endsWith('.fsceneb')) {
          await _instantiatePrefab(asset.path);
        } else {
          await widget.onImportModel(asset.path);
        }
      case FileAssetKind.scene:
        await _instantiatePrefab(asset.path);
      case FileAssetKind.environmentImage:
        await importEnvironmentMap(_ctrl, asset.path);
      case FileAssetKind.image:
        // Assigning an image to a material slot is done from the material
        // inspector; the browser previews it. TODO(asset-drag-to-slot): wire a
        // drag from here onto material/texture slots.
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Assign images from a material slot in the inspector.',
              ),
              duration: Duration(seconds: 2),
            ),
          );
        }
      case FileAssetKind.blueprint:
        await openBlueprintEditor(
          context: context,
          controller: _ctrl,
          file: BlueprintFile(asset.path),
        );
      case FileAssetKind.material:
        final selected = _ctrl.selection.primary;
        if (selected != null &&
            _ctrl
                    .displayNode(selected)
                    ?.components
                    .any((c) => c.type == 'mesh') ==
                true) {
          await assignFmatMaterial(_ctrl, selected, asset.path);
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Select a mesh node to assign this .fmat material to.',
              ),
              duration: Duration(seconds: 2),
            ),
          );
        }
    }
  }

  /// Saves the subtree at [nodeId] as a reusable `.fscene`, and turns the
  /// node it came from into an instance of it.
  ///
  /// The second half is what makes it a prefab rather than a copy: the crate
  /// in the level and the crate on disk are the same crate afterwards, so
  /// editing the asset changes the one standing in the scene. It is also what
  /// every tool with a content browser does when you drag an object into it,
  /// and being surprised by that is worse than being asked.
  Future<void> _makePrefab(LocalId nodeId) async {
    final root = _scanRoot;
    final node = _ctrl.document.node(nodeId);
    if (root == null || node == null) return;

    final extracted = extractPrefab(_ctrl.document, nodeId);
    final name = node.name.isEmpty ? 'Prefab' : node.name;
    final file = freePrefabPath(_currentDirectory ?? root, name);

    try {
      await File(file).writeAsString(writeFscene(extracted.document));
    } on Object catch (error) {
      _report('Could not write the prefab: $error');
      return;
    }

    final relative = file.startsWith('$root${Platform.pathSeparator}')
        ? file.substring(root.length + 1)
        : file;

    // The swap is two commands, and so two undo steps, like every other
    // multi-step gesture here. If the second half fails the first is rolled
    // back, so a failure leaves the scene as it was rather than holding both
    // the instance and the node it was made from.
    final parent = _ctrl.query.parentOf(nodeId);
    try {
      final instance = await _ctrl.run('instantiatePrefab', {
        'prefabAsset': relative,
        'name': node.name,
        if (parent != null) 'parentId': parent.toToken(),
      });
      try {
        await _ctrl.run('deleteNode', {'nodeId': nodeId.toToken()});
      } on Object {
        if (_ctrl.history.canUndo) await _ctrl.undo();
        rethrow;
      }
      _ctrl.selection.selectOnly(instance.records.first.targetId);
    } on Object catch (error) {
      _report('Made $relative, but could not swap the node for it: $error');
      await _rescan();
      return;
    }

    await _rescan();
    if (!extracted.isComplete) {
      _report(
        'Made $relative. ${extracted.droppedNodeReferences.length} '
        'reference(s) to nodes outside it were cleared: '
        '${extracted.droppedNodeReferences.join(', ')}.',
      );
    } else {
      _report('Made $relative.');
    }
  }

  void _report(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _instantiatePrefab(String path) async {
    final base = _ctrl.baseDirectory;
    final source = (base != null && path.startsWith('$base/'))
        ? path.substring(base.length + 1)
        : path;
    final name = source
        .split(Platform.pathSeparator)
        .last
        .replaceAll(RegExp(r'\.(fscene|fsceneb)$'), '');
    try {
      final tx = await _ctrl.run('instantiatePrefab', {
        'prefabAsset': source,
        'name': name,
      });
      _ctrl.selection.selectOnly(tx.records.first.targetId);
    } catch (e) {
      if (_ctrl.history.canUndo) await _ctrl.undo();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not add: $e')));
      }
    }
  }

  Future<void> _removeUnused(List<EmbeddedResource> resources) async {
    for (final r in resources) {
      // Re-check it is still unused (a prior removal cannot have referenced it,
      // but the list may be stale across awaits).
      try {
        await _ctrl.run('removeResource', {'resourceId': r.id.toToken()});
      } catch (_) {
        // Skip a resource that can no longer be removed; the rest still go.
      }
    }
  }
}

enum _AssetViewMode { list, thumbnails }

class _AssetDirectory {
  _AssetDirectory({required this.name, required this.path});

  final String name;
  final String path;
  final Map<String, _AssetDirectory> directories = {};
  final List<FileAsset> files = [];

  List<_AssetDirectory> get sortedDirectories {
    final result = directories.values.toList();
    result.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return result;
  }

  List<FileAsset> get sortedFiles {
    final result = files.toList();
    result.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return result;
  }
}

_AssetDirectory _buildAssetTree(List<FileAsset> files) {
  final root = _AssetDirectory(name: '', path: '');
  for (final asset in files) {
    final parts = asset.relativePath.split(RegExp(r'[/\\]'));
    var directory = root;
    var path = '';
    for (final part in parts.take(parts.length - 1)) {
      path = path.isEmpty ? part : '$path/$part';
      directory = directory.directories.putIfAbsent(
        part,
        () => _AssetDirectory(name: part, path: path),
      );
    }
    directory.files.add(asset);
  }
  return root;
}

Set<String> _directoryPaths(List<FileAsset> files) {
  final result = <String>{};
  for (final asset in files) {
    final parts = asset.relativePath.split(RegExp(r'[/\\]'));
    var path = '';
    for (final part in parts.take(parts.length - 1)) {
      path = path.isEmpty ? part : '$path/$part';
      result.add(path);
    }
  }
  return result;
}

IconData _embeddedIcon(EmbeddedResourceKind kind) => switch (kind) {
  EmbeddedResourceKind.material => Icons.brush_outlined,
  EmbeddedResourceKind.geometry => Icons.category_outlined,
  EmbeddedResourceKind.texture => Icons.image_outlined,
  EmbeddedResourceKind.environment => Icons.light_mode_outlined,
  EmbeddedResourceKind.other => Icons.data_object,
};

IconData _fileIcon(FileAssetKind kind) => switch (kind) {
  FileAssetKind.model => Icons.view_in_ar_outlined,
  FileAssetKind.scene => Icons.account_tree_outlined,
  FileAssetKind.environmentImage => Icons.light_mode_outlined,
  FileAssetKind.image => Icons.image_outlined,
  FileAssetKind.material => Icons.brush_outlined,
  FileAssetKind.blueprint => Icons.schema_outlined,
};

/// A folder in the left pane: a caret that opens it, and a body that selects
/// it.
///
/// The two are separate targets on purpose. Clicking a folder to see what is
/// in it and clicking it to reveal its subfolders are different intentions,
/// and a row that does both on one click does the wrong one half the time.
class _DirectoryRow extends StatelessWidget {
  const _DirectoryRow({
    required this.name,
    required this.depth,
    required this.expanded,
    required this.selected,
    required this.hasChildren,
    required this.onSelect,
    required this.onToggle,
    this.icon,
  });

  final String name;
  final int depth;
  final bool expanded;
  final bool selected;
  final bool hasChildren;
  final VoidCallback onSelect;
  final VoidCallback onToggle;

  /// Overrides the folder glyph, for a row that is not a folder on disk.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onSelect,
      child: Container(
        height: 22,
        color: selected ? editorRaisedColor : null,
        padding: EdgeInsets.only(left: depth * 12.0 + 2, right: 4),
        child: Row(
          children: [
            SizedBox(
              width: 14,
              child: hasChildren
                  ? InkWell(
                      onTap: onToggle,
                      child: Icon(
                        expanded ? Icons.arrow_drop_down : Icons.arrow_right,
                        size: 16,
                        color: editorMutedTextColor,
                      ),
                    )
                  : null,
            ),
            Icon(
              icon ??
                  (expanded
                      ? Icons.folder_open_outlined
                      : Icons.folder_outlined),
              size: 14,
              color: selected ? editorAccentColor : editorMutedTextColor,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: selected ? editorTextColor : editorMutedTextColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FileListRow extends StatelessWidget {
  const _FileListRow({
    required this.asset,
    required this.depth,
    required this.onAct,
    required this.onContextMenu,
    this.onOpenScene,
  });

  final FileAsset asset;
  final int depth;
  final Future<void> Function(FileAsset) onAct;
  final void Function(FileAsset, Offset) onContextMenu;

  /// Opens this `.fscene` in the editor (tap still instantiates as a prefab).
  final VoidCallback? onOpenScene;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: asset.relativePath,
      waitDuration: const Duration(milliseconds: 600),
      child: GestureDetector(
        onSecondaryTapUp: (d) => onContextMenu(asset, d.globalPosition),
        child: InkWell(
          onTap: () => onAct(asset),
          child: SizedBox(
            height: 26,
            child: Padding(
              padding: EdgeInsets.only(left: depth * 14.0 + 19, right: 4),
              child: Row(
                children: [
                  Icon(_fileIcon(asset.kind), size: 16, color: scheme.primary),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      asset.name,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  if (onOpenScene != null)
                    Tooltip(
                      message: 'Open scene',
                      waitDuration: const Duration(milliseconds: 400),
                      child: InkWell(
                        onTap: onOpenScene,
                        borderRadius: BorderRadius.circular(3),
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(Icons.open_in_new, size: 14),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FileThumbnailTile extends StatelessWidget {
  const _FileThumbnailTile({
    required this.asset,
    required this.onAct,
    required this.onContextMenu,
  });

  final FileAsset asset;
  final Future<void> Function(FileAsset) onAct;
  final void Function(FileAsset, Offset) onContextMenu;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: asset.relativePath,
      waitDuration: const Duration(milliseconds: 600),
      child: GestureDetector(
        onSecondaryTapUp: (d) => onContextMenu(asset, d.globalPosition),
        child: InkWell(
          onTap: () => onAct(asset),
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            width: 80,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: asset.kind == FileAssetKind.environmentImage
                      ? EnvironmentThumbnail(path: asset.path)
                      : asset.kind == FileAssetKind.image
                      ? Image.file(
                          File(asset.path),
                          fit: BoxFit.cover,
                          cacheWidth: 144,
                          errorBuilder: (_, _, _) =>
                              Icon(_fileIcon(asset.kind), size: 28),
                        )
                      : Icon(_fileIcon(asset.kind), size: 28),
                ),
                const SizedBox(height: 2),
                Text(
                  asset.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 10),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A path under [root] for a prefab called [name] that no file has yet.
///
/// The name comes from a node, and a node's name is whatever somebody typed
/// into it, so it reaches the filesystem having been nowhere near one: a node
/// called "../../etc/passwd" is a node somebody named that. Everything but
/// letters, digits, spaces, dashes and underscores goes, which leaves the
/// result inside [root] by construction rather than by checking afterwards.
String freePrefabPath(String root, String name) {
  final safe = name.replaceAll(RegExp(r'[^A-Za-z0-9_\- ]'), '').trim();
  final base = safe.isEmpty ? 'Prefab' : safe;
  final separator = Platform.pathSeparator;
  for (var i = 0; ; i++) {
    final candidate = i == 0
        ? '$root$separator$base.fscene'
        : '$root$separator$base $i.fscene';
    if (!File(candidate).existsSync()) return candidate;
  }
}
