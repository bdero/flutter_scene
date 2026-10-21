import 'dart:convert';
import 'dart:io';

import 'package:flutter_scene_mcp/coverage_host.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  late File report;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('flutter-scene-coverage-');
    report = File.fromUri(root.uri.resolve('coverage/report/summary.json'));
    await report.parent.create(recursive: true);
  });
  tearDown(() async => root.delete(recursive: true));

  test(
    'reads actual file, retains revision and recomputes percentage from counts',
    () async {
      await report.writeAsString(
        jsonEncode({
          'revision': 'measured-sha',
          'packages': [
            {
              'package': 'app',
              'hit': 3,
              'found': 4,
              'percent': 100,
              'files': ['lib/main.dart'],
            },
          ],
        }),
      );
      final summary = await readProjectTestCoverage(root.path);
      expect(summary['revision'], 'measured-sha');
      final package = (summary['packages'] as List).single as Map;
      expect(package['percent'], 75.0);
      expect(package.containsKey('files'), isFalse);
      final detailed = await readProjectTestCoverage(
        root.path,
        includeFiles: true,
      );
      expect(((detailed['packages'] as List).single as Map)['files'], [
        'lib/main.dart',
      ]);
    },
  );

  test(
    'missing, malformed, empty and impossible denominators fail explicitly',
    () async {
      await expectLater(
        readProjectTestCoverage(root.path),
        throwsFormatException,
      );
      for (final text in [
        '{bad',
        '{}',
        '{"packages":[]}',
        '{"packages":[{"hit":2,"found":1}]}',
        '{"packages":[{"hit":0,"found":0}]}',
      ]) {
        await report.writeAsString(text);
        await expectLater(
          readProjectTestCoverage(root.path),
          throwsFormatException,
        );
      }
    },
  );
}
