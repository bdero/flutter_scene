import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
// ignore: implementation_imports
import 'package:scene/scene.dart';
import '../shell/editor_dialog.dart';

typedef ReferencePickerEntry = ({LocalId id, String label});

/// A compact reference field whose options are built only while it is open.
class ReferencePicker extends StatelessWidget {
  const ReferencePicker({
    super.key,
    required this.entries,
    required this.value,
    required this.emptyLabel,
    required this.onChanged,
  });

  final List<ReferencePickerEntry> entries;
  final LocalId? value;
  final String emptyLabel;
  final ValueChanged<LocalId> onChanged;

  String get _valueLabel {
    for (final entry in entries) {
      if (entry.id == value) return entry.label;
    }
    return 'Pick…';
  }

  Future<void> _open(BuildContext context) async {
    final selected = await showEditorDialog<LocalId>(
      context,
      builder: (context) {
        final colors = context.theme.colors;
        return Dialog(
          backgroundColor: colors.card,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: colors.border),
            borderRadius: BorderRadius.circular(5),
          ),
          child: _ReferencePickerDialog(entries: entries, selected: value),
        );
      },
    );
    if (selected != null) onChanged(selected);
  }

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return Text(
        emptyLabel,
        style: const TextStyle(fontSize: 11, color: Colors.grey),
      );
    }
    return FButton(
      variant: .outline,
      size: .xs,
      mainAxisAlignment: .spaceBetween,
      onPress: () => _open(context),
      suffix: const Icon(Icons.unfold_more, size: 13),
      child: Flexible(
        child: Text(
          _valueLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11),
        ),
      ),
    );
  }
}

class _ReferencePickerDialog extends StatefulWidget {
  const _ReferencePickerDialog({required this.entries, required this.selected});

  final List<ReferencePickerEntry> entries;
  final LocalId? selected;

  @override
  State<_ReferencePickerDialog> createState() => _ReferencePickerDialogState();
}

class _ReferencePickerDialogState extends State<_ReferencePickerDialog> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final filtered = query.isEmpty
        ? widget.entries
        : [
            for (final entry in widget.entries)
              if (entry.label.toLowerCase().contains(query) ||
                  entry.id.toToken().toLowerCase().contains(query))
                entry,
          ];
    return SizedBox(
      width: 520,
      height: 560,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Select reference',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            FTextField(
              control: FTextFieldControl.managed(
                controller: _search,
                onChange: (value) => setState(() => _query = value.text),
              ),
              size: .sm,
              hint: 'Filter by name or id',
              autofocus: true,
            ),
            const SizedBox(height: 10),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(child: Text('No matching references'))
                  : ListView.builder(
                      itemExtent: 30,
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final entry = filtered[index];
                        return _ReferencePickerRow(
                          entry: entry,
                          selected: entry.id == widget.selected,
                          onPressed: () => Navigator.of(context).pop(entry.id),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: FButton(
                variant: .outline,
                size: .xs,
                mainAxisSize: .min,
                onPress: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReferencePickerRow extends StatefulWidget {
  const _ReferencePickerRow({
    required this.entry,
    required this.selected,
    required this.onPressed,
  });

  final ReferencePickerEntry entry;
  final bool selected;
  final VoidCallback onPressed;

  @override
  State<_ReferencePickerRow> createState() => _ReferencePickerRowState();
}

class _ReferencePickerRowState extends State<_ReferencePickerRow> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final highlighted = widget.selected || _hovered || _focused;
    return Semantics(
      button: true,
      selected: widget.selected,
      label: widget.entry.label,
      child: ExcludeSemantics(
        child: FocusableActionDetector(
          onShowHoverHighlight: (value) => setState(() => _hovered = value),
          onShowFocusHighlight: (value) => setState(() => _focused = value),
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                widget.onPressed();
                return null;
              },
            ),
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onPressed,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: highlighted ? colors.secondary : Colors.transparent,
                borderRadius: BorderRadius.circular(3),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 18,
                      child: widget.selected
                          ? const Icon(Icons.check, size: 13)
                          : null,
                    ),
                    Expanded(
                      child: Text(
                        widget.entry.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
