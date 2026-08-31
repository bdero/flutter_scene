/// The status bar: the last thing that happened, and whether anything is
/// still happening.
///
/// A strip along the bottom that is nearly always quiet, which is the point.
/// Without one, a build running in a hidden Console is a window that has gone
/// still for no reason anybody can see, and the last error is a thing you find
/// by going to look for it rather than a thing that tells you.
///
/// It says one line, never a history. Anything worth reading twice is in the
/// Console, and the whole strip is a click away from opening it.
library;

import 'package:flutter/material.dart';

import '../project/project_runner.dart';
import 'editor_theme.dart';

/// The height of the strip along the window's bottom edge.
const double editorStatusBarHeight = 22;

/// What a status line is, which decides its glyph and its colour.
enum StatusSeverity { info, warning, error }

/// The last line worth showing, or null when nothing has happened.
///
/// Errors outrank everything: an error scrolled past by chatter is an error
/// nobody saw. Otherwise it is simply the most recent line.
({String text, StatusSeverity severity})? latestStatus(
  List<ConsoleLine> console,
) {
  ConsoleLine? newest;
  for (final line in console) {
    if (line.text.trim().isEmpty) continue;
    if (line.kind == ConsoleLineKind.error) {
      newest = line;
    } else if (newest == null || newest.kind != ConsoleLineKind.error) {
      newest = line;
    }
  }
  if (newest == null) return null;
  return (
    text: newest.text.trim(),
    severity: switch (newest.kind) {
      ConsoleLineKind.error => StatusSeverity.error,
      ConsoleLineKind.status => StatusSeverity.warning,
      _ => StatusSeverity.info,
    },
  );
}

/// The strip along the bottom of the window.
class EditorStatusBar extends StatelessWidget {
  const EditorStatusBar({
    super.key,
    required this.runner,
    required this.onOpenConsole,
    this.busyLabel,
  });

  /// Where the lines come from, and what says whether a build is running.
  final ProjectRunner? runner;

  /// Opens the Console, which is what the whole strip is a shortcut to.
  final VoidCallback onOpenConsole;

  /// What else is going on, when something is: a bake, an import, a scan.
  ///
  /// Null when nothing is. A build is read from [runner] rather than passed,
  /// since the runner already knows.
  final String? busyLabel;

  static IconData _glyph(StatusSeverity severity) => switch (severity) {
    StatusSeverity.error => Icons.error_outline,
    StatusSeverity.warning => Icons.warning_amber,
    StatusSeverity.info => Icons.info_outline,
  };

  static Color _colour(StatusSeverity severity) => switch (severity) {
    StatusSeverity.error => editorErrorColor,
    StatusSeverity.warning => editorWarningColor,
    StatusSeverity.info => editorMutedTextColor,
  };

  @override
  Widget build(BuildContext context) {
    final runner = this.runner;
    return Container(
      height: editorStatusBarHeight,
      decoration: const BoxDecoration(
        color: editorPanelColor,
        border: Border(top: BorderSide(color: editorLineColor)),
      ),
      child: runner == null
          ? _content(context, null, null)
          : ListenableBuilder(
              listenable: runner,
              builder: (context, _) => _content(
                context,
                latestStatus(runner.console),
                runner.building ? 'Building' : busyLabel,
              ),
            ),
    );
  }

  Widget _content(
    BuildContext context,
    ({String text, StatusSeverity severity})? status,
    String? busy,
  ) {
    return InkWell(
      onTap: onOpenConsole,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            if (status != null) ...[
              Icon(
                _glyph(status.severity),
                size: 12,
                color: _colour(status.severity),
              ),
              const SizedBox(width: 5),
            ],
            Expanded(
              child: Text(
                // One line, and only the first of it: a stack trace in the
                // status bar is a status bar you cannot read past.
                status == null ? '' : status.text.split('\n').first,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: status == null
                      ? editorMutedTextColor
                      : _colour(status.severity),
                ),
              ),
            ),
            if (busy != null) ...[
              const SizedBox(width: 8),
              const SizedBox(
                width: 10,
                height: 10,
                child: CircularProgressIndicator(strokeWidth: 1.6),
              ),
              const SizedBox(width: 6),
              Text(busy, style: editorMicroText),
            ],
          ],
        ),
      ),
    );
  }
}
