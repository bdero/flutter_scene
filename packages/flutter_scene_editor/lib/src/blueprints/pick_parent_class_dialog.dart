/// The Pick Parent Class dialog, asked before a Blueprint Class is made.
///
/// Two lists, for the reason the split exists at all: a short Common list
/// that covers almost every blueprint anyone makes, and All Classes
/// underneath for the rest, searchable because the rest is long.
///
/// The question is asked up front rather than left to a property afterwards
/// because the answer decides what the blueprint's graphs can assume — which
/// events they receive, what `self` is. Changing it later is reparenting, and
/// reparenting can invalidate every node in the graph.
library;

import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../shell/editor_dialog.dart';
import '../shell/editor_theme.dart';
import 'blueprint_parents.dart';

/// Asks which class a new blueprint should extend.
///
/// Returns the chosen parent's key, or null when the dialog is dismissed —
/// dismissal cancels the whole creation, since a blueprint with no parent is
/// not a thing that can exist.
Future<String?> pickParentClass({
  required BuildContext context,
  required List<BlueprintParent> all,
  String title = 'Pick Parent Class',
}) {
  final search = TextEditingController();
  return showEditorFDialog<String>(
    context: context,
    builder: (context, style, animation) => StatefulBuilder(
      builder: (context, setLocal) {
        final query = search.text;
        final matching = [
          for (final parent in all)
            if (blueprintParentMatches(parent, query)) parent,
        ];
        return FDialog(
          animation: animation,
          builder: (context, style) => Padding(
            padding: const EdgeInsets.all(14),
            child: SizedBox(
              width: 520,
              height: 520,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(title, style: editorDialogTitleText),
                  const SizedBox(height: 12),
                  // The common few, with what each is for beside it. The
                  // sentence is the point: "Pawn" tells you nothing until
                  // somebody says what a pawn is.
                  Text('COMMON', style: editorMicroText),
                  const SizedBox(height: 6),
                  for (final parent in commonBlueprintParents)
                    _ParentRow(
                      parent: parent,
                      onTap: () => Navigator.of(context).pop(parent.key),
                    ),
                  const SizedBox(height: 14),
                  Text('ALL CLASSES', style: editorMicroText),
                  const SizedBox(height: 6),
                  FTextField(
                    control: FTextFieldControl.managed(
                      controller: search,
                      onChange: (_) => setLocal(() {}),
                    ),
                    autofocus: true,
                    hint: 'Search',
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: matching.isEmpty
                        ? Center(
                            child: Text(
                              'No class matches "$query".',
                              style: editorDetailText,
                            ),
                          )
                        : ListView.builder(
                            itemCount: matching.length,
                            itemBuilder: (context, index) => _ClassRow(
                              parent: matching[index],
                              onTap: () => Navigator.of(
                                context,
                              ).pop(matching[index].key),
                            ),
                          ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text('${matching.length} items', style: editorMicroText),
                      const Spacer(),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

/// A common parent: the name, and one line on what extending it gets you.
class _ParentRow extends StatelessWidget {
  const _ParentRow({required this.parent, required this.onTap});

  final BlueprintParent parent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(editorControlRadius),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 6),
      child: Row(
        children: [
          SizedBox(
            width: 150,
            child: Text(
              parent.label,
              style: editorBodyText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              parent.doc,
              style: editorDetailText,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    ),
  );
}

/// One row of the full class list.
class _ClassRow extends StatelessWidget {
  const _ClassRow({required this.parent, required this.onTap});

  final BlueprintParent parent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
      child: Row(
        children: [
          const Icon(Icons.data_object, size: 13, color: editorMutedTextColor),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              parent.label,
              style: editorBodyText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            parent.key,
            style: editorMicroText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    ),
  );
}
