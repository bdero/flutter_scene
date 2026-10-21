import 'package:flutter_scene_mcp/flutter_scene_mcp.dart';
import 'package:test/test.dart';

void main() {
  test('coverage is advertised only when a host provider exists', () {
    expect(
      EditorToolSurface(() => null).bootstrapTools().map((t) => t.name),
      isNot(contains('get_test_coverage')),
    );
    final surface = EditorToolSurface(
      () => null,
      readTestCoverage: ({required includeFiles}) async => {},
    );
    final definition = surface.bootstrapTools().singleWhere(
      (t) => t.name == 'get_test_coverage',
    );
    expect(definition.returnsImage, isFalse);
    expect(definition.inputSchema['additionalProperties'], isFalse);
  });

  test(
    'reads latest revision and forwards file-detail choice without a document',
    () async {
      var revision = 'first';
      final choices = <bool>[];
      final surface = EditorToolSurface(
        () => null,
        readTestCoverage: ({required includeFiles}) async {
          choices.add(includeFiles);
          return {
            'revision': revision,
            'metric': 'reported Dart line coverage',
            'packages': [
              {'hit': 3, 'found': 4, 'percent': 75.0},
            ],
            if (includeFiles) 'files': ['lib/example.dart'],
          };
        },
      );
      final first = await surface.dispatch('get_test_coverage', {});
      expect(first['revision'], 'first');
      expect(first.containsKey('files'), isFalse);
      revision = 'second';
      final second = await surface.dispatch('get_test_coverage', {
        'includeFiles': true,
      });
      expect(second['revision'], 'second');
      expect(second['files'], ['lib/example.dart']);
      expect(choices, [false, true]);
    },
  );

  test('rejects unsupported arguments before calling the provider', () async {
    var calls = 0;
    final surface = EditorToolSurface(
      () => null,
      readTestCoverage: ({required includeFiles}) async {
        calls++;
        return {};
      },
    );
    for (final args in [
      {'includeFiles': 'true'},
      {'includeFiles': null},
      {'path': '/other-project'},
    ]) {
      await expectLater(
        surface.dispatch('get_test_coverage', args),
        throwsA(isA<ToolError>()),
      );
    }
    expect(calls, 0);
  });

  test(
    'missing or invalid reports are tool errors, not zero coverage',
    () async {
      await expectLater(
        EditorToolSurface(() => null).dispatch('get_test_coverage', {}),
        throwsA(isA<ToolError>()),
      );
      final surface = EditorToolSurface(
        () => null,
        readTestCoverage: ({required includeFiles}) async =>
            throw const FormatException('No measured report for this revision'),
      );
      await expectLater(
        surface.dispatch('get_test_coverage', {}),
        throwsA(
          isA<ToolError>().having(
            (e) => e.message,
            'message',
            contains('No measured report'),
          ),
        ),
      );
    },
  );
}
