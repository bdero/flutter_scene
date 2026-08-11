import 'dart:io';

import 'package:flutter_scene_editor/src/project/project_runner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('hook_log_tailer_test');
  });

  tearDown(() {
    temp.deleteSync(recursive: true);
  });

  File log(String package) {
    final dir = Directory('${temp.path}/$package/abc123')
      ..createSync(recursive: true);
    return File('${dir.path}/stderr.txt');
  }

  test('emits only lines appended after start', () {
    final file = log('flutter_scene')..writeAsStringSync('old line\n');
    final lines = <String>[];
    final tailer = HookLogTailer(temp, lines.add)..start();
    file.writeAsStringSync('old line\nnew line\n');
    tailer.stop();
    expect(lines, ['new line']);
  });

  test('rereads a truncated log from the top', () {
    final file = log('scene')..writeAsStringSync('a much longer old line\n');
    final lines = <String>[];
    final tailer = HookLogTailer(temp, lines.add)..start();
    file.writeAsStringSync('fresh\n');
    tailer.stop();
    expect(lines, ['fresh']);
  });

  test('tolerates a missing hooks_runner directory', () {
    final lines = <String>[];
    final tailer = HookLogTailer(
      Directory('${temp.path}/does_not_exist'),
      lines.add,
    )..start();
    tailer.stop();
    expect(lines, isEmpty);
  });
}
