/// Launching a source file in the user's configured editor.
library;

import 'dart:io';

/// The placeholder an editor command carries for the file to open.
const String kSourceFilePlaceholder = r'${SOURCE_FILE}';

/// Single-quotes [path] for the editor-command shells. Both interpreters
/// treat single-quoted strings as fully literal: POSIX sh, and PowerShell on
/// Windows (where cmd.exe would expand `%...%` even inside double quotes).
String quoteEditorCommandPath(String path) => Platform.isWindows
    ? "'${path.replaceAll("'", "''")}'"
    : "'${path.replaceAll("'", r"'\''")}'";

/// Expands [command] for [sourceFile]: the placeholder is replaced with the
/// shell-quoted path, and when the command carries no placeholder the quoted
/// path is appended as a final argument.
String buildEditorInvocation(String command, String sourceFile) {
  final quoted = quoteEditorCommandPath(sourceFile);
  if (command.contains(kSourceFilePlaceholder)) {
    return command.replaceAll(kSourceFilePlaceholder, quoted);
  }
  return '$command $quoted';
}

/// Runs [command] for [sourceFile] detached, through a shell that resolves
/// commands a GUI-launched app's environment lacks: a login shell for PATH
/// entries like VS Code's `code` on POSIX, and PowerShell on Windows (it
/// resolves `.cmd` shims and, unlike cmd.exe, never expands `%...%` inside
/// quoted paths).
Future<void> openSourceInEditor(String command, String sourceFile) async {
  final invocation = buildEditorInvocation(command, sourceFile);
  if (Platform.isWindows) {
    await Process.start('powershell.exe', [
      '-NoProfile',
      '-Command',
      invocation,
    ], mode: ProcessStartMode.detached);
    return;
  }
  await Process.start('/bin/sh', [
    '-lc',
    invocation,
  ], mode: ProcessStartMode.detached);
}
