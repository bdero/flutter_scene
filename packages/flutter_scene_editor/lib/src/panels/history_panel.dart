import 'package:flutter/material.dart';

import '../controller/editor_controller.dart';

/// History panel: lists committed transactions with the undo cursor marked.
///
/// Shows Undo and Redo buttons and all transactions oldest-first. The entry
/// at [history.cursor - 1] is the most-recently applied one.
class HistoryPanel extends StatelessWidget {
  const HistoryPanel({super.key, required this.controller});

  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final history = controller.history;
        final transactions = history.transactions;
        final cursor = history.cursor;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Undo/redo buttons.
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.undo, size: 18),
                  tooltip: history.canUndo
                      ? 'Undo: ${history.undoLabel}'
                      : 'Nothing to undo',
                  onPressed: history.canUndo ? controller.undo : null,
                ),
                IconButton(
                  icon: const Icon(Icons.redo, size: 18),
                  tooltip: history.canRedo
                      ? 'Redo: ${history.redoLabel}'
                      : 'Nothing to redo',
                  onPressed: history.canRedo ? controller.redo : null,
                ),
              ],
            ),
            const VerticalDivider(width: 1),
            // Transaction list (scrollable).
            Expanded(
              child: transactions.isEmpty
                  ? const Center(
                      child: Text(
                        'No history',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: transactions.length,
                      itemBuilder: (context, index) {
                        final tx = transactions[index];
                        final isApplied = index < cursor;
                        final isCursor = index == cursor - 1;
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 2,
                            vertical: 4,
                          ),
                          child: Chip(
                            label: Text(
                              tx.name,
                              style: TextStyle(
                                fontSize: 10,
                                color: isApplied ? null : Colors.grey,
                                fontWeight: isCursor
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                            backgroundColor: isCursor
                                ? Theme.of(context).colorScheme.primaryContainer
                                : isApplied
                                ? null
                                : Theme.of(
                                    context,
                                  ).colorScheme.surfaceContainerHighest,
                            side: isCursor
                                ? BorderSide(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  )
                                : BorderSide.none,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 0,
                            ),
                            labelPadding: EdgeInsets.zero,
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}
