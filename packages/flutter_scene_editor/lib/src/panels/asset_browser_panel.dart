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

import 'dart:io';

import 'package:flutter/material.dart';

import '../assets/asset_index.dart';
import '../controller/editor_controller.dart';
import '../assets/environment_thumbnail.dart';
import '../io/scene_io.dart';

/// The asset browser panel.
class AssetBrowserPanel extends StatefulWidget {
  const AssetBrowserPanel({
    super.key,
    required this.controller,
    required this.onImportModel,
  });

  final EditorController controller;

  /// Imports a raw glTF model file (`.glb`/`.gltf`); the shell shows the import
  /// options dialog. `.fscene`/`.fsceneb` are instantiated directly as prefabs.
  final Future<void> Function(String path) onImportModel;

  @override
  State<AssetBrowserPanel> createState() => _AssetBrowserPanelState();
}

class _AssetBrowserPanelState extends State<AssetBrowserPanel> {
  List<FileAsset> _files = const [];
  final Set<String> _expandedDirectories = {};
  _AssetViewMode _viewMode = _AssetViewMode.list;
  bool _scanning = false;
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
    }
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onDocChanged);
    _ctrl.history.removeListener(_onHistoryChanged);
    super.dispose();
  }

  void _onDocChanged() {
    if (_ctrl.baseDirectory != _scannedDir) {
      _rescan();
    }
  }

  void _onHistoryChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _rescan() async {
    final dir = _ctrl.baseDirectory;
    _scannedDir = dir;
    if (dir == null) {
      setState(() => _files = const []);
      return;
    }
    setState(() => _scanning = true);
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

    final models = visibleFiles
        .where((f) => f.kind == FileAssetKind.model)
        .toList();
    final scenes = visibleFiles
        .where((f) => f.kind == FileAssetKind.scene)
        .toList();
    final environmentImages = visibleFiles
        .where((f) => f.kind == FileAssetKind.environmentImage)
        .toList();
    final images = visibleFiles
        .where((f) => f.kind == FileAssetKind.image)
        .toList();
    final embedded = embeddedResources(
      _ctrl.document,
    ).where((r) => q.isEmpty || r.label.toLowerCase().contains(q)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _toolbar(context),
        if (_ctrl.baseDirectory == null)
          const Expanded(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Save the scene to browse project assets.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          )
        else
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              children: [
                if (_viewMode == _AssetViewMode.list)
                  _fileTree(context, visibleFiles, searching: q.isNotEmpty)
                else ...[
                  _fileSection(context, 'Models', models),
                  _fileSection(context, 'Scenes', scenes),
                  _fileSection(
                    context,
                    'Environment images',
                    environmentImages,
                  ),
                  _fileSection(context, 'Images', images),
                ],
                _embeddedSection(context, embedded),
              ],
            ),
          ),
      ],
    );
  }

  Widget _toolbar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          const Icon(Icons.folder_open, size: 14),
          const SizedBox(width: 6),
          const Text('Assets', style: TextStyle(fontSize: 12)),
          const SizedBox(width: 12),
          Expanded(
            child: SizedBox(
              height: 26,
              child: TextField(
                style: const TextStyle(fontSize: 12),
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search, size: 14),
                  prefixIconConstraints: BoxConstraints(minWidth: 28),
                  hintText: 'Filter',
                  contentPadding: EdgeInsets.symmetric(vertical: 4),
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
          ),
          const SizedBox(width: 4),
          _viewButton(
            context,
            mode: _AssetViewMode.list,
            icon: Icons.view_list_outlined,
            tooltip: 'List view',
          ),
          _viewButton(
            context,
            mode: _AssetViewMode.thumbnails,
            icon: Icons.grid_view_outlined,
            tooltip: 'Thumbnail view',
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
      ),
    );
  }

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
            size: 15,
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _fileTree(
    BuildContext context,
    List<FileAsset> files, {
    required bool searching,
  }) {
    if (files.isEmpty) return const SizedBox.shrink();
    final root = _buildAssetTree(files);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(context, 'Project files  (${files.length})'),
        for (final directory in root.sortedDirectories)
          _directoryBranch(context, directory, depth: 0, searching: searching),
        for (final file in root.sortedFiles)
          _FileListRow(asset: file, depth: 0, onAct: _actOn),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _directoryBranch(
    BuildContext context,
    _AssetDirectory directory, {
    required int depth,
    required bool searching,
  }) {
    final expanded = searching || _expandedDirectories.contains(directory.path);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DirectoryRow(
          name: directory.name,
          depth: depth,
          expanded: expanded,
          onPressed: () => setState(() {
            if (expanded && !searching) {
              _expandedDirectories.remove(directory.path);
            } else {
              _expandedDirectories.add(directory.path);
            }
          }),
        ),
        if (expanded) ...[
          for (final child in directory.sortedDirectories)
            _directoryBranch(
              context,
              child,
              depth: depth + 1,
              searching: searching,
            ),
          for (final file in directory.sortedFiles)
            _FileListRow(asset: file, depth: depth + 1, onAct: _actOn),
        ],
      ],
    );
  }

  Widget _fileSection(
    BuildContext context,
    String title,
    List<FileAsset> items,
  ) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(context, '$title  (${items.length})'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final f in items) _FileThumbnailTile(asset: f, onAct: _actOn),
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
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
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      visualDensity: VisualDensity.compact,
      leading: Icon(_embeddedIcon(r.kind), size: 18),
      title: Text(r.label, style: const TextStyle(fontSize: 12)),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 11,
          color: r.isUnused ? Colors.orange : Colors.grey,
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
    }
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
};

/// A collapsible project directory row.
class _DirectoryRow extends StatelessWidget {
  const _DirectoryRow({
    required this.name,
    required this.depth,
    required this.expanded,
    required this.onPressed,
  });

  final String name;
  final int depth;
  final bool expanded;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onPressed,
      child: SizedBox(
        height: 26,
        child: Padding(
          padding: EdgeInsets.only(left: depth * 14.0 + 2, right: 4),
          child: Row(
            children: [
              Icon(
                expanded ? Icons.expand_more : Icons.chevron_right,
                size: 15,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 2),
              Icon(
                expanded ? Icons.folder_open_outlined : Icons.folder_outlined,
                size: 16,
                color: scheme.primary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
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
  });

  final FileAsset asset;
  final int depth;
  final Future<void> Function(FileAsset) onAct;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: asset.relativePath,
      waitDuration: const Duration(milliseconds: 600),
      child: InkWell(
        onTap: () => onAct(asset),
        child: SizedBox(
          height: 26,
          child: Padding(
            padding: EdgeInsets.only(left: depth * 14.0 + 19, right: 4),
            child: Row(
              children: [
                Icon(_fileIcon(asset.kind), size: 15, color: scheme.primary),
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FileThumbnailTile extends StatelessWidget {
  const _FileThumbnailTile({required this.asset, required this.onAct});

  final FileAsset asset;
  final Future<void> Function(FileAsset) onAct;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: asset.relativePath,
      waitDuration: const Duration(milliseconds: 600),
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
    );
  }
}
