import '../shell/editor_theme.dart';
import 'package:flutter/material.dart';

import '../controller/editor_controller.dart';

/// History panel: lists committed transactions with the undo cursor marked.
///
/// Shows Undo and Redo buttons and all transactions oldest-first. The entry
/// at [history.cursor - 1] is the most-recently applied one. The list
/// auto-scrolls to keep the undo cursor in view.
class HistoryPanel extends StatefulWidget {
  const HistoryPanel({super.key, required this.controller});

  final EditorController controller;

  @override
  State<HistoryPanel> createState() => _HistoryPanelState();
}

class _HistoryPanelState extends State<HistoryPanel> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.controller.history.addListener(_onHistoryChanged);
  }

  @override
  void didUpdateWidget(HistoryPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.history.removeListener(_onHistoryChanged);
      widget.controller.history.addListener(_onHistoryChanged);
    }
  }

  void _onHistoryChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.history.removeListener(_onHistoryChanged);
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToCursor(int cursor, int count) {
    if (!_scroll.hasClients || count == 0) return;
    final position = _scroll.position;
    final index = (cursor - 1).clamp(0, count - 1);
    final centered =
        index * _HistoryEntry.height -
        (position.viewportDimension - _HistoryEntry.height) / 2;
    _scroll.jumpTo(centered.clamp(0.0, position.maxScrollExtent));
  }

  @override
  Widget build(BuildContext context) {
    final history = widget.controller.history;
    final controller = widget.controller;
    final transactions = history.transactions;
    final cursor = history.cursor;

    // Follow the undo cursor rather than leaving the user at the redo tail.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _scrollToCursor(cursor, transactions.length),
    );

    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EditorToolbar(
          leading: [
            Text(
              transactions.isEmpty
                  ? 'No edits'
                  : '$cursor of ${transactions.length} applied',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          trailing: [
            IconButton(
              icon: const Icon(Icons.undo, size: 16),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              tooltip: history.canUndo
                  ? 'Undo: ${history.undoLabel}'
                  : 'Nothing to undo',
              onPressed: history.canUndo ? controller.undo : null,
            ),
            IconButton(
              icon: const Icon(Icons.redo, size: 16),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              tooltip: history.canRedo
                  ? 'Redo: ${history.redoLabel}'
                  : 'Nothing to redo',
              onPressed: history.canRedo ? controller.redo : null,
            ),
          ],
        ),
        Divider(height: 1, color: scheme.outlineVariant),
        Expanded(
          child: transactions.isEmpty
              ? Center(
                  child: Text(
                    'Edits will appear here',
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                )
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemExtent: _HistoryEntry.height,
                  itemCount: transactions.length,
                  itemBuilder: (context, index) {
                    final tx = transactions[index];
                    return _HistoryEntry(
                      index: index,
                      name: tx.name,
                      changeCount: tx.records.length,
                      isApplied: index < cursor,
                      isCurrent: index == cursor - 1,
                      isFirst: index == 0,
                      isLast: index == transactions.length - 1,
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _HistoryEntry extends StatelessWidget {
  const _HistoryEntry({
    required this.index,
    required this.name,
    required this.changeCount,
    required this.isApplied,
    required this.isCurrent,
    required this.isFirst,
    required this.isLast,
  });

  static const double height = 32;

  final int index;
  final String name;
  final int changeCount;
  final bool isApplied;
  final bool isCurrent;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = isCurrent
        ? scheme.onSurface
        : isApplied
        ? scheme.onSurface.withValues(alpha: 0.78)
        : scheme.onSurfaceVariant.withValues(alpha: 0.52);
    final rail = isApplied
        ? scheme.primary.withValues(alpha: isCurrent ? 1 : 0.5)
        : scheme.outlineVariant;

    return Container(
      color: isCurrent
          ? scheme.primary.withValues(alpha: 0.09)
          : Colors.transparent,
      padding: const EdgeInsets.only(right: 10),
      child: Row(
        children: [
          SizedBox(
            width: 38,
            child: Text(
              '${index + 1}',
              maxLines: 1,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: isCurrent ? scheme.primary : scheme.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
                fontSize: 10,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 13,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (!isFirst)
                  Positioned(
                    top: 0,
                    bottom: height / 2,
                    child: Container(width: 1, color: rail),
                  ),
                if (!isLast)
                  Positioned(
                    top: height / 2,
                    bottom: 0,
                    child: Container(width: 1, color: rail),
                  ),
                Container(
                  width: isCurrent ? 9 : 6,
                  height: isCurrent ? 9 : 6,
                  decoration: BoxDecoration(
                    color: isCurrent ? scheme.primary : rail,
                    shape: BoxShape.circle,
                    border: isCurrent
                        ? Border.all(color: scheme.surface, width: 2)
                        : null,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: foreground,
                fontSize: 11,
                fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$changeCount ${changeCount == 1 ? 'change' : 'changes'}',
            maxLines: 1,
            style: TextStyle(
              color: foreground.withValues(alpha: 0.65),
              fontFeatures: const [FontFeature.tabularFigures()],
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}
