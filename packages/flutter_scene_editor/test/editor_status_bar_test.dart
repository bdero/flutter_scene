// What the status bar says. It shows one line and only one, so which line it
// picks is the whole behaviour: an error scrolled past by chatter is an error
// nobody saw.

import 'package:flutter_scene_editor/src/project/project_runner.dart';
import 'package:flutter_scene_editor/src/shell/editor_status_bar.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('nothing to say when nothing has happened', () {
    expect(latestStatus(const []), isNull);
  });

  test('the newest line, when nothing is wrong', () {
    final status = latestStatus(const [
      ConsoleLine('first'),
      ConsoleLine('second'),
    ]);
    expect(status!.text, 'second');
    expect(status.severity, StatusSeverity.info);
  });

  test('an error outranks anything newer than it', () {
    // Output keeps coming after a failure; the failure is still the news.
    final status = latestStatus(const [
      ConsoleLine('building'),
      ConsoleLine('it broke', kind: ConsoleLineKind.error),
      ConsoleLine('tidying up'),
    ]);
    expect(status!.text, 'it broke');
    expect(status.severity, StatusSeverity.error);
  });

  test('a newer error replaces an older one', () {
    final status = latestStatus(const [
      ConsoleLine('first failure', kind: ConsoleLineKind.error),
      ConsoleLine('second failure', kind: ConsoleLineKind.error),
    ]);
    expect(status!.text, 'second failure');
  });

  test('blank lines are not news', () {
    final status = latestStatus(const [
      ConsoleLine('something'),
      ConsoleLine('   '),
      ConsoleLine(''),
    ]);
    expect(status!.text, 'something');
  });

  test('a status line reads as a warning', () {
    final status = latestStatus(const [
      ConsoleLine('reloading', kind: ConsoleLineKind.status),
    ]);
    expect(status!.severity, StatusSeverity.warning);
  });

  test('a console of nothing but blanks says nothing', () {
    expect(latestStatus(const [ConsoleLine(''), ConsoleLine('  ')]), isNull);
  });
}
