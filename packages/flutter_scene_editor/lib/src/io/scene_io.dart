import 'dart:io';

import 'package:flutter/material.dart';

import '../controller/editor_controller.dart';

/// Saves [controller]'s document to a `.fscene` file at [path].
///
/// Throws [IOException] on write failure.
Future<void> saveFscene(EditorController controller, String path) async {
  final json = controller.session.toFscene();
  await File(path).writeAsString(json);
}

/// Loads a `.fscene` file from [path] and returns a fresh [EditorController].
///
/// Throws [IOException] on read failure and [FormatException] on bad JSON.
Future<EditorController> openFscene(String path) async {
  final source = await File(path).readAsString();
  return EditorController.fromFscene(source);
}

// ---------------------------------------------------------------------------
// Path-dialog helpers.
// ---------------------------------------------------------------------------

/// Shows a simple text-field dialog asking for a file path.
/// Returns the entered path, or null if the user cancelled.
Future<String?> promptFilePath(
  BuildContext context, {
  required String title,
  String? initial,
}) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => _FilePathDialog(title: title, initial: initial),
  );
}

class _FilePathDialog extends StatefulWidget {
  const _FilePathDialog({required this.title, this.initial});
  final String title;
  final String? initial;

  @override
  State<_FilePathDialog> createState() => _FilePathDialogState();
}

class _FilePathDialogState extends State<_FilePathDialog> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initial ?? '');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'File path',
          hintText: '/path/to/scene.fscene',
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        TextButton(onPressed: _submit, child: const Text('OK')),
      ],
    );
  }

  void _submit() {
    final path = _ctrl.text.trim();
    if (path.isNotEmpty) Navigator.of(context).pop(path);
  }
}
