import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../shell/editor_theme.dart';
import '../io/scene_io.dart';
import 'asset_index.dart';
import 'environment_thumbnail.dart';
import '../shell/editor_dialog.dart';

/// Picks an existing project environment image or imports one from disk.
Future<String?> showEnvironmentImagePicker(
  BuildContext context, {
  required String? projectDirectory,
  String? selectedPath,
}) async {
  final assets = projectDirectory == null
      ? const <FileAsset>[]
      : (await scanProjectAssets(projectDirectory))
            .where((asset) => asset.kind == FileAssetKind.environmentImage)
            .toList();
  if (!context.mounted) return null;
  return showEditorDialog<String>(
    context,
    builder: (context) => Dialog(
      child: _EnvironmentImagePickerDialog(
        assets: assets,
        selectedPath: selectedPath,
        projectDirectory: projectDirectory,
      ),
    ),
  );
}

class _EnvironmentImagePickerDialog extends StatefulWidget {
  const _EnvironmentImagePickerDialog({
    required this.assets,
    required this.selectedPath,
    required this.projectDirectory,
  });

  final List<FileAsset> assets;
  final String? selectedPath;
  final String? projectDirectory;

  @override
  State<_EnvironmentImagePickerDialog> createState() =>
      _EnvironmentImagePickerDialogState();
}

class _EnvironmentImagePickerDialogState
    extends State<_EnvironmentImagePickerDialog> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    final path = await pickEnvironmentPath(
      initialDirectory: widget.projectDirectory,
    );
    if (path != null && mounted) Navigator.of(context).pop(path);
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final assets = query.isEmpty
        ? widget.assets
        : widget.assets
              .where(
                (asset) =>
                    asset.name.toLowerCase().contains(query) ||
                    asset.relativePath.toLowerCase().contains(query),
              )
              .toList();
    return SizedBox(
      width: 620,
      height: 500,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Choose environment image',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            FTextField(
              control: FTextFieldControl.managed(
                controller: _search,
                onChange: (value) => setState(() => _query = value.text),
              ),
              size: .sm,
              hint: 'Filter HDR and EXR assets',
              autofocus: true,
            ),
            const SizedBox(height: 10),
            Expanded(
              child: assets.isEmpty
                  ? const Center(
                      child: Text(
                        'No HDR or EXR images found in this project.',
                        style: TextStyle(
                          fontSize: 12,
                          color: editorMutedTextColor,
                        ),
                      ),
                    )
                  : GridView.builder(
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 170,
                            mainAxisExtent: 112,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                          ),
                      itemCount: assets.length,
                      itemBuilder: (context, index) {
                        final asset = assets[index];
                        return _EnvironmentImageTile(
                          asset: asset,
                          selected: asset.path == widget.selectedPath,
                          onPressed: () =>
                              Navigator.of(context).pop(asset.path),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                FButton(
                  variant: .outline,
                  size: .xs,
                  mainAxisSize: .min,
                  onPress: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FButton(
                  size: .xs,
                  mainAxisSize: .min,
                  onPress: _import,
                  prefix: const Icon(Icons.file_open_outlined, size: 14),
                  child: const Text('Import from file…'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EnvironmentImageTile extends StatelessWidget {
  const _EnvironmentImageTile({
    required this.asset,
    required this.selected,
    required this.onPressed,
  });

  final FileAsset asset;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: asset.relativePath,
      waitDuration: const Duration(milliseconds: 500),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(5),
        child: Container(
          decoration: BoxDecoration(
            color: selected
                ? scheme.primaryContainer
                : scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: EnvironmentThumbnail(path: asset.path)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                child: Text(
                  asset.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
