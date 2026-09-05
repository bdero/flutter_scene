/// The Console: what the build and the running session said.
///
/// A log with the three things that make a log usable. **Collapse**, because a
/// build prints the same warning forty times and forty rows of it is a console
/// you scroll past. **Counters that filter**, because the question is almost
/// always "did anything fail", and the answer should be one glance and one
/// click. And a **detail pane**, because the row shows one line and the thing
/// you need is usually on the third.
library;

import 'package:flutter/material.dart';

import '../project/app_session.dart';
import '../project/project_runner.dart';
import '../shell/editor_theme.dart';
import 'console_model.dart';

/// The Console panel.
class ConsolePanel extends StatefulWidget {
  const ConsolePanel({super.key, required this.runner, this.session});

  final ProjectRunner runner;
  final AppSession? session;

  @override
  State<ConsolePanel> createState() => _ConsolePanelState();
}

class _ConsolePanelState extends State<ConsolePanel> {
  final ScrollController _scroll = ScrollController();

  bool _collapse = false;

  /// Which severities are shown. All three, until a counter is clicked.
  final Set<ConsoleSeverity> _shown = {...ConsoleSeverity.values};

  String _query = '';

  /// The selected row, by where its first line sits in the raw output.
  ///
  /// By index rather than by row, so the selection survives collapsing,
  /// filtering, and more output arriving underneath it.
  int? _selected;

  @override
  void initState() {
    super.initState();
    widget.runner.addListener(_onOutput);
  }

  @override
  void didUpdateWidget(ConsolePanel old) {
    super.didUpdateWidget(old);
    if (old.runner != widget.runner) {
      old.runner.removeListener(_onOutput);
      widget.runner.addListener(_onOutput);
    }
  }

  @override
  void dispose() {
    widget.runner.removeListener(_onOutput);
    _scroll.dispose();
    super.dispose();
  }

  void _onOutput() {
    if (!mounted) return;
    setState(() {});
    // Follow the tail, but only from the tail: scrolling up to read something
    // and being yanked back down by the next line is the worst thing a
    // console does.
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.pixels >= position.maxScrollExtent - 24) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    }
  }

  void _toggle(ConsoleSeverity severity) => setState(() {
    if (!_shown.remove(severity)) _shown.add(severity);
  });

  @override
  Widget build(BuildContext context) {
    final runner = widget.runner;
    final counts = countBySeverity(runner.console);
    final rows = consoleRows(
      runner.console,
      collapse: _collapse,
      shown: _shown,
      query: _query,
    );
    final selected = _selected == null
        ? null
        : rows.where((row) => row.firstIndex == _selected).firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EditorToolbar(
          leading: [
            _Action(label: 'Clear', onPressed: runner.clearConsole),
            const SizedBox(width: 4),
            _Toggle(
              label: 'Collapse',
              value: _collapse,
              tooltip:
                  'Group identical messages, however far apart. The same '
                  'warning from forty files is one thing wrong.',
              onChanged: (value) => setState(() => _collapse = value),
            ),
            const SizedBox(width: 8),
            if (runner.building)
              _Action(label: 'Stop build', onPressed: runner.stopBuild),
            if (widget.session case final session? when session.active)
              _Action(label: 'Stop', onPressed: session.stop),
          ],
          trailing: [
            SizedBox(
              width: 150,
              height: 22,
              child: TextField(
                style: editorBodyText,
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'Search',
                  hintStyle: editorDetailText,
                  prefixIcon: Icon(Icons.search, size: 13),
                  prefixIconConstraints: BoxConstraints.tightFor(
                    width: 22,
                    height: 18,
                  ),
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 4),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            const SizedBox(width: 8),
            for (final severity in ConsoleSeverity.values)
              _Counter(
                severity: severity,
                count: switch (severity) {
                  ConsoleSeverity.info => counts.info,
                  ConsoleSeverity.warning => counts.warning,
                  ConsoleSeverity.error => counts.error,
                },
                on: _shown.contains(severity),
                onTap: () => _toggle(severity),
              ),
          ],
        ),
        Expanded(
          child: Container(
            color: editorSurfaceColor,
            child: rows.isEmpty
                ? Center(
                    child: Text(
                      runner.console.isEmpty
                          ? 'Build or Play output appears here.'
                          : 'Nothing matches.',
                      style: editorDetailText,
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    itemCount: rows.length,
                    itemBuilder: (context, index) {
                      final row = rows[index];
                      return _Row(
                        entry: row,
                        selected: row.firstIndex == _selected,
                        onTap: () => setState(
                          () => _selected = row.firstIndex == _selected
                              ? null
                              : row.firstIndex,
                        ),
                      );
                    },
                  ),
          ),
        ),
        if (selected != null) _Detail(entry: selected),
      ],
    );
  }
}

/// The glyph and colour a severity reads as.
IconData consoleGlyph(ConsoleSeverity severity) => switch (severity) {
  ConsoleSeverity.error => Icons.error_outline,
  ConsoleSeverity.warning => Icons.warning_amber,
  ConsoleSeverity.info => Icons.info_outline,
};

Color consoleColour(ConsoleSeverity severity) => switch (severity) {
  ConsoleSeverity.error => editorErrorColor,
  ConsoleSeverity.warning => editorWarningColor,
  ConsoleSeverity.info => editorMutedTextColor,
};

class _Row extends StatelessWidget {
  const _Row({
    required this.entry,
    required this.selected,
    required this.onTap,
  });

  final ConsoleEntry entry;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      color: selected
          ? editorAccentColor.withValues(alpha: 0.16)
          : Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: Row(
        children: [
          Icon(
            consoleGlyph(entry.severity),
            size: 12,
            color: consoleColour(entry.severity),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              entry.summary,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: entry.severity == ConsoleSeverity.info
                    ? editorTextColor
                    : consoleColour(entry.severity),
              ),
            ),
          ),
          if (entry.count > 1) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: editorRaisedColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('${entry.count}', style: editorMicroText),
            ),
          ],
        ],
      ),
    ),
  );
}

/// The selected message in full, under the list.
///
/// The row shows one line and the thing you need is usually on the third.
class _Detail extends StatelessWidget {
  const _Detail({required this.entry});

  final ConsoleEntry entry;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(maxHeight: 120),
    decoration: const BoxDecoration(
      color: editorPanelColor,
      border: Border(top: BorderSide(color: editorLineColor)),
    ),
    width: double.infinity,
    child: SelectionArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(8),
        child: Text(
          entry.line.text.trimRight(),
          style: const TextStyle(
            fontSize: 11,
            fontFamily: 'monospace',
            color: editorTextColor,
          ),
        ),
      ),
    ),
  );
}

class _Counter extends StatelessWidget {
  const _Counter({
    required this.severity,
    required this.count,
    required this.on,
    required this.onTap,
  });

  final ConsoleSeverity severity;
  final int count;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: on ? 'Hide ${severity.name}' : 'Show ${severity.name}',
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(3),
      child: Container(
        margin: const EdgeInsets.only(left: 2),
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
        decoration: BoxDecoration(
          color: on ? editorRaisedColor : Colors.transparent,
          borderRadius: BorderRadius.circular(3),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              consoleGlyph(severity),
              size: 12,
              // Dimmed rather than hidden when off: a filter you cannot see
              // the state of is a console that is lying about what happened.
              color: on
                  ? consoleColour(severity)
                  : editorMutedTextColor.withValues(alpha: 0.5),
            ),
            const SizedBox(width: 3),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 10,
                color: on ? editorTextColor : editorMutedTextColor,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Action extends StatelessWidget {
  const _Action({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => TextButton(
    style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
    onPressed: onPressed,
    child: Text(label, style: const TextStyle(fontSize: 11)),
  );
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.tooltip,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final String tooltip;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(3),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: value ? editorRaisedColor : Colors.transparent,
          border: Border.all(
            color: value ? editorAccentColor : editorLineColor,
          ),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: value ? editorTextColor : editorMutedTextColor,
          ),
        ),
      ),
    ),
  );
}
