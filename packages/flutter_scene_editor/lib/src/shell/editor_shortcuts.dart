/// The keyboard, written down.
///
/// Every shortcut the editor binds, in one sheet reachable from the rail. A
/// tool with a keyboard and no cheat sheet is a tool where the keyboard is a
/// rumour: the tooltips carry a key each, but nobody hovers twenty buttons to
/// learn a keymap.
library;

import 'package:flutter/material.dart';

import 'editor_dialog.dart';
import 'editor_theme.dart';
import 'panel_chrome.dart';

/// One binding.
typedef EditorShortcut = ({String keys, String action});

/// A named group of bindings.
typedef EditorShortcutGroup = ({String title, List<EditorShortcut> shortcuts});

/// What the editor binds, grouped the way it is learned.
///
/// The modifier is spelled the way the platform spells it, and the list is
/// the source rather than a copy: a binding added to the shell without a line
/// here is a binding nobody finds.
List<EditorShortcutGroup> editorShortcuts({bool apple = true}) {
  final meta = apple ? '⌘' : 'Ctrl';
  return [
    (
      title: 'Tools',
      shortcuts: [
        (keys: 'W', action: 'Move'),
        (keys: 'E', action: 'Rotate'),
        (keys: 'R', action: 'Scale'),
        (keys: 'X', action: 'World or object space'),
        (keys: 'F', action: 'Frame the selection'),
      ],
    ),
    (
      title: 'Editing',
      shortcuts: [
        (keys: '$meta Z', action: 'Undo'),
        (keys: '$meta ⇧ Z', action: 'Redo'),
        (keys: '$meta C', action: 'Copy'),
        (keys: '$meta V', action: 'Paste'),
        (keys: '$meta D', action: 'Duplicate'),
        (keys: 'Delete', action: 'Delete the selection'),
      ],
    ),
    (
      title: 'The editor',
      shortcuts: [
        (keys: '$meta S', action: 'Save'),
        (keys: '$meta P', action: 'Commands'),
        (keys: 'Esc', action: 'Leave a full-screen editor'),
      ],
    ),
  ];
}

/// Shows the shortcut sheet.
Future<void> showEditorShortcuts(BuildContext context) =>
    showEditorDialog<void>(
      context,
      builder: (context) => Dialog(
        backgroundColor: editorPanelColor,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420, maxHeight: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const EditorPanelHeader(label: 'Keyboard'),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final group in editorShortcuts(
                        apple:
                            Theme.of(context).platform == TargetPlatform.macOS,
                      )) ...[
                        EditorSectionHeader(label: group.title),
                        for (final shortcut in group.shortcuts)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: editorPanelInset,
                              vertical: editorRowGap,
                            ),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 90,
                                  child: Text(
                                    shortcut.keys,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: editorValueColor,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    shortcut.action,
                                    style: editorRowLabelText,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
