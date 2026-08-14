// Covers the editor-command invocation builder: placeholder substitution,
// appending when absent, and shell quoting of the source path.

import 'dart:io';

import 'package:flutter_scene_editor/src/settings/open_in_editor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('replaces the placeholder with the quoted path', () {
    expect(
      buildEditorInvocation(r'code ${SOURCE_FILE}', '/p/lib/turntable.dart'),
      "code '/p/lib/turntable.dart'",
    );
  }, skip: Platform.isWindows);

  test('appends the quoted path when the placeholder is absent', () {
    expect(
      buildEditorInvocation('subl -w', '/p/lib/a.dart'),
      "subl -w '/p/lib/a.dart'",
    );
  }, skip: Platform.isWindows);

  test('quotes paths containing spaces and single quotes', () {
    expect(
      buildEditorInvocation(r'code ${SOURCE_FILE}', "/p/my lib/it's.dart"),
      r"code '/p/my lib/it'\''s.dart'",
    );
  }, skip: Platform.isWindows);
}
