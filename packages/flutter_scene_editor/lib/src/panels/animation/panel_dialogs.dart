// Dialog chrome for the Animation panel, kept out of the panel state so the
// widget stays about wiring and commands. Each helper owns one screen's UI
// and returns the user's decision; the state applies it.

part of '../animation_panel.dart';

/// The rename prompt. Returns the chosen name, or null when cancelled.
Future<String?> _promptAnimationRename(
  BuildContext context,
  String currentName,
) {
  final controller = TextEditingController(text: currentName);
  return showEditorDialog<String>(
    context,
    builder: (context) => AlertDialog(
      title: const Text('Rename animation'),
      content: TextField(
        controller: controller,
        autofocus: true,
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(controller.text),
          child: const Text('Rename'),
        ),
      ],
    ),
  );
}

/// Asks which unused paths to drop; true only on explicit confirmation.
Future<bool> _confirmCleanUnusedPaths(BuildContext context) async {
  final confirmed = await showEditorDialog<bool>(
    context,
    builder: (context) => AlertDialog(
      title: const Text('Clean unused paths'),
      content: const Text(
        'Removes every path that carries no motion: channels whose '
        'keyframes all hold the same value, channels without keyframes, '
        'and channels whose target node no longer exists.\n\n'
        'The animation keeps every path that actually animates. Undoable '
        'like any edit.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton.tonal(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Clean'),
        ),
      ],
    ),
  );
  return confirmed == true;
}

/// The walkthrough behind the header's ? button: the whole loop from
/// empty scene to playing keyframes in an app.
Future<void> _showAnimationHelpDialog(BuildContext context) {
  return showEditorDialog<void>(
    context,
    builder: (context) => AlertDialog(
      title: const Text('Animating a model'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _helpStep(
                '1 · Create',
                'Press + in this panel\'s header to create an animation '
                    '(a named clip, e.g. "Spin"). Rename it to something you '
                    'will recognize in code.',
              ),
              _helpStep(
                '2 · Pose',
                'Select a node in the Outliner and pose it with the '
                    'viewport gizmo (move / rotate / scale).',
              ),
              _helpStep(
                '3 · Key',
                'Drag the playhead in this panel to where the pose belongs, '
                    'then press Key. That captures the node\'s translation, '
                    'rotation, and scale as one keyframe.',
              ),
              _helpStep(
                '4 · Repeat',
                'Move the playhead to another time, pose again, press Key '
                    'again. Between two keys the editor interpolates smoothly; '
                    'each lane row below shows one animated property with its '
                    'keys as diamonds.',
              ),
              _helpStep(
                '5 · Preview',
                'Press Play. Scrub by dragging the timeline. Stop restores '
                    'the nodes to their authored pose (what the Outliner '
                    'shows); the viewport\'s original-pose button does the '
                    'same without touching the playhead.',
              ),
              _helpStep(
                '6 · Save & play',
                'Save the scene — keyframes persist beside the .fscene in '
                    'a .fsceneb sidecar. In your app, load the scene and play '
                    'the clip from the root\'s parsedAnimations by name '
                    '(see the flutter_scene docs on AnimationClip).',
              ),
              const SizedBox(height: 8),
              Text(
                'Every edit here is undoable (Cmd+Z) and also available to '
                'agents through the same commands.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Got it'),
        ),
      ],
    ),
  );
}

Widget _helpStep(String title, String body) => Padding(
  padding: const EdgeInsets.only(bottom: 10),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      const SizedBox(height: 2),
      Text(body, style: const TextStyle(fontSize: 12, height: 1.45)),
    ],
  ),
);
