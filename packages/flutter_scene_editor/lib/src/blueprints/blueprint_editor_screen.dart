/// The Blueprint editor: a screen, not a tab.
///
/// A blueprint is a class, and editing one is a mode you enter and leave —
/// you are working on the Door, not on the level with a Door in it. Unreal
/// opens a window for exactly that reason, and a docked tab gets this wrong
/// twice: it competes for room with the panels you need while editing a
/// graph, and it makes a class look like a view of the current selection when
/// it is not.
///
/// So this takes the screen, says which blueprint it is and what it extends,
/// and gives it back when you close.
library;

import 'package:flutter/material.dart';
import 'package:scene/visual_script.dart';

import '../controller/editor_controller.dart';
import '../panels/visual_scripter_panel.dart';
import '../shell/editor_theme.dart';
import 'blueprint_file.dart';
import 'blueprint_parents.dart';

/// Opens [file] as a full-screen blueprint editor.
///
/// A route rather than a dialog: it is a place you go and come back from, so
/// Escape and the platform's back gesture should both leave, and the editor
/// underneath should still be there when you do.
Future<void> openBlueprintEditor({
  required BuildContext context,
  required EditorController controller,
  required BlueprintFile file,
}) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    fullscreenDialog: true,
    builder: (context) =>
        BlueprintEditorScreen(controller: controller, file: file),
  ),
);

/// Opens the selected node's own script as a full-screen graph editor.
///
/// The same screen, without a file: a graph that belongs to one node rather
/// than a class in the project. It is here rather than in a docked tab for the
/// same reason -- drawing a graph wants the room.
Future<void> openNodeScriptEditor({
  required BuildContext context,
  required EditorController controller,
  required String nodeName,
}) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    fullscreenDialog: true,
    builder: (context) => Scaffold(
      backgroundColor: editorSurfaceColor,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: const BoxDecoration(
              color: editorPanelColor,
              border: Border(bottom: BorderSide(color: editorLineColor)),
            ),
            child: Row(
              children: [
                const Icon(Icons.schema_outlined, size: 16),
                const SizedBox(width: 8),
                Text(nodeName, style: editorSubheadText),
                const SizedBox(width: 10),
                const _Chip(label: 'Node script'),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Text('Close'),
                ),
              ],
            ),
          ),
          Expanded(child: VisualScripterPanel(controller: controller)),
        ],
      ),
    ),
  ),
);

/// The blueprint editor screen.
class BlueprintEditorScreen extends StatelessWidget {
  const BlueprintEditorScreen({
    super.key,
    required this.controller,
    required this.file,
  });

  final EditorController controller;
  final BlueprintFile file;

  @override
  Widget build(BuildContext context) {
    final blueprint = file.read();
    return Scaffold(
      backgroundColor: editorSurfaceColor,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(
            file: file,
            blueprint: blueprint,
            controller: controller,
            onClose: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: blueprint == null
                ? _Unreadable(file: file)
                : VisualScripterPanel(controller: controller, file: file),
          ),
        ],
      ),
    );
  }
}

/// What you are editing, and the way out.
class _Header extends StatelessWidget {
  const _Header({
    required this.file,
    required this.blueprint,
    required this.controller,
    required this.onClose,
  });

  final BlueprintFile file;
  final Blueprint? blueprint;
  final EditorController controller;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final parents = allBlueprintParents(
      controller.componentTypes(),
      schemaFor: controller.componentSchemaFor,
    );
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(
        color: editorPanelColor,
        border: Border(bottom: BorderSide(color: editorLineColor)),
      ),
      child: Row(
        children: [
          const Icon(Icons.schema_outlined, size: 16),
          const SizedBox(width: 8),
          Text(file.name, style: editorSubheadText),
          const SizedBox(width: 10),
          if (blueprint != null) ...[
            _Chip(label: blueprint!.kind.label),
            const SizedBox(width: 6),
            _Chip(
              label:
                  'extends '
                  '${blueprintParentLabel(blueprint!.parentClass, parents)}',
            ),
          ],
          const Spacer(),
          Text(file.path, style: editorMicroText),
          const SizedBox(width: 12),
          TextButton(onPressed: onClose, child: const Text('Close')),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: editorRaisedColor,
      borderRadius: BorderRadius.circular(editorControlRadius),
    ),
    child: Text(label, style: editorMicroText),
  );
}

/// What the screen says when the file will not parse.
///
/// Named rather than blank: a blank canvas over a file that failed to read is
/// how you save over your own work.
class _Unreadable extends StatelessWidget {
  const _Unreadable({required this.file});

  final BlueprintFile file;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.report_gmailerrorred_outlined,
            size: 22,
            color: editorMutedTextColor,
          ),
          const SizedBox(height: 8),
          Text(
            'This blueprint could not be read.',
            style: editorBodyText,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            'Nothing has been changed on disk. Editing it here would save an '
            'empty graph over whatever is in ${file.path}.',
            style: editorDetailText,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}
