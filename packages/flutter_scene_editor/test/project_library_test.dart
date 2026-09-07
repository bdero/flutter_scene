// The launcher's model: reading project cards off disk, and how the gallery
// filters and orders them.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_scene_editor/flutter_scene_editor.dart';
import 'package:flutter_test/flutter_test.dart';

/// Writes a minimal but valid .fproject at [path], with [scenes] scene files
/// beside it, and returns the project path.
String writeProject(
  Directory root,
  String name, {
  int scenes = 0,
  String? defaultScene,
}) {
  final dir = Directory('${root.path}/$name')..createSync(recursive: true);
  final path = '${dir.path}/$name.fproject';
  File(path).writeAsStringSync(
    jsonEncode({
      'version': 2,
      'flutterProjectRoot': '.',
      'buildConfigurations': <Object?>[],
      if (defaultScene != null) 'defaultScene': defaultScene,
    }),
  );
  for (var i = 0; i < scenes; i++) {
    File('${dir.path}/scene$i.fscene').writeAsStringSync('{}');
  }
  return path;
}

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('launcher_test'));
  tearDown(() => root.deleteSync(recursive: true));

  group('readProjectEntry', () {
    test('reads the name, root, and scene count', () {
      final path = writeProject(root, 'Skyline', scenes: 3);
      final entry = readProjectEntry(path, recentIndex: 0);
      expect(entry.name, 'Skyline');
      expect(entry.exists, isTrue);
      expect(entry.problem, isNull);
      expect(entry.sceneCount, 3);
      expect(entry.root, File(path).parent.path);
      expect(entry.modified, isNotNull);
    });

    test('a missing project keeps its card so it can be removed', () {
      final entry = readProjectEntry(
        '${root.path}/gone/Gone.fproject',
        recentIndex: 2,
      );
      expect(entry.exists, isFalse);
      expect(entry.isBroken, isTrue);
      expect(entry.name, 'Gone');
      expect(entry.recentIndex, 2);
    });

    test('a malformed project reports the problem rather than vanishing', () {
      final dir = Directory('${root.path}/Broken')..createSync();
      final path = '${dir.path}/Broken.fproject';
      File(path).writeAsStringSync('this is not json');
      final entry = readProjectEntry(path, recentIndex: 0);
      expect(entry.exists, isTrue);
      expect(entry.problem, isNotNull);
      expect(entry.isBroken, isTrue);
    });

    test('build and tool directories are not searched for scenes', () {
      final path = writeProject(root, 'Deep', scenes: 1);
      final dir = File(path).parent;
      for (final skipped in ['build', '.dart_tool', 'ios']) {
        Directory('${dir.path}/$skipped').createSync();
        File('${dir.path}/$skipped/stale.fscene').writeAsStringSync('{}');
      }
      Directory('${dir.path}/assets/levels').createSync(recursive: true);
      File('${dir.path}/assets/levels/nested.fscene').writeAsStringSync('{}');

      final entry = readProjectEntry(path, recentIndex: 0);
      expect(entry.sceneCount, 2, reason: 'the real scene plus the nested one');
    });
  });

  group('buildProjectLibrary', () {
    test('keeps the recent order and collapses duplicates', () {
      final first = writeProject(root, 'First');
      final second = writeProject(root, 'Second');
      final library = buildProjectLibrary(
        [second, first],
        // The same project again, from a folder scan.
        extraPaths: [first],
      );
      expect(library.entries, hasLength(2));
      expect([for (final e in library.entries) e.name], ['Second', 'First']);
      expect(library.entries[1].recentIndex, 1, reason: 'kept its recency');
    });

    test('a cover resolver decorates the entries', () {
      final path = writeProject(root, 'Art');
      final library = buildProjectLibrary([path], coverFor: (p) => '$p.png');
      expect(library.entries.single.coverPath, '$path.png');
    });
  });

  group('ProjectLibrary.view', () {
    ProjectLibrary libraryOf(List<ProjectEntry> entries) =>
        ProjectLibrary(entries);

    ProjectEntry entry(
      String name, {
      int recent = 0,
      DateTime? modified,
      bool exists = true,
      String? path,
    }) => ProjectEntry(
      path: path ?? '/projects/$name/$name.fproject',
      name: name,
      root: '/projects/$name',
      exists: exists,
      recentIndex: recent,
      modified: modified,
    );

    test('recency is the default order', () {
      final library = libraryOf([
        entry('Beta', recent: 1),
        entry('Alpha', recent: 0),
      ]);
      expect([for (final e in library.view()) e.name], ['Alpha', 'Beta']);
    });

    test('sorting by name is case-insensitive', () {
      final library = libraryOf([
        entry('zebra', recent: 0),
        entry('Apple', recent: 1),
      ]);
      expect(
        [for (final e in library.view(sort: ProjectSort.name)) e.name],
        ['Apple', 'zebra'],
      );
    });

    test('sorting by modification puts the newest first, nulls last', () {
      final library = libraryOf([
        entry('Old', recent: 0, modified: DateTime(2020)),
        entry('New', recent: 1, modified: DateTime(2026)),
        entry('Unknown', recent: 2),
      ]);
      expect(
        [for (final e in library.view(sort: ProjectSort.modified)) e.name],
        ['New', 'Old', 'Unknown'],
      );
    });

    test('broken projects sort last whatever the order', () {
      final library = libraryOf([
        entry('Gone', recent: 0, exists: false),
        entry('Live', recent: 1),
      ]);
      for (final sort in ProjectSort.values) {
        expect(
          [for (final e in library.view(sort: sort)) e.name],
          ['Live', 'Gone'],
          reason: 'sorted by ${sort.name}',
        );
      }
    });

    test('search matches the name and the path', () {
      final library = libraryOf([
        entry('Skyline', path: '/work/games/Skyline/Skyline.fproject'),
        entry('Harbour', recent: 1, path: '/work/demos/Harbour/H.fproject'),
      ]);
      expect([for (final e in library.view(query: 'sky')) e.name], ['Skyline']);
      expect(
        [for (final e in library.view(query: 'demos')) e.name],
        ['Harbour'],
        reason: 'a directory the name does not contain',
      );
      expect(library.view(query: '  '), hasLength(2), reason: 'blank matches');
      expect(library.view(query: 'nothing'), isEmpty);
    });
  });

  group('scanForProjects', () {
    test('finds projects at the root and one level down', () {
      writeProject(root, 'Nested');
      File('${root.path}/Loose.fproject').writeAsStringSync('{}');
      Directory('${root.path}/deep/deeper').createSync(recursive: true);
      File('${root.path}/deep/deeper/TooDeep.fproject').writeAsStringSync('{}');

      final found = scanForProjects(root.path);
      expect([
        for (final p in found) p.split('/').last,
      ], containsAll(<String>['Loose.fproject', 'Nested.fproject']));
      expect(
        found.any((p) => p.endsWith('TooDeep.fproject')),
        isFalse,
        reason: 'a full walk would wander into build outputs',
      );
    });

    test('a missing directory scans to nothing rather than throwing', () {
      expect(scanForProjects('${root.path}/absent'), isEmpty);
    });

    test('hidden directories are skipped', () {
      Directory('${root.path}/.cache').createSync();
      File('${root.path}/.cache/Hidden.fproject').writeAsStringSync('{}');
      expect(scanForProjects(root.path), isEmpty);
    });
  });

  group('describeAge', () {
    final now = DateTime(2026, 8, 28, 12);

    test('rounds down to a single readable unit', () {
      expect(describeAge(now, now: now), 'just now');
      expect(
        describeAge(now.subtract(const Duration(minutes: 5)), now: now),
        '5 minutes ago',
      );
      expect(
        describeAge(now.subtract(const Duration(hours: 1)), now: now),
        '1 hour ago',
      );
      expect(
        describeAge(now.subtract(const Duration(days: 3)), now: now),
        '3 days ago',
      );
      expect(
        describeAge(now.subtract(const Duration(days: 60)), now: now),
        '2 months ago',
      );
      expect(
        describeAge(now.subtract(const Duration(days: 800)), now: now),
        '2 years ago',
      );
    });

    test('a clock skewed into the future still reads sensibly', () {
      expect(
        describeAge(now.add(const Duration(hours: 2)), now: now),
        'just now',
      );
    });

    test('an unknown time is blank, not a fake one', () {
      expect(describeAge(null), '');
    });
  });

  group('cover keys', () {
    test('the key is stable and path-specific', () {
      expect(coverKey('/a/b.fproject'), coverKey('/a/b.fproject'));
      expect(coverKey('/a/b.fproject'), isNot(coverKey('/a/c.fproject')));
      expect(coverKey('/a/b.fproject'), matches(RegExp(r'^[0-9a-f]{16}$')));
    });

    test('the placeholder hue is stable and inside a colour wheel', () {
      final hue = placeholderHue('/a/b.fproject');
      expect(hue, placeholderHue('/a/b.fproject'));
      expect(hue, inInclusiveRange(0, 359));
    });

    test('two projects with the same name in different folders differ', () {
      expect(
        coverKey('/one/Game/Game.fproject'),
        isNot(coverKey('/two/Game/Game.fproject')),
      );
    });
  });

  test('projectDisplayName strips the extension, not the name', () {
    expect(projectDisplayName('/a/Skyline.fproject'), 'Skyline');
    expect(projectDisplayName('/a/no-extension'), 'no-extension');
    expect(projectDisplayName(r'C:\work\Win.fproject'), 'Win');
  });
}
