import 'package:flutter/material.dart';

/// Options chosen in the glTF import dialog.
class GlbImportOptions {
  const GlbImportOptions({this.compressTextures = false});

  /// Whether to compress imported textures during the import.
  final bool compressTextures;
}

/// Shows the glTF import configuration dialog and returns the chosen
/// [GlbImportOptions], or null if the user cancels.
Future<GlbImportOptions?> showGlbImportOptions(BuildContext context) {
  return showDialog<GlbImportOptions>(
    context: context,
    builder: (context) {
      var compressTextures = false;
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Import glTF'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Import the model into a new editable scene. Save it as a '
                  '.fscene when you are done.',
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: compressTextures,
                  onChanged: (v) =>
                      setState(() => compressTextures = v ?? false),
                  title: const Text('Compress textures'),
                  subtitle: const Text(
                    'Smaller GPU memory, slightly slower import.',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(
                  context,
                ).pop(GlbImportOptions(compressTextures: compressTextures)),
                child: const Text('Import'),
              ),
            ],
          );
        },
      );
    },
  );
}
