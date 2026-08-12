/// Generates fscene codecs for every annotated component under a project's
/// `lib/`, plus the project registrar and the component manifest.
///
/// Usage, `dart run flutter_scene_codegen:generate [projectRoot]` (the
/// current directory by default). Writes `<file>.fscene.dart` beside each
/// source file containing annotated components,
/// `lib/src/fscene_registrar.g.dart`, and `flutter_scene_components.json`
/// at the project root. Only files whose content changed are rewritten.
library;

import 'dart:io';

import 'package:flutter_scene_codegen/flutter_scene_codegen.dart';

void main(List<String> args) {
  if (args.length > 1 || args.contains('--help') || args.contains('-h')) {
    stderr.writeln(
      'Usage: dart run flutter_scene_codegen:generate [projectRoot]',
    );
    exit(args.length > 1 ? 64 : 0);
  }
  final root = args.isEmpty ? '.' : args.first;

  final ProjectGenerationResult result;
  try {
    result = generateProjectComponents(root);
  } on ArgumentError catch (e) {
    stderr.writeln(e.message);
    exit(64);
  }

  for (final diagnostic in result.diagnostics) {
    stderr.writeln(diagnostic);
  }
  for (final path in result.filesWritten) {
    stdout.writeln('wrote $path');
  }
  if (result.schemas.isEmpty) {
    stdout.writeln('No annotated components found under $root/lib');
  }
  stdout.writeln(
    'Generated ${result.schemas.length} component schema(s); '
    '${result.filesWritten.length} file(s) written.',
  );
  if (result.hadErrors) exit(1);
}
