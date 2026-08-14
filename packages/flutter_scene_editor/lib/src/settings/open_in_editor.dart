/// Launching a source file in the user's configured editor.
library;

import 'dart:io';

/// The placeholder an editor command carries for the file to open.
const String kSourceFilePlaceholder = r'${SOURCE_FILE}';

/// Expands [command] for [sourceFile]: the placeholder is replaced with the
/// shell-quoted path, and when the command carries no placeholder the quoted
/// path is appended as a final argument.
String buildEditorInvocation(String command, String sourceFile) {
  final quoted = Platform.isWindows
      ? '"$sourceFile"'
      : "'${sourceFile.replaceAll("'", r"'\''")}'";
  if (command.contains(kSourceFilePlaceholder)) {
    return command.replaceAll(kSourceFilePlaceholder, quoted);
  }
  return '$command $quoted';
}

/// Runs [command] for [sourceFile] detached, through a login shell so PATH
/// entries a GUI-launched app lacks (VS Code's `code`) still resolve.
Future<void> openSourceInEditor(String command, String sourceFile) async {
  final invocation = buildEditorInvocation(command, sourceFile);
  if (Platform.isWindows) {
    await Process.start('cmd.exe', [
      '/c',
      invocation,
    ], mode: ProcessStartMode.detached);
    return;
  }
  await Process.start('/bin/sh', [
    '-lc',
    invocation,
  ], mode: ProcessStartMode.detached);
}
