// What the console shows. A build prints the same warning forty times, and a
// console showing forty warnings is a console you scroll past; one showing it
// once with a 40 beside it is a console you read.

import 'package:flutter_scene_editor/src/panels/console_model.dart';
import 'package:flutter_scene_editor/src/project/project_runner.dart';
import 'package:flutter_test/flutter_test.dart';

const _lines = [
  ConsoleLine('building', kind: ConsoleLineKind.command),
  ConsoleLine('unused import'),
  ConsoleLine('unused import'),
  ConsoleLine('reloading', kind: ConsoleLineKind.status),
  ConsoleLine('it broke', kind: ConsoleLineKind.error),
  ConsoleLine('unused import'),
  ConsoleLine('it broke', kind: ConsoleLineKind.error),
];

void main() {
  group('counting', () {
    test('splits into the three buckets', () {
      final counts = countBySeverity(_lines);
      expect(counts.info, 4, reason: 'command plus three outputs');
      expect(counts.warning, 1);
      expect(counts.error, 2);
    });

    test('blank lines are not counted', () {
      expect(countBySeverity(const [ConsoleLine('  ')]).info, 0);
    });

    test('counts are over everything, not over what the filter left', () {
      // A counter that dropped to zero because you filtered errors out would
      // be a counter telling you there are no errors.
      final all = countBySeverity(_lines);
      final rows = consoleRows(_lines, shown: const {ConsoleSeverity.info});
      expect(rows.every((r) => r.severity == ConsoleSeverity.info), isTrue);
      expect(countBySeverity(_lines).error, all.error);
    });
  });

  group('rows', () {
    test('uncollapsed, every line is a row', () {
      expect(consoleRows(_lines), hasLength(7));
    });

    test('collapsed, identical messages become one row with a count', () {
      final rows = consoleRows(_lines, collapse: true);
      final unused = rows.firstWhere((r) => r.line.text == 'unused import');
      expect(unused.count, 3);
      expect(rows, hasLength(4), reason: 'four distinct messages');
    });

    test('collapsing groups across the whole log, not just neighbours', () {
      // The same warning from forty files is one thing wrong, not forty.
      final rows = consoleRows(_lines, collapse: true);
      expect(rows.firstWhere((r) => r.line.text == 'it broke').count, 2);
    });

    test('a warning and an error reading alike stay two rows', () {
      const same = [
        ConsoleLine('the same words', kind: ConsoleLineKind.status),
        ConsoleLine('the same words', kind: ConsoleLineKind.error),
      ];
      expect(consoleRows(same, collapse: true), hasLength(2));
    });

    test('a collapsed row remembers where its first line was', () {
      // So a selection survives the collapse being switched off.
      final rows = consoleRows(_lines, collapse: true);
      expect(
        rows.firstWhere((r) => r.line.text == 'unused import').firstIndex,
        1,
      );
    });

    test('order follows the log, not the grouping', () {
      final rows = consoleRows(_lines, collapse: true);
      expect(rows.map((r) => r.line.text), [
        'building',
        'unused import',
        'reloading',
        'it broke',
      ]);
    });
  });

  group('filtering', () {
    test('a severity switched off drops its rows', () {
      final rows = consoleRows(_lines, shown: const {ConsoleSeverity.error});
      expect(rows, hasLength(2));
      expect(rows.every((r) => r.severity == ConsoleSeverity.error), isTrue);
    });

    test('everything off shows nothing', () {
      expect(consoleRows(_lines, shown: const {}), isEmpty);
    });

    test('search matches the text, whatever the case', () {
      expect(consoleRows(_lines, query: 'BROKE'), hasLength(2));
    });

    test('search and collapse compose', () {
      final rows = consoleRows(_lines, query: 'unused', collapse: true);
      expect(rows, hasLength(1));
      expect(rows.single.count, 3);
    });

    test('search that matches nothing gives nothing', () {
      expect(consoleRows(_lines, query: 'nonsense'), isEmpty);
    });

    test('blank lines never become rows', () {
      expect(consoleRows(const [ConsoleLine(''), ConsoleLine(' ')]), isEmpty);
    });
  });

  test('a row summarises to its first line', () {
    final rows = consoleRows(const [
      ConsoleLine('the headline\nand the stack trace\nand more'),
    ]);
    expect(rows.single.summary, 'the headline');
  });
}
