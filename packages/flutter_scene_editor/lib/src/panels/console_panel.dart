/// The Console dock panel, the streamed output of task subprocesses and the
/// Play session, with stop/clear controls.
library;

import 'package:flutter/material.dart';

import '../shell/editor_theme.dart';
import '../project/app_session.dart';
import '../project/project_runner.dart';

class ConsolePanel extends StatefulWidget {
  const ConsolePanel({super.key, required this.runner, this.session});

  final ProjectRunner runner;
  final AppSession? session;

  @override
  State<ConsolePanel> createState() => _ConsolePanelState();
}

class _ConsolePanelState extends State<ConsolePanel> {
  final _scroll = ScrollController();
  bool _pinnedToEnd = true;

  @override
  void initState() {
    super.initState();
    widget.runner.addListener(_onChanged);
    widget.session?.addListener(_onChanged);
    _scroll.addListener(() {
      if (!_scroll.hasClients) return;
      _pinnedToEnd =
          _scroll.position.pixels >= _scroll.position.maxScrollExtent - 24;
    });
  }

  @override
  void dispose() {
    widget.runner.removeListener(_onChanged);
    widget.session?.removeListener(_onChanged);
    _scroll.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    setState(() {});
    if (_pinnedToEnd) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    }
  }

  Color _colorFor(BuildContext context, ConsoleLineKind kind) {
    final scheme = Theme.of(context).colorScheme;
    return switch (kind) {
      ConsoleLineKind.command => scheme.primary,
      ConsoleLineKind.error => editorErrorColor,
      ConsoleLineKind.status => editorSuccessColor,
      ConsoleLineKind.output => scheme.onSurface,
    };
  }

  @override
  Widget build(BuildContext context) {
    final runner = widget.runner;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: editorToolbarHeight,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Row(
            children: [
              const Icon(Icons.terminal, size: 14),
              const SizedBox(width: 6),
              const Text('Console', style: TextStyle(fontSize: 12)),
              const Spacer(),
              if (runner.building)
                TextButton(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: runner.stopBuild,
                  child: const Text(
                    'Stop build',
                    style: TextStyle(fontSize: 11),
                  ),
                ),
              if (widget.session case final session? when session.active)
                TextButton(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: session.stop,
                  child: const Text('Stop', style: TextStyle(fontSize: 11)),
                ),
              IconButton(
                tooltip: 'Clear console',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.block, size: 14),
                onPressed: runner.clearConsole,
              ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            color: Theme.of(context).colorScheme.surfaceContainerLowest,
            child: runner.console.isEmpty
                ? const Center(
                    child: Text(
                      'Build or Play output appears here.',
                      style: TextStyle(
                        fontSize: 12,
                        color: editorMutedTextColor,
                      ),
                    ),
                  )
                : SelectionArea(
                    child: ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.all(8),
                      itemCount: runner.console.length,
                      itemBuilder: (context, index) {
                        final line = runner.console[index];
                        return Text(
                          line.text,
                          style: TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            color: _colorFor(context, line.kind),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}
