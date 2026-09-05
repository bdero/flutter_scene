/// Scene settings as a File-menu dialog.
///
/// These are the scene's own settings -- its environment lighting, its
/// background, its color management and its render toggles -- and they belong
/// with the scene's other File-level concerns rather than in the inspector.
/// The inspector inspects what is selected; standing in for it whenever
/// nothing was made scene settings the thing you saw by accident and the
/// selected node the thing you had to go looking for.
library;

import 'package:flutter/material.dart';

import '../controller/editor_controller.dart';
import '../shell/editor_dialog.dart';
import '../shell/editor_theme.dart';
import 'stage_section.dart';

/// Opens the scene settings over the shell.
Future<void> showSceneSettings(
  BuildContext context, {
  required EditorController controller,
}) => showEditorDialog<void>(
  context,
  builder: (context) => _SceneSettingsDialog(controller: controller),
);

class _SceneSettingsDialog extends StatelessWidget {
  const _SceneSettingsDialog({required this.controller});

  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Scene Settings', style: editorDialogTitleText),
      contentPadding: const EdgeInsets.fromLTRB(0, 4, 0, 0),
      content: SizedBox(
        width: 560,
        // Tall enough to work in without being taller than a laptop screen;
        // the section list scrolls inside it.
        height: 560,
        // Every edit inside runs a command against the live document, so the
        // dialog has nothing to apply on close and nothing to cancel.
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => StageSection(controller: controller),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
