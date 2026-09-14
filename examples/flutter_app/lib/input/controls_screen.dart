import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_scene_input/flutter_scene_input.dart';

/// One row of [ControlsScreen]: an action and the name shown for it.
class ControlsEntry {
  const ControlsEntry(this.action, this.label);

  final InputAction action;
  final String label;
}

/// A reference rebinding screen: every action's keyboard and gamepad
/// bindings, click any control to listen for a new one, with conflict
/// resolution, per-action reset, and the saved profile JSON.
class ControlsScreen extends StatefulWidget {
  const ControlsScreen({
    super.key,
    required this.player,
    required this.set,
    required this.entries,
  });

  final PlayerInput player;
  final ActionSet set;
  final List<ControlsEntry> entries;

  /// Opens the screen in a dialog.
  static Future<void> show(
    BuildContext context, {
    required PlayerInput player,
    required ActionSet set,
    required List<ControlsEntry> entries,
  }) => showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      child: ControlsScreen(player: player, set: set, entries: entries),
    ),
  );

  @override
  State<ControlsScreen> createState() => _ControlsScreenState();
}

class _ControlsScreenState extends State<ControlsScreen> {
  BindingLocation? _listening;
  RebindOperation? _operation;

  @override
  void initState() {
    super.initState();
    widget.player.addBindingsListener(_changed);
  }

  @override
  void dispose() {
    _operation?.cancel();
    widget.player.removeBindingsListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _listen(InputAction action, String slot, String? part) async {
    _operation?.cancel();
    final operation = widget.player.listenForBinding(
      action,
      slot: slot,
      part: part,
      set: widget.set,
    );
    setState(() {
      _operation = operation;
      _listening = operation.location;
    });
    final result = await operation.result;
    if (!mounted || !identical(_operation, operation)) return;
    setState(() {
      _operation = null;
      _listening = null;
    });
    if (result.status != RebindStatus.bound) return;
    if (result.conflicts.isEmpty) {
      result.apply();
      return;
    }
    final resolution = await _askResolution(result);
    if (resolution != null) result.apply(resolution: resolution);
  }

  Future<ConflictResolution?> _askResolution(RebindResult result) {
    final control = widget.player.controlLabel(result.control!);
    final others = result.conflicts
        .map((c) => '${c.location.action.name} (${c.location.slot})')
        .join(', ');
    return showDialog<ConflictResolution>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$control is already bound'),
        content: Text('It is used by $others.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(context, ConflictResolution.allowDuplicate),
            child: const Text('Keep both'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, ConflictResolution.swap),
            child: const Text('Swap'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, ConflictResolution.replace),
            child: const Text('Replace'),
          ),
        ],
      ),
    );
  }

  void _showProfile() {
    unawaited(
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Saved profile'),
          content: SingleChildScrollView(
            child: SelectableText(
              widget.player.overrides.toJsonString(),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _slot(InputAction action, String slot) {
    final display = widget.player.bindingDisplay(
      action,
      slot: slot,
      set: widget.set,
    );
    if (display == null) return const SizedBox.shrink();
    final parts = display.controls;
    // A slot with named parts rebinds each part; otherwise the whole slot.
    final chips = parts.isEmpty
        ? [(null, 'Unbound')]
        : [
            for (final label in parts)
              if (parts.length == 1 || label.part != null)
                (label.part, label.label),
          ];
    return Wrap(
      spacing: 4,
      children: [
        for (final (part, label) in chips)
          ActionChip(
            label: Text(
              _listening == BindingLocation(widget.set, action, slot, part)
                  ? 'Press...'
                  : label,
            ),
            onPressed: () => unawaited(_listen(action, slot, part)),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640, maxHeight: 520),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Controls', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Click a control, then press the new key or button. Esc or '
              'Start cancels.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: Table(
                  columnWidths: const {
                    0: IntrinsicColumnWidth(),
                    3: IntrinsicColumnWidth(),
                  },
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                  children: [
                    for (final entry in widget.entries)
                      TableRow(
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: Text(entry.label),
                          ),
                          for (final slot in ['keyboard', 'gamepad'])
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: _slot(entry.action, slot),
                            ),
                          IconButton(
                            tooltip: 'Reset',
                            icon: const Icon(Icons.restart_alt),
                            onPressed: () => widget.player.overrides.reset(
                              entry.action,
                              set: widget.set,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton(
                  onPressed: widget.player.overrides.resetAll,
                  child: const Text('Reset all'),
                ),
                TextButton(
                  onPressed: _showProfile,
                  child: const Text('Show profile'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Done'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
