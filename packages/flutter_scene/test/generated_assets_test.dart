import 'dart:io';

import 'package:flutter_scene/src/generated_assets/generated_asset_lookup.dart';
import 'package:flutter_scene/src/generated_assets/generated_assets.dart';
import 'package:flutter_scene/src/generated_assets/generated_tree.dart';
import 'package:flutter_test/flutter_test.dart';

GeneratedAssetEntry _entry({
  GeneratedAssetFamily family = GeneratedAssetFamily.scene,
  required String id,
  required String owner,
  String? file,
  String? source,
}) => GeneratedAssetEntry(
  family: family,
  id: id,
  owner: owner,
  file: file ?? generatedFileName(family, id, '.fsceneb'),
  stamp: 'stamp',
  source: source,
);

void main() {
  group('generated file names', () {
    test('are unsigned hex with no leading dash', () {
      // FNV-1a overflows into the sign bit; every name must still be readable.
      for (final id in [
        'assets_src/fcar',
        'assets_src/flutter_logo_baked',
        'assets/a',
        'assets/b',
        'x',
      ]) {
        final name = generatedFileName(
          GeneratedAssetFamily.scene,
          id,
          '.fsceneb',
        );
        expect(name, isNot(contains('-')));
        expect(name, matches(RegExp(r'^scene\.[A-Za-z0-9_]+\.[0-9a-f]{8}\.')));
      }
    });

    test('are stable', () {
      expect(
        generatedFileName(GeneratedAssetFamily.scene, 'assets/a', '.fsceneb'),
        generatedFileName(GeneratedAssetFamily.scene, 'assets/a', '.fsceneb'),
      );
    });

    test('keep same-named sources in different directories apart', () {
      final one = generatedFileName(
        GeneratedAssetFamily.scene,
        'levels/one/room',
        '.fsceneb',
      );
      final two = generatedFileName(
        GeneratedAssetFamily.scene,
        'levels/two/room',
        '.fsceneb',
      );
      expect(one, isNot(two));
      expect(one, startsWith('scene.room.'));
      expect(two, startsWith('scene.room.'));
    });

    test('separate families sharing an id', () {
      expect(
        generatedFileName(GeneratedAssetFamily.scene, 'a/b', '.fsceneb'),
        isNot(
          generatedFileName(GeneratedAssetFamily.texture, 'a/b', '.fsceneb'),
        ),
      );
    });

    test('are recognized by the tree sweep, and other files are not', () {
      expect(
        isGeneratedFileName(
          generatedFileName(
            GeneratedAssetFamily.material,
            'x',
            '.shaderbundle',
          ),
        ),
        isTrue,
      );
      expect(isGeneratedFileName('manifest.json'), isFalse);
      expect(isGeneratedFileName('.gitignore'), isFalse);
      expect(isGeneratedFileName('README.md'), isFalse);
      expect(isGeneratedFileName('scene.a.fsceneb'), isFalse);
    });

    test('fnv1aHex is 16 unsigned hex digits', () {
      expect(fnv1aHex(const [1, 2, 3]), matches(RegExp(r'^[0-9a-f]{16}$')));
      expect(fnv1aHex(const []), matches(RegExp(r'^[0-9a-f]{16}$')));
    });
  });

  group('manifest', () {
    test('round trips, defaulting owner to the manifest package', () {
      final manifest = GeneratedAssetManifest(package: 'my_app')
        ..put(_entry(id: 'assets/a', owner: 'my_app', source: 'assets/a.glb'))
        ..put(
          _entry(
            family: GeneratedAssetFamily.shaderBundle,
            id: 'base',
            owner: 'flutter_scene',
          ),
        );
      final decoded = GeneratedAssetManifest.decode(manifest.encode())!;
      expect(decoded.package, 'my_app');
      expect(decoded.entries, hasLength(2));
      final scene = decoded.find(GeneratedAssetFamily.scene, 'assets/a')!;
      expect(scene.owner, 'my_app');
      expect(scene.source, 'assets/a.glb');
      expect(
        decoded.find(GeneratedAssetFamily.shaderBundle, 'base')!.owner,
        'flutter_scene',
      );
    });

    test('rejects another schema', () {
      expect(
        GeneratedAssetManifest.decode('{"schema": 99, "entries": []}'),
        isNull,
      );
      expect(GeneratedAssetManifest.decode('not json'), isNull);
    });

    test('put replaces the entry for a family and id', () {
      final manifest = GeneratedAssetManifest(package: 'app')
        ..put(_entry(id: 'a', owner: 'app', file: 'one'))
        ..put(_entry(id: 'a', owner: 'app', file: 'two'));
      expect(manifest.entries, hasLength(1));
      expect(manifest.find(GeneratedAssetFamily.scene, 'a')!.file, 'two');
    });
  });

  group('GeneratedAssetIndex', () {
    GeneratedAssetIndex indexOf(List<GeneratedAssetEntry> entries) =>
        GeneratedAssetIndex([
          GeneratedAssetSource(
            keyPrefix: '$generatedAssetsDirectory/',
            manifest: GeneratedAssetManifest(package: 'app', entries: entries),
          ),
        ]);

    test('resolves a hit to a bundle key', () {
      final index = indexOf([_entry(id: 'assets/a', owner: 'app')]);
      expect(
        index.resolveKey(GeneratedAssetFamily.scene, 'assets/a'),
        '$generatedAssetsDirectory/'
        '${generatedFileName(GeneratedAssetFamily.scene, 'assets/a', '.fsceneb')}',
      );
    });

    test('returns null on a miss', () {
      expect(
        indexOf([]).resolveKey(GeneratedAssetFamily.scene, 'assets/a'),
        isNull,
      );
      expect(
        indexOf([
          _entry(id: 'assets/a', owner: 'app'),
        ]).resolveKey(GeneratedAssetFamily.scene, 'assets/a', package: 'other'),
        isNull,
      );
    });

    test('disambiguates by owner across sources', () {
      final index = GeneratedAssetIndex([
        GeneratedAssetSource(
          keyPrefix: '$generatedAssetsDirectory/',
          manifest: GeneratedAssetManifest(
            package: 'app',
            entries: [_entry(id: 'shared', owner: 'app', file: 'app.fsceneb')],
          ),
        ),
        GeneratedAssetSource(
          keyPrefix: 'packages/dep/$generatedAssetsDirectory/',
          manifest: GeneratedAssetManifest(
            package: 'dep',
            entries: [_entry(id: 'shared', owner: 'dep', file: 'dep.fsceneb')],
          ),
        ),
      ]);
      expect(
        () => index.resolveKey(GeneratedAssetFamily.scene, 'shared'),
        throwsStateError,
      );
      expect(
        index.resolveKey(GeneratedAssetFamily.scene, 'shared', package: 'dep'),
        'packages/dep/$generatedAssetsDirectory/dep.fsceneb',
      );
    });
  });

  group('pubspec assets', () {
    test('reads a block list, ignoring comments and quotes', () {
      final assets = parsePubspecAssets(
        '''
name: app

flutter:
  uses-material-design: true
  assets:
    # a comment
    - assets/one.png
    - "assets/two.png" # trailing comment
    - $generatedAssetsEntry
  fonts:
    - family: X
'''
            .split('\n'),
      );
      expect(assets.style, PubspecAssetsStyle.block);
      expect(assets.entries, [
        'assets/one.png',
        'assets/two.png',
        normalizeAssetEntry(generatedAssetsEntry),
      ]);
    });

    test('reports a flow list rather than calling it absent', () {
      final assets = parsePubspecAssets(
        '''
flutter:
  assets: [assets/one.png, $generatedAssetsEntry]
'''
            .split('\n'),
      );
      expect(assets.style, PubspecAssetsStyle.flow);
      expect(assets.entries, isEmpty);
    });

    test('ignores an assets key that is not a direct child of flutter', () {
      final assets = parsePubspecAssets(
        '''
flutter:
  deferred-components:
    - name: one
      assets:
        - assets/one.png
'''
            .split('\n'),
      );
      expect(assets.style, PubspecAssetsStyle.absent);
    });

    test('ignores a top-level assets key outside flutter', () {
      final assets = parsePubspecAssets(
        '''
some_tool:
  assets:
    - assets/one.png
'''
            .split('\n'),
      );
      expect(assets.style, PubspecAssetsStyle.absent);
    });

    test('reads an empty flutter block', () {
      expect(
        parsePubspecAssets('name: app\nflutter:\n'.split('\n')).style,
        PubspecAssetsStyle.absent,
      );
    });
  });

  group('ensureGeneratedAssetsEntry', () {
    late Directory temp;

    setUp(() => temp = Directory.systemTemp.createTempSync('fs_pubspec'));
    tearDown(() => temp.deleteSync(recursive: true));

    File write(String contents) =>
        File.fromUri(temp.uri.resolve('pubspec.yaml'))
          ..writeAsStringSync(contents);

    test('appends to an existing asset list, keeping comments', () {
      final pubspec = write('''
name: app

flutter:
  uses-material-design: true
  assets:
    # keep me
    - assets/one.png
''');
      expect(
        ensureGeneratedAssetsEntry(pubspec).status,
        PubspecEditStatus.added,
      );
      expect(pubspec.readAsStringSync(), '''
name: app

flutter:
  uses-material-design: true
  assets:
    # keep me
    - assets/one.png
    - $generatedAssetsEntry
''');
    });

    test('is idempotent', () {
      final pubspec = write(
        'name: app\nflutter:\n  assets:\n    - $generatedAssetsEntry\n',
      );
      final before = pubspec.readAsStringSync();
      expect(
        ensureGeneratedAssetsEntry(pubspec).status,
        PubspecEditStatus.alreadyPresent,
      );
      expect(pubspec.readAsStringSync(), before);
    });

    test('matches an entry written without its trailing slash', () {
      final pubspec = write(
        'name: app\nflutter:\n  assets:\n'
        '    - ${normalizeAssetEntry(generatedAssetsEntry)}\n',
      );
      expect(
        ensureGeneratedAssetsEntry(pubspec).status,
        PubspecEditStatus.alreadyPresent,
      );
    });

    test('adds an assets key to a flutter block that has none', () {
      final pubspec = write(
        'name: app\nflutter:\n  uses-material-design: true\n',
      );
      expect(
        ensureGeneratedAssetsEntry(pubspec).status,
        PubspecEditStatus.added,
      );
      expect(pubspec.readAsStringSync(), '''
name: app
flutter:
  uses-material-design: true
  assets:
    - $generatedAssetsEntry
''');
    });

    test('inserts before a following key of the same depth', () {
      final pubspec = write('''
name: app
flutter:
  assets:
    - assets/one.png
  fonts:
    - family: X
''');
      ensureGeneratedAssetsEntry(pubspec);
      expect(pubspec.readAsStringSync(), '''
name: app
flutter:
  assets:
    - assets/one.png
    - $generatedAssetsEntry
  fonts:
    - family: X
''');
    });

    test('adds a whole flutter section when there is none', () {
      final pubspec = write('name: app\n');
      expect(
        ensureGeneratedAssetsEntry(pubspec).status,
        PubspecEditStatus.added,
      );
      expect(
        pubspec.readAsStringSync(),
        'name: app\n\n$generatedAssetsPubspecSnippet\n',
      );
    });

    test('refuses a flow list', () {
      final pubspec = write(
        'name: app\nflutter:\n  assets: [assets/one.png]\n',
      );
      expect(
        ensureGeneratedAssetsEntry(pubspec).status,
        PubspecEditStatus.unsupported,
      );
    });
  });

  group('GeneratedAssetTree', () {
    late Directory temp;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('fs_tree');
      File.fromUri(temp.uri.resolve('pubspec.yaml')).writeAsStringSync(
        'name: app\nflutter:\n  assets:\n    - $generatedAssetsEntry\n',
      );
    });
    tearDown(() => temp.deleteSync(recursive: true));

    Uri treeUri() => temp.uri.resolve('$generatedAssetsDirectory/');

    test('creates the directory and its gitignore, and requires the entry', () {
      final tree = GeneratedAssetTree.open(temp.uri, 'app');
      expect(Directory.fromUri(treeUri()).existsSync(), isTrue);
      expect(
        File.fromUri(
          treeUri().resolve(generatedAssetsGitignoreFileName),
        ).readAsStringSync(),
        generatedAssetsGitignore,
      );
      tree.requireAssetEntry();
    });

    test('fails loudly when the pubspec does not list the directory', () {
      File.fromUri(
        temp.uri.resolve('pubspec.yaml'),
      ).writeAsStringSync('name: app\n');
      expect(
        () => GeneratedAssetTree.open(temp.uri, 'app').requireAssetEntry(),
        throwsA(
          isA<MissingGeneratedAssetEntryException>().having(
            (e) => e.toString(),
            'message',
            allOf(
              contains('flutter_scene:init'),
              contains(generatedAssetsEntry),
            ),
          ),
        ),
      );
    });

    test('openExisting is null until a manifest exists', () {
      expect(GeneratedAssetTree.openExisting(temp.uri, 'app'), isNull);
      final tree = GeneratedAssetTree.open(temp.uri, 'app');
      final file = tree.fileUri(
        GeneratedAssetFamily.scene,
        nameId: 'assets/a',
        extension: '.fsceneb',
      );
      File.fromUri(file).writeAsBytesSync(const [1]);
      tree
        ..recordFile(
          family: GeneratedAssetFamily.scene,
          id: 'assets/a',
          uri: file,
          stamp: 'one',
        )
        ..save();
      expect(GeneratedAssetTree.openExisting(temp.uri, 'app'), isNotNull);
    });

    test('save sweeps unreferenced generated files and keeps others', () {
      final tree = GeneratedAssetTree.open(temp.uri, 'app');
      final kept = tree.fileUri(
        GeneratedAssetFamily.scene,
        nameId: 'assets/a',
        extension: '.fsceneb',
      );
      File.fromUri(kept).writeAsBytesSync(const [1]);
      final orphan = treeUri().resolve(
        generatedFileName(
          GeneratedAssetFamily.scene,
          'assets/gone',
          '.fsceneb',
        ),
      );
      File.fromUri(orphan).writeAsBytesSync(const [2]);
      final keeper = treeUri().resolve('NOTES.md');
      File.fromUri(keeper).writeAsStringSync('mine');
      tree
        ..recordFile(
          family: GeneratedAssetFamily.scene,
          id: 'assets/a',
          uri: kept,
          stamp: 'one',
        )
        ..save();
      expect(File.fromUri(kept).existsSync(), isTrue);
      expect(File.fromUri(orphan).existsSync(), isFalse);
      expect(File.fromUri(keeper).existsSync(), isTrue);
    });

    test('prunes entries whose source is gone, and only its own', () {
      final tree = GeneratedAssetTree.open(temp.uri, 'app');
      final source = File.fromUri(temp.uri.resolve('assets/a.glb'))
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(const [1]);
      final own = tree.fileUri(
        GeneratedAssetFamily.scene,
        nameId: 'assets/a',
        extension: '.fsceneb',
      );
      File.fromUri(own).writeAsBytesSync(const [1]);
      final dependency = tree.fileUri(
        GeneratedAssetFamily.scene,
        nameId: 'assets/dep',
        extension: '.fsceneb',
      );
      File.fromUri(dependency).writeAsBytesSync(const [1]);
      tree
        ..recordFile(
          family: GeneratedAssetFamily.scene,
          id: 'assets/a',
          uri: own,
          stamp: 'one',
          source: 'assets/a.glb',
        )
        ..recordFile(
          family: GeneratedAssetFamily.scene,
          id: 'assets/dep',
          uri: dependency,
          stamp: 'one',
          owner: 'dep',
          source: 'assets/dep.glb',
        )
        ..pruneMissingSources()
        ..save();
      expect(File.fromUri(own).existsSync(), isTrue);
      expect(File.fromUri(dependency).existsSync(), isTrue);

      source.deleteSync();
      GeneratedAssetTree.open(temp.uri, 'app')
        ..pruneMissingSources()
        ..save();
      expect(File.fromUri(own).existsSync(), isFalse);
      expect(File.fromUri(dependency).existsSync(), isTrue);
    });

    test('isFresh tracks the stamp and the output', () {
      final tree = GeneratedAssetTree.open(temp.uri, 'app');
      final file = tree.fileUri(
        GeneratedAssetFamily.texture,
        nameId: 'assets/t',
        extension: '.fstex',
      );
      File.fromUri(file).writeAsBytesSync(const [1]);
      tree
        ..recordFile(
          family: GeneratedAssetFamily.texture,
          id: 'assets/t',
          uri: file,
          stamp: 'one',
        )
        ..save();

      final reopened = GeneratedAssetTree.open(temp.uri, 'app');
      expect(
        reopened.isFresh(GeneratedAssetFamily.texture, 'assets/t', 'one', [
          file,
        ]),
        isTrue,
      );
      expect(
        reopened.isFresh(GeneratedAssetFamily.texture, 'assets/t', 'two', [
          file,
        ]),
        isFalse,
      );
      File.fromUri(file).deleteSync();
      expect(
        reopened.isFresh(GeneratedAssetFamily.texture, 'assets/t', 'one', [
          file,
        ]),
        isFalse,
      );
    });

    test(
      'dropOwned removes only the entries that owner has in that family',
      () {
        final tree = GeneratedAssetTree.open(temp.uri, 'app');
        final mine = tree.fileUri(
          GeneratedAssetFamily.shaderBundle,
          nameId: 'app',
          extension: '.shaderbundle',
        );
        final theirs = tree.fileUri(
          GeneratedAssetFamily.shaderBundle,
          nameId: 'base',
          extension: '.shaderbundle',
        );
        File.fromUri(mine).writeAsBytesSync(const [1]);
        File.fromUri(theirs).writeAsBytesSync(const [1]);
        tree
          ..recordFile(
            family: GeneratedAssetFamily.shaderBundle,
            id: 'app',
            uri: mine,
            stamp: 'one',
          )
          ..recordFile(
            family: GeneratedAssetFamily.shaderBundle,
            id: 'base',
            uri: theirs,
            stamp: 'one',
            owner: 'flutter_scene',
          )
          ..dropOwned(GeneratedAssetFamily.shaderBundle, owner: 'app')
          ..save();
        expect(File.fromUri(mine).existsSync(), isFalse);
        expect(File.fromUri(theirs).existsSync(), isTrue);
      },
    );

    test('a manifest from another package starts over', () {
      GeneratedAssetTree.open(temp.uri, 'app')
        ..record(
          family: GeneratedAssetFamily.scene,
          id: 'a',
          file: 'x',
          stamp: 'one',
        )
        ..save();
      expect(GeneratedAssetTree.openExisting(temp.uri, 'other'), isNull);
    });
  });
}
