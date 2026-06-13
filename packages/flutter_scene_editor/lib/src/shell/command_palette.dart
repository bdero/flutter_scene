import 'package:flutter/material.dart';
import 'package:flutter_scene_editor_core/flutter_scene_editor_core.dart';

import '../controller/editor_controller.dart';

/// Searchable command-palette overlay.
///
/// Lists [builtinCommands] by name and category. For no-param commands (or
/// commands whose only required param is a nodeId filled from the selection),
/// it runs immediately. Commands requiring additional user-supplied params show
/// a simple form built from [uiDescriptors].
///
/// Dismiss by pressing Escape or tapping outside.
class CommandPaletteOverlay extends StatefulWidget {
  const CommandPaletteOverlay({
    super.key,
    required this.controller,
    required this.onDismiss,
  });

  final EditorController controller;
  final VoidCallback onDismiss;

  @override
  State<CommandPaletteOverlay> createState() => _CommandPaletteOverlayState();
}

class _CommandPaletteOverlayState extends State<CommandPaletteOverlay> {
  final _search = TextEditingController();
  CommandEntry? _selected;

  List<CommandEntry> get _allCommands =>
      widget.controller.session.registry.all.toList();

  List<CommandEntry> get _filtered {
    final q = _search.text.toLowerCase();
    if (q.isEmpty) return _allCommands;
    return _allCommands
        .where(
          (c) =>
              c.name.toLowerCase().contains(q) ||
              c.category.toLowerCase().contains(q) ||
              c.doc.toLowerCase().contains(q),
        )
        .toList();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _run(CommandEntry entry) {
    final descriptors = uiDescriptors(entry);
    // Compute which params need user input (excluding nodeId when there is a
    // selection that can fill it automatically).
    final primary = widget.controller.selection.primary;
    final autoFillable = {'nodeId', 'resourceId'};
    final needsInput = descriptors
        .where(
          (d) =>
              d.required &&
              !(autoFillable.contains(d.field) && primary != null),
        )
        .toList();

    if (needsInput.isEmpty) {
      // Run immediately with auto-filled params.
      final params = <String, Object?>{};
      if (primary != null) {
        for (final d in descriptors) {
          if (d.field == 'nodeId') params['nodeId'] = primary.toToken();
        }
      }
      try {
        widget.controller.run(entry.name, params);
      } on CommandException catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(e.message),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
      widget.onDismiss();
    } else {
      setState(() => _selected = entry);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onDismiss,
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.4),
        child: Center(
          child: GestureDetector(
            onTap: () {}, // absorb taps inside the palette
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 500,
                height: 400,
                child: _selected != null
                    ? _CommandForm(
                        entry: _selected!,
                        controller: widget.controller,
                        onCancel: () => setState(() => _selected = null),
                        onRun: (params) {
                          try {
                            widget.controller.run(_selected!.name, params);
                          } on CommandException catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(e.message),
                                  duration: const Duration(seconds: 3),
                                ),
                              );
                            }
                          }
                          widget.onDismiss();
                        },
                      )
                    : _CommandList(
                        search: _search,
                        filtered: _filtered,
                        onSelect: _run,
                        onDismiss: widget.onDismiss,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CommandList extends StatelessWidget {
  const _CommandList({
    required this.search,
    required this.filtered,
    required this.onSelect,
    required this.onDismiss,
  });

  final TextEditingController search;
  final List<CommandEntry> filtered;
  final void Function(CommandEntry) onSelect;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: TextField(
            controller: search,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Search commands...',
              prefixIcon: Icon(Icons.search, size: 18),
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) {
              if (filtered.isNotEmpty) onSelect(filtered.first);
            },
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: filtered.isEmpty
              ? const Center(child: Text('No commands found'))
              : ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final cmd = filtered[index];
                    return ListTile(
                      dense: true,
                      leading: Text(
                        cmd.category,
                        style: TextStyle(
                          fontSize: 10,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      title: Text(
                        cmd.name,
                        style: const TextStyle(fontSize: 13),
                      ),
                      subtitle: Text(
                        cmd.doc,
                        style: const TextStyle(fontSize: 10),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => onSelect(cmd),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// A simple form for commands that need user-supplied parameters.
class _CommandForm extends StatefulWidget {
  const _CommandForm({
    required this.entry,
    required this.controller,
    required this.onCancel,
    required this.onRun,
  });

  final CommandEntry entry;
  final EditorController controller;
  final VoidCallback onCancel;
  final void Function(Map<String, Object?>) onRun;

  @override
  State<_CommandForm> createState() => _CommandFormState();
}

class _CommandFormState extends State<_CommandForm> {
  late final Map<String, TextEditingController> _fields;

  @override
  void initState() {
    super.initState();
    _fields = {
      for (final d in uiDescriptors(widget.entry))
        d.field: TextEditingController(text: d.defaultValue?.toString() ?? ''),
    };
    // Pre-fill nodeId from selection.
    final primary = widget.controller.selection.primary;
    if (primary != null && _fields.containsKey('nodeId')) {
      _fields['nodeId']!.text = primary.toToken();
    }
  }

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    final params = <String, Object?>{};
    for (final d in uiDescriptors(widget.entry)) {
      final text = _fields[d.field]?.text.trim() ?? '';
      if (text.isEmpty && !d.required) continue;
      params[d.field] = switch (d.type) {
        ParamType.boolean => text == 'true',
        ParamType.integer => int.tryParse(text) ?? 0,
        ParamType.number => double.tryParse(text) ?? 0.0,
        _ => text,
      };
    }
    widget.onRun(params);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.entry.name,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(
            widget.entry.doc,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              children: [
                for (final d in uiDescriptors(widget.entry))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: TextField(
                      controller: _fields[d.field],
                      decoration: InputDecoration(
                        labelText:
                            '${d.label}${d.required ? "" : " (optional)"}',
                        hintText: d.type.name,
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: widget.onCancel,
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: _submit, child: const Text('Run')),
            ],
          ),
        ],
      ),
    );
  }
}
