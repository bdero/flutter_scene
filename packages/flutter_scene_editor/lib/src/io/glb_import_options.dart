import 'package:flutter/material.dart';

/// The up axis the imported model was authored in. glTF is Y-up by spec, so
/// [yUp] is the default and a no-op; [zUp] adds a corrective rotation.
enum ImportUpAxis { yUp, zUp }

/// Options chosen in the glTF import dialog.
class GlbImportOptions {
  const GlbImportOptions({
    this.compressTextures = false,
    this.scale = 1.0,
    this.upAxis = ImportUpAxis.yUp,
  });

  /// Whether to compress imported textures during the import.
  final bool compressTextures;

  /// A uniform scale applied to the imported content (1.0 leaves it as-is).
  final double scale;

  /// The up axis to interpret the imported model in.
  final ImportUpAxis upAxis;
}

/// Shows the glTF import configuration dialog and returns the chosen
/// [GlbImportOptions], or null if the user cancels.
Future<GlbImportOptions?> showGlbImportOptions(BuildContext context) {
  return showDialog<GlbImportOptions>(
    context: context,
    builder: (context) => const _GlbImportDialog(),
  );
}

class _GlbImportDialog extends StatefulWidget {
  const _GlbImportDialog();

  @override
  State<_GlbImportDialog> createState() => _GlbImportDialogState();
}

class _GlbImportDialogState extends State<_GlbImportDialog> {
  final _scale = TextEditingController(text: '1.0');
  bool _compressTextures = false;
  ImportUpAxis _upAxis = ImportUpAxis.yUp;

  @override
  void dispose() {
    _scale.dispose();
    super.dispose();
  }

  void _import() {
    final parsed = double.tryParse(_scale.text.trim());
    final scale = (parsed == null || parsed <= 0) ? 1.0 : parsed;
    Navigator.of(context).pop(
      GlbImportOptions(
        compressTextures: _compressTextures,
        scale: scale,
        upAxis: _upAxis,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Import glTF'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Import the model into the current scene. Save it as a .fscene '
            'when you are done.',
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const SizedBox(width: 80, child: Text('Scale')),
              Expanded(
                child: TextField(
                  controller: _scale,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const SizedBox(width: 80, child: Text('Up axis')),
              SegmentedButton<ImportUpAxis>(
                segments: const [
                  ButtonSegment(value: ImportUpAxis.yUp, label: Text('Y up')),
                  ButtonSegment(value: ImportUpAxis.zUp, label: Text('Z up')),
                ],
                selected: {_upAxis},
                onSelectionChanged: (s) => setState(() => _upAxis = s.first),
              ),
            ],
          ),
          const SizedBox(height: 4),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _compressTextures,
            onChanged: (v) => setState(() => _compressTextures = v ?? false),
            title: const Text('Compress textures'),
            subtitle: const Text('Smaller GPU memory, slightly slower import.'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _import, child: const Text('Import')),
      ],
    );
  }
}
